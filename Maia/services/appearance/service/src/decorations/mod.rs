//! The window decorations area: which themes there are, which one is used, changing it,
//! installing and removing themes, and the choice of each frontend.
//!
//! Plain values and async functions, no Cap'n Proto (that is rpc/decorations.rs). The parts:
//!
//! - `theme.rs`     the values (Engine, ThemeId "engine:name", Theme, Current, BorderSize)
//! - `catalog.rs`   finds the themes on disk
//! - `qtplugin.rs`  reads the names of native plugins (Breeze) from their files
//! - `install.rs`   installs and removes the user's themes
//! - `frontends.rs` remembers a choice per frontend (maia/appearance.json)
//!
//! Rules:
//! - One change at a time (`lock`): set, setBorderSize, install, remove, activateFrontend and the
//!   re-reading after outside changes wait for each other, so the compositor and the remembered
//!   choices never see two changes mixed. Reads (themes(), current()) never wait.
//! - Every change of the list or of the choice goes to the subscribers as an Event.
//! - While a frontend is active (between activate_frontend and its release), what the user
//!   chooses is remembered for it, also when chosen in another program (KDE's System Settings).

pub mod catalog;
pub mod frontends;
pub mod install;
pub mod qtplugin;
pub mod theme;

use std::cell::{Cell, RefCell};
use std::collections::HashSet;
use std::path::PathBuf;
use std::rc::Rc;
use std::time::Duration;

use tokio::sync::{Mutex, mpsc};

use crate::compositor::{Applied, Compositor, CompositorInfo};
use crate::error::{ErrorCode, OpError, OpResult};
use crate::inotify::Watcher;
use crate::paths::{self, Paths};
use frontends::DecorationChoices;
use theme::{BorderSize, Current, Engine, Theme, ThemeId};

/// Sent to the subscribers (rpc/decorations.rs turns them into listener calls)
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Event {
    ThemesChanged(Vec<Theme>),
    CurrentChanged(Current),
}

const THEMES_SETTLE: Duration = Duration::from_millis(500);

struct State {
    themes: Vec<Theme>,
    current: Current,
    choices: DecorationChoices,
    /// The active frontend and the token of its activation
    active: Option<(u64, String)>,
}

pub struct Decorations {
    paths: Paths,
    locales: Vec<String>,
    compositor: Rc<dyn Compositor>,
    info: CompositorInfo,
    choices_file: PathBuf,
    state: RefCell<State>,
    lock: Mutex<()>,
    subscribers: RefCell<Vec<mpsc::UnboundedSender<Event>>>,
    next_token: Cell<u64>,
}

impl Decorations {
    /// Reads the themes, the choice and the remembered choices, and starts watching for changes
    /// made by other programs (in tasks of the current LocalSet)
    pub async fn start(paths: Paths, compositor: Rc<dyn Compositor>) -> Rc<Decorations> {
        let info = compositor.info();
        let locales = paths::locale_keys();
        let choices_file = frontends::file_path(&paths.config_home);
        let choices = frontends::load(&choices_file).await;
        let current = match compositor.read().await {
            Ok(state) => Current { theme: state.theme, border_size: state.border_size, confirmed: false, frontend: String::new() },
            Err(error) => {
                eprintln!("maia-appearance-service: reading the decoration: {error}");
                Current::default()
            }
        };
        let decorations = Rc::new(Decorations {
            paths,
            locales,
            compositor: compositor.clone(),
            info,
            choices_file,
            state: RefCell::new(State { themes: Vec::new(), current, choices, active: None }),
            lock: Mutex::new(()),
            subscribers: RefCell::default(),
            next_token: Cell::new(1),
        });
        decorations.rescan().await;

        // Outside changes of the compositor's settings
        let (changed, mut changes) = mpsc::unbounded_channel();
        tokio::task::spawn_local(compositor.watch(changed));
        let weak = Rc::downgrade(&decorations);
        tokio::task::spawn_local(async move {
            while changes.recv().await.is_some() {
                let Some(this) = weak.upgrade() else { return };
                this.reread_choice().await;
            }
        });
        // Themes installed or removed by other programs
        let weak = Rc::downgrade(&decorations);
        let dirs = decorations.theme_dirs().await;
        tokio::task::spawn_local(async move {
            let Ok(watcher) = Watcher::new() else { return };
            for dir in &dirs {
                watcher.add_dir(dir);
            }
            while watcher.next_burst(THEMES_SETTLE, |_| true).await.is_ok() {
                let Some(this) = weak.upgrade() else { return };
                this.rescan().await;
            }
        });
        decorations
    }

    async fn theme_dirs(&self) -> Vec<PathBuf> {
        let users = self.paths.data_home.join("aurorae/themes");
        let _ = tokio::fs::create_dir_all(&users).await;
        let mut dirs = self.paths.data_subdirs("aurorae/themes");
        dirs.extend(self.paths.data_subdirs("kwin/decorations"));
        dirs.extend(self.paths.plugin_dirs.iter().map(|d| d.join(catalog::PLUGIN_SUBDIR)));
        dirs
    }

    pub fn info(&self) -> &CompositorInfo {
        &self.info
    }

    pub fn themes(&self) -> Vec<Theme> {
        self.state.borrow().themes.clone()
    }

    pub fn current(&self) -> Current {
        self.state.borrow().current.clone()
    }

    /// Events of every change from now on
    pub fn subscribe(&self) -> mpsc::UnboundedReceiver<Event> {
        let (sender, receiver) = mpsc::unbounded_channel();
        self.subscribers.borrow_mut().push(sender);
        receiver
    }

    fn emit(&self, event: Event) {
        self.subscribers.borrow_mut().retain(|s| s.send(event.clone()).is_ok());
    }

    fn update_current(&self, change: impl FnOnce(&mut Current)) {
        let current = {
            let mut state = self.state.borrow_mut();
            let before = state.current.clone();
            change(&mut state.current);
            state.current.frontend = state.active.as_ref().map(|(_, f)| f.clone()).unwrap_or_default();
            if state.current == before {
                return;
            }
            state.current.clone()
        };
        self.emit(Event::CurrentChanged(current));
    }

    fn find(&self, id: &ThemeId) -> Option<Theme> {
        self.state.borrow().themes.iter().find(|t| &t.id == id).cloned()
    }

    /// A theme that can be used now: it exists and the compositor draws it
    fn usable(&self, id: &str) -> OpResult<ThemeId> {
        let id: ThemeId = id.parse()?;
        let theme = self.find(&id).ok_or_else(|| OpError::new(ErrorCode::NotFound, format!("no theme {id}")))?;
        if !theme.available {
            return Err(OpError::new(ErrorCode::NotSupported, theme.unavailable_reason));
        }
        Ok(id)
    }

    /// Looks for themes again; sends the list when it changed
    pub async fn rescan(&self) {
        let (paths, engines, name, locales) = (self.paths.clone(), self.info.engines.clone(), self.info.name.clone(), self.locales.clone());
        let Ok(themes) = tokio::task::spawn_blocking(move || catalog::scan(&paths, &engines, &name, &locales)).await else { return };
        let changed = {
            let mut state = self.state.borrow_mut();
            let changed = state.themes != themes;
            state.themes = themes.clone();
            changed
        };
        if changed {
            self.emit(Event::ThemesChanged(themes));
        }
    }

    /// Remembers `id` as the active frontend's choice
    async fn remember(&self, id: Option<&ThemeId>) {
        let choices = {
            let mut state = self.state.borrow_mut();
            let Some((_, frontend)) = state.active.clone() else { return };
            let Some(id) = id else { return };
            if state.choices.frontends.get(&frontend) == Some(&id.to_string()) {
                return;
            }
            state.choices.frontends.insert(frontend, id.to_string());
            state.choices.clone()
        };
        if let Err(error) = frontends::save(&self.choices_file, &choices).await {
            eprintln!("maia-appearance-service: {error}");
        }
    }

    /// Applies a usable theme (with the lock held)
    async fn apply(&self, id: ThemeId) -> OpResult {
        match self.compositor.apply_theme(&id).await {
            Ok(applied) => {
                self.update_current(|c| {
                    c.theme = Some(id.clone());
                    c.confirmed = applied == Applied::Confirmed;
                });
                self.remember(Some(&id)).await;
                Ok(())
            }
            Err(error) => {
                // What the compositor uses now (it may have fallen back)
                if let Ok(state) = self.compositor.read().await {
                    self.update_current(|c| {
                        c.theme = state.theme;
                        c.confirmed = false;
                    });
                }
                Err(error)
            }
        }
    }

    pub async fn set(&self, id: &str) -> OpResult {
        let id = self.usable(id)?;
        let _guard = self.lock.lock().await;
        self.apply(id).await
    }

    pub async fn set_border_size(&self, size: BorderSize) -> OpResult {
        if !self.info.border_sizes {
            return Err(OpError::new(ErrorCode::NotSupported, format!("{} has no border sizes", self.info.name)));
        }
        let _guard = self.lock.lock().await;
        let applied = self.compositor.apply_border_size(size).await?;
        self.update_current(|c| {
            c.border_size = size;
            c.confirmed = c.confirmed && applied == Applied::Confirmed;
        });
        Ok(())
    }

    pub async fn install(&self, path: &str) -> OpResult<ThemeId> {
        if !self.info.engines.contains(&Engine::AuroraeSvg) {
            return Err(OpError::new(ErrorCode::NotSupported, format!("{} draws no Aurorae themes", self.info.name)));
        }
        let source = std::path::PathBuf::from(path.strip_prefix("file://").unwrap_or(path));
        if !source.is_absolute() {
            return Err(OpError::invalid("the path must be absolute"));
        }
        let _guard = self.lock.lock().await;
        let taken: HashSet<String> =
            self.state.borrow().themes.iter().filter(|t| t.id.engine == Engine::AuroraeSvg).map(|t| t.id.name.clone()).collect();
        let id = install::install(&self.paths, &source, &taken).await?;
        self.rescan().await;
        Ok(id)
    }

    pub async fn remove(&self, id: &str) -> OpResult {
        let id: ThemeId = id.parse()?;
        let _guard = self.lock.lock().await;
        let theme = self.find(&id).ok_or_else(|| OpError::new(ErrorCode::NotFound, format!("no theme {id}")))?;
        if self.state.borrow().current.theme.as_ref() == Some(&id) {
            return Err(OpError::new(ErrorCode::NotAllowed, "the theme is in use; choose another one first"));
        }
        install::remove(&self.paths, &theme).await?;
        self.rescan().await;
        Ok(())
    }

    /// A frontend's shell starts. Returns the token its release gives back, and how applying its
    /// choice went (the frontend is active either way).
    pub async fn activate_frontend(&self, frontend: &str, default: &str) -> OpResult<(u64, OpResult)> {
        if frontend.is_empty() {
            return Err(OpError::invalid("no frontend name"));
        }
        let _guard = self.lock.lock().await;
        let token = self.next_token.get();
        self.next_token.set(token + 1);
        let remembered = self.state.borrow().choices.frontends.get(frontend).cloned();
        self.state.borrow_mut().active = Some((token, frontend.to_string()));
        self.update_current(|_| {});

        let remembered = remembered.and_then(|id| self.usable(&id).ok());
        let target = remembered.clone().or_else(|| (!default.is_empty()).then(|| self.usable(default)).and_then(Result::ok));
        if !default.is_empty() && remembered.is_none() && target.is_none() {
            eprintln!("maia-appearance-service: {frontend}'s default decoration {default} cannot be used");
        }
        let current = self.state.borrow().current.theme.clone();
        let result = match target {
            Some(target) if Some(&target) != current.as_ref() => self.apply(target).await,
            Some(target) => {
                self.remember(Some(&target)).await;
                Ok(())
            }
            // Nothing remembered, no default: what is used now becomes the frontend's choice
            None => {
                self.remember(current.as_ref()).await;
                Ok(())
            }
        };
        Ok((token, result))
    }

    /// The frontend's activation was released (the shell ended or the frontend was switched)
    pub fn deactivate_frontend(&self, token: u64) {
        let ended = {
            let mut state = self.state.borrow_mut();
            let ended = state.active.as_ref().is_some_and(|(t, _)| *t == token);
            if ended {
                state.active = None;
            }
            ended
        };
        if ended {
            self.update_current(|_| {});
        }
    }

    /// Another program changed the compositor's settings
    async fn reread_choice(&self) {
        let _guard = self.lock.lock().await;
        let Ok(state) = self.compositor.read().await else { return };
        let before = self.current();
        if before.theme == state.theme && before.border_size == state.border_size {
            return;
        }
        self.update_current(|c| {
            c.theme = state.theme.clone();
            c.border_size = state.border_size;
            c.confirmed = false;
        });
        if before.theme != state.theme {
            self.remember(state.theme.as_ref()).await;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::compositor::fake::Fake;
    use crate::compositor::DecorationState;
    use crate::test_support::TempDir;

    fn paths_with_themes(tmp: &TempDir, names: &[&str]) -> Paths {
        let home = tmp.path().join("home");
        for name in names {
            let dir = home.join("aurorae/themes").join(name);
            std::fs::create_dir_all(&dir).unwrap();
            std::fs::write(dir.join("metadata.desktop"), format!("[Desktop Entry]\nName={name}\n")).unwrap();
        }
        let plugins = tmp.path().join("plugins").join(catalog::PLUGIN_SUBDIR);
        std::fs::create_dir_all(&plugins).unwrap();
        std::fs::write(plugins.join("org.kde.breeze.so"), b"").unwrap();
        Paths {
            data_home: home.clone(),
            data_dirs: vec![home],
            config_home: tmp.path().join("config"),
            maia_data_dirs: vec![],
            plugin_dirs: vec![tmp.path().join("plugins")],
        }
    }

    async fn local<F: std::future::Future>(f: F) -> F::Output {
        tokio::task::LocalSet::new().run_until(f).await
    }

    #[tokio::test(flavor = "current_thread")]
    async fn each_frontend_keeps_its_choice() {
        local(async {
            let tmp = TempDir::new("area-frontends");
            let paths = paths_with_themes(&tmp, &["XBoomer", "Glass"]);
            let fake = Rc::new(Fake::new());
            let area = Decorations::start(paths.clone(), fake.clone()).await;

            // XPLuna the first time: its default
            let (xp, applied) = area.activate_frontend("XPLuna", "aurorae-svg:XBoomer").await.unwrap();
            applied.unwrap();
            assert_eq!(fake.state().theme.unwrap().to_string(), "aurorae-svg:XBoomer");
            assert_eq!(area.current().frontend, "XPLuna");
            // The user chooses another one in XPLuna
            area.set("aurorae-svg:Glass").await.unwrap();
            area.deactivate_frontend(xp);
            assert_eq!(area.current().frontend, "");

            // Lumen has no default: it keeps what is there and remembers it
            let (lumen, _) = area.activate_frontend("Lumen", "").await.unwrap();
            area.set("kdecoration:org.kde.breeze").await.unwrap();
            area.deactivate_frontend(lumen);

            // XPLuna again: the user's choice, not its default
            area.activate_frontend("XPLuna", "aurorae-svg:XBoomer").await.unwrap().1.unwrap();
            assert_eq!(fake.state().theme.unwrap().to_string(), "aurorae-svg:Glass");

            // Remembered across restarts
            let saved = frontends::load(&frontends::file_path(&paths.config_home)).await;
            assert_eq!(saved.frontends["Lumen"], "kdecoration:org.kde.breeze");
            assert_eq!(saved.frontends["XPLuna"], "aurorae-svg:Glass");
        })
        .await;
    }

    #[tokio::test(flavor = "current_thread")]
    async fn refusals_and_outside_changes() {
        local(async {
            let tmp = TempDir::new("area-refusals");
            let paths = paths_with_themes(&tmp, &["broken", "Glass"]);
            let fake = Rc::new(Fake::new());
            let area = Decorations::start(paths, fake.clone()).await;
            let mut events = area.subscribe();

            assert_eq!(area.set("aurorae-svg:Missing").await.unwrap_err().code, ErrorCode::NotFound);
            assert_eq!(area.set("nonsense").await.unwrap_err().code, ErrorCode::InvalidArgument);
            assert_eq!(area.set("aurorae-svg:broken").await.unwrap_err().code, ErrorCode::Failed);
            area.set("aurorae-svg:Glass").await.unwrap();
            assert_eq!(area.remove("aurorae-svg:Glass").await.unwrap_err().code, ErrorCode::NotAllowed);
            match events.recv().await.unwrap() {
                Event::CurrentChanged(current) => assert!(current.confirmed && current.theme.unwrap().name == "Glass"),
                other => panic!("{other:?}"),
            }

            fake.change_externally(DecorationState { theme: Some("kdecoration:org.kde.breeze".parse().unwrap()), border_size: BorderSize::Large });
            match tokio::time::timeout(Duration::from_secs(2), events.recv()).await.unwrap().unwrap() {
                Event::CurrentChanged(current) => {
                    assert_eq!(current.theme.unwrap().to_string(), "kdecoration:org.kde.breeze");
                    assert_eq!(current.border_size, BorderSize::Large);
                    assert!(!current.confirmed);
                }
                other => panic!("{other:?}"),
            }
        })
        .await;
    }
}

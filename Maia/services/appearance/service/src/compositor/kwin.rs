//! KWin: where it keeps the decoration and how it is told.
//!
//! - Settings: `$XDG_CONFIG_HOME/kwinrc`, group `[org.kde.kdecoration2]`: `library` (the plugin),
//!   `theme`, `BorderSize`, `BorderSizeAuto`, `NoPlugin`. The group's name stayed from
//!   KDecoration2 although the API is KDecoration3. Written with kwriteconfig6 (KDE's own tool: it
//!   keeps KConfig's locking and escaping), read directly.
//! - Telling KWin: the D-Bus signal `/KWin org.kde.KWin.reloadConfig` on the session bus; KWin
//!   re-reads its settings 200 ms later (Workspace::reconfigure).
//! - Checking: `org.kde.KWin.supportInformation`; its "Decoration" section says which plugin and
//!   theme KWin really loaded (it falls back to Breeze when a plugin cannot be loaded).
//! - Other programs (KDE's System Settings) write kwinrc too: the config directory is watched.
//!
//! How themes map (see kwin/src/kcms/decoration and aurorae/v2/decorationthemeprovider.cpp):
//!
//! | ThemeId                     | library                  | theme                   |
//! |-----------------------------|--------------------------|-------------------------|
//! | aurorae-svg:X               | org.kde.kwin.aurorae.v2  | __aurorae__svg__X       |
//! | aurorae-qml:kwin4_..._plastik | org.kde.kwin.aurorae   | kwin4_..._plastik       |
//! | kdecoration:org.kde.breeze  | org.kde.breeze           | (none)                  |

use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::Duration;

use futures::future::LocalBoxFuture;
use tokio::process::Command;
use tokio::sync::{OnceCell, mpsc};

use super::{Applied, Compositor, CompositorInfo, DecorationState};
use crate::decorations::catalog::{self, AURORAE_V1, AURORAE_V2};
use crate::decorations::theme::{BorderSize, Engine, ThemeId};
use crate::error::{ErrorCode, OpError, OpResult};
use crate::inotify::Watcher;
use crate::kconfig::KConfig;
use crate::paths::Paths;

pub const NAME: &str = "kwin";

const GROUP: &str = "org.kde.kdecoration2";
const SVG_PREFIX: &str = "__aurorae__svg__";
const DEFAULT_PLUGIN: &str = "org.kde.breeze";
const DEFAULT_QML_THEME: &str = "kwin4_decoration_qml_plastik";
/// KWin re-reads 200 ms after reloadConfig; it is asked again until it reports the change
const CHECK_INTERVAL: Duration = Duration::from_millis(250);
const CHECK_ATTEMPTS: u32 = 12;
const SETTLE: Duration = Duration::from_millis(300);

// --- Mapping (pure) ---

/// (library, theme) for kwinrc; theme None = remove the key
pub fn settings_of(theme: &ThemeId) -> OpResult<(String, Option<String>)> {
    match theme.engine {
        Engine::AuroraeSvg => Ok((AURORAE_V2.into(), Some(format!("{SVG_PREFIX}{}", theme.name)))),
        Engine::AuroraeQml => Ok((AURORAE_V1.into(), Some(theme.name.clone()))),
        Engine::Kdecoration => Ok((theme.name.clone(), None)),
        Engine::Wayfire => Err(OpError::new(ErrorCode::NotSupported, "a Wayfire decoration cannot be used in KWin")),
    }
}

/// The ThemeId of kwinrc's values (None when decorations are off)
pub fn theme_of(library: Option<&str>, theme: Option<&str>, no_plugin: bool) -> Option<ThemeId> {
    if no_plugin {
        return None;
    }
    let library = library.filter(|l| !l.is_empty()).unwrap_or(DEFAULT_PLUGIN);
    let theme = theme.unwrap_or_default();
    if library == AURORAE_V2 || (library == AURORAE_V1 && theme.starts_with(SVG_PREFIX)) {
        // The old engine also draws SVG themes (differently); either way it is the same theme
        let name = theme.strip_prefix(SVG_PREFIX).unwrap_or(theme);
        return (!name.is_empty()).then(|| ThemeId::new(Engine::AuroraeSvg, name));
    }
    if library == AURORAE_V1 {
        let name = if theme.is_empty() { DEFAULT_QML_THEME } else { theme };
        return Some(ThemeId::new(Engine::AuroraeQml, name));
    }
    Some(ThemeId::new(Engine::Kdecoration, library))
}

pub fn border_value(size: BorderSize) -> Option<&'static str> {
    Some(match size {
        BorderSize::Theme => return None,
        BorderSize::None => "None",
        BorderSize::NoSides => "NoSides",
        BorderSize::Tiny => "Tiny",
        BorderSize::Normal => "Normal",
        BorderSize::Large => "Large",
        BorderSize::VeryLarge => "VeryLarge",
        BorderSize::Huge => "Huge",
        BorderSize::VeryHuge => "VeryHuge",
        BorderSize::Oversized => "Oversized",
    })
}

pub fn border_of(value: Option<&str>, auto: Option<bool>) -> BorderSize {
    if auto.unwrap_or(true) {
        return BorderSize::Theme;
    }
    match value.unwrap_or("Normal") {
        "None" => BorderSize::None,
        "NoSides" => BorderSize::NoSides,
        "Tiny" => BorderSize::Tiny,
        "Large" => BorderSize::Large,
        "VeryLarge" => BorderSize::VeryLarge,
        "Huge" => BorderSize::Huge,
        "VeryHuge" => BorderSize::VeryHuge,
        "Oversized" => BorderSize::Oversized,
        _ => BorderSize::Normal,
    }
}

pub fn state_of(kwinrc: &str) -> DecorationState {
    let config = KConfig::parse(kwinrc);
    DecorationState {
        theme: theme_of(config.get(GROUP, "library"), config.get(GROUP, "theme"), config.get_bool(GROUP, "NoPlugin").unwrap_or(false)),
        border_size: border_of(config.get(GROUP, "BorderSize"), config.get_bool(GROUP, "BorderSizeAuto")),
    }
}

/// (plugin, theme) of the "Decoration" section of KWin's support information; None when KWin
/// has decorations off or the section is missing
pub fn loaded_of(support: &str) -> Option<(String, String)> {
    let start = support.find("Decoration\n==========\n")?;
    let section = &support[start..];
    let mut plugin = None;
    let mut theme = String::new();
    for line in section.lines().skip(2) {
        if line.is_empty() {
            break;
        }
        if let Some(value) = line.strip_prefix("Plugin: ") {
            plugin = Some(value.to_string());
        } else if let Some(value) = line.strip_prefix("Theme: ") {
            theme = value.to_string();
        }
    }
    plugin.map(|p| (p, theme))
}

// --- The backend ---

pub struct KWin {
    kwinrc: PathBuf,
    config_home: PathBuf,
    /// kwriteconfig6, or $MAIA_KWRITECONFIG
    kwriteconfig: String,
    engines: Vec<Engine>,
    bus: OnceCell<Option<zbus::Connection>>,
}

impl KWin {
    pub fn new(paths: &Paths) -> KWin {
        // The Aurorae engines are plugins too: without them KWin cannot draw Aurorae themes
        let plugins: Vec<String> =
            catalog::plugin_files(paths).iter().filter_map(|f| f.file_stem()?.to_str().map(str::to_string)).collect();
        let mut engines = vec![Engine::Kdecoration];
        if plugins.iter().any(|p| p == AURORAE_V2) || plugins.is_empty() {
            engines.push(Engine::AuroraeSvg);
        }
        if plugins.iter().any(|p| p == AURORAE_V1) || plugins.is_empty() {
            engines.push(Engine::AuroraeQml);
        }
        KWin {
            kwinrc: paths.config_home.join("kwinrc"),
            config_home: paths.config_home.clone(),
            kwriteconfig: std::env::var("MAIA_KWRITECONFIG").unwrap_or_else(|_| "kwriteconfig6".into()),
            engines,
            bus: OnceCell::new(),
        }
    }

    async fn bus(&self) -> Option<&zbus::Connection> {
        self.bus
            .get_or_init(|| async {
                match zbus::Connection::session().await {
                    Ok(connection) => Some(connection),
                    Err(error) => {
                        eprintln!("maia-appearance-service: no session bus ({error}): KWin is not told about changes");
                        None
                    }
                }
            })
            .await
            .as_ref()
    }

    /// Writes one key of the decoration group (value None removes it)
    async fn write(&self, key: &str, value: Option<&str>) -> OpResult {
        let mut command = Command::new(&self.kwriteconfig);
        command.arg("--file").arg(&self.kwinrc).args(["--group", GROUP, "--key", key]);
        match value {
            Some(value) => command.arg(value),
            None => command.arg("--delete"),
        };
        let output = command
            .env("XDG_CONFIG_HOME", &self.config_home)
            .stdin(std::process::Stdio::null())
            .kill_on_drop(true)
            .output()
            .await
            .map_err(|e| OpError::failed(format!("running {}: {e}", self.kwriteconfig)))?;
        if output.status.success() {
            Ok(())
        } else {
            Err(OpError::failed(format!("{} failed: {}", self.kwriteconfig, String::from_utf8_lossy(&output.stderr).trim())))
        }
    }

    /// Tells KWin and waits until it reports `expected` (plugin, theme) as loaded. Theme None:
    /// only the plugin is compared (native plugins have no themes).
    async fn reload_and_check(&self, expected: Option<(&str, Option<&str>)>) -> OpResult<Applied> {
        let Some(bus) = self.bus().await else { return Ok(Applied::Saved) };
        bus.emit_signal(None::<&str>, "/KWin", "org.kde.KWin", "reloadConfig", &())
            .await
            .map_err(|e| OpError::failed(format!("reloadConfig: {e}")))?;
        let Some((plugin, theme)) = expected else { return Ok(Applied::Confirmed) };
        let mut last = None;
        for _ in 0..CHECK_ATTEMPTS {
            tokio::time::sleep(CHECK_INTERVAL).await;
            let reply = bus.call_method(Some("org.kde.KWin"), "/KWin", Some("org.kde.KWin"), "supportInformation", &()).await;
            let Ok(reply) = reply else { return Ok(Applied::Saved) };
            let Ok(support) = reply.body().deserialize::<String>() else { return Ok(Applied::Saved) };
            last = loaded_of(&support);
            if let Some((loaded_plugin, loaded_theme)) = &last {
                if loaded_plugin == plugin && theme.is_none_or(|t| t == loaded_theme) {
                    return Ok(Applied::Confirmed);
                }
            }
        }
        Err(OpError::failed(match last {
            Some((plugin, theme)) => format!("KWin uses {plugin} {theme} instead"),
            None => "KWin did not report its decoration".into(),
        }))
    }
}

impl Compositor for KWin {
    fn info(&self) -> CompositorInfo {
        CompositorInfo { name: NAME.into(), engines: self.engines.clone(), border_sizes: true }
    }

    fn read(&self) -> LocalBoxFuture<'_, OpResult<DecorationState>> {
        Box::pin(async move {
            match tokio::fs::read_to_string(&self.kwinrc).await {
                Ok(text) => Ok(state_of(&text)),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(state_of("")),
                Err(error) => Err(OpError::io("reading kwinrc", error)),
            }
        })
    }

    fn apply_theme(&self, theme: &ThemeId) -> LocalBoxFuture<'_, OpResult<Applied>> {
        let settings = settings_of(theme);
        Box::pin(async move {
            let (library, theme) = settings?;
            self.write("library", Some(&library)).await?;
            self.write("theme", theme.as_deref()).await?;
            self.write("NoPlugin", None).await?;
            self.reload_and_check(Some((&library, theme.as_deref()))).await
        })
    }

    fn apply_border_size(&self, size: BorderSize) -> LocalBoxFuture<'_, OpResult<Applied>> {
        Box::pin(async move {
            match border_value(size) {
                Some(value) => {
                    self.write("BorderSize", Some(value)).await?;
                    self.write("BorderSizeAuto", Some("false")).await?;
                }
                None => self.write("BorderSizeAuto", Some("true")).await?,
            }
            self.reload_and_check(None).await
        })
    }

    fn watch(self: Rc<Self>, changed: mpsc::UnboundedSender<()>) -> LocalBoxFuture<'static, ()> {
        Box::pin(async move {
            let watcher = match Watcher::new() {
                Ok(watcher) => watcher,
                Err(error) => {
                    eprintln!("maia-appearance-service: not watching kwinrc: {error}");
                    return;
                }
            };
            // kwinrc is saved by renaming a new file over it: watch its directory
            let dir = self.kwinrc.parent().map(Path::to_path_buf).unwrap_or_default();
            let _ = tokio::fs::create_dir_all(&dir).await;
            if !watcher.add_dir(&dir) {
                eprintln!("maia-appearance-service: cannot watch {}", dir.display());
                return;
            }
            loop {
                if watcher.next_burst(SETTLE, |name| name == "kwinrc").await.is_err() || changed.send(()).is_err() {
                    return;
                }
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn themes_map_to_kwinrc_and_back() {
        for id in ["aurorae-svg:XBoomer", "aurorae-qml:kwin4_decoration_qml_plastik", "kdecoration:org.kde.breeze"] {
            let id: ThemeId = id.parse().unwrap();
            let (library, theme) = settings_of(&id).unwrap();
            assert_eq!(theme_of(Some(&library), theme.as_deref(), false), Some(id));
        }
        assert_eq!(settings_of(&"aurorae-svg:X".parse().unwrap()).unwrap(), (AURORAE_V2.into(), Some("__aurorae__svg__X".into())));
        assert!(settings_of(&"wayfire:default".parse().unwrap()).is_err());
        // What KDE wrote with the old engine is the same SVG theme
        assert_eq!(theme_of(Some(AURORAE_V1), Some("__aurorae__svg__XBoomer"), false), Some("aurorae-svg:XBoomer".parse().unwrap()));
        assert_eq!(theme_of(None, None, false), Some("kdecoration:org.kde.breeze".parse().unwrap()));
        assert_eq!(theme_of(Some("org.kde.breeze"), None, true), None);
    }

    #[test]
    fn kwinrc_is_read() {
        let state = state_of("[org.kde.kdecoration2]\nlibrary=org.kde.kwin.aurorae.v2\ntheme=__aurorae__svg__Se7enAero\nBorderSize=Large\nBorderSizeAuto=false\n");
        assert_eq!(state.theme, Some("aurorae-svg:Se7enAero".parse().unwrap()));
        assert_eq!(state.border_size, BorderSize::Large);
        assert_eq!(state_of("").border_size, BorderSize::Theme);
    }

    #[test]
    fn the_support_information_tells_the_loaded_decoration() {
        let support = "Options\n=======\nPlugin: not this one\n\nDecoration\n==========\nPlugin: org.kde.kwin.aurorae.v2\nTheme: __aurorae__svg__XBoomer\nPlugin recommends border size: No\n\nLogicalOutput backend\n";
        assert_eq!(loaded_of(support), Some(("org.kde.kwin.aurorae.v2".into(), "__aurorae__svg__XBoomer".into())));
        assert_eq!(loaded_of("Decoration\n==========\nDecorations are disabled\n"), None);
    }
}

//! The user's rules of notifications, kept across sessions in
//! $MAIA_CONFIG_DIR/maia-notifications-service.json (named after the service, its only writer;
//! replaced as a whole): do not disturb, notifications on the lock
//! screen (the shells' business, kept here so every shell and the settings agree), and each
//! application on or off.
//!
//! The applications: those that have sent a notification (remembered) and those whose desktop entry
//! or .notifyrc declares it (desktop.rs, found again at every start). An application is known by
//! its desktop entry, or by the name it sends when it has none (notify-send).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::desktop::{Declared, Entry};

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct App {
    pub key: String,
    pub desktop_entry: String,
    pub app_name: String,
    pub app_icon: String,
    pub enabled: bool,
    pub sent: bool,
    pub declared: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Settings {
    pub dnd_enabled: bool,
    /// ms since 1970, 0 until turned off
    pub dnd_until: i64,
    pub lock_screen_notifications: bool,
    pub apps: BTreeMap<String, App>,
}

impl Default for Settings {
    fn default() -> Self {
        Settings { dnd_enabled: false, dnd_until: 0, lock_screen_notifications: true, apps: BTreeMap::new() }
    }
}

/// The most applications remembered (a program sending under ever new names cannot grow the file
/// without end); beyond it, applications that are on and not declared go
pub const MAX_APPS: usize = 500;

// --- On disk ---

#[derive(Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct FileDoNotDisturb {
    enabled: bool,
    until: i64,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
struct FileApp {
    key: String,
    desktop_entry: String,
    app_name: String,
    app_icon: String,
    enabled: bool,
    sent: bool,
}

impl Default for FileApp {
    fn default() -> Self {
        FileApp { key: String::new(), desktop_entry: String::new(), app_name: String::new(), app_icon: String::new(), enabled: true, sent: false }
    }
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
struct File {
    version: u32,
    do_not_disturb: FileDoNotDisturb,
    lock_screen_notifications: bool,
    apps: Vec<FileApp>,
}

impl Default for File {
    fn default() -> Self {
        File { version: 1, do_not_disturb: FileDoNotDisturb::default(), lock_screen_notifications: true, apps: Vec::new() }
    }
}

pub const FILE_NAME: &str = "maia-notifications-service.json";

/// $MAIA_NOTIFICATIONS_SETTINGS (tests), else $MAIA_CONFIG_DIR/maia-notifications-service.json, else
/// $XDG_CONFIG_HOME/maia/<version>/maia-notifications-service.json
pub fn default_path() -> PathBuf {
    if let Some(path) = std::env::var_os("MAIA_NOTIFICATIONS_SETTINGS").filter(|v| !v.is_empty()) {
        return PathBuf::from(path);
    }
    config_dir().join(FILE_NAME)
}

/// $MAIA_CONFIG_DIR, else $XDG_CONFIG_HOME/maia/<version>
fn config_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("MAIA_CONFIG_DIR").filter(|v| !v.is_empty()) {
        return PathBuf::from(dir);
    }
    let config_home = std::env::var_os("XDG_CONFIG_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config"));
    let version = option_env!("MAIA_VERSION").unwrap_or("dev");
    config_home.join("maia").join(version)
}

impl Settings {
    /// What the file says; nothing there (or a damaged file, reported) is the defaults
    pub fn load(path: &Path) -> Settings {
        let text = match std::fs::read_to_string(path) {
            Ok(text) => text,
            Err(error) => {
                if error.kind() != std::io::ErrorKind::NotFound {
                    eprintln!("maia-notifications-service: {}: {error}", path.display());
                }
                return Settings::default();
            }
        };
        match serde_json::from_str::<File>(&text) {
            Ok(file) => Settings::from_file(file),
            Err(error) => {
                eprintln!("maia-notifications-service: {}: {error}; the defaults instead", path.display());
                Settings::default()
            }
        }
    }

    fn from_file(file: File) -> Settings {
        let mut settings = Settings {
            dnd_enabled: file.do_not_disturb.enabled,
            dnd_until: if file.do_not_disturb.enabled { file.do_not_disturb.until.max(0) } else { 0 },
            lock_screen_notifications: file.lock_screen_notifications,
            apps: BTreeMap::new(),
        };
        for app in file.apps.into_iter().filter(|a| !a.key.is_empty()).take(MAX_APPS) {
            settings.apps.insert(
                app.key.clone(),
                App {
                    key: app.key,
                    desktop_entry: app.desktop_entry,
                    app_name: app.app_name,
                    app_icon: app.app_icon,
                    enabled: app.enabled,
                    sent: app.sent,
                    declared: false,
                },
            );
        }
        settings
    }

    /// The file's text: what is worth keeping (declared applications that are on are found again)
    pub fn to_json(&self) -> String {
        let file = File {
            version: 1,
            do_not_disturb: FileDoNotDisturb { enabled: self.dnd_enabled, until: self.dnd_until },
            lock_screen_notifications: self.lock_screen_notifications,
            apps: self
                .apps
                .values()
                .filter(|a| a.sent || !a.enabled)
                .map(|a| FileApp {
                    key: a.key.clone(),
                    desktop_entry: a.desktop_entry.clone(),
                    app_name: a.app_name.clone(),
                    app_icon: a.app_icon.clone(),
                    enabled: a.enabled,
                    sent: a.sent,
                })
                .collect(),
        };
        serde_json::to_string_pretty(&file).unwrap_or_default() + "\n"
    }

    /// Writes the file whole: a new file renamed over the old one, so a crash leaves one or the other
    pub fn save(text: &str, path: &Path) -> std::io::Result<()> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let temporary = path.with_extension("json.new");
        std::fs::write(&temporary, text)?;
        std::fs::rename(&temporary, path)
    }

    /// Who sends: its desktop entry, else its name; None for a notification that names nobody
    pub fn key_of(desktop_entry: &str, app_name: &str) -> Option<String> {
        let key = if desktop_entry.is_empty() { app_name.trim() } else { desktop_entry };
        (!key.is_empty()).then(|| key.to_string())
    }

    /// Whether the application's notifications are let through (unknown ones are)
    pub fn allows(&self, key: &str) -> bool {
        self.apps.get(key).is_none_or(|a| a.enabled)
    }

    /// An application sent a notification; true when that is news (the list changed). `entry`: its
    /// desktop entry, when it has one, names it
    pub fn sent(&mut self, key: &str, desktop_entry: &str, app_name: &str, app_icon: &str, entry: Option<&Entry>) -> bool {
        if let Some(app) = self.apps.get_mut(key) {
            if app.sent {
                return false;
            }
            app.sent = true;
            if app.app_name.is_empty() {
                app.app_name = app_name.to_string();
            }
            if app.app_icon.is_empty() {
                app.app_icon = app_icon.to_string();
            }
            return true;
        }
        let (name, icon) = match entry {
            Some(entry) if !entry.name.is_empty() => (entry.name.clone(), if entry.icon.is_empty() { app_icon.to_string() } else { entry.icon.clone() }),
            _ => (app_name.to_string(), app_icon.to_string()),
        };
        self.apps.insert(
            key.to_string(),
            App {
                key: key.to_string(),
                desktop_entry: desktop_entry.to_string(),
                app_name: if name.is_empty() { key.to_string() } else { name },
                app_icon: icon,
                enabled: true,
                sent: true,
                declared: false,
            },
        );
        self.trim();
        true
    }

    /// The declared applications found at start: added, and named by their desktop entries
    pub fn apply_declared(&mut self, declared: &[Declared]) -> bool {
        let before = self.apps.clone();
        for d in declared {
            let app = self.apps.entry(d.desktop_entry.clone()).or_insert_with(|| App {
                key: d.desktop_entry.clone(),
                desktop_entry: d.desktop_entry.clone(),
                enabled: true,
                ..Default::default()
            });
            app.declared = true;
            app.app_name = d.name.clone();
            if !d.icon.is_empty() {
                app.app_icon = d.icon.clone();
            }
        }
        self.apps != before
    }

    /// Remembered applications named by their desktop entries as they are now (an update renamed
    /// it, the language changed)
    pub fn apply_entries(&mut self, entries: &std::collections::HashMap<String, Entry>) -> bool {
        let mut changed = false;
        for app in self.apps.values_mut().filter(|a| !a.declared && !a.desktop_entry.is_empty()) {
            if let Some(entry) = entries.get(&app.desktop_entry) {
                if !entry.name.is_empty() && app.app_name != entry.name {
                    app.app_name = entry.name.clone();
                    changed = true;
                }
                if !entry.icon.is_empty() && app.app_icon != entry.icon {
                    app.app_icon = entry.icon.clone();
                    changed = true;
                }
            }
        }
        changed
    }

    /// Some(changed), None when no such application is listed
    pub fn set_enabled(&mut self, key: &str, enabled: bool) -> Option<bool> {
        let app = self.apps.get_mut(key)?;
        let changed = app.enabled != enabled;
        app.enabled = enabled;
        Some(changed)
    }

    /// Beyond MAX_APPS: applications that are on and not declared go, in key order
    fn trim(&mut self) {
        while self.apps.len() > MAX_APPS {
            let Some(key) = self.apps.values().find(|a| a.enabled && !a.declared).map(|a| a.key.clone()) else { break };
            self.apps.remove(&key);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn declared(id: &str, name: &str) -> Declared {
        Declared { desktop_entry: id.into(), name: name.into(), icon: format!("{id}-icon") }
    }

    #[test]
    fn the_defaults_without_a_file_and_with_a_damaged_one() {
        let dir = std::env::temp_dir().join(format!("maia-settings-load-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join(FILE_NAME);
        assert_eq!(Settings::load(&path), Settings::default());
        assert!(Settings::default().lock_screen_notifications);
        std::fs::write(&path, "{ not json").unwrap();
        assert_eq!(Settings::load(&path), Settings::default());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn what_is_kept_comes_back() {
        let dir = std::env::temp_dir().join(format!("maia-settings-save-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let path = dir.join("sub").join(FILE_NAME);
        let mut settings = Settings { dnd_enabled: true, dnd_until: 5000, lock_screen_notifications: false, ..Default::default() };
        settings.sent("org.mozilla.firefox", "org.mozilla.firefox", "Firefox", "firefox", None);
        settings.sent("notify-send", "", "notify-send", "", None);
        settings.apply_declared(&[declared("org.gnome.Calendar", "Calendar"), declared("org.kde.dolphin", "Dolphin")]);
        settings.set_enabled("org.kde.dolphin", false);
        Settings::save(&settings.to_json(), &path).unwrap();

        let back = Settings::load(&path);
        assert_eq!((back.dnd_enabled, back.dnd_until, back.lock_screen_notifications), (true, 5000, false));
        // A declared application that is on is found again at start, not kept
        let keys: Vec<&str> = back.apps.keys().map(String::as_str).collect();
        assert_eq!(keys, ["notify-send", "org.kde.dolphin", "org.mozilla.firefox"]);
        assert!(!back.allows("org.kde.dolphin"));
        assert!(back.allows("org.mozilla.firefox") && back.allows("someone new"));
        assert_eq!(back.apps["org.mozilla.firefox"].app_name, "Firefox");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn an_application_is_its_desktop_entry_or_its_name() {
        assert_eq!(Settings::key_of("org.kde.dolphin", "Dolphin").as_deref(), Some("org.kde.dolphin"));
        assert_eq!(Settings::key_of("", " notify-send ").as_deref(), Some("notify-send"));
        assert_eq!(Settings::key_of("", ""), None);
    }

    #[test]
    fn sending_is_news_once_and_a_desktop_entry_names_it() {
        let mut settings = Settings::default();
        let entry = Entry { name: "Pliki".into(), icon: "org.gnome.Nautilus".into(), ..Default::default() };
        assert!(settings.sent("org.gnome.Nautilus", "org.gnome.Nautilus", "nautilus", "", Some(&entry)));
        assert!(!settings.sent("org.gnome.Nautilus", "org.gnome.Nautilus", "nautilus", "", Some(&entry)));
        let app = &settings.apps["org.gnome.Nautilus"];
        assert_eq!((app.app_name.as_str(), app.app_icon.as_str(), app.sent, app.enabled), ("Pliki", "org.gnome.Nautilus", true, true));
        // Declared first, then sent: still one, now both
        settings.apply_declared(&[declared("org.gnome.Calendar", "Calendar")]);
        assert!(settings.sent("org.gnome.Calendar", "org.gnome.Calendar", "gnome-calendar", "", None));
        let app = &settings.apps["org.gnome.Calendar"];
        assert!(app.sent && app.declared && app.app_name == "Calendar");
    }

    #[test]
    fn only_listed_applications_can_be_turned_off() {
        let mut settings = Settings::default();
        assert_eq!(settings.set_enabled("nobody", false), None);
        settings.sent("a", "", "a", "", None);
        assert_eq!(settings.set_enabled("a", false), Some(true));
        assert_eq!(settings.set_enabled("a", false), Some(false));
        assert!(!settings.allows("a"));
    }

    #[test]
    fn a_flood_of_names_does_not_grow_the_list_without_end() {
        let mut settings = Settings::default();
        settings.sent("kept", "", "kept", "", None);
        settings.set_enabled("kept", false);
        for i in 0..(MAX_APPS + 50) {
            settings.sent(&format!("spam {i:04}"), "", "spam", "", None);
        }
        assert_eq!(settings.apps.len(), MAX_APPS);
        // Turned off is a choice of the user: it stays
        assert!(!settings.allows("kept"));
    }
}

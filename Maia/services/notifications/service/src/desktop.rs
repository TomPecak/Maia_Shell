//! Applications as their desktop entries say: the name and icon of a desktop entry (for jobs and
//! for the settings' list), and which applications declare that they send notifications.
//!
//! Declared: a desktop entry with X-GNOME-UsesNotifications=true (what GNOME's settings list), or
//! a KDE .notifyrc (knotifications6/) whose [Global] names its DesktopEntry. Read from the data
//! directories ($XDG_DATA_HOME, then $XDG_DATA_DIRS), the first one winning for an id; names in the
//! session's language (Name[pl] before Name). These are a few hundred small files: read once, on a
//! blocking thread.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// What a desktop entry says about its application
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Entry {
    pub name: String,
    pub icon: String,
    pub uses_notifications: bool,
    /// Hidden from menus (NoDisplay, Hidden): not offered as a declared sender
    pub hidden: bool,
}

/// An application that declares notifications
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Declared {
    pub desktop_entry: String,
    pub name: String,
    pub icon: String,
}

/// The data directories, as the session sets them
pub fn data_dirs() -> Vec<PathBuf> {
    let mut dirs: Vec<PathBuf> = Vec::new();
    let home = std::env::var_os("XDG_DATA_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share")));
    dirs.extend(home);
    let system = std::env::var("XDG_DATA_DIRS").ok().filter(|v| !v.is_empty()).unwrap_or_else(|| "/usr/local/share:/usr/share".into());
    for dir in system.split(':').filter(|d| !d.is_empty()).map(PathBuf::from) {
        if !dirs.contains(&dir) {
            dirs.push(dir);
        }
    }
    dirs
}

/// The session's languages for localized keys, the preferred first: $LANGUAGE ("pl_PL:en"), then
/// $LC_ALL, $LC_MESSAGES, $LANG; "pl_PL.UTF-8" gives "pl_PL" and "pl"
pub fn languages() -> Vec<String> {
    let get = |name: &str| std::env::var(name).ok().filter(|v| !v.is_empty());
    let locale = ["LC_ALL", "LC_MESSAGES", "LANG"].iter().find_map(|v| get(v)).unwrap_or_default();
    let mut values: Vec<String> = Vec::new();
    // LANGUAGE counts unless the locale is C (as gettext has it)
    if !matches!(locale.as_str(), "" | "C" | "POSIX") {
        values.extend(get("LANGUAGE").unwrap_or_default().split(':').map(str::to_string));
    }
    values.push(locale);
    languages_of(&values)
}

fn languages_of(values: &[String]) -> Vec<String> {
    let mut list: Vec<String> = Vec::new();
    for value in values {
        let locale = value.split(['.', '@']).next().unwrap_or("");
        if locale.is_empty() || locale == "C" || locale == "POSIX" {
            continue;
        }
        let language = locale.split('_').next().unwrap_or(locale);
        for candidate in [locale, language] {
            if !list.iter().any(|l| l == candidate) {
                list.push(candidate.to_string());
            }
        }
    }
    list
}

/// One key of a group: Key[pl_PL], Key[pl], then Key
fn localized(values: &HashMap<String, String>, key: &str, languages: &[String]) -> String {
    for language in languages {
        if let Some(value) = values.get(&format!("{key}[{language}]")) {
            return value.clone();
        }
    }
    values.get(key).cloned().unwrap_or_default()
}

/// The keys of one [group] of an ini-like file (desktop entries, .notifyrc)
fn group(text: &str, name: &str) -> HashMap<String, String> {
    let mut values = HashMap::new();
    let mut inside = false;
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            inside = line == format!("[{name}]");
        } else if inside && !line.starts_with('#') {
            if let Some((key, value)) = line.split_once('=') {
                values.insert(key.trim().to_string(), value.trim().to_string());
            }
        }
    }
    values
}

pub fn parse_entry(text: &str, languages: &[String]) -> Entry {
    let values = group(text, "Desktop Entry");
    let yes = |key: &str| values.get(key).is_some_and(|v| v == "true");
    Entry {
        name: localized(&values, "Name", languages),
        icon: values.get("Icon").cloned().unwrap_or_default(),
        uses_notifications: yes("X-GNOME-UsesNotifications"),
        hidden: yes("NoDisplay") || yes("Hidden"),
    }
}

/// The desktop entry `id` (without .desktop), from the first directory that has it
pub fn find(dirs: &[PathBuf], id: &str, languages: &[String]) -> Option<Entry> {
    if id.is_empty() || id.contains('/') {
        return None;
    }
    dirs.iter().find_map(|dir| {
        let text = std::fs::read_to_string(dir.join("applications").join(format!("{id}.desktop"))).ok()?;
        Some(parse_entry(&text, languages))
    })
}

/// Every desktop entry by its id (the first directory wins)
pub fn index(dirs: &[PathBuf], languages: &[String]) -> HashMap<String, Entry> {
    let mut entries = HashMap::new();
    for dir in dirs {
        for (id, path) in files(&dir.join("applications"), "desktop") {
            if !entries.contains_key(&id) {
                if let Ok(text) = std::fs::read_to_string(&path) {
                    entries.insert(id, parse_entry(&text, languages));
                }
            }
        }
    }
    entries
}

/// The applications that declare notifications; `entries`: the index of desktop entries
pub fn declared(dirs: &[PathBuf], entries: &HashMap<String, Entry>, languages: &[String]) -> Vec<Declared> {
    let mut found: HashMap<String, Declared> = HashMap::new();
    for (id, entry) in entries {
        if entry.uses_notifications && !entry.hidden {
            found.insert(id.clone(), Declared { desktop_entry: id.clone(), name: entry.name.clone(), icon: entry.icon.clone() });
        }
    }
    for dir in dirs {
        for (_, path) in files(&dir.join("knotifications6"), "notifyrc") {
            let Ok(text) = std::fs::read_to_string(&path) else { continue };
            let global = group(&text, "Global");
            let Some(id) = global.get("DesktopEntry").map(|e| e.trim_end_matches(".desktop").to_string()) else { continue };
            if id.is_empty() || found.contains_key(&id) {
                continue;
            }
            // Its desktop entry names it best; else the .notifyrc's own name
            let (name, icon) = match entries.get(&id) {
                Some(entry) if entry.hidden => continue,
                Some(entry) => (entry.name.clone(), entry.icon.clone()),
                None => (localized(&global, "Name", languages), global.get("IconName").cloned().unwrap_or_default()),
            };
            if name.is_empty() {
                continue;
            }
            found.insert(id.clone(), Declared { desktop_entry: id, name, icon });
        }
    }
    let mut list: Vec<Declared> = found.into_values().collect();
    list.sort_by(|a, b| a.desktop_entry.cmp(&b.desktop_entry));
    list
}

/// Files with `extension` in `dir` and one level below (applications/kde/x.desktop has the id
/// kde-x), with their ids
fn files(dir: &Path, extension: &str) -> Vec<(String, PathBuf)> {
    let mut list = Vec::new();
    let Ok(read) = std::fs::read_dir(dir) else { return list };
    for item in read.flatten() {
        let path = item.path();
        if path.is_dir() {
            let prefix = item.file_name().to_string_lossy().to_string();
            for (id, inner) in files_flat(&path, extension) {
                list.push((format!("{prefix}-{id}"), inner));
            }
        } else if path.extension().is_some_and(|e| e == extension) {
            if let Some(stem) = path.file_stem() {
                list.push((stem.to_string_lossy().to_string(), path));
            }
        }
    }
    list
}

fn files_flat(dir: &Path, extension: &str) -> Vec<(String, PathBuf)> {
    let Ok(read) = std::fs::read_dir(dir) else { return Vec::new() };
    read.flatten()
        .map(|item| item.path())
        .filter(|path| path.is_file() && path.extension().is_some_and(|e| e == extension))
        .filter_map(|path| Some((path.file_stem()?.to_string_lossy().to_string(), path)))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("maia-desktop-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("applications")).unwrap();
        std::fs::create_dir_all(dir.join("knotifications6")).unwrap();
        dir
    }

    fn write(dir: &Path, path: &str, text: &str) {
        std::fs::write(dir.join(path), text).unwrap();
    }

    #[test]
    fn languages_the_preferred_first() {
        let values = |list: &[&str]| list.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(languages_of(&values(&["de_DE", "en", "pl_PL.UTF-8"])), ["de_DE", "de", "en", "pl_PL", "pl"]);
        assert_eq!(languages_of(&values(&["pl_PL.UTF-8", "pl_PL.UTF-8"])), ["pl_PL", "pl"]);
        assert!(languages_of(&values(&["C", ""])).is_empty());
    }

    #[test]
    fn a_name_in_the_sessions_language() {
        let text = "[Desktop Entry]\nName=Files\nName[pl]=Pliki\nIcon=org.gnome.Nautilus\n[Desktop Action new]\nName=New window\n";
        let entry = parse_entry(text, &["pl_PL".into(), "pl".into()]);
        assert_eq!((entry.name.as_str(), entry.icon.as_str()), ("Pliki", "org.gnome.Nautilus"));
        assert_eq!(parse_entry(text, &[]).name, "Files");
    }

    #[test]
    fn declared_by_desktop_entries_and_notifyrc_files() {
        let dir = temp("declared");
        write(&dir, "applications/org.gnome.Calendar.desktop", "[Desktop Entry]\nName=Calendar\nIcon=calendar\nX-GNOME-UsesNotifications=true\n");
        write(&dir, "applications/org.kde.dolphin.desktop", "[Desktop Entry]\nName=Dolphin\nIcon=system-file-manager\n");
        write(&dir, "applications/hidden.desktop", "[Desktop Entry]\nName=Hidden\nNoDisplay=true\nX-GNOME-UsesNotifications=true\n");
        write(&dir, "applications/plain.desktop", "[Desktop Entry]\nName=Plain\n");
        write(&dir, "knotifications6/dolphin.notifyrc", "[Global]\nDesktopEntry=org.kde.dolphin\nName=Dolphin notifications\n");
        write(&dir, "knotifications6/kdeconnect.notifyrc", "[Global]\nDesktopEntry=org.kde.kdeconnect.app\nName=KDE Connect\nIconName=kdeconnect\n");
        write(&dir, "knotifications6/kded.notifyrc", "[Global]\nName=Background services\n");
        let dirs = vec![dir.clone()];
        let entries = index(&dirs, &[]);
        let list = declared(&dirs, &entries, &[]);
        let ids: Vec<&str> = list.iter().map(|d| d.desktop_entry.as_str()).collect();
        assert_eq!(ids, ["org.gnome.Calendar", "org.kde.dolphin", "org.kde.kdeconnect.app"]);
        // A desktop entry names it best
        assert_eq!(list[1].name, "Dolphin");
        assert_eq!((list[2].name.as_str(), list[2].icon.as_str()), ("KDE Connect", "kdeconnect"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_first_directory_wins_and_subdirectories_prefix_the_id() {
        let user = temp("user");
        let system = temp("system");
        write(&user, "applications/app.desktop", "[Desktop Entry]\nName=Mine\n");
        write(&system, "applications/app.desktop", "[Desktop Entry]\nName=System\n");
        std::fs::create_dir_all(system.join("applications/kde")).unwrap();
        write(&system, "applications/kde/old.desktop", "[Desktop Entry]\nName=Old\n");
        let dirs = vec![user.clone(), system.clone()];
        assert_eq!(find(&dirs, "app", &[]).unwrap().name, "Mine");
        let entries = index(&dirs, &[]);
        assert_eq!(entries["app"].name, "Mine");
        assert_eq!(entries["kde-old"].name, "Old");
        assert!(find(&dirs, "../app", &[]).is_none());
        let _ = std::fs::remove_dir_all(&user);
        let _ = std::fs::remove_dir_all(&system);
    }
}

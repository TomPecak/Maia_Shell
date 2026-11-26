//! Which application an item belongs to, by the desktop entries of the system.
//!
//! An item says little about its application: its Id is often the application's name
//! ("org.kde.konversation", "steam", "TelegramDesktop", the X11 class of an XEmbed icon), but
//! Chromium and Electron call every item "chrome_status_icon_1". So the service also asks who owns
//! the item's D-Bus connection: the Flatpak application id of a sandboxed process
//! (/proc/<pid>/root/.flatpak-info), the program (/proc/<pid>/exe). These are matched against the
//! desktop entries: their id, StartupWMClass and the program of Exec.
//!
//! The desktop entries are read once, at start, on a blocking thread (a few hundred small files).

use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// What a desktop entry says about its application
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Entry {
    pub id: String,
    pub name: String,
    pub icon: String,
    /// StartupWMClass, lower case
    pub wm_class: String,
    /// The program of Exec, its file name in lower case ("signal-desktop")
    pub program: String,
}

/// What is known of an item's process
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Process {
    pub flatpak_id: String,
    /// The file name of its program ("telegram-desktop")
    pub program: String,
}

/// All desktop entries, and keys that find them
#[derive(Debug, Default)]
pub struct Apps {
    entries: HashMap<String, Entry>,
    /// A lower-case key → an id, by how sure the key is (0 = the id itself)
    keys: [HashMap<String, String>; 4],
}

/// The last part of a reverse-DNS id that names nothing on its own ("org.telegram.desktop")
const GENERIC_PARTS: [&str; 6] = ["desktop", "app", "application", "client", "gui", "qt"];

impl Apps {
    pub fn from_entries(list: Vec<Entry>) -> Apps {
        let mut apps = Apps::default();
        for entry in list {
            let id = entry.id.clone();
            let mut add = |rank: usize, key: &str| {
                if !key.is_empty() {
                    apps.keys[rank].entry(key.to_lowercase()).or_insert_with(|| id.clone());
                }
            };
            add(0, &entry.id);
            add(1, &entry.wm_class);
            add(2, &entry.program);
            if let Some(last) = entry.id.rsplit('.').next().filter(|_| entry.id.contains('.')) {
                if !GENERIC_PARTS.contains(&last.to_lowercase().as_str()) {
                    add(3, last);
                }
            }
            apps.entries.entry(entry.id.clone()).or_insert(entry);
        }
        apps
    }

    pub fn get(&self, id: &str) -> Option<&Entry> {
        self.entries.get(id)
    }

    /// The entry of an item with the Id `item_id` in `process`
    pub fn find(&self, item_id: &str, process: &Process) -> Option<&Entry> {
        if let Some(entry) = self.entries.get(&process.flatpak_id) {
            return Some(entry);
        }
        // A program that runs many applications says nothing about which
        let program = match process.program.as_str() {
            "python3" | "python" | "java" | "electron" | "node" | "wine" | "wine64" | "wine-preloader" | "wine64-preloader"
            | "xembedsniproxy" | "bash" | "sh" | "perl" | "mono" => "",
            program => program,
        };
        let item_id = if item_id.starts_with("chrome_status_icon_") { "" } else { item_id };
        for candidate in [item_id, program] {
            if candidate.is_empty() {
                continue;
            }
            if let Some(entry) = self.entries.get(candidate) {
                return Some(entry);
            }
            let key = candidate.to_lowercase();
            if let Some(entry) = self.keys.iter().find_map(|keys| keys.get(&key)).and_then(|id| self.entries.get(id)) {
                return Some(entry);
            }
        }
        None
    }
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

/// The session's languages for localized keys, the preferred first: $LANGUAGE, then $LC_ALL,
/// $LC_MESSAGES, $LANG; "pl_PL.UTF-8" gives "pl_PL" and "pl"
pub fn languages() -> Vec<String> {
    let get = |name: &str| std::env::var(name).ok().filter(|v| !v.is_empty());
    let locale = ["LC_ALL", "LC_MESSAGES", "LANG"].iter().find_map(|v| get(v)).unwrap_or_default();
    let mut values: Vec<String> = Vec::new();
    if !matches!(locale.as_str(), "" | "C" | "POSIX") {
        values.extend(get("LANGUAGE").unwrap_or_default().split(':').map(str::to_string));
    }
    values.push(locale);
    let mut list: Vec<String> = Vec::new();
    for value in &values {
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

/// The keys of the [Desktop Entry] group
fn desktop_group(text: &str) -> HashMap<String, String> {
    let mut values = HashMap::new();
    let mut inside = false;
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            inside = line == "[Desktop Entry]";
        } else if inside && !line.starts_with('#') {
            if let Some((key, value)) = line.split_once('=') {
                values.insert(key.trim().to_string(), value.trim().to_string());
            }
        }
    }
    values
}

/// The words of Exec; a "quoted word" may contain spaces
fn exec_words(exec: &str) -> Vec<String> {
    let mut words = Vec::new();
    let mut word = String::new();
    let mut quoted = false;
    for c in exec.chars() {
        match c {
            '"' => quoted = !quoted,
            c if c.is_whitespace() && !quoted => {
                if !word.is_empty() {
                    words.push(std::mem::take(&mut word));
                }
            }
            c => word.push(c),
        }
    }
    if !word.is_empty() {
        words.push(word);
    }
    words
}

/// The program Exec starts, without env, flatpak run and the like: its file name in lower case
fn program_of(exec: &str) -> String {
    let words = exec_words(exec);
    let mut rest = &words[..];
    while let Some((first, tail)) = rest.split_first() {
        let name = first.rsplit('/').next().unwrap_or(first);
        if name == "env" || first.contains('=') {
            rest = tail;
            continue;
        }
        if name == "flatpak" {
            // flatpak run [options] <app id>: the id names the application
            return tail.iter().find(|w| !w.starts_with('-') && w.as_str() != "run").map(|w| w.to_lowercase()).unwrap_or_default();
        }
        return name.to_lowercase();
    }
    String::new()
}

/// A desktop entry; None when it is not an application the user sees
pub fn parse_entry(id: &str, text: &str, languages: &[String]) -> Option<Entry> {
    let values = desktop_group(text);
    if values.get("Type").is_some_and(|t| t != "Application") || values.get("Hidden").is_some_and(|v| v == "true") {
        return None;
    }
    let name = languages
        .iter()
        .find_map(|l| values.get(&format!("Name[{l}]")))
        .or_else(|| values.get("Name"))
        .cloned()
        .unwrap_or_default();
    Some(Entry {
        id: id.to_string(),
        name,
        icon: values.get("Icon").cloned().unwrap_or_default(),
        wm_class: values.get("StartupWMClass").map(|c| c.to_lowercase()).unwrap_or_default(),
        program: values.get("Exec").map(|e| program_of(e)).unwrap_or_default(),
    })
}

/// Every desktop entry of `dirs`, the first directory winning for an id. Blocking.
pub fn read_apps(dirs: &[PathBuf], languages: &[String]) -> Apps {
    let mut list = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for dir in dirs {
        for (id, path) in files(&dir.join("applications")) {
            if !seen.insert(id.clone()) {
                continue;
            }
            if let Some(entry) = std::fs::read_to_string(&path).ok().and_then(|text| parse_entry(&id, &text, languages)) {
                list.push(entry);
            }
        }
    }
    Apps::from_entries(list)
}

/// .desktop files in `dir` and one level below (applications/kde/x.desktop has the id kde-x)
fn files(dir: &Path) -> Vec<(String, PathBuf)> {
    let mut list = Vec::new();
    let Ok(read) = std::fs::read_dir(dir) else { return list };
    for item in read.flatten() {
        let path = item.path();
        if path.is_dir() {
            let prefix = item.file_name().to_string_lossy().to_string();
            if let Ok(inner) = std::fs::read_dir(&path) {
                for file in inner.flatten().map(|f| f.path()) {
                    if file.extension().is_some_and(|e| e == "desktop") {
                        if let Some(stem) = file.file_stem() {
                            list.push((format!("{prefix}-{}", stem.to_string_lossy()), file));
                        }
                    }
                }
            }
        } else if path.extension().is_some_and(|e| e == "desktop") {
            if let Some(stem) = path.file_stem() {
                list.push((stem.to_string_lossy().to_string(), path));
            }
        }
    }
    list
}

/// What /proc says of a process. Blocking (a few small reads).
pub fn process(pid: u32) -> Process {
    let root = PathBuf::from(format!("/proc/{pid}"));
    let program = std::fs::read_link(root.join("exe"))
        .ok()
        .and_then(|exe| exe.file_name().map(|n| n.to_string_lossy().to_lowercase()))
        // A deleted program after an update: "telegram-desktop (deleted)"
        .map(|n| n.trim_end_matches(" (deleted)").to_string())
        .unwrap_or_default();
    let flatpak_id = std::fs::read_to_string(root.join("root/.flatpak-info")).map(|text| flatpak_id(&text)).unwrap_or_default();
    Process { flatpak_id, program }
}

/// name= of the [Application] group of a .flatpak-info
fn flatpak_id(text: &str) -> String {
    let mut inside = false;
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            inside = line == "[Application]";
        } else if inside {
            if let Some(name) = line.strip_prefix("name=") {
                return name.trim().to_string();
            }
        }
    }
    String::new()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(id: &str, text: &str) -> Entry {
        parse_entry(id, text, &[]).unwrap()
    }

    fn apps() -> Apps {
        Apps::from_entries(vec![
            entry("org.kde.konversation", "[Desktop Entry]\nType=Application\nName=Konversation\nIcon=konversation\nExec=konversation -qwindowtitle %c\n"),
            entry("org.telegram.desktop", "[Desktop Entry]\nName=Telegram\nIcon=org.telegram.desktop\nExec=telegram-desktop -- %u\nStartupWMClass=TelegramDesktop\n"),
            entry("signal-desktop", "[Desktop Entry]\nName=Signal\nExec=env BAMF_DESKTOP_FILE_HINT=x /opt/Signal/signal-desktop --no-sandbox %U\n"),
            entry("steam", "[Desktop Entry]\nName=Steam\nExec=/usr/bin/steam %U\n"),
            entry("com.discordapp.Discord", "[Desktop Entry]\nName=Discord\nExec=flatpak run --branch=stable --command=com.discordapp.Discord com.discordapp.Discord\n"),
        ])
    }

    fn process(program: &str) -> Process {
        Process { flatpak_id: String::new(), program: program.into() }
    }

    #[test]
    fn exec_names_the_program() {
        assert_eq!(program_of("env A=1 /opt/Signal/signal-desktop --no-sandbox %U"), "signal-desktop");
        assert_eq!(program_of("\"/opt/My App/app\" %f"), "app");
        assert_eq!(program_of("flatpak run --branch=stable org.gimp.GIMP"), "org.gimp.gimp");
        assert_eq!(program_of(""), "");
    }

    #[test]
    fn items_find_their_applications() {
        let apps = apps();
        let id = |item: &str, p: &Process| apps.find(item, p).map(|e| e.id.clone()).unwrap_or_default();
        assert_eq!(id("org.kde.konversation", &process("")), "org.kde.konversation");
        assert_eq!(id("konversation", &process("")), "org.kde.konversation");
        assert_eq!(id("TelegramDesktop", &process("")), "org.telegram.desktop");
        assert_eq!(id("chrome_status_icon_1", &process("signal-desktop")), "signal-desktop");
        assert_eq!(id("steam", &process("steam")), "steam");
        let sandboxed = Process { flatpak_id: "com.discordapp.Discord".into(), program: "xdg-dbus-proxy".into() };
        assert_eq!(id("chrome_status_icon_1", &sandboxed), "com.discordapp.Discord");
        assert_eq!(id("chrome_status_icon_1", &process("electron")), "");
        // "desktop" of org.telegram.desktop names nothing
        assert_eq!(id("desktop", &process("")), "");
    }

    #[test]
    fn hidden_entries_and_other_types_are_left_out() {
        assert!(parse_entry("a", "[Desktop Entry]\nType=Link\nName=A\n", &[]).is_none());
        assert!(parse_entry("a", "[Desktop Entry]\nHidden=true\nName=A\n", &[]).is_none());
        let named = parse_entry("a", "[Desktop Entry]\nName=Files\nName[pl]=Pliki\n", &["pl".into()]).unwrap();
        assert_eq!(named.name, "Pliki");
    }

    #[test]
    fn flatpak_info_names_the_application() {
        assert_eq!(flatpak_id("[Application]\nname=org.signal.Signal\nruntime=x\n[Instance]\nname=other\n"), "org.signal.Signal");
        assert_eq!(flatpak_id("[Instance]\nname=x\n"), "");
    }

    #[test]
    fn this_process_is_read() {
        let me = super::process(std::process::id());
        assert!(!me.program.is_empty());
        assert_eq!(me.flatpak_id, "");
    }
}

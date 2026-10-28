//! Which application a window belongs to.
//!
//! The compositor only says what the window reported about itself (Wayland app_id, X11 resource
//! name) and its pid. The application (name, icon, how to start it again) comes from desktop
//! entries (.desktop files in $XDG_DATA_HOME/applications and $XDG_DATA_DIRS/*/applications).
//! This is what TaskTools::windowUrlFromMetadata does in KDE's libtaskmanager, in a simpler form.
//!
//! Matching, first hit wins:
//!   1. desktop entry id == app id            ("org.kde.konsole" -> org.kde.konsole.desktop)
//!   2. StartupWMClass == app id or resource name
//!   3. desktop entry id == resource name
//!   4. reverse-DNS id ending with the app id ("konsole" -> org.kde.konsole.desktop)
//!   5. the program of the process (/proc/<pid>/exe) == the program in Exec=
//! When nothing matches, the entries are read again (an application may have just been installed),
//! at most every few seconds.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct AppInfo {
    /// Desktop entry id, e.g. "org.kde.konsole.desktop"
    pub desktop_id: String,
    /// Name=, localized
    pub name: String,
    /// GenericName=, localized
    pub generic_name: String,
    /// Icon= (theme icon name or absolute path)
    pub icon: String,
    /// Exec= (with field codes, see launch.rs)
    pub exec: String,
}

impl AppInfo {
    /// The launcher URL in the form used by Plasma: "applications:org.kde.konsole.desktop"
    pub fn launcher_url(&self) -> String {
        format!("applications:{}", self.desktop_id)
    }
}

struct Entry {
    info: AppInfo,
    /// StartupWMClass=, lowercase
    wm_class: String,
    /// File name of the program in Exec=, lowercase
    program: String,
}

pub struct AppIndex {
    dirs: Vec<PathBuf>,
    locales: Vec<String>,
    entries: Vec<Entry>,
    by_id: HashMap<String, usize>,
    by_wm_class: HashMap<String, usize>,
    by_program: HashMap<String, usize>,
    scanned_at: Instant,
}

const RESCAN_INTERVAL: Duration = Duration::from_secs(5);

impl AppIndex {
    /// Desktop entry directories and the language of the session from the environment
    pub fn from_environment() -> Self {
        let mut dirs = Vec::new();
        let data_home = std::env::var("XDG_DATA_HOME")
            .ok()
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
            .or_else(|| std::env::var("HOME").ok().map(|home| Path::new(&home).join(".local/share")));
        dirs.extend(data_home);
        let data_dirs = std::env::var("XDG_DATA_DIRS")
            .ok()
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| "/usr/local/share:/usr/share".into());
        dirs.extend(data_dirs.split(':').filter(|d| !d.is_empty()).map(PathBuf::from));
        let dirs = dirs.into_iter().map(|d| d.join("applications")).collect();

        let locale = ["LC_ALL", "LC_MESSAGES", "LANG"]
            .iter()
            .filter_map(|name| std::env::var(name).ok())
            .find(|v| !v.is_empty())
            .unwrap_or_default();
        Self::new(dirs, &locale)
    }

    /// `dirs` are "applications" directories in order of precedence; `locale` e.g. "pl_PL.UTF-8"
    pub fn new(dirs: Vec<PathBuf>, locale: &str) -> Self {
        let mut index = AppIndex {
            dirs,
            locales: locale_variants(locale),
            entries: Vec::new(),
            by_id: HashMap::new(),
            by_wm_class: HashMap::new(),
            by_program: HashMap::new(),
            scanned_at: Instant::now(),
        };
        index.rescan();
        index
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Reads all desktop entries again
    pub fn rescan(&mut self) {
        self.entries.clear();
        self.by_id.clear();
        self.by_wm_class.clear();
        self.by_program.clear();
        for dir in self.dirs.clone() {
            self.scan_dir(&dir, &dir);
        }
        self.scanned_at = Instant::now();
    }

    fn scan_dir(&mut self, root: &Path, dir: &Path) {
        let Ok(read) = std::fs::read_dir(dir) else { return };
        let mut paths: Vec<PathBuf> = read.filter_map(|e| e.ok().map(|e| e.path())).collect();
        paths.sort();
        for path in paths {
            if path.is_dir() {
                self.scan_dir(root, &path);
                continue;
            }
            if path.extension().is_none_or(|ext| ext != "desktop") {
                continue;
            }
            // The id of a file in a subdirectory: "kde/konsole.desktop" -> "kde-konsole.desktop"
            let Ok(relative) = path.strip_prefix(root) else { continue };
            let id = relative.to_string_lossy().replace('/', "-");
            // An entry of a directory with higher precedence hides the same id in the others
            if self.by_id.contains_key(&id_key(&id)) {
                continue;
            }
            let Ok(text) = std::fs::read_to_string(&path) else { continue };
            if let Some(entry) = parse_entry(&id, &text, &self.locales) {
                self.add(entry);
            }
        }
    }

    fn add(&mut self, entry: Entry) {
        let index = self.entries.len();
        self.by_id.insert(id_key(&entry.info.desktop_id), index);
        if !entry.wm_class.is_empty() {
            self.by_wm_class.entry(entry.wm_class.clone()).or_insert(index);
        }
        if !entry.program.is_empty() {
            self.by_program.entry(entry.program.clone()).or_insert(index);
        }
        self.entries.push(entry);
    }

    /// The application of a window (see the order at the top of the file)
    pub fn identify(&mut self, app_id: &str, resource_name: &str, pid: u32) -> Option<AppInfo> {
        if let Some(app) = self.lookup(app_id, resource_name, pid) {
            return Some(app);
        }
        if self.scanned_at.elapsed() >= RESCAN_INTERVAL {
            self.rescan();
            return self.lookup(app_id, resource_name, pid);
        }
        None
    }

    fn lookup(&self, app_id: &str, resource_name: &str, pid: u32) -> Option<AppInfo> {
        let app_id = id_key(app_id);
        let resource_name = resource_name.to_lowercase();
        let found = (!app_id.is_empty())
            .then(|| self.by_id.get(&app_id).or_else(|| self.by_wm_class.get(&app_id)))
            .flatten()
            .or_else(|| (!resource_name.is_empty()).then(|| self.by_wm_class.get(&resource_name)).flatten())
            .or_else(|| (!resource_name.is_empty()).then(|| self.by_id.get(&resource_name)).flatten())
            .copied()
            .or_else(|| self.reverse_dns(&app_id))
            .or_else(|| program_of(pid).and_then(|program| self.by_program.get(&program).copied()));
        found.map(|i| self.entries[i].info.clone())
    }

    /// "konsole" -> "org.kde.konsole.desktop"
    fn reverse_dns(&self, app_id: &str) -> Option<usize> {
        if app_id.is_empty() || app_id.contains('.') {
            return None;
        }
        let suffix = format!(".{app_id}");
        self.entries.iter().position(|e| id_key(&e.info.desktop_id).ends_with(&suffix))
    }

    /// The application of a launcher URL: "applications:<id>" or "file:///path/to/<id>"
    pub fn by_launcher_url(&self, url: &str) -> Option<AppInfo> {
        let id = url
            .strip_prefix("applications:")
            .or_else(|| url.strip_prefix("file://").and_then(|path| Path::new(path).file_name()?.to_str()))?;
        self.by_id.get(&id_key(id)).map(|&i| self.entries[i].info.clone())
    }
}

/// Key for comparing ids: lowercase, without ".desktop"
fn id_key(id: &str) -> String {
    let id = id.to_lowercase();
    id.strip_suffix(".desktop").map(str::to_string).unwrap_or(id)
}

/// "pl_PL.UTF-8@euro" -> ["pl_PL@euro", "pl_PL", "pl@euro", "pl"] (the lookup order of the spec)
fn locale_variants(locale: &str) -> Vec<String> {
    let (base, modifier) = match locale.split_once('@') {
        Some((base, modifier)) => (base, Some(modifier)),
        None => (locale, None),
    };
    let base = base.split('.').next().unwrap_or("");
    if base.is_empty() || base == "C" || base == "POSIX" {
        return Vec::new();
    }
    let (lang, country) = match base.split_once('_') {
        Some((lang, country)) => (lang, Some(country)),
        None => (base, None),
    };
    let mut variants = Vec::new();
    if let (Some(country), Some(modifier)) = (country, modifier) {
        variants.push(format!("{lang}_{country}@{modifier}"));
    }
    if let Some(country) = country {
        variants.push(format!("{lang}_{country}"));
    }
    if let Some(modifier) = modifier {
        variants.push(format!("{lang}@{modifier}"));
    }
    variants.push(lang.to_string());
    variants
}

/// The [Desktop Entry] group of an application; None for hidden entries and other types
fn parse_entry(id: &str, text: &str, locales: &[String]) -> Option<Entry> {
    let mut in_group = false;
    let mut values: HashMap<String, String> = HashMap::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') {
            in_group = line == "[Desktop Entry]";
            continue;
        }
        if !in_group {
            continue;
        }
        if let Some((key, value)) = line.split_once('=') {
            values.entry(key.trim().to_string()).or_insert_with(|| unescape(value.trim()));
        }
    }
    if values.get("Type").map(String::as_str) != Some("Application") || values.get("Hidden").is_some_and(|v| v == "true") {
        return None;
    }
    let localized = |key: &str| {
        locales
            .iter()
            .find_map(|locale| values.get(&format!("{key}[{locale}]")))
            .or_else(|| values.get(key))
            .cloned()
            .unwrap_or_default()
    };
    let exec = values.get("Exec").cloned().unwrap_or_default();
    Some(Entry {
        info: AppInfo {
            desktop_id: id.to_string(),
            name: localized("Name"),
            generic_name: localized("GenericName"),
            icon: values.get("Icon").cloned().unwrap_or_default(),
            exec: exec.clone(),
        },
        wm_class: values.get("StartupWMClass").map(|v| v.to_lowercase()).unwrap_or_default(),
        program: exec_program(&exec),
    })
}

/// Escapes of string values in desktop entries: \s \n \t \r \\
fn unescape(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    let mut chars = value.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('s') => out.push(' '),
            Some('n') => out.push('\n'),
            Some('t') => out.push('\t'),
            Some('r') => out.push('\r'),
            Some(other) => out.push(other),
            None => out.push('\\'),
        }
    }
    out
}

/// File name of the program started by Exec=, lowercase ("env A=1 /usr/bin/kate %U" -> "kate")
fn exec_program(exec: &str) -> String {
    let mut words = crate::launch::split_exec(exec).into_iter();
    let mut program = words.next().unwrap_or_default();
    if Path::new(&program).file_name().is_some_and(|name| name == "env") {
        program = words.find(|w| !w.contains('=') && !w.starts_with('-')).unwrap_or_default();
    }
    Path::new(&program).file_name().map(|name| name.to_string_lossy().to_lowercase()).unwrap_or_default()
}

/// File name of the program of a process, lowercase
fn program_of(pid: u32) -> Option<String> {
    if pid == 0 {
        return None;
    }
    let exe = std::fs::read_link(format!("/proc/{pid}/exe")).ok()?;
    Some(exe.file_name()?.to_string_lossy().to_lowercase())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};

    /// A temporary "applications" directory with the given desktop entries
    fn applications(files: &[(&str, &str)]) -> PathBuf {
        static COUNTER: AtomicU32 = AtomicU32::new(0);
        let dir = std::env::temp_dir().join(format!(
            "maia-windows-apps-{}-{}",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = std::fs::remove_dir_all(&dir);
        for (name, text) in files {
            let path = dir.join(name);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(path, text).unwrap();
        }
        dir
    }

    const KONSOLE: &str = "[Desktop Entry]\nType=Application\nName=Konsole\nName[pl]=Konsola\n\
                           GenericName=Terminal\nIcon=utilities-terminal\nExec=konsole\n\
                           [Desktop Action NewWindow]\nName=New Window\nExec=konsole --new\n";

    #[test]
    fn identifies_by_app_id_and_localizes() {
        let dir = applications(&[("org.kde.konsole.desktop", KONSOLE)]);
        let mut index = AppIndex::new(vec![dir], "pl_PL.UTF-8");
        let app = index.identify("org.kde.konsole", "", 0).unwrap();
        assert_eq!(app.desktop_id, "org.kde.konsole.desktop");
        assert_eq!(app.name, "Konsola");
        assert_eq!(app.generic_name, "Terminal");
        assert_eq!(app.icon, "utilities-terminal");
        // The action group must not override the main Exec=
        assert_eq!(app.exec, "konsole");
        assert_eq!(app.launcher_url(), "applications:org.kde.konsole.desktop");
    }

    #[test]
    fn identifies_by_reverse_dns_wm_class_and_resource_name() {
        let dir = applications(&[
            ("org.kde.konsole.desktop", KONSOLE),
            ("google-chrome.desktop", "[Desktop Entry]\nType=Application\nName=Chrome\nExec=/opt/google/chrome/google-chrome %U\nStartupWMClass=Google-chrome\n"),
            ("xterm.desktop", "[Desktop Entry]\nType=Application\nName=XTerm\nExec=xterm\n"),
        ]);
        let mut index = AppIndex::new(vec![dir], "");
        assert_eq!(index.identify("konsole", "", 0).unwrap().desktop_id, "org.kde.konsole.desktop");
        assert_eq!(index.identify("google-chrome", "", 0).unwrap().desktop_id, "google-chrome.desktop");
        assert_eq!(index.identify("", "Google-chrome", 0).unwrap().desktop_id, "google-chrome.desktop");
        assert_eq!(index.identify("", "xterm", 0).unwrap().desktop_id, "xterm.desktop");
        assert_eq!(index.identify("unknown-app", "", 0), None);
    }

    #[test]
    fn earlier_directories_take_precedence_and_hidden_entries_are_skipped() {
        let user = applications(&[("app.desktop", "[Desktop Entry]\nType=Application\nName=Mine\nExec=app\n")]);
        let system = applications(&[
            ("app.desktop", "[Desktop Entry]\nType=Application\nName=System\nExec=app\n"),
            ("gone.desktop", "[Desktop Entry]\nType=Application\nName=Gone\nHidden=true\nExec=gone\n"),
            ("link.desktop", "[Desktop Entry]\nType=Link\nName=Link\nURL=https://kde.org\n"),
        ]);
        let mut index = AppIndex::new(vec![user, system], "");
        assert_eq!(index.identify("app", "", 0).unwrap().name, "Mine");
        assert_eq!(index.identify("gone", "", 0), None);
        assert_eq!(index.identify("link", "", 0), None);
        assert_eq!(index.len(), 1);
    }

    #[test]
    fn subdirectories_give_dashed_ids() {
        let dir = applications(&[("kde/dolphin.desktop", "[Desktop Entry]\nType=Application\nName=Dolphin\nExec=dolphin\n")]);
        let index = AppIndex::new(vec![dir], "");
        assert_eq!(index.by_launcher_url("applications:kde-dolphin.desktop").unwrap().name, "Dolphin");
    }

    #[test]
    fn identifies_by_the_program_of_the_process() {
        // The test process itself: its program becomes the Exec= of an entry
        let me = std::fs::read_link("/proc/self/exe").unwrap();
        let exec = format!("[Desktop Entry]\nType=Application\nName=Me\nExec=env FOO=1 {} --flag\n", me.display());
        let dir = applications(&[("me.desktop", &exec)]);
        let mut index = AppIndex::new(vec![dir], "");
        assert_eq!(index.identify("", "", std::process::id()).unwrap().desktop_id, "me.desktop");
    }

    #[test]
    fn locale_variants_follow_the_spec() {
        assert_eq!(locale_variants("pl_PL.UTF-8"), ["pl_PL", "pl"]);
        assert_eq!(locale_variants("sr_RS@latin"), ["sr_RS@latin", "sr_RS", "sr@latin", "sr"]);
        assert!(locale_variants("C.UTF-8").is_empty());
    }

    #[test]
    fn unescapes_values() {
        assert_eq!(unescape(r"a\sb\\c"), r"a b\c");
    }
}

//! Where things are: the XDG directories of the user, the Qt plugin directories, and where a file
//! comes from (the system, Maia, the user). Resolved once at start and passed around, so tests can
//! point everything at a temporary directory.

use std::path::{Path, PathBuf};

use crate::decorations::theme::Origin;

#[derive(Clone, Debug)]
pub struct Paths {
    /// $XDG_DATA_HOME (~/.local/share): user themes are installed here
    pub data_home: PathBuf,
    /// Searched in this order (the first one wins for a theme name): data_home, then $XDG_DATA_DIRS
    pub data_dirs: Vec<PathBuf>,
    /// $XDG_CONFIG_HOME (~/.config): kwinrc, maia/appearance.json
    pub config_home: PathBuf,
    /// Data directories of Maia itself (<prefix>/share): their themes have origin Maia
    pub maia_data_dirs: Vec<PathBuf>,
    /// Qt plugin directories (with org.kde.kdecoration3/ inside)
    pub plugin_dirs: Vec<PathBuf>,
}

fn env_path(name: &str) -> Option<PathBuf> {
    std::env::var_os(name).filter(|v| !v.is_empty()).map(PathBuf::from)
}

fn env_list(name: &str) -> Option<Vec<PathBuf>> {
    let value = std::env::var(name).ok().filter(|v| !v.is_empty())?;
    Some(value.split(':').filter(|s| !s.is_empty()).map(PathBuf::from).collect())
}

impl Paths {
    /// From the environment, as the session sets it. The Qt plugin directories come from
    /// $QT_PLUGIN_PATH, $MAIA_APPEARANCE_PLUGIN_DIRS (tests) and the usual system places.
    pub fn from_environment() -> Paths {
        let home = env_path("HOME").unwrap_or_else(|| PathBuf::from("/"));
        let data_home = env_path("XDG_DATA_HOME").unwrap_or_else(|| home.join(".local/share"));
        let config_home = env_path("XDG_CONFIG_HOME").unwrap_or_else(|| home.join(".config"));
        let system = env_list("XDG_DATA_DIRS")
            .unwrap_or_else(|| vec![PathBuf::from("/usr/local/share"), PathBuf::from("/usr/share")]);
        let mut data_dirs = vec![data_home.clone()];
        for dir in system {
            if !data_dirs.contains(&dir) {
                data_dirs.push(dir);
            }
        }

        // Maia's share: next to its programs (<prefix>/libexec/.. or <prefix>/bin/..), or given
        let mut maia_data_dirs = env_list("MAIA_APPEARANCE_MAIA_DATA_DIRS").unwrap_or_default();
        if let Ok(exe) = std::env::current_exe() {
            if let Some(prefix) = exe.parent().and_then(Path::parent) {
                let share = prefix.join("share");
                if share.is_dir() && !maia_data_dirs.contains(&share) {
                    maia_data_dirs.push(share);
                }
            }
        }

        let mut plugin_dirs = env_list("MAIA_APPEARANCE_PLUGIN_DIRS").unwrap_or_default();
        if plugin_dirs.is_empty() {
            plugin_dirs.extend(env_list("QT_PLUGIN_PATH").unwrap_or_default());
            for dir in ["/usr/lib/x86_64-linux-gnu/qt6/plugins", "/usr/lib/aarch64-linux-gnu/qt6/plugins", "/usr/lib/qt6/plugins", "/usr/lib64/qt6/plugins"] {
                let dir = PathBuf::from(dir);
                if dir.is_dir() && !plugin_dirs.contains(&dir) {
                    plugin_dirs.push(dir);
                }
            }
        }

        Paths { data_home, data_dirs, config_home, maia_data_dirs, plugin_dirs }
    }

    /// Where a theme file or directory comes from
    pub fn origin_of(&self, path: &Path) -> Origin {
        if path.starts_with(&self.data_home) {
            Origin::User
        } else if self.maia_data_dirs.iter().any(|dir| path.starts_with(dir)) {
            Origin::Maia
        } else {
            Origin::System
        }
    }

    /// `<dir>/<relative>` for every data directory, in search order
    pub fn data_subdirs(&self, relative: &str) -> Vec<PathBuf> {
        self.data_dirs.iter().map(|dir| dir.join(relative)).collect()
    }
}

/// The user's language for localized names: "pl_PL" and "pl" from $LANGUAGE / $LC_ALL /
/// $LC_MESSAGES / $LANG ("pl_PL.UTF-8")
pub fn locale_keys() -> Vec<String> {
    let raw = ["LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"]
        .iter()
        .filter_map(|name| std::env::var(name).ok())
        .find(|v| !v.is_empty() && v != "C" && v != "POSIX")
        .unwrap_or_default();
    let first = raw.split(':').next().unwrap_or("");
    let locale = first.split(['.', '@']).next().unwrap_or("").to_string();
    let mut keys = Vec::new();
    if !locale.is_empty() {
        keys.push(locale.clone());
        if let Some((language, _)) = locale.split_once('_') {
            keys.push(language.to_string());
        }
    }
    keys
}

#[cfg(test)]
mod tests {
    use super::*;

    fn paths() -> Paths {
        Paths {
            data_home: "/home/u/.local/share".into(),
            data_dirs: vec!["/home/u/.local/share".into(), "/opt/Maia/share".into(), "/usr/share".into()],
            config_home: "/home/u/.config".into(),
            maia_data_dirs: vec!["/opt/Maia/share".into()],
            plugin_dirs: vec![],
        }
    }

    #[test]
    fn origins_follow_the_directories() {
        let p = paths();
        assert_eq!(p.origin_of(Path::new("/home/u/.local/share/aurorae/themes/A")), Origin::User);
        assert_eq!(p.origin_of(Path::new("/opt/Maia/share/aurorae/themes/B")), Origin::Maia);
        assert_eq!(p.origin_of(Path::new("/usr/share/aurorae/themes/C")), Origin::System);
    }
}

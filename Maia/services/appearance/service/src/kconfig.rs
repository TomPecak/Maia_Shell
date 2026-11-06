//! Reading KConfig files (kwinrc) and desktop files (metadata.desktop of Aurorae themes).
//!
//! Only reading: writing KConfig files is left to kwriteconfig6, which knows the locking and
//! escaping KDE expects (compositor/kwin.rs). The format: `[Group]` or `[Group][Sub]` lines,
//! `Key=Value`, `Key[pl]=Value` for languages, `Key[$i]=` flags, `#` comments, and the escapes
//! `\s \t \n \r \\ \;` in values.

use std::collections::HashMap;

#[derive(Clone, Debug, Default)]
pub struct KConfig {
    /// group ("Group" or "Group][Sub") -> key (with its [locale], without [$flags]) -> value
    groups: HashMap<String, HashMap<String, String>>,
}

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
            Some('t') => out.push('\t'),
            Some('n') => out.push('\n'),
            Some('r') => out.push('\r'),
            Some('\\') => out.push('\\'),
            Some(';') => out.push(';'),
            Some(other) => {
                out.push('\\');
                out.push(other);
            }
            None => out.push('\\'),
        }
    }
    out
}

/// "Key[$i]" -> "Key", "Name[pl][$i]" -> "Name[pl]"
fn strip_flags(key: &str) -> &str {
    match key.find("[$") {
        Some(at) => &key[..at],
        None => key,
    }
}

impl KConfig {
    pub fn parse(text: &str) -> KConfig {
        let mut config = KConfig::default();
        let mut group = String::new();
        for line in text.lines() {
            let line = line.trim_start();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if line.starts_with('[') {
                if let Some(end) = line.rfind(']') {
                    group = line[1..end].to_string();
                }
                continue;
            }
            let Some((key, value)) = line.split_once('=') else { continue };
            let key = strip_flags(key.trim_end());
            config.groups.entry(group.clone()).or_default().insert(key.to_string(), unescape(value.trim()));
        }
        config
    }

    pub fn get(&self, group: &str, key: &str) -> Option<&str> {
        self.groups.get(group).and_then(|g| g.get(key)).map(String::as_str)
    }

    pub fn get_bool(&self, group: &str, key: &str) -> Option<bool> {
        self.get(group, key).map(|v| matches!(v.to_ascii_lowercase().as_str(), "true" | "1" | "yes" | "on"))
    }

    /// The value in the user's language (`Key[pl_PL]`, `Key[pl]`), else `Key`
    pub fn get_localized(&self, group: &str, key: &str, locales: &[String]) -> Option<&str> {
        for locale in locales {
            if let Some(value) = self.get(group, &format!("{key}[{locale}]")) {
                return Some(value);
            }
        }
        self.get(group, key)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn groups_keys_escapes_and_languages() {
        let config = KConfig::parse(
            "# comment\n[org.kde.kdecoration2]\nlibrary=org.kde.kwin.aurorae.v2\ntheme=__aurorae__svg__X\\sY\nBorderSizeAuto[$i]=false\n\
             [Desktop Entry]\nName=Plastik\nName[pl]=Plastik PL\n[A][B]\nk=v\n",
        );
        assert_eq!(config.get("org.kde.kdecoration2", "library"), Some("org.kde.kwin.aurorae.v2"));
        assert_eq!(config.get("org.kde.kdecoration2", "theme"), Some("__aurorae__svg__X Y"));
        assert_eq!(config.get_bool("org.kde.kdecoration2", "BorderSizeAuto"), Some(false));
        assert_eq!(config.get_localized("Desktop Entry", "Name", &["pl_PL".into(), "pl".into()]), Some("Plastik PL"));
        assert_eq!(config.get_localized("Desktop Entry", "Name", &["de".into()]), Some("Plastik"));
        assert_eq!(config.get("A][B", "k"), Some("v"));
    }
}

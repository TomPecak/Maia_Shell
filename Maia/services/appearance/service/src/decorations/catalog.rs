//! Finding the decoration themes on disk, for every engine.
//!
//! - aurorae-svg: `<data dir>/aurorae/themes/<name>/metadata.desktop` (Aurorae v2 reads themes
//!   from every XDG data directory, so Maia's <prefix>/share counts too)
//! - aurorae-qml: `<data dir>/kwin/decorations/<id>/metadata.json` (KPackage KWin/Decoration)
//! - kdecoration: `<qt plugin dir>/org.kde.kdecoration3/<plugin id>.so`, without the Aurorae
//!   engines themselves (their themes are listed above)
//!
//! A name found in several data directories is the first one's (the user's overrides Maia's,
//! Maia's the system's), as in KDE. `scan` blocks (it reads directories and plugin files): call
//! it through spawn_blocking.

use std::collections::HashSet;
use std::path::Path;

use super::qtplugin;
use super::theme::{Engine, Theme, ThemeId};
use crate::kconfig::KConfig;
use crate::paths::Paths;

/// The plugin directory of KDecoration3 plugins, inside a Qt plugin directory
pub const PLUGIN_SUBDIR: &str = "org.kde.kdecoration3";
/// The Aurorae engines: their plugin ids are not themes
pub const AURORAE_V2: &str = "org.kde.kwin.aurorae.v2";
pub const AURORAE_V1: &str = "org.kde.kwin.aurorae";

fn reason_for(engine: Engine, compositor: &str) -> String {
    match engine {
        Engine::Kdecoration | Engine::AuroraeQml => format!("a KWin decoration; {compositor} cannot draw it"),
        Engine::Wayfire => format!("Wayfire's own decoration; {compositor} cannot draw it"),
        Engine::AuroraeSvg => format!("{compositor} has no Aurorae SVG engine"),
    }
}

fn sorted_dirs(dir: &Path) -> Vec<std::path::PathBuf> {
    let Ok(entries) = std::fs::read_dir(dir) else { return Vec::new() };
    let mut dirs: Vec<_> = entries.filter_map(Result::ok).map(|e| e.path()).filter(|p| p.is_dir()).collect();
    dirs.sort();
    dirs
}

fn aurorae_svg(paths: &Paths, locales: &[String], out: &mut Vec<Theme>) {
    let mut seen = HashSet::new();
    for root in paths.data_subdirs("aurorae/themes") {
        for dir in sorted_dirs(&root) {
            let Some(name) = dir.file_name().and_then(|n| n.to_str()).map(str::to_string) else { continue };
            let Ok(text) = std::fs::read_to_string(dir.join("metadata.desktop")) else { continue };
            if !seen.insert(name.clone()) {
                continue;
            }
            let desktop = KConfig::parse(&text);
            let group = "Desktop Entry";
            out.push(Theme {
                id: ThemeId::new(Engine::AuroraeSvg, name.clone()),
                name: desktop.get_localized(group, "Name", locales).filter(|s| !s.is_empty()).unwrap_or(&name).to_string(),
                description: desktop.get_localized(group, "Comment", locales).unwrap_or_default().to_string(),
                author: desktop.get(group, "X-KDE-PluginInfo-Author").unwrap_or_default().to_string(),
                origin: paths.origin_of(&dir),
                available: true,
                unavailable_reason: String::new(),
                path: dir,
            });
        }
    }
}

fn json_text(map: &serde_json::Value, key: &str, locales: &[String]) -> String {
    for locale in locales {
        if let Some(text) = map.get(format!("{key}[{locale}]")).and_then(|v| v.as_str()) {
            return text.to_string();
        }
    }
    map.get(key).and_then(|v| v.as_str()).unwrap_or_default().to_string()
}

fn aurorae_qml(paths: &Paths, locales: &[String], out: &mut Vec<Theme>) {
    let mut seen = HashSet::new();
    for root in paths.data_subdirs("kwin/decorations") {
        for dir in sorted_dirs(&root) {
            let Ok(text) = std::fs::read_to_string(dir.join("metadata.json")) else { continue };
            let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) else { continue };
            let kplugin = &json["KPlugin"];
            let dir_name = dir.file_name().and_then(|n| n.to_str()).unwrap_or_default().to_string();
            let id = kplugin.get("Id").and_then(|v| v.as_str()).map(str::to_string).unwrap_or(dir_name);
            if id.is_empty() || !seen.insert(id.clone()) {
                continue;
            }
            let author = kplugin["Authors"].get(0).map(|a| json_text(a, "Name", locales)).unwrap_or_default();
            let name = json_text(kplugin, "Name", locales);
            out.push(Theme {
                id: ThemeId::new(Engine::AuroraeQml, id.clone()),
                name: if name.is_empty() { id } else { name },
                description: json_text(kplugin, "Description", locales),
                author,
                origin: paths.origin_of(&dir),
                available: true,
                unavailable_reason: String::new(),
                path: dir,
            });
        }
    }
}

/// The plugin files of KDecoration3 (with the Aurorae engines), first directory first
pub fn plugin_files(paths: &Paths) -> Vec<std::path::PathBuf> {
    let mut seen = HashSet::new();
    let mut files = Vec::new();
    for dir in &paths.plugin_dirs {
        let Ok(entries) = std::fs::read_dir(dir.join(PLUGIN_SUBDIR)) else { continue };
        let mut found: Vec<_> = entries.filter_map(Result::ok).map(|e| e.path()).filter(|p| p.extension().is_some_and(|e| e == "so")).collect();
        found.sort();
        for file in found {
            if let Some(stem) = file.file_stem().and_then(|s| s.to_str()) {
                if seen.insert(stem.to_string()) {
                    files.push(file);
                }
            }
        }
    }
    files
}

fn kdecoration(paths: &Paths, locales: &[String], out: &mut Vec<Theme>) {
    for file in plugin_files(paths) {
        let Some(id) = file.file_stem().and_then(|s| s.to_str()).map(str::to_string) else { continue };
        if id == AURORAE_V1 || id == AURORAE_V2 {
            continue;
        }
        let info = std::fs::read(&file).ok().and_then(|bytes| qtplugin::read(&bytes, locales)).unwrap_or_default();
        out.push(Theme {
            id: ThemeId::new(Engine::Kdecoration, id.clone()),
            name: if info.name.is_empty() { id } else { info.name },
            description: info.description,
            author: info.author,
            origin: paths.origin_of(&file),
            available: true,
            unavailable_reason: String::new(),
            path: file,
        });
    }
}

/// Every theme of every engine, sorted by shown name; those the compositor cannot draw have
/// available = false and the reason
pub fn scan(paths: &Paths, engines: &[Engine], compositor: &str, locales: &[String]) -> Vec<Theme> {
    let mut themes = Vec::new();
    aurorae_svg(paths, locales, &mut themes);
    aurorae_qml(paths, locales, &mut themes);
    kdecoration(paths, locales, &mut themes);
    for theme in &mut themes {
        if !engines.contains(&theme.id.engine) {
            theme.available = false;
            theme.unavailable_reason = reason_for(theme.id.engine, compositor);
        }
    }
    themes.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()).then_with(|| a.id.cmp(&b.id)));
    themes
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::decorations::theme::Origin;
    use crate::test_support::TempDir;

    #[test]
    fn themes_of_every_engine_are_found_once() {
        let tmp = TempDir::new("catalog");
        let home = tmp.path().join("home");
        let maia = tmp.path().join("maia");
        let system = tmp.path().join("system");
        let theme = |root: &Path, name: &str, title: &str| {
            let dir = root.join("aurorae/themes").join(name);
            std::fs::create_dir_all(&dir).unwrap();
            std::fs::write(dir.join("metadata.desktop"), format!("[Desktop Entry]\nName={title}\nName[pl]={title} PL\n")).unwrap();
        };
        theme(&home, "Mine", "Mine");
        theme(&maia, "XBoomer", "XBoomer");
        theme(&system, "XBoomer", "Shadowed");
        let qml = system.join("kwin/decorations/kwin4_decoration_qml_plastik");
        std::fs::create_dir_all(&qml).unwrap();
        std::fs::write(qml.join("metadata.json"), r#"{"KPlugin": {"Id": "kwin4_decoration_qml_plastik", "Name": "Plastik"}}"#).unwrap();
        let plugins = tmp.path().join("plugins").join(PLUGIN_SUBDIR);
        std::fs::create_dir_all(&plugins).unwrap();
        std::fs::write(plugins.join("org.example.flat.so"), b"no metadata").unwrap();
        std::fs::write(plugins.join("org.kde.kwin.aurorae.v2.so"), b"engine").unwrap();

        let paths = Paths {
            data_home: home.clone(),
            data_dirs: vec![home, maia.clone(), system],
            config_home: tmp.path().join("config"),
            maia_data_dirs: vec![maia],
            plugin_dirs: vec![tmp.path().join("plugins")],
        };
        let themes = scan(&paths, &[Engine::AuroraeSvg, Engine::Kdecoration], "kwin", &["pl".into()]);
        let ids: Vec<String> = themes.iter().map(|t| t.id.to_string()).collect();
        assert_eq!(ids, ["aurorae-svg:Mine", "kdecoration:org.example.flat", "aurorae-qml:kwin4_decoration_qml_plastik", "aurorae-svg:XBoomer"]);
        let xboomer = themes.iter().find(|t| t.id.name == "XBoomer").unwrap();
        assert_eq!((xboomer.name.as_str(), xboomer.origin), ("XBoomer PL", Origin::Maia));
        let plastik = themes.iter().find(|t| t.id.engine == Engine::AuroraeQml).unwrap();
        assert!(!plastik.available, "aurorae-qml is not among the engines given");
        assert_eq!(themes.iter().find(|t| t.id.name == "Mine").unwrap().origin, Origin::User);
    }
}

//! The metadata of a Qt 6 plugin (.so), read without Qt: shown names of native decoration plugins
//! (Breeze, Oxygen, third-party ones such as Klassy).
//!
//! Qt 6 puts it in the ELF note `.note.qt.metadata`: the note name "qt-project!", then 4 bytes
//! (format version, Qt major, Qt minor, architecture requirements), then a CBOR map whose key 4 is
//! the plugin's JSON metadata, here `{"KPlugin": {"Name": ..., "Name[pl]": ..., "Description":
//! ..., "Authors": [{"Name": ...}]}}`. The note is near the start of the file, but the whole file
//! is searched to be sure (a plugin is a few hundred kB).

use ciborium::value::Value;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct PluginInfo {
    pub name: String,
    pub description: String,
    pub author: String,
}

const NOTE_NAME: &[u8] = b"qt-project!\0";
/// The CBOR key of the JSON metadata (QtPluginMetaDataKeys::MetaData)
const METADATA_KEY: i128 = 4;

fn map_get<'a>(map: &'a Value, key: &str) -> Option<&'a Value> {
    map.as_map()?.iter().find(|(k, _)| k.as_text() == Some(key)).map(|(_, v)| v)
}

fn text_of(map: &Value, key: &str, locales: &[String]) -> String {
    for locale in locales {
        if let Some(text) = map_get(map, &format!("{key}[{locale}]")).and_then(Value::as_text) {
            return text.to_string();
        }
    }
    map_get(map, key).and_then(Value::as_text).unwrap_or_default().to_string()
}

/// The KPlugin metadata of a plugin file's bytes, None when it has none
pub fn read(bytes: &[u8], locales: &[String]) -> Option<PluginInfo> {
    let at = bytes.windows(NOTE_NAME.len()).position(|w| w == NOTE_NAME)?;
    let cbor = bytes.get(at + NOTE_NAME.len() + 4..)?;
    let root: Value = ciborium::de::from_reader(cbor).ok()?;
    let metadata = root.as_map()?.iter().find(|(k, _)| k.as_integer().map(i128::from) == Some(METADATA_KEY)).map(|(_, v)| v)?;
    let kplugin = map_get(metadata, "KPlugin")?;
    let author = map_get(kplugin, "Authors")
        .and_then(Value::as_array)
        .and_then(|authors| authors.first())
        .map(|first| text_of(first, "Name", locales))
        .unwrap_or_default();
    Some(PluginInfo { name: text_of(kplugin, "Name", locales), description: text_of(kplugin, "Description", locales), author })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plugin_bytes(metadata: Value) -> Vec<u8> {
        let root = Value::Map(vec![
            (Value::Integer(2.into()), Value::Text("org.kde.KPluginFactory".into())),
            (Value::Integer(4.into()), metadata),
        ]);
        let mut bytes = b"\x7fELF...padding...".to_vec();
        bytes.extend_from_slice(NOTE_NAME);
        bytes.extend_from_slice(&[1, 6, 10, 1]);
        ciborium::ser::into_writer(&root, &mut bytes).unwrap();
        bytes.extend_from_slice(b"...rest of the library...");
        bytes
    }

    #[test]
    fn names_come_from_kplugin_in_the_users_language() {
        let kplugin = Value::Map(vec![
            (Value::Text("Name".into()), Value::Text("Breeze".into())),
            (Value::Text("Name[pl]".into()), Value::Text("Bryza".into())),
            (Value::Text("Description".into()), Value::Text("Window decoration".into())),
            (
                Value::Text("Authors".into()),
                Value::Array(vec![Value::Map(vec![(Value::Text("Name".into()), Value::Text("KDE".into()))])]),
            ),
        ]);
        let bytes = plugin_bytes(Value::Map(vec![(Value::Text("KPlugin".into()), kplugin)]));
        let info = read(&bytes, &["pl_PL".into(), "pl".into()]).unwrap();
        assert_eq!(info, PluginInfo { name: "Bryza".into(), description: "Window decoration".into(), author: "KDE".into() });
        assert_eq!(read(&bytes, &[]).unwrap().name, "Breeze");
    }

    #[test]
    fn files_without_metadata_have_none() {
        assert_eq!(read(b"not a plugin", &[]), None);
    }

    /// The real plugins of this machine, when they are there
    #[test]
    fn the_installed_breeze_plugin_is_read() {
        let path = "/usr/lib/x86_64-linux-gnu/qt6/plugins/org.kde.kdecoration3/org.kde.breeze.so";
        let Ok(bytes) = std::fs::read(path) else { return };
        assert_eq!(read(&bytes, &[]).unwrap().name, "Breeze");
    }
}

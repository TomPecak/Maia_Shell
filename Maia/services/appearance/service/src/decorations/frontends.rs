//! The choice remembered per frontend: each Maia frontend (Lumen, XPLuna, ...) keeps its own window
//! decoration. Stored in `$XDG_CONFIG_HOME/maia/appearance.json`:
//!
//! ```json
//! { "version": 1, "decorations": { "frontends": { "XPLuna": "aurorae-svg:XBoomer" } } }
//! ```
//!
//! Written atomically (a temporary file renamed over the old one), read once at start.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::error::{OpError, OpResult};

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DecorationChoices {
    #[serde(default)]
    pub frontends: BTreeMap<String, String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
struct File {
    version: u32,
    #[serde(default)]
    decorations: DecorationChoices,
}

pub fn file_path(config_home: &Path) -> PathBuf {
    config_home.join("maia").join("appearance.json")
}

/// The remembered choices; none when the file is missing or broken (it is then rewritten)
pub async fn load(path: &Path) -> DecorationChoices {
    match tokio::fs::read_to_string(path).await {
        Ok(text) => match serde_json::from_str::<File>(&text) {
            Ok(file) => file.decorations,
            Err(error) => {
                eprintln!("maia-appearance-service: ignoring {}: {error}", path.display());
                DecorationChoices::default()
            }
        },
        Err(_) => DecorationChoices::default(),
    }
}

pub async fn save(path: &Path, choices: &DecorationChoices) -> OpResult {
    let file = File { version: 1, decorations: choices.clone() };
    let text = serde_json::to_string_pretty(&file).map_err(|e| OpError::failed(e.to_string()))?;
    if let Some(dir) = path.parent() {
        tokio::fs::create_dir_all(dir).await.map_err(|e| OpError::io("creating the config directory", e))?;
    }
    let temporary = path.with_extension("json.new");
    tokio::fs::write(&temporary, text).await.map_err(|e| OpError::io("writing appearance.json", e))?;
    tokio::fs::rename(&temporary, path).await.map_err(|e| OpError::io("replacing appearance.json", e))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;

    #[tokio::test(flavor = "current_thread")]
    async fn choices_survive_a_restart() {
        let tmp = TempDir::new("frontends");
        let path = file_path(tmp.path());
        assert_eq!(load(&path).await, DecorationChoices::default());
        let mut choices = DecorationChoices::default();
        choices.frontends.insert("XPLuna".into(), "aurorae-svg:XBoomer".into());
        save(&path, &choices).await.unwrap();
        assert_eq!(load(&path).await, choices);
        std::fs::write(&path, "{ broken").unwrap();
        assert_eq!(load(&path).await, DecorationChoices::default());
    }
}

//! The values of the decorations area, as in the contract (decorations.capnp), without Cap'n Proto.
//!
//! A theme is named "<engine>:<name>" on every compositor; each compositor backend translates it
//! to its own settings (compositor/kwin.rs).

use std::fmt;
use std::path::PathBuf;
use std::str::FromStr;

use crate::error::OpError;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Engine {
    /// Aurorae SVG theme: aurorae/themes/<name>/ with metadata.desktop and decoration.svg(z)
    AuroraeSvg,
    /// Aurorae QML theme: kwin/decorations/<id>/ (a KPackage); KWin only
    AuroraeQml,
    /// A native KDecoration3 plugin (Breeze, Oxygen); KWin only
    Kdecoration,
    /// Wayfire's own decoration
    Wayfire,
}

impl Engine {
    pub const ALL: [Engine; 4] = [Engine::AuroraeSvg, Engine::AuroraeQml, Engine::Kdecoration, Engine::Wayfire];

    pub fn key(self) -> &'static str {
        match self {
            Engine::AuroraeSvg => "aurorae-svg",
            Engine::AuroraeQml => "aurorae-qml",
            Engine::Kdecoration => "kdecoration",
            Engine::Wayfire => "wayfire",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Origin {
    System,
    Maia,
    User,
}

/// "aurorae-svg:XBoomer"
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct ThemeId {
    pub engine: Engine,
    pub name: String,
}

impl ThemeId {
    pub fn new(engine: Engine, name: impl Into<String>) -> ThemeId {
        ThemeId { engine, name: name.into() }
    }
}

impl fmt::Display for ThemeId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}:{}", self.engine.key(), self.name)
    }
}

impl FromStr for ThemeId {
    type Err = OpError;

    fn from_str(text: &str) -> Result<ThemeId, OpError> {
        let (engine, name) = text.split_once(':').ok_or_else(|| OpError::invalid(format!("\"{text}\" is not \"<engine>:<name>\"")))?;
        let engine = Engine::ALL
            .into_iter()
            .find(|e| e.key() == engine)
            .ok_or_else(|| OpError::invalid(format!("unknown engine \"{engine}\"")))?;
        if name.is_empty() || name.contains('/') || name.contains('\0') {
            return Err(OpError::invalid(format!("bad theme name \"{name}\"")));
        }
        Ok(ThemeId::new(engine, name))
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Theme {
    pub id: ThemeId,
    pub name: String,
    pub description: String,
    pub author: String,
    pub origin: Origin,
    pub available: bool,
    pub unavailable_reason: String,
    pub path: PathBuf,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum BorderSize {
    /// What the theme recommends
    #[default]
    Theme,
    None,
    NoSides,
    Tiny,
    Normal,
    Large,
    VeryLarge,
    Huge,
    VeryHuge,
    Oversized,
}

/// What is chosen, as clients see it
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Current {
    pub theme: Option<ThemeId>,
    pub border_size: BorderSize,
    /// The compositor reported that it uses it
    pub confirmed: bool,
    /// The frontend whose choice this is
    pub frontend: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_round_trip_and_reject_nonsense() {
        let id: ThemeId = "aurorae-svg:XBoomer".parse().unwrap();
        assert_eq!(id, ThemeId::new(Engine::AuroraeSvg, "XBoomer"));
        assert_eq!(id.to_string(), "aurorae-svg:XBoomer");
        assert_eq!("kdecoration:org.kde.breeze".parse::<ThemeId>().unwrap().engine, Engine::Kdecoration);
        assert!("XBoomer".parse::<ThemeId>().is_err());
        assert!("svg:XBoomer".parse::<ThemeId>().is_err());
        assert!("aurorae-svg:../x".parse::<ThemeId>().is_err());
        assert!("aurorae-svg:".parse::<ThemeId>().is_err());
    }
}

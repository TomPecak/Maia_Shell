//! The compositors: one backend each, behind the `Compositor` trait.
//!
//! A backend knows how its compositor stores the decoration and how to make it take a change;
//! nothing else in the service does. It works on ThemeIds ("aurorae-svg:XBoomer") and translates
//! them itself. The decorations area (decorations/mod.rs) asks it what it can draw, what is chosen,
//! to apply a choice, and listens to its change notifications (changes made by other programs).
//!
//! - `kwin.rs`: KWin (kwinrc, kwriteconfig6, D-Bus reloadConfig and supportInformation)
//! - `fake.rs`: in memory, for tests and interface work (MAIA_APPEARANCE_BACKEND=fake)
//! - later `wayfire.rs`: wayfire.ini (the wayfire-aurorae plugin's section) and Wayfire's IPC
//!
//! Adding a compositor = a new file implementing `Compositor`, and a line in `create()`.

pub mod fake;
pub mod kwin;

use std::rc::Rc;

use futures::future::LocalBoxFuture;
use tokio::sync::mpsc;

use crate::decorations::theme::{BorderSize, Engine, ThemeId};
use crate::error::OpResult;
use crate::paths::Paths;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CompositorInfo {
    /// "kwin", "wayfire", "fake"
    pub name: String,
    /// The theme engines it draws
    pub engines: Vec<Engine>,
    pub border_sizes: bool,
}

/// What the compositor is told to use (its settings), and whether it said it does
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct DecorationState {
    pub theme: Option<ThemeId>,
    pub border_size: BorderSize,
}

/// The outcome of applying a change
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Applied {
    /// The compositor reported that it uses it
    Confirmed,
    /// Saved; the compositor did not answer (not running): it uses it when it starts
    Saved,
}

pub trait Compositor {
    fn info(&self) -> CompositorInfo;

    /// What the compositor's settings say now
    fn read(&self) -> LocalBoxFuture<'_, OpResult<DecorationState>>;

    /// Uses a theme. Failed (with what the compositor uses instead) when it does not take it.
    fn apply_theme(&self, theme: &ThemeId) -> LocalBoxFuture<'_, OpResult<Applied>>;

    fn apply_border_size(&self, size: BorderSize) -> LocalBoxFuture<'_, OpResult<Applied>>;

    /// Runs until the end of the service: sends () when the settings may have been changed by
    /// another program (the area then calls read() and compares)
    fn watch(self: Rc<Self>, changed: mpsc::UnboundedSender<()>) -> LocalBoxFuture<'static, ()>;
}

/// The backend named by MAIA_APPEARANCE_BACKEND ("kwin", the default, or "fake")
pub fn create(name: &str, paths: &Paths) -> Result<Rc<dyn Compositor>, String> {
    match name {
        kwin::NAME => Ok(Rc::new(kwin::KWin::new(paths))),
        fake::NAME => Ok(Rc::new(fake::Fake::new())),
        other => Err(format!("unknown backend \"{other}\" (kwin or fake)")),
    }
}

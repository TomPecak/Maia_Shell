//! A compositor in memory, for tests and interface work (MAIA_APPEARANCE_BACKEND=fake): nothing
//! reaches a real compositor. It draws every engine but Wayfire's, takes every theme but one named
//! "broken" (it then "falls back" like KWin), and `change_externally` plays another program
//! changing the settings.

use std::cell::RefCell;
use std::rc::Rc;

use futures::future::LocalBoxFuture;
use tokio::sync::mpsc;

use super::{Applied, Compositor, CompositorInfo, DecorationState};
use crate::decorations::theme::{BorderSize, Engine, ThemeId};
use crate::error::{OpError, OpResult};

pub const NAME: &str = "fake";

#[derive(Default)]
pub struct Fake {
    state: RefCell<DecorationState>,
    watchers: RefCell<Vec<mpsc::UnboundedSender<()>>>,
}

impl Fake {
    pub fn new() -> Fake {
        Fake { state: RefCell::new(DecorationState { theme: Some(ThemeId::new(Engine::Kdecoration, "org.kde.breeze")), border_size: BorderSize::Theme }), watchers: RefCell::default() }
    }

    pub fn state(&self) -> DecorationState {
        self.state.borrow().clone()
    }

    /// Another program changed the settings
    pub fn change_externally(&self, state: DecorationState) {
        *self.state.borrow_mut() = state;
        self.watchers.borrow_mut().retain(|w| w.send(()).is_ok());
    }
}

impl Compositor for Fake {
    fn info(&self) -> CompositorInfo {
        CompositorInfo { name: NAME.into(), engines: vec![Engine::AuroraeSvg, Engine::AuroraeQml, Engine::Kdecoration], border_sizes: true }
    }

    fn read(&self) -> LocalBoxFuture<'_, OpResult<DecorationState>> {
        let state = self.state();
        Box::pin(async move { Ok(state) })
    }

    fn apply_theme(&self, theme: &ThemeId) -> LocalBoxFuture<'_, OpResult<Applied>> {
        let theme = theme.clone();
        Box::pin(async move {
            if theme.engine == Engine::Wayfire {
                return Err(OpError::new(crate::error::ErrorCode::NotSupported, "no Wayfire here"));
            }
            if theme.name == "broken" {
                return Err(OpError::failed("the fake uses org.kde.breeze instead"));
            }
            self.state.borrow_mut().theme = Some(theme);
            Ok(Applied::Confirmed)
        })
    }

    fn apply_border_size(&self, size: BorderSize) -> LocalBoxFuture<'_, OpResult<Applied>> {
        self.state.borrow_mut().border_size = size;
        Box::pin(async { Ok(Applied::Confirmed) })
    }

    fn watch(self: Rc<Self>, changed: mpsc::UnboundedSender<()>) -> LocalBoxFuture<'static, ()> {
        self.watchers.borrow_mut().push(changed);
        Box::pin(async {})
    }
}

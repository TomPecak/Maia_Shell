//! The window list: what the service knows about every window, in which order, and what changed.
//!
//! Pure logic without I/O, so it is tested directly (see the tests at the bottom). The backend gives
//! the store a whole `Window` whenever something about it changes; the store keeps what the
//! compositor does not know (the identified application, the last activation time) and reports a
//! `Change` only when the window really differs.

use std::collections::HashMap;

use crate::apps::AppInfo;
use crate::windows_capnp;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Window {
    /// Stable id (the UUID from the compositor)
    pub id: String,
    pub title: String,
    /// App id reported by the window (Wayland app_id, X11 class)
    pub raw_app_id: String,
    /// X11 resource name (windows through XWayland), helps to identify the application
    pub resource_name: String,
    /// The identified application (set by the store, not by the backend)
    pub app: Option<AppInfo>,
    /// Icon name the window gave itself
    pub theme_icon: String,
    /// > 0 when the compositor has a bitmap icon; changes with the icon
    pub icon_serial: u32,
    pub pid: u32,
    /// Bits of the contract (stateActive, stateMinimized, ...)
    pub states: u32,
    pub geometry: Rect,
    pub virtual_desktops: Vec<String>,
    pub parent_id: String,
    /// ms since 1970 when the window was last activated (set by the store)
    pub last_activated: i64,
}

impl Window {
    pub fn is_active(&self) -> bool {
        self.states & windows_capnp::STATE_ACTIVE != 0
    }

    /// The icon clients should show: the application icon, otherwise the one the window gave
    pub fn icon_name(&self) -> &str {
        match &self.app {
            Some(app) if !app.icon.is_empty() => &app.icon,
            _ => &self.theme_icon,
        }
    }

    /// What identifies the application of the window; when it changes, the window is identified again
    fn identity(&self) -> (&str, &str, u32) {
        (&self.raw_app_id, &self.resource_name, self.pid)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Change {
    Added(Window),
    Changed(Window),
    Removed(String),
}

/// The windows in the order they appeared (like the manual sort of the Plasma task manager)
#[derive(Default)]
pub struct WindowStore {
    windows: HashMap<String, Window>,
    order: Vec<String>,
}

impl WindowStore {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn get(&self, id: &str) -> Option<&Window> {
        self.windows.get(id)
    }

    pub fn len(&self) -> usize {
        self.order.len()
    }

    pub fn is_empty(&self) -> bool {
        self.order.is_empty()
    }

    /// All windows, in the order they appeared
    pub fn snapshot(&self) -> Vec<Window> {
        self.order.iter().filter_map(|id| self.windows.get(id)).cloned().collect()
    }

    /// The window as the backend sees it now. `identify` is called only for a new window or when its
    /// app id / resource name / pid changed (identification reads desktop entries, it is not free).
    pub fn upsert(
        &mut self,
        mut window: Window,
        now_ms: i64,
        identify: impl FnOnce(&Window) -> Option<AppInfo>,
    ) -> Option<Change> {
        match self.windows.get(&window.id) {
            None => {
                window.app = identify(&window);
                window.last_activated = if window.is_active() { now_ms } else { 0 };
                self.order.push(window.id.clone());
                self.windows.insert(window.id.clone(), window.clone());
                Some(Change::Added(window))
            }
            Some(old) => {
                window.app = if old.identity() == window.identity() {
                    old.app.clone()
                } else {
                    identify(&window)
                };
                window.last_activated = if window.is_active() && !old.is_active() {
                    now_ms
                } else {
                    old.last_activated
                };
                if *old == window {
                    return None;
                }
                self.windows.insert(window.id.clone(), window.clone());
                Some(Change::Changed(window))
            }
        }
    }

    pub fn remove(&mut self, id: &str) -> Option<Change> {
        self.windows.remove(id)?;
        self.order.retain(|other| other != id);
        Some(Change::Removed(id.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn window(id: &str, title: &str) -> Window {
        Window { id: id.into(), title: title.into(), raw_app_id: "org.kde.konsole".into(), ..Default::default() }
    }

    fn konsole() -> Option<AppInfo> {
        Some(AppInfo { desktop_id: "org.kde.konsole.desktop".into(), icon: "utilities-terminal".into(), ..Default::default() })
    }

    #[test]
    fn new_window_is_added_and_identified() {
        let mut store = WindowStore::new();
        let change = store.upsert(window("a", "Terminal"), 10, |_| konsole()).unwrap();
        let Change::Added(added) = change else { panic!("expected Added") };
        assert_eq!(added.app.unwrap().desktop_id, "org.kde.konsole.desktop");
        assert_eq!(store.len(), 1);
    }

    #[test]
    fn unchanged_window_reports_nothing() {
        let mut store = WindowStore::new();
        store.upsert(window("a", "Terminal"), 10, |_| konsole());
        assert_eq!(store.upsert(window("a", "Terminal"), 20, |_| panic!("not identified again")), None);
    }

    #[test]
    fn changed_title_is_reported_and_identity_is_kept() {
        let mut store = WindowStore::new();
        store.upsert(window("a", "Terminal"), 10, |_| konsole());
        let change = store.upsert(window("a", "vim"), 20, |_| panic!("same app id, no identification"));
        let Some(Change::Changed(changed)) = change else { panic!("expected Changed") };
        assert_eq!(changed.title, "vim");
        assert!(changed.app.is_some());
    }

    #[test]
    fn new_app_id_is_identified_again() {
        let mut store = WindowStore::new();
        store.upsert(window("a", "x"), 10, |_| konsole());
        let mut other = window("a", "x");
        other.raw_app_id = "firefox".into();
        let Some(Change::Changed(changed)) = store.upsert(other, 20, |_| None) else { panic!() };
        assert!(changed.app.is_none());
    }

    #[test]
    fn activation_sets_last_activated_once() {
        let mut store = WindowStore::new();
        store.upsert(window("a", "x"), 10, |_| None);
        let mut active = window("a", "x");
        active.states = windows_capnp::STATE_ACTIVE;
        let Some(Change::Changed(changed)) = store.upsert(active.clone(), 50, |_| None) else { panic!() };
        assert_eq!(changed.last_activated, 50);
        // Still active later: the time of the activation stays
        active.title = "y".into();
        let Some(Change::Changed(changed)) = store.upsert(active, 90, |_| None) else { panic!() };
        assert_eq!(changed.last_activated, 50);
    }

    #[test]
    fn snapshot_keeps_the_order_of_appearance() {
        let mut store = WindowStore::new();
        for id in ["c", "a", "b"] {
            store.upsert(window(id, id), 0, |_| None);
        }
        store.remove("a");
        let ids: Vec<String> = store.snapshot().into_iter().map(|w| w.id).collect();
        assert_eq!(ids, ["c", "b"]);
        assert_eq!(store.remove("a"), None);
    }

    #[test]
    fn icon_name_prefers_the_application_icon() {
        let mut w = window("a", "x");
        w.theme_icon = "window-icon".into();
        assert_eq!(w.icon_name(), "window-icon");
        w.app = konsole();
        assert_eq!(w.icon_name(), "utilities-terminal");
    }
}

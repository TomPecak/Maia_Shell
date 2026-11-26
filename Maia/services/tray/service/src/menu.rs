//! Menus of items: com.canonical.dbusmenu, read for a shell while it has the menu open.
//!
//! An item names its menu's object (the Menu property); the menu is a tree of entries with
//! properties (label, enabled, icon, toggle). Applications fill a menu or a submenu when it opens
//! (AboutToShow; Qt and libdbusmenu do), and tell changes with LayoutUpdated and
//! ItemsPropertiesUpdated. The shell gets the whole menu as one tree, again after every change: a
//! tray menu has tens of entries, and one tree is simpler for a shell than patches.
//!
//! An open menu (`open`) has its own task: AboutToShow(0), GetLayout, then a new layout after the
//! application's signals, at most one a frame. The shell's Menu capability keeps it open; dropping
//! it tells the application "closed".

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::{Rc, Weak};
use std::time::Duration;

use futures::StreamExt;
use zbus::zvariant::Value;

use crate::hub::{Address, CALL_TIMEOUT, Hub, HubRef};
use crate::image::{ImageRef, ImageStore, ImageStoreRef, url_from_path};
use crate::markup;
use crate::model::Icon;
use crate::tray_capnp::menu_listener;

pub const INTERFACE: &str = "com.canonical.dbusmenu";

/// The most entries of a menu, and how deep its submenus go
pub const MAX_ENTRIES: usize = 500;
pub const MAX_DEPTH: usize = 8;
/// The shortest time between two layouts to the shell
pub const LAYOUT_INTERVAL: Duration = Duration::from_millis(16);

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Toggle {
    #[default]
    None,
    Checkmark,
    Radio,
}

/// An entry as the application gives it
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct RawEntry {
    pub id: i32,
    pub separator: bool,
    pub label: String,
    pub enabled: bool,
    pub icon_name: String,
    /// PNG bytes
    pub icon_data: Vec<u8>,
    pub toggle: Toggle,
    pub checked: bool,
    pub shortcut: String,
    pub submenu: bool,
    pub children: Vec<RawEntry>,
}

/// An entry for the shells (tray.capnp MenuEntry)
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Entry {
    pub id: i32,
    pub separator: bool,
    pub label: String,
    pub enabled: bool,
    pub icon: Icon,
    pub toggle: Toggle,
    pub checked: bool,
    pub shortcut: String,
    pub submenu: bool,
    pub children: Vec<Entry>,
}

/// "_Quit" → "Quit", "Save __as" → "Save _as"
pub fn without_mnemonics(label: &str) -> String {
    let mut out = String::with_capacity(label.len());
    let mut chars = label.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '_' {
            if chars.peek() == Some(&'_') {
                out.push('_');
                chars.next();
            }
            continue;
        }
        out.push(c);
    }
    out
}

/// A key as people write it: [["Control", "q"]] → "Ctrl+Q"
pub fn shortcut_text(sequences: &[Vec<String>]) -> String {
    let key = |part: &str| -> String {
        match part {
            "Control" => "Ctrl".into(),
            "Super" => "Meta".into(),
            part if part.chars().count() == 1 => part.to_uppercase(),
            part => part.to_string(),
        }
    };
    sequences
        .iter()
        .map(|sequence| sequence.iter().map(|p| key(p)).collect::<Vec<_>>().join("+"))
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join(", ")
}

/// The properties of an entry: name → value, variants unwrapped
type Props<'a> = HashMap<String, &'a Value<'a>>;

fn props_of<'a>(dict: &'a zbus::zvariant::Dict<'a, 'a>) -> Props<'a> {
    let mut props = HashMap::new();
    for (key, value) in dict.iter() {
        let Value::Str(key) = key else { continue };
        let value = match value {
            Value::Value(inner) => &**inner,
            value => value,
        };
        props.insert(key.as_str().to_string(), value);
    }
    props
}

fn prop<'a>(props: &Props<'a>, key: &str) -> Option<&'a Value<'a>> {
    props.get(key).copied()
}

fn prop_string(props: &Props<'_>, key: &str) -> String {
    match prop(props, key) {
        Some(Value::Str(s)) => s.as_str().to_string(),
        _ => String::new(),
    }
}

fn prop_bool(props: &Props<'_>, key: &str, default: bool) -> bool {
    match prop(props, key) {
        Some(Value::Bool(b)) => *b,
        _ => default,
    }
}

/// One node of GetLayout, (ia{sv}av), with its children; None when it is hidden or broken
fn read_node(value: &Value<'_>, depth: usize, budget: &mut usize) -> Option<RawEntry> {
    // Children are variants (av), sometimes a variant in a variant
    let mut value = value;
    while let Value::Value(inner) = value {
        value = inner;
    }
    let Value::Structure(structure) = value else { return None };
    let [Value::I32(id), Value::Dict(dict), Value::Array(children)] = structure.fields() else { return None };
    let props = props_of(dict);
    if !prop_bool(&props, "visible", true) || *budget == 0 {
        return None;
    }
    *budget -= 1;
    let toggle = match prop_string(&props, "toggle-type").as_str() {
        "checkmark" => Toggle::Checkmark,
        "radio" => Toggle::Radio,
        _ => Toggle::None,
    };
    let checked = matches!(prop(&props, "toggle-state"), Some(Value::I32(1)));
    let shortcut = prop(&props, "shortcut")
        .and_then(|v| v.try_to_owned().ok())
        .and_then(|v| <Vec<Vec<String>>>::try_from(v).ok())
        .map(|s| shortcut_text(&s))
        .unwrap_or_default();
    let icon_data = prop(&props, "icon-data")
        .and_then(|v| v.try_to_owned().ok())
        .and_then(|v| <Vec<u8>>::try_from(v).ok())
        .unwrap_or_default();
    let mut entry = RawEntry {
        id: *id,
        separator: prop_string(&props, "type") == "separator",
        label: markup::limit_chars(without_mnemonics(&prop_string(&props, "label")), crate::model::MAX_TITLE_CHARS),
        enabled: prop_bool(&props, "enabled", true),
        icon_name: prop_string(&props, "icon-name").trim().to_string(),
        icon_data,
        toggle,
        checked,
        shortcut,
        submenu: prop_string(&props, "children-display") == "submenu",
        children: Vec::new(),
    };
    if depth < MAX_DEPTH {
        for child in children.iter() {
            if let Some(child) = read_node(child, depth + 1, budget) {
                entry.children.push(child);
            }
        }
    }
    entry.submenu |= !entry.children.is_empty();
    Some(entry)
}

/// The entries of a GetLayout reply's root, u(ia{sv}av)
pub fn read_layout(root: &Value<'_>) -> Vec<RawEntry> {
    let mut budget = MAX_ENTRIES + 1;
    read_node(root, 0, &mut budget).map(|root| root.children).unwrap_or_default()
}

/// Entries for the shell, their icons written (the images stay while `images` holds them)
async fn resolve(store: &ImageStoreRef, raw: Vec<RawEntry>, images: &mut Vec<ImageRef>) -> Vec<Entry> {
    let mut out = Vec::with_capacity(raw.len());
    // Depth first, without recursion in an async fn: a stack of (entries left, built so far)
    let mut stack: Vec<(std::vec::IntoIter<RawEntry>, Vec<Entry>, Option<RawEntry>)> = vec![(raw.into_iter(), Vec::new(), None)];
    while let Some((mut rest, built, parent)) = stack.pop() {
        match rest.next() {
            Some(mut entry) => {
                let children = std::mem::take(&mut entry.children);
                stack.push((rest, built, parent));
                stack.push((children.into_iter(), Vec::new(), Some(entry)));
            }
            None => {
                let Some(parent) = parent else {
                    out = built;
                    continue;
                };
                let mut icon = Icon::default();
                if parent.icon_name.starts_with('/') {
                    icon.url = url_from_path(&parent.icon_name);
                } else {
                    icon.name = parent.icon_name.clone();
                }
                if icon.is_empty() && !parent.icon_data.is_empty() {
                    if let Some(written) = ImageStore::png(store, parent.icon_data.clone()).await {
                        icon.url = written.url;
                        icon.mask = written.mask;
                        images.push(written.image);
                    }
                }
                let entry = Entry {
                    id: parent.id,
                    separator: parent.separator,
                    label: parent.label,
                    enabled: parent.enabled,
                    icon,
                    toggle: parent.toggle,
                    checked: parent.checked,
                    shortcut: parent.shortcut,
                    submenu: parent.submenu,
                    children: built,
                };
                match stack.last_mut() {
                    Some((_, siblings, _)) => siblings.push(entry),
                    None => out.push(entry),
                }
            }
        }
    }
    out
}

/// The ids of a tree's entries (activate() checks them)
fn ids(entries: &[Entry], into: &mut Vec<i32>) {
    for entry in entries {
        into.push(entry.id);
        ids(&entry.children, into);
    }
}

// --- An open menu ---

pub struct OpenMenu {
    hub: Weak<RefCell<Hub>>,
    connection: zbus::Connection,
    item: Address,
    path: String,
    /// The hub's number of this menu
    number: u64,
    known_ids: RefCell<Vec<i32>>,
    task: RefCell<Option<tokio::task::JoinHandle<()>>>,
    /// A layout is wanted (a signal, a submenu that opened)
    refresh: Rc<tokio::sync::Notify>,
}

impl OpenMenu {
    /// Opens the menu of item `id` for `listener`
    pub fn open(hub: &HubRef, id: u32, listener: menu_listener::Client) -> Result<Rc<OpenMenu>, crate::hub::OpError> {
        let (connection, item, path) = hub.borrow().menu_target(id)?;
        let number = hub.borrow_mut().add_menu(id, listener.clone());
        let menu = Rc::new(OpenMenu {
            hub: Rc::downgrade(hub),
            connection,
            item,
            path,
            number,
            known_ids: RefCell::new(Vec::new()),
            task: RefCell::new(None),
            refresh: Rc::new(tokio::sync::Notify::new()),
        });
        let task = tokio::task::spawn_local(run(Rc::downgrade(&menu), listener, hub.borrow().images()));
        *menu.task.borrow_mut() = Some(task);
        Ok(menu)
    }

    fn call<B>(&self, method: &'static str, body: B)
    where
        B: serde::ser::Serialize + zbus::zvariant::DynamicType + 'static,
    {
        let connection = self.connection.clone();
        let (name, path) = (self.item.name.clone(), self.path.clone());
        tokio::task::spawn_local(async move {
            let call = connection.call_method(Some(name.as_str()), path.as_str(), Some(INTERFACE), method, &body);
            let _ = tokio::time::timeout(CALL_TIMEOUT, call).await;
        });
    }

    fn event(&self, id: i32, kind: &'static str) {
        self.call("Event", (id, kind, Value::I32(0), 0u32));
    }

    pub fn about_to_show(self: &Rc<Self>, id: i32) {
        let weak = Rc::downgrade(self);
        let connection = self.connection.clone();
        let (name, path) = (self.item.name.clone(), self.path.clone());
        tokio::task::spawn_local(async move {
            let body = (id,);
            let call = connection.call_method(Some(name.as_str()), path.as_str(), Some(INTERFACE), "AboutToShow", &body);
            let update = match tokio::time::timeout(CALL_TIMEOUT, call).await {
                Ok(Ok(reply)) => reply.body().deserialize::<bool>().unwrap_or(true),
                _ => false,
            };
            if let Some(menu) = weak.upgrade() {
                menu.event(id, "opened");
                if update {
                    menu.refresh.notify_one();
                }
            }
        });
    }

    pub fn submenu_closed(&self, id: i32) {
        self.event(id, "closed");
    }

    /// The user picked entry `id`
    pub fn activate(&self, id: i32, token: &str) -> Result<(), crate::hub::OpError> {
        if !self.known_ids.borrow().contains(&id) {
            return Err(crate::hub::OpError::new(crate::hub::ErrorCode::NotFound, format!("no menu entry {id}")));
        }
        let connection = self.connection.clone();
        let (item, path, token) = (self.item.clone(), self.path.clone(), token.to_string());
        tokio::task::spawn_local(async move {
            // The window the entry raises ("Show Telegram") may come forward
            if !token.is_empty() {
                crate::sni::provide_token(&connection, &item, &token).await;
            }
            let body = (id, "clicked", Value::I32(0), 0u32);
            let call = connection.call_method(Some(item.name.as_str()), path.as_str(), Some(INTERFACE), "Event", &body);
            let _ = tokio::time::timeout(CALL_TIMEOUT, call).await;
        });
        Ok(())
    }
}

impl Drop for OpenMenu {
    fn drop(&mut self) {
        if let Some(task) = self.task.borrow_mut().take() {
            task.abort();
        }
        if let Some(hub) = self.hub.upgrade() {
            if let Ok(mut hub) = hub.try_borrow_mut() {
                hub.remove_menu(self.number);
            }
        }
        // Closed for the application
        let connection = self.connection.clone();
        let (name, path) = (self.item.name.clone(), self.path.clone());
        tokio::task::spawn_local(async move {
            let body = (0i32, "closed", Value::I32(0), 0u32);
            let call = connection.call_method(Some(name.as_str()), path.as_str(), Some(INTERFACE), "Event", &body);
            let _ = tokio::time::timeout(CALL_TIMEOUT, call).await;
        });
    }
}

async fn get_layout(connection: &zbus::Connection, name: &str, path: &str) -> Option<Vec<RawEntry>> {
    let body = (0i32, -1i32, Vec::<String>::new());
    let call = connection.call_method(Some(name), path, Some(INTERFACE), "GetLayout", &body);
    let reply = tokio::time::timeout(CALL_TIMEOUT, call).await.ok()?.ok()?;
    let body = reply.body();
    // The root as a value like its children, (ia{sv}av)
    type Node = (i32, HashMap<String, zbus::zvariant::OwnedValue>, Vec<zbus::zvariant::OwnedValue>);
    let (_revision, (id, props, children)): (u32, Node) = body.deserialize().ok()?;
    let root = zbus::zvariant::StructureBuilder::new().add_field(id).add_field(props).add_field(children).build().ok()?;
    Some(read_layout(&Value::Structure(root)))
}

/// The open menu's task: layouts to the listener until the menu is dropped
async fn run(menu: Weak<OpenMenu>, listener: menu_listener::Client, store: ImageStoreRef) {
    let Some(this) = menu.upgrade() else { return };
    let (connection, name, path) = (this.connection.clone(), this.item.name.clone(), this.path.clone());
    let owner = this.hub.upgrade().and_then(|hub| hub.borrow().get_owner_of(&this.item)).unwrap_or_else(|| name.clone());
    // Never held while waiting: the shell's Menu alone keeps the menu open
    let refresh = this.refresh.clone();
    drop(this);

    let rule = zbus::MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender(owner.as_str())
        .and_then(|b| b.path(path.as_str()))
        .and_then(|b| b.interface(INTERFACE))
        .map(|b| b.build());
    let mut signals = match rule {
        Ok(rule) => zbus::MessageStream::for_match_rule(rule, &connection, Some(64)).await.ok(),
        Err(_) => None,
    };

    // As a menu that opens: the application may fill it now
    let body = (0i32,);
    let call = connection.call_method(Some(name.as_str()), path.as_str(), Some(INTERFACE), "AboutToShow", &body);
    let _ = tokio::time::timeout(CALL_TIMEOUT, call).await;
    let mut images: Vec<ImageRef> = Vec::new();
    let mut first = true;
    loop {
        let started = tokio::time::Instant::now();
        if let Some(raw) = get_layout(&connection, &name, &path).await {
            let mut new_images = Vec::new();
            let entries = resolve(&store, raw, &mut new_images).await;
            // The new images are taken before the old ones are let go
            drop(std::mem::replace(&mut images, new_images));
            {
                let Some(this) = menu.upgrade() else { return };
                let mut known = Vec::new();
                ids(&entries, &mut known);
                *this.known_ids.borrow_mut() = known;
                if first {
                    this.event(0, "opened");
                    first = false;
                }
            }
            let mut request = listener.layout_request();
            crate::rpc::write_menu(request.get().init_entries(entries.len() as u32), &entries);
            if request.send().promise.await.is_err() {
                return;
            }
        } else if first {
            // A menu that cannot be read is an empty one: the shell shows nothing and closes it
            let request = listener.layout_request();
            let _ = request.send().promise.await;
            first = false;
        }
        match signals.as_mut() {
            Some(stream) => {
                tokio::select! {
                    next = stream.next() => if next.is_none() { return },
                    _ = refresh.notified() => {}
                }
            }
            None => refresh.notified().await,
        }
        tokio::time::sleep_until(started + LAYOUT_INTERVAL).await;
        if let Some(stream) = signals.as_mut() {
            while let Some(Some(_)) = futures::FutureExt::now_or_never(stream.next()) {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use zbus::zvariant::StructureBuilder;

    fn node(id: i32, props: Vec<(&str, Value<'static>)>, children: Vec<Value<'static>>) -> Value<'static> {
        let props: HashMap<String, Value<'static>> = props.into_iter().map(|(k, v)| (k.to_string(), v)).collect();
        let children: Vec<Value<'static>> = children.into_iter().map(|c| Value::Value(Box::new(c))).collect();
        Value::Structure(StructureBuilder::new().add_field(id).add_field(props).add_field(children).build().unwrap())
    }

    #[test]
    fn labels_lose_their_mnemonics() {
        assert_eq!(without_mnemonics("_Quit"), "Quit");
        assert_eq!(without_mnemonics("Save __as"), "Save _as");
        assert_eq!(without_mnemonics("plain"), "plain");
    }

    #[test]
    fn shortcuts_as_people_write_them() {
        let s = |list: &[&[&str]]| list.iter().map(|seq| seq.iter().map(|p| p.to_string()).collect()).collect::<Vec<Vec<String>>>();
        assert_eq!(shortcut_text(&s(&[&["Control", "q"]])), "Ctrl+Q");
        assert_eq!(shortcut_text(&s(&[&["Control", "Shift", "Delete"], &["Super", "x"]])), "Ctrl+Shift+Delete, Meta+X");
        assert_eq!(shortcut_text(&[]), "");
    }

    #[test]
    fn a_layout_becomes_a_tree_without_hidden_entries() {
        let root = node(
            0,
            vec![("children-display", Value::from("submenu"))],
            vec![
                node(1, vec![("label", Value::from("_Show Telegram")), ("icon-name", Value::from("window"))], vec![]),
                node(2, vec![("type", Value::from("separator"))], vec![]),
                node(3, vec![("label", Value::from("Hidden")), ("visible", Value::from(false))], vec![]),
                node(
                    4,
                    vec![("label", Value::from("Status")), ("children-display", Value::from("submenu"))],
                    vec![
                        node(5, vec![("label", Value::from("Online")), ("toggle-type", Value::from("radio")), ("toggle-state", Value::from(1i32))], vec![]),
                        node(6, vec![("label", Value::from("Away")), ("toggle-type", Value::from("radio")), ("toggle-state", Value::from(0i32)), ("enabled", Value::from(false))], vec![]),
                    ],
                ),
                node(7, vec![("label", Value::from("Quit")), ("shortcut", Value::from(vec![vec!["Control".to_string(), "q".to_string()]]))], vec![]),
            ],
        );
        let entries = read_layout(&root);
        let ids: Vec<i32> = entries.iter().map(|e| e.id).collect();
        assert_eq!(ids, [1, 2, 4, 7]);
        assert_eq!(entries[0].label, "Show Telegram");
        assert_eq!(entries[0].icon_name, "window");
        assert!(entries[0].enabled && !entries[0].submenu);
        assert!(entries[1].separator);
        assert!(entries[2].submenu);
        assert_eq!(entries[2].children.len(), 2);
        assert_eq!((entries[2].children[0].toggle, entries[2].children[0].checked), (Toggle::Radio, true));
        assert!(!entries[2].children[1].checked && !entries[2].children[1].enabled);
        assert_eq!(entries[3].shortcut, "Ctrl+Q");
    }

    #[test]
    fn huge_and_broken_layouts_are_bounded() {
        let many: Vec<Value<'static>> = (1..=2000).map(|i| node(i, vec![("label", Value::from("x"))], vec![])).collect();
        assert_eq!(read_layout(&node(0, vec![], many)).len(), MAX_ENTRIES);
        let mut deep = node(100, vec![], vec![]);
        for i in (1..20).rev() {
            deep = node(i, vec![], vec![deep]);
        }
        let entries = read_layout(&node(0, vec![], vec![deep]));
        let mut depth = 0;
        let mut level = &entries;
        while let Some(first) = level.first() {
            depth += 1;
            level = &first.children;
        }
        assert_eq!(depth, MAX_DEPTH);
        assert!(read_layout(&Value::from("not a layout")).is_empty());
    }

    #[test]
    fn resolving_keeps_the_tree() {
        let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
        tokio::task::LocalSet::new().block_on(&runtime, async {
            let store = ImageStore::new(None);
            let raw = vec![
                RawEntry { id: 1, label: "a".into(), children: vec![RawEntry { id: 2, label: "b".into(), ..Default::default() }], submenu: true, ..Default::default() },
                RawEntry { id: 3, label: "c".into(), icon_name: "/x/c.png".into(), ..Default::default() },
            ];
            let mut images = Vec::new();
            let entries = resolve(&store, raw, &mut images).await;
            assert_eq!(entries.len(), 2);
            assert_eq!(entries[0].children[0].label, "b");
            assert_eq!(entries[1].icon.url, "file:///x/c.png");
            let mut all = Vec::new();
            ids(&entries, &mut all);
            assert_eq!(all, [1, 2, 3]);
        });
    }
}

//! Items in the service's terms, and how they are read from the D-Bus properties of an item
//! (org.kde.StatusNotifierItem, GetAll).
//!
//! Reading is forgiving: applications differ (a property missing, a number where a string should
//! be, a tool tip of the wrong type), and a property that cannot be read is empty, never an error
//! that hides the whole item.

use std::collections::HashMap;

use zbus::zvariant::{OwnedValue, Value};

use crate::markup;

/// The longest title and tool tip title, in characters; a tool tip's text
pub const MAX_TITLE_CHARS: usize = 200;
pub const MAX_TEXT_CHARS: usize = 1000;
/// Pixmaps of one icon taken into account; larger pixmaps are refused before any work
pub const MAX_PIXMAPS: usize = 16;
pub const MAX_PIXMAP_SIDE: i32 = 1024;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Status {
    Passive,
    #[default]
    Active,
    NeedsAttention,
}

impl Status {
    /// Unknown values count as Active: the item is shown rather than lost
    pub fn parse(text: &str) -> Status {
        match text {
            "Passive" => Status::Passive,
            "NeedsAttention" => Status::NeedsAttention,
            _ => Status::Active,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Category {
    #[default]
    ApplicationStatus,
    Communications,
    SystemServices,
    Hardware,
}

impl Category {
    pub fn parse(text: &str) -> Category {
        match text {
            "Communications" => Category::Communications,
            "SystemServices" => Category::SystemServices,
            "Hardware" => Category::Hardware,
            _ => Category::ApplicationStatus,
        }
    }
}

/// An icon as the shells get it: a theme name and/or an image URL
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Icon {
    pub name: String,
    pub url: String,
}

impl Icon {
    pub fn is_empty(&self) -> bool {
        self.name.is_empty() && self.url.is_empty()
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ToolTip {
    pub title: String,
    pub text: String,
    pub icon: Icon,
}

/// An item as the shells get it (tray.capnp Item)
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Item {
    pub id: u32,
    pub key: String,
    pub title: String,
    pub status: Status,
    pub category: Category,
    pub icon: Icon,
    pub attention_icon: Icon,
    pub overlay_icon: Icon,
    pub tool_tip: ToolTip,
    pub has_menu: bool,
    pub item_is_menu: bool,
    pub desktop_entry: String,
    pub app_name: String,
    pub app_icon: String,
}

/// One image of an icon: ARGB32, 4 bytes a pixel in network byte order (A, R, G, B)
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct Pixmap {
    pub width: i32,
    pub height: i32,
    pub data: Vec<u8>,
}

impl Pixmap {
    pub fn is_valid(&self) -> bool {
        self.width > 0
            && self.height > 0
            && self.width <= MAX_PIXMAP_SIDE
            && self.height <= MAX_PIXMAP_SIDE
            && self.data.len() == self.width as usize * self.height as usize * 4
    }
}

/// An icon as the application gives it, before its images are written
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct RawIcon {
    pub name: String,
    pub pixmaps: Vec<Pixmap>,
}

impl RawIcon {
    pub fn is_empty(&self) -> bool {
        self.name.is_empty() && self.pixmaps.is_empty()
    }
}

/// What the properties of an item say
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Properties {
    pub id: String,
    pub title: String,
    pub status: Status,
    pub category: Category,
    pub icon: RawIcon,
    pub attention_icon: RawIcon,
    pub overlay_icon: RawIcon,
    /// The application's own icon directory, where its icon names are looked up first
    pub icon_theme_path: String,
    pub tool_tip_title: String,
    pub tool_tip_text: String,
    pub tool_tip_icon: RawIcon,
    pub item_is_menu: bool,
    /// The object path of its com.canonical.dbusmenu, "" none
    pub menu: String,
}

fn value<'a>(map: &'a HashMap<String, OwnedValue>, key: &str) -> Option<&'a Value<'static>> {
    map.get(key).map(|v| &**v)
}

fn string(map: &HashMap<String, OwnedValue>, key: &str) -> String {
    match value(map, key) {
        Some(Value::Str(s)) => s.as_str().to_string(),
        Some(Value::ObjectPath(p)) => p.as_str().to_string(),
        Some(Value::Value(inner)) => match &**inner {
            Value::Str(s) => s.as_str().to_string(),
            _ => String::new(),
        },
        _ => String::new(),
    }
}

fn boolean(map: &HashMap<String, OwnedValue>, key: &str) -> bool {
    match value(map, key) {
        Some(Value::Bool(b)) => *b,
        Some(Value::I32(v)) => *v != 0,
        Some(Value::U32(v)) => *v != 0,
        _ => false,
    }
}

/// a(iiay), the type of IconPixmap; anything else gives none
pub fn pixmaps(value: Option<&Value<'_>>) -> Vec<Pixmap> {
    let Some(value) = value else { return Vec::new() };
    let Ok(owned) = value.try_to_owned() else { return Vec::new() };
    let Ok(list) = <Vec<(i32, i32, Vec<u8>)>>::try_from(owned) else { return Vec::new() };
    list.into_iter()
        .take(MAX_PIXMAPS)
        .map(|(width, height, data)| Pixmap { width, height, data })
        .filter(Pixmap::is_valid)
        .collect()
}

/// An icon name: trimmed; an absolute path stays a path (image.rs makes it a URL)
fn icon_name(map: &HashMap<String, OwnedValue>, key: &str) -> String {
    string(map, key).trim().to_string()
}

fn raw_icon(map: &HashMap<String, OwnedValue>, name: &str, pixmap: &str) -> RawIcon {
    RawIcon { name: icon_name(map, name), pixmaps: pixmaps(value(map, pixmap)) }
}

/// The menu's object path, without the values applications use for "none"
fn menu_path(map: &HashMap<String, OwnedValue>) -> String {
    let path = string(map, "Menu");
    match path.as_str() {
        "" | "/" | "/NO_DBUSMENU" => String::new(),
        _ => path,
    }
}

/// The properties of an item, as GetAll gives them
pub fn read_properties(map: &HashMap<String, OwnedValue>) -> Properties {
    let mut properties = Properties {
        id: string(map, "Id").trim().to_string(),
        title: markup::limit_chars(markup::line(&string(map, "Title")), MAX_TITLE_CHARS),
        status: Status::parse(&string(map, "Status")),
        category: Category::parse(&string(map, "Category")),
        icon: raw_icon(map, "IconName", "IconPixmap"),
        attention_icon: raw_icon(map, "AttentionIconName", "AttentionIconPixmap"),
        overlay_icon: raw_icon(map, "OverlayIconName", "OverlayIconPixmap"),
        icon_theme_path: string(map, "IconThemePath").trim().to_string(),
        item_is_menu: boolean(map, "ItemIsMenu"),
        menu: menu_path(map),
        ..Properties::default()
    };
    // (sa(iiay)ss): icon name, icon pixmaps, title, text
    if let Some(Value::Structure(tool_tip)) = value(map, "ToolTip") {
        let fields = tool_tip.fields();
        if let [Value::Str(name), pixmap, Value::Str(title), Value::Str(text)] = fields {
            properties.tool_tip_icon = RawIcon { name: name.as_str().trim().to_string(), pixmaps: pixmaps(Some(pixmap)) };
            properties.tool_tip_title = markup::limit_chars(markup::line(title.as_str()), MAX_TITLE_CHARS);
            properties.tool_tip_text = markup::limit_chars(markup::plain(text.as_str()), MAX_TEXT_CHARS);
        }
    }
    properties
}

#[cfg(test)]
mod tests {
    use super::*;
    use zbus::zvariant::{ObjectPath, StructureBuilder};

    fn map(pairs: Vec<(&str, Value<'static>)>) -> HashMap<String, OwnedValue> {
        pairs.into_iter().map(|(k, v)| (k.to_string(), v.try_to_owned().unwrap())).collect()
    }

    fn red(side: i32) -> (i32, i32, Vec<u8>) {
        (side, side, [255u8, 255, 0, 0].repeat((side * side) as usize))
    }

    #[test]
    fn properties_of_a_qt_application() {
        let tool_tip = StructureBuilder::new()
            .add_field("mail-unread")
            .add_field(Vec::<(i32, i32, Vec<u8>)>::new())
            .add_field("KMail")
            .add_field("3 new messages<br/>in <b>Inbox</b>")
            .build()
            .unwrap();
        let properties = read_properties(&map(vec![
            ("Id", Value::from("org.kde.kmail2")),
            ("Title", Value::from("KMail")),
            ("Status", Value::from("NeedsAttention")),
            ("Category", Value::from("Communications")),
            ("IconName", Value::from("kmail")),
            ("AttentionIconName", Value::from("mail-unread-new")),
            ("IconPixmap", Value::from(vec![red(16), red(32)])),
            ("ToolTip", Value::Structure(tool_tip)),
            ("ItemIsMenu", Value::from(false)),
            ("Menu", Value::ObjectPath(ObjectPath::from_static_str("/MenuBar").unwrap())),
        ]));
        assert_eq!(properties.id, "org.kde.kmail2");
        assert_eq!(properties.status, Status::NeedsAttention);
        assert_eq!(properties.category, Category::Communications);
        assert_eq!(properties.icon.name, "kmail");
        assert_eq!(properties.icon.pixmaps.len(), 2);
        assert_eq!(properties.attention_icon.name, "mail-unread-new");
        assert_eq!(properties.tool_tip_title, "KMail");
        assert_eq!(properties.tool_tip_text, "3 new messages\nin Inbox");
        assert_eq!(properties.tool_tip_icon.name, "mail-unread");
        assert_eq!(properties.menu, "/MenuBar");
    }

    #[test]
    fn missing_and_odd_properties_are_empty() {
        let properties = read_properties(&map(vec![
            ("Status", Value::from("Unknown")),
            ("Title", Value::from(7u32)),
            ("ToolTip", Value::from("not a structure")),
            ("Menu", Value::ObjectPath(ObjectPath::from_static_str("/NO_DBUSMENU").unwrap())),
        ]));
        assert_eq!(properties.status, Status::Active);
        assert_eq!(properties.category, Category::ApplicationStatus);
        assert_eq!(properties.title, "");
        assert!(properties.icon.is_empty());
        assert_eq!(properties.tool_tip_text, "");
        assert_eq!(properties.menu, "");
    }

    #[test]
    fn broken_pixmaps_are_dropped() {
        let short = (4, 4, vec![0u8; 10]);
        let huge = (5000, 1, vec![0u8; 20000]);
        let empty = (0, 0, Vec::new());
        let list = pixmaps(Some(&Value::from(vec![short, huge, empty, red(8)])));
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].width, 8);
    }
}

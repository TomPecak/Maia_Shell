//! One item on the bus (org.kde.StatusNotifierItem): read, followed, clicked.
//!
//! Each item has its own task (`track`), so an application that is slow or hangs only delays its
//! own item:
//!
//! 1. who owns it: the unique name (signals come from it) and the process (desktop.rs);
//! 2. its properties, with GetAll, with a time limit; an item that cannot be read is dropped;
//! 3. its icons (image.rs), then the item goes to the hub;
//! 4. it waits for a signal of the item (NewIcon, NewStatus, …), and reads it again. Signals that
//!    come close together are one read, at most every READ_INTERVAL: an application that animates
//!    its icon costs at most a few reads a second, and an unchanged image is never written twice.
//!
//! Reading all properties after any signal is what Plasma does too; the arguments of the signals
//! (NewStatus has one) are not needed, and an application that forgets a signal is right again at
//! its next one.

use std::collections::HashMap;
use std::rc::Weak;
use std::cell::RefCell;
use std::time::Duration;

use futures::StreamExt;
use zbus::zvariant::OwnedValue;

use crate::hub::{Address, CALL_TIMEOUT, Hub, ItemRead};
use crate::image::ImageStore;
use crate::model::{Item, Properties, ToolTip, read_properties};

pub const INTERFACE: &str = "org.kde.StatusNotifierItem";

/// The shortest time between two reads of one item
pub const READ_INTERVAL: Duration = Duration::from_millis(100);

/// Calls a method of an item; a failure only goes to the log (the application decides what a click
/// does, and many leave out the methods they do not need)
pub async fn call<B>(connection: &zbus::Connection, address: &Address, method: &str, body: &B)
where
    B: serde::ser::Serialize + zbus::zvariant::DynamicType,
{
    let call = connection.call_method(Some(address.name.as_str()), address.path.as_str(), Some(INTERFACE), method, body);
    match tokio::time::timeout(CALL_TIMEOUT, call).await {
        Ok(Ok(_)) => {}
        Ok(Err(zbus::Error::MethodError(name, _, _))) if name.as_str() == "org.freedesktop.DBus.Error.UnknownMethod" => {}
        Ok(Err(error)) => eprintln!("maia-tray-service: {} {method}: {error}", address.service),
        Err(_) => eprintln!("maia-tray-service: {} {method}: no answer", address.service),
    }
}

/// Gives the item an xdg-activation token for the window it raises next (KDE's extension; items
/// without it ignore it)
pub async fn provide_token(connection: &zbus::Connection, address: &Address, token: &str) {
    let body = (token,);
    let call = connection.call_method(Some(address.name.as_str()), address.path.as_str(), Some(INTERFACE), "ProvideXdgActivationToken", &body);
    let _ = tokio::time::timeout(CALL_TIMEOUT, call).await;
}

/// The unique name that owns `name` (a unique name owns itself)
async fn owner_of(connection: &zbus::Connection, name: &str) -> Option<String> {
    if name.starts_with(':') {
        return Some(name.to_string());
    }
    let proxy = zbus::fdo::DBusProxy::new(connection).await.ok()?;
    let bus_name = zbus::names::BusName::try_from(name).ok()?;
    let owner = tokio::time::timeout(CALL_TIMEOUT, proxy.get_name_owner(bus_name)).await.ok()?.ok()?;
    Some(owner.to_string())
}

async fn process_of(connection: &zbus::Connection, owner: &str) -> crate::desktop::Process {
    let Ok(proxy) = zbus::fdo::DBusProxy::new(connection).await else { return Default::default() };
    let Ok(name) = zbus::names::BusName::try_from(owner) else { return Default::default() };
    let pid = match tokio::time::timeout(CALL_TIMEOUT, proxy.get_connection_unix_process_id(name)).await {
        Ok(Ok(pid)) => pid,
        _ => return Default::default(),
    };
    tokio::task::spawn_blocking(move || crate::desktop::process(pid)).await.unwrap_or_default()
}

enum Read {
    Properties(HashMap<String, OwnedValue>),
    /// The object or the application is gone
    Gone,
    /// It did not answer this time
    Failed,
}

async fn read(connection: &zbus::Connection, address: &Address) -> Read {
    let body = (INTERFACE,);
    let call = connection.call_method(Some(address.name.as_str()), address.path.as_str(), Some("org.freedesktop.DBus.Properties"), "GetAll", &body);
    match tokio::time::timeout(CALL_TIMEOUT, call).await {
        Ok(Ok(reply)) => match reply.body().deserialize::<HashMap<String, OwnedValue>>() {
            Ok(map) => Read::Properties(map),
            Err(_) => Read::Gone,
        },
        Ok(Err(zbus::Error::MethodError(name, _, _)))
            if matches!(
                name.as_str(),
                "org.freedesktop.DBus.Error.ServiceUnknown"
                    | "org.freedesktop.DBus.Error.UnknownObject"
                    | "org.freedesktop.DBus.Error.UnknownInterface"
                    | "org.freedesktop.DBus.Error.UnknownMethod"
                    | "org.freedesktop.DBus.Error.NameHasNoOwner"
            ) =>
        {
            Read::Gone
        }
        _ => Read::Failed,
    }
}

/// The item for the shells, with its icons written
async fn resolve(hub: &Weak<RefCell<Hub>>, properties: Properties) -> Option<ItemRead> {
    let images = hub.upgrade()?.borrow().images();
    let theme = properties.icon_theme_path.as_str();
    let icon = ImageStore::resolve(&images, &properties.icon, theme).await;
    let attention = ImageStore::resolve(&images, &properties.attention_icon, theme).await;
    let overlay = ImageStore::resolve(&images, &properties.overlay_icon, theme).await;
    let tool_tip_icon = ImageStore::resolve(&images, &properties.tool_tip_icon, theme).await;
    let item = Item {
        title: properties.title,
        status: properties.status,
        category: properties.category,
        icon: icon.icon,
        attention_icon: attention.icon,
        overlay_icon: overlay.icon,
        tool_tip: ToolTip { title: properties.tool_tip_title, text: properties.tool_tip_text, icon: tool_tip_icon.icon },
        has_menu: !properties.menu.is_empty(),
        item_is_menu: properties.item_is_menu,
        ..Item::default()
    };
    let images = [icon.image, attention.image, overlay.image, tool_tip_icon.image].into_iter().flatten().collect();
    Some(ItemRead { item, images, menu_path: properties.menu, sni_id: properties.id })
}

/// Follows one item until it is gone (or the hub removes it and aborts the task)
pub async fn track(hub: Weak<RefCell<Hub>>, id: u32, address: Address, connection: zbus::Connection) {
    let remove = |hub: &Weak<RefCell<Hub>>| {
        if let Some(hub) = hub.upgrade() {
            Hub::remove_item(&hub, id);
        }
    };
    let Some(owner) = owner_of(&connection, &address.name).await else {
        remove(&hub);
        return;
    };
    // Subscribed before the first read: a change in between is not lost
    let rule = zbus::MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender(owner.as_str())
        .and_then(|b| b.path(address.path.as_str()))
        .and_then(|b| b.interface(INTERFACE))
        .map(|b| b.build());
    let mut signals = match rule {
        Ok(rule) => match zbus::MessageStream::for_match_rule(rule, &connection, Some(64)).await {
            Ok(stream) => stream,
            Err(error) => {
                eprintln!("maia-tray-service: {}: {error}", address.service);
                remove(&hub);
                return;
            }
        },
        Err(_) => {
            remove(&hub);
            return;
        }
    };
    let process = process_of(&connection, &owner).await;
    match hub.upgrade() {
        Some(hub) => Hub::set_owner(&hub, id, owner, process),
        None => return,
    }

    let mut read_once = false;
    loop {
        let started = tokio::time::Instant::now();
        match read(&connection, &address).await {
            Read::Properties(map) => {
                let Some(read) = resolve(&hub, read_properties(&map)).await else { return };
                let Some(hub) = hub.upgrade() else { return };
                Hub::item_read(&hub, id, read);
                read_once = true;
            }
            Read::Gone => {
                remove(&hub);
                return;
            }
            // Never answered: never shown. A later failure keeps what was read.
            Read::Failed if !read_once => {
                eprintln!("maia-tray-service: {} does not answer", address.service);
                remove(&hub);
                return;
            }
            Read::Failed => {}
        }

        // Until a signal; the ones that come meanwhile are one read
        if signals.next().await.is_none() {
            remove(&hub);
            return;
        }
        tokio::time::sleep_until(started + READ_INTERVAL).await;
        while let Some(Some(_)) = futures::FutureExt::now_or_never(signals.next()) {}
    }
}

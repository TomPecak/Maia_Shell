//! Reading D-Bus properties (a{sv}) into plain values; a missing or mistyped value reads as its
//! default, as the sources' own clients do.

use std::collections::HashMap;

use zbus::Connection;
use zbus::zvariant::{OwnedObjectPath, OwnedValue};

pub type Props = HashMap<String, OwnedValue>;

pub const PROPERTIES: &str = "org.freedesktop.DBus.Properties";

pub fn u32_of(props: &Props, key: &str) -> u32 {
    props.get(key).and_then(|v| u32::try_from(&**v).ok()).unwrap_or(0)
}

pub fn i64_of(props: &Props, key: &str) -> i64 {
    props.get(key).and_then(|v| i64::try_from(&**v).ok()).unwrap_or(0)
}

pub fn f64_of(props: &Props, key: &str) -> f64 {
    props.get(key).and_then(|v| f64::try_from(&**v).ok()).unwrap_or(0.0)
}

pub fn bool_of(props: &Props, key: &str) -> bool {
    props.get(key).and_then(|v| bool::try_from(&**v).ok()).unwrap_or(false)
}

pub fn string_of(props: &Props, key: &str) -> String {
    props.get(key).and_then(|v| <&str>::try_from(&**v).ok()).map(str::to_string).unwrap_or_default()
}

pub fn owned<T: TryFrom<OwnedValue>>(props: &Props, key: &str) -> Option<T> {
    props.get(key).and_then(|v| v.try_clone().ok()).and_then(|v| T::try_from(v).ok())
}

/// A list of dictionaries (aa{sv}), as power-profiles-daemon's Profiles and ActiveProfileHolds
pub fn dicts_of(props: &Props, key: &str) -> Vec<Props> {
    owned::<Vec<Props>>(props, key).unwrap_or_default()
}

pub async fn get_all(conn: &Connection, dest: &str, path: &str, interface: &str) -> zbus::Result<Props> {
    let reply = conn.call_method(Some(dest), path, Some(PROPERTIES), "GetAll", &(interface,)).await?;
    reply.body().deserialize::<Props>()
}

pub async fn call<B, R>(conn: &Connection, dest: &str, path: &str, interface: &str, method: &str, body: &B) -> zbus::Result<R>
where
    B: serde::ser::Serialize + zbus::zvariant::DynamicType,
    R: for<'d> zbus::zvariant::DynamicDeserialize<'d>,
{
    let reply = conn.call_method(Some(dest), path, Some(interface), method, body).await?;
    reply.body().deserialize::<R>()
}

pub fn paths(values: Vec<OwnedObjectPath>) -> Vec<String> {
    values.into_iter().map(|p| p.as_str().to_string()).collect()
}

/// Whether a bus name has an owner now
pub async fn has_owner(conn: &Connection, name: &str) -> bool {
    call::<_, bool>(conn, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner", &(name,))
        .await
        .unwrap_or(false)
}

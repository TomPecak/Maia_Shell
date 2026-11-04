//! Prints the settings of every Wi-Fi profile as the details editor would read them. Read-only
//! (GetSettings, which returns no secrets); does not register a secret agent.

use std::collections::HashMap;

use maia_network::nmsettings::{SettingsDict, read_settings};
use zbus::Connection;
use zbus::zvariant::OwnedObjectPath;

#[tokio::main(flavor = "current_thread")]
async fn main() -> zbus::Result<()> {
    let conn = Connection::system().await?;
    let nm = "org.freedesktop.NetworkManager";
    let reply = conn
        .call_method(Some(nm), "/org/freedesktop/NetworkManager/Settings", Some("org.freedesktop.NetworkManager.Settings"), "ListConnections", &())
        .await?;
    let paths: Vec<OwnedObjectPath> = reply.body().deserialize()?;
    for path in paths {
        let reply =
            conn.call_method(Some(nm), &path, Some("org.freedesktop.NetworkManager.Settings.Connection"), "GetSettings", &()).await?;
        let dict: SettingsDict = reply.body().deserialize()?;
        let kind = dict.get("connection").and_then(|c: &HashMap<_, _>| c.get("type")).and_then(|v| <&str>::try_from(&**v).ok());
        if kind == Some("802-11-wireless") {
            println!("{:#?}", read_settings(&dict));
        }
    }
    Ok(())
}

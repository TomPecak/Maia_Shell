//! Prints the state the network service serves, then every change, until Ctrl+C.
//!
//!   cargo run --example watch [socket]
//!
//! Only watches: it sends no command, so it is safe against the real NetworkManager.
//! Socket: the argument, $MAIA_NETWORK_SOCKET, or $XDG_RUNTIME_DIR/maia/network-$WAYLAND_DISPLAY.sock

use std::rc::Rc;

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use maia_network::network_capnp::{self as n, network_listener, network_service};
use tokio_util::compat::TokioAsyncReadCompatExt;

struct Printer;

fn device(d: n::wifi_device::Reader) -> capnp::Result<String> {
    Ok(format!(
        "device {} {:?} ({:?}) active={} hotspot={} bitrate={}kbit/s bands={:#x} scanning={} ip4={}",
        d.get_id()?.to_str()?,
        d.get_state()?,
        d.get_state_reason()?,
        d.get_active_network_id()?.to_str()?,
        d.get_hotspot(),
        d.get_bitrate(),
        d.get_bands(),
        d.get_scanning(),
        d.get_ip4()?.get_addresses()?.iter().filter_map(|a| a.get_address().ok()?.to_str().ok().map(String::from)).collect::<Vec<_>>().join(","),
    ))
}

fn network(n: n::wifi_network::Reader) -> capnp::Result<String> {
    Ok(format!(
        "network {:<24} {:?} {:>3}% {}MHz aps={} saved={} active={}",
        n.get_name()?.to_str()?,
        n.get_security()?,
        n.get_strength(),
        n.get_frequency(),
        n.get_access_points()?.len(),
        n.get_connection_uuids()?.len(),
        n.get_active(),
    ))
}

fn connection(c: n::saved_connection::Reader) -> capnp::Result<String> {
    Ok(format!(
        "connection {:<24} {:?} autoconnect={} hidden={} hotspot={} active on '{}'",
        c.get_name()?.to_str()?,
        c.get_security()?,
        c.get_autoconnect(),
        c.get_hidden(),
        c.get_hotspot(),
        c.get_active_device_id()?.to_str()?,
    ))
}

fn status(s: n::status::Reader) -> capnp::Result<String> {
    let p = s.get_primary()?;
    Ok(format!(
        "status running={} wifi={} hardware={} connectivity={:?} primary={:?} '{}' on {}",
        s.get_running(),
        s.get_wireless_enabled(),
        s.get_wireless_hardware_enabled(),
        s.get_connectivity()?,
        p.get_type()?,
        p.get_name()?.to_str()?,
        p.get_device_id()?.to_str()?,
    ))
}

impl network_listener::Server for Printer {
    async fn snapshot(self: Rc<Self>, p: network_listener::SnapshotParams, _: network_listener::SnapshotResults) -> Result<(), capnp::Error> {
        let s = p.get()?.get_snapshot()?;
        println!("{}", status(s.get_status()?)?);
        for d in s.get_devices()? {
            println!("{}", device(d)?);
        }
        for n in s.get_networks()? {
            println!("{}", network(n)?);
        }
        for c in s.get_connections()? {
            println!("{}", connection(c)?);
        }
        println!("--- changes:");
        Ok(())
    }
    async fn status_changed(self: Rc<Self>, p: network_listener::StatusChangedParams, _: network_listener::StatusChangedResults) -> Result<(), capnp::Error> {
        println!("{}", status(p.get()?.get_status()?)?);
        Ok(())
    }
    async fn device_changed(self: Rc<Self>, p: network_listener::DeviceChangedParams, _: network_listener::DeviceChangedResults) -> Result<(), capnp::Error> {
        println!("{}", device(p.get()?.get_device()?)?);
        Ok(())
    }
    async fn device_removed(self: Rc<Self>, p: network_listener::DeviceRemovedParams, _: network_listener::DeviceRemovedResults) -> Result<(), capnp::Error> {
        println!("device removed {}", p.get()?.get_id()?.to_str()?);
        Ok(())
    }
    async fn network_changed(self: Rc<Self>, p: network_listener::NetworkChangedParams, _: network_listener::NetworkChangedResults) -> Result<(), capnp::Error> {
        println!("{}", network(p.get()?.get_network()?)?);
        Ok(())
    }
    async fn network_removed(self: Rc<Self>, p: network_listener::NetworkRemovedParams, _: network_listener::NetworkRemovedResults) -> Result<(), capnp::Error> {
        println!("network removed {}", p.get()?.get_id()?.to_str()?);
        Ok(())
    }
    async fn connection_changed(self: Rc<Self>, p: network_listener::ConnectionChangedParams, _: network_listener::ConnectionChangedResults) -> Result<(), capnp::Error> {
        println!("{}", connection(p.get()?.get_connection()?)?);
        Ok(())
    }
    async fn connection_removed(self: Rc<Self>, p: network_listener::ConnectionRemovedParams, _: network_listener::ConnectionRemovedResults) -> Result<(), capnp::Error> {
        println!("connection removed {}", p.get()?.get_uuid()?.to_str()?);
        Ok(())
    }
    async fn event(self: Rc<Self>, p: network_listener::EventParams, _: network_listener::EventResults) -> Result<(), capnp::Error> {
        match p.get()?.get_event()?.which()? {
            n::event::ActivationFailed(f) => {
                let f = f?;
                println!("event: activation of '{}' failed: {:?}", f.get_name()?.to_str()?, f.get_reason()?)
            }
            n::event::Connected(uuid) => println!("event: connected {}", uuid?.to_str()?),
        }
        Ok(())
    }
}

fn socket() -> std::path::PathBuf {
    if let Some(path) = std::env::args().nth(1).or_else(|| std::env::var("MAIA_NETWORK_SOCKET").ok()) {
        return path.into();
    }
    let runtime = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
    let display = std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
    format!("{runtime}/maia/network-{}.sock", display.rsplit('/').next().unwrap_or("wayland-0")).into()
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build()?;
    tokio::task::LocalSet::new().block_on(&runtime, async {
        let stream = tokio::net::UnixStream::connect(socket()).await?;
        let (reader, writer) = stream.compat().split();
        let network = twoparty::VatNetwork::new(reader, writer, rpc_twoparty_capnp::Side::Client, Default::default());
        let mut rpc = RpcSystem::new(Box::new(network), None);
        let service: network_service::Client = rpc.bootstrap(rpc_twoparty_capnp::Side::Server);
        tokio::task::spawn_local(rpc);
        let mut request = service.watch_request();
        request.get().set_listener(capnp_rpc::new_client(Printer));
        let _subscription = request.send().promise.await?;
        tokio::signal::ctrl_c().await?;
        Ok(())
    })
}

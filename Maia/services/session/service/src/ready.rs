//! The ready helper: `maia-session-service --compositor-ready`.
//!
//! The compositor starts it once its display is up (KWin as an application on its command line,
//! Wayfire from [autostart] through $MAIA_SESSION_SCRIPT). It inherits the compositor's
//! environment and hands the display variables to the session service through
//! $MAIA_SESSION_SOCKET, then ends. Under KWin it runs again after every restart of KWin by its
//! wrapper, which the service notes in the log.

use std::time::Duration;

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use tokio_util::compat::TokioAsyncReadCompatExt;

use crate::session::DISPLAY_VARIABLES;
use crate::session_capnp::session_service;

const TIMEOUT: Duration = Duration::from_secs(10);

pub async fn report() -> Result<(), String> {
    let socket = std::env::var("MAIA_SESSION_SOCKET").map_err(|_| "MAIA_SESSION_SOCKET is not set".to_string())?;
    let variables: Vec<(String, String)> = DISPLAY_VARIABLES
        .iter()
        .filter_map(|name| std::env::var(name).ok().filter(|v| !v.is_empty()).map(|v| (name.to_string(), v)))
        .collect();
    if !variables.iter().any(|(name, _)| name == "WAYLAND_DISPLAY") {
        return Err("WAYLAND_DISPLAY is not set: not started by the compositor?".into());
    }
    let call = async {
        let stream = tokio::net::UnixStream::connect(&socket).await.map_err(|e| format!("{socket}: {e}"))?;
        let (reader, writer) = stream.compat().split();
        let network = Box::new(twoparty::VatNetwork::new(
            futures::io::BufReader::new(reader),
            futures::io::BufWriter::new(writer),
            rpc_twoparty_capnp::Side::Client,
            Default::default(),
        ));
        let mut rpc_system = RpcSystem::new(network, None);
        let service: session_service::Client = rpc_system.bootstrap(rpc_twoparty_capnp::Side::Server);
        tokio::task::spawn_local(rpc_system);
        let mut request = service.compositor_ready_request();
        let mut list = request.get().init_environment(variables.len() as u32);
        for (i, (name, value)) in variables.iter().enumerate() {
            let mut variable = list.reborrow().get(i as u32);
            variable.set_name(name);
            variable.set_value(value);
        }
        request.send().promise.await.map(|_| ()).map_err(|e| e.to_string())
    };
    tokio::time::timeout(TIMEOUT, call).await.map_err(|_| "the session service did not answer".to_string())?
}

//! Prints what a running service serves: the compositor, the themes and the choice. Read-only,
//! unless --set is given.
//!
//!   cargo run --example list [-- <socket>]                  (default: the session's socket)
//!   cargo run --example list -- <socket> --set <theme id>   (uses the theme, prints the result)

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use maia_appearance::appearance_capnp::appearance_service;
use tokio_util::compat::TokioAsyncReadCompatExt;

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();
    let set = args.iter().position(|a| a == "--set").and_then(|i| args.get(i + 1)).cloned();
    let socket = args.get(1).filter(|a| !a.starts_with("--")).map(std::path::PathBuf::from).unwrap_or_else(|| {
        let runtime = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
        let display = std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
        format!("{runtime}/maia/appearance-{display}.sock").into()
    });
    tokio::task::LocalSet::new()
        .run_until(async move {
            let stream = tokio::net::UnixStream::connect(&socket).await?;
            let (reader, writer) = stream.compat().split();
            let network = twoparty::VatNetwork::new(reader, writer, rpc_twoparty_capnp::Side::Client, Default::default());
            let mut rpc = RpcSystem::new(Box::new(network), None);
            let service: appearance_service::Client = rpc.bootstrap(rpc_twoparty_capnp::Side::Server);
            tokio::task::spawn_local(rpc);

            let info = service.info_request().send().promise.await?;
            let info = info.get()?;
            println!("backend {}, compositor {}", info.get_backend()?.to_str()?, info.get_compositor()?.to_str()?);
            let decorations = service.decorations_request().send().pipeline.get_decorations();
            if let Some(id) = &set {
                let started = std::time::Instant::now();
                let mut request = decorations.set_request();
                request.get().set_theme_id(id.as_str());
                let response = request.send().promise.await?;
                let result = response.get()?.get_result()?;
                println!("set {id}: {:?} \"{}\" after {} ms", result.get_error()?, result.get_message()?.to_str()?, started.elapsed().as_millis());
            }
            let current = decorations.current_request().send().promise.await?;
            let current = current.get()?.get_current()?;
            println!(
                "current: {} (border {:?}, confirmed {}, frontend \"{}\")",
                current.get_theme_id()?.to_str()?,
                current.get_border_size()?,
                current.get_confirmed(),
                current.get_frontend()?.to_str()?
            );
            let themes = decorations.list_request().send().promise.await?;
            for theme in themes.get()?.get_themes()? {
                println!(
                    "  {:<45} {:<28} {:?}{}",
                    theme.get_id()?.to_str()?,
                    theme.get_name()?.to_str()?,
                    theme.get_origin()?,
                    if theme.get_available() { String::new() } else { format!(" (unavailable: {})", theme.get_unavailable_reason()?.to_str()?) }
                );
            }
            Ok(())
        })
        .await
}

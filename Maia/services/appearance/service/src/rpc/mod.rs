//! The Cap'n Proto side: AppearanceService (appearance.capnp), one interface per area
//! (`decorations.rs` for decorations.capnp), and serving a client connection.
//!
//! The areas know nothing of Cap'n Proto; this layer reads parameters, calls the area's async
//! functions and writes the results, and turns the area's events into listener calls.

pub mod decorations;

use std::rc::Rc;

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use tokio_util::compat::TokioAsyncReadCompatExt;

use crate::appearance_capnp::appearance_service;
use crate::common_capnp::{self as c, result};
use crate::error::{ErrorCode, OpResult};

pub struct AppearanceService {
    backend: String,
    compositor: String,
    decorations: crate::decorations_capnp::decorations::Client,
}

impl AppearanceService {
    pub fn client(backend: &str, decorations: Rc<crate::decorations::Decorations>) -> appearance_service::Client {
        let compositor = decorations.info().name.clone();
        let decorations = decorations::DecorationsServer::client(decorations);
        capnp_rpc::new_client(AppearanceService { backend: backend.into(), compositor, decorations })
    }
}

impl appearance_service::Server for AppearanceService {
    async fn info(
        self: Rc<Self>,
        _: appearance_service::InfoParams,
        mut results: appearance_service::InfoResults,
    ) -> Result<(), capnp::Error> {
        let mut b = results.get();
        b.set_backend(&self.backend);
        b.set_compositor(&self.compositor);
        b.set_service_version(env!("CARGO_PKG_VERSION"));
        Ok(())
    }

    async fn decorations(
        self: Rc<Self>,
        _: appearance_service::DecorationsParams,
        mut results: appearance_service::DecorationsResults,
    ) -> Result<(), capnp::Error> {
        results.get().set_decorations(self.decorations.clone());
        Ok(())
    }
}

/// Serves one client connection (until it ends)
pub fn serve(stream: tokio::net::UnixStream, service: appearance_service::Client) {
    let (reader, writer) = stream.compat().split();
    let network = twoparty::VatNetwork::new(reader, writer, rpc_twoparty_capnp::Side::Server, Default::default());
    let rpc = RpcSystem::new(Box::new(network), Some(service.client));
    tokio::task::spawn_local(async move {
        let _ = rpc.await;
    });
}

pub(crate) fn write_result<T>(mut b: result::Builder, result: &OpResult<T>) {
    match result {
        Ok(_) => b.set_error(c::ErrorCode::None),
        Err(error) => {
            b.set_error(match error.code {
                ErrorCode::NotFound => c::ErrorCode::NotFound,
                ErrorCode::NotAllowed => c::ErrorCode::NotAllowed,
                ErrorCode::InvalidArgument => c::ErrorCode::InvalidArgument,
                ErrorCode::NotSupported => c::ErrorCode::NotSupported,
                ErrorCode::Unavailable => c::ErrorCode::Unavailable,
                ErrorCode::Failed => c::ErrorCode::Failed,
                ErrorCode::AlreadyExists => c::ErrorCode::AlreadyExists,
            });
            b.set_message(&error.message);
        }
    }
}

/// Text parameters (Cap'n Proto Text may be invalid UTF-8)
pub(crate) fn text(reader: capnp::Result<capnp::text::Reader<'_>>) -> Result<String, capnp::Error> {
    Ok(reader?.to_string()?)
}

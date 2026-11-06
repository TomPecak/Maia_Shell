//! The service over a real Cap'n Proto connection (a socket pair), with the fake compositor and
//! XDG directories in a temporary directory: what a client (Maia.Appearance) sees.

use std::path::Path;
use std::rc::Rc;
use std::time::Duration;

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use maia_appearance::appearance_capnp::appearance_service;
use maia_appearance::common_capnp::ErrorCode;
use maia_appearance::compositor::fake::Fake;
use maia_appearance::decorations::Decorations;
use maia_appearance::decorations_capnp::{decorations, decorations_listener};
use maia_appearance::paths::Paths;
use maia_appearance::rpc::{AppearanceService, serve};
use maia_appearance::test_support::TempDir;
use tokio::sync::mpsc;
use tokio_util::compat::TokioAsyncReadCompatExt;

fn theme(root: &Path, name: &str) {
    let dir = root.join(name);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("metadata.desktop"), format!("[Desktop Entry]\nName={name}\n")).unwrap();
    std::fs::write(dir.join("decoration.svg"), "<svg/>").unwrap();
}

fn paths(tmp: &TempDir) -> Paths {
    let home = tmp.path().join("home");
    let maia = tmp.path().join("maia");
    theme(&maia.join("aurorae/themes"), "XBoomer");
    let plugins = tmp.path().join("plugins/org.kde.kdecoration3");
    std::fs::create_dir_all(&plugins).unwrap();
    std::fs::write(plugins.join("org.kde.breeze.so"), b"").unwrap();
    Paths {
        data_home: home.clone(),
        data_dirs: vec![home, maia.clone()],
        config_home: tmp.path().join("config"),
        maia_data_dirs: vec![maia],
        plugin_dirs: vec![tmp.path().join("plugins")],
    }
}

/// A client of the service, connected over a socket pair
async fn connect(paths: Paths, fake: Rc<Fake>) -> decorations::Client {
    let area = Decorations::start(paths, fake).await;
    let service = AppearanceService::client("fake", area);
    let (server_end, client_end) = tokio::net::UnixStream::pair().unwrap();
    serve(server_end, service);
    let (reader, writer) = client_end.compat().split();
    let network = twoparty::VatNetwork::new(reader, writer, rpc_twoparty_capnp::Side::Client, Default::default());
    let mut rpc = RpcSystem::new(Box::new(network), None);
    let client: appearance_service::Client = rpc.bootstrap(rpc_twoparty_capnp::Side::Server);
    tokio::task::spawn_local(rpc);
    let info = client.info_request().send().promise.await.unwrap();
    assert_eq!(info.get().unwrap().get_compositor().unwrap().to_str().unwrap(), "fake");
    client.decorations_request().send().pipeline.get_decorations()
}

#[derive(Debug, PartialEq)]
enum Heard {
    Snapshot { themes: Vec<String>, current: String },
    Themes(Vec<String>),
    Current { theme: String, frontend: String },
}

struct Listener(mpsc::UnboundedSender<Heard>);

fn ids(list: capnp::struct_list::Reader<maia_appearance::decorations_capnp::theme::Owned>) -> Vec<String> {
    list.iter().map(|t| t.get_id().unwrap().to_string().unwrap()).collect()
}

impl decorations_listener::Server for Listener {
    async fn snapshot(self: Rc<Self>, params: decorations_listener::SnapshotParams, _: decorations_listener::SnapshotResults) -> Result<(), capnp::Error> {
        let p = params.get()?;
        let current = p.get_current()?.get_theme_id()?.to_string()?;
        let _ = self.0.send(Heard::Snapshot { themes: ids(p.get_themes()?), current });
        Ok(())
    }

    async fn themes_changed(
        self: Rc<Self>,
        params: decorations_listener::ThemesChangedParams,
        _: decorations_listener::ThemesChangedResults,
    ) -> Result<(), capnp::Error> {
        let _ = self.0.send(Heard::Themes(ids(params.get()?.get_themes()?)));
        Ok(())
    }

    async fn current_changed(
        self: Rc<Self>,
        params: decorations_listener::CurrentChangedParams,
        _: decorations_listener::CurrentChangedResults,
    ) -> Result<(), capnp::Error> {
        let current = params.get()?.get_current()?;
        let _ = self.0.send(Heard::Current { theme: current.get_theme_id()?.to_string()?, frontend: current.get_frontend()?.to_string()? });
        Ok(())
    }
}

async fn next(heard: &mut mpsc::UnboundedReceiver<Heard>) -> Heard {
    tokio::time::timeout(Duration::from_secs(5), heard.recv()).await.expect("an event in time").expect("the listener is there")
}

fn error_of(result: maia_appearance::common_capnp::result::Reader) -> ErrorCode {
    result.get_error().unwrap()
}

#[tokio::test(flavor = "current_thread")]
async fn choosing_installing_and_frontends() {
    tokio::task::LocalSet::new()
        .run_until(async {
            let tmp = TempDir::new("service");
            let paths = paths(&tmp);
            let fake = Rc::new(Fake::new());
            let decorations = connect(paths, fake.clone()).await;

            let (sender, mut heard) = mpsc::unbounded_channel();
            let mut watch = decorations.watch_request();
            watch.get().set_listener(capnp_rpc::new_client(Listener(sender)));
            let subscription = watch.send().promise.await.unwrap();
            let _keep = subscription.get().unwrap().get_subscription().unwrap();
            assert_eq!(
                next(&mut heard).await,
                Heard::Snapshot { themes: vec!["kdecoration:org.kde.breeze".into(), "aurorae-svg:XBoomer".into()], current: "kdecoration:org.kde.breeze".into() }
            );

            // A frontend's first start: its default is used and remembered
            let mut activate = decorations.activate_frontend_request();
            activate.get().set_frontend("XPLuna");
            activate.get().set_default_theme_id("aurorae-svg:XBoomer");
            let activated = activate.send().promise.await.unwrap();
            assert_eq!(error_of(activated.get().unwrap().get_result().unwrap()), ErrorCode::None);
            let activation = activated.get().unwrap().get_activation().unwrap();
            assert_eq!(next(&mut heard).await, Heard::Current { theme: "kdecoration:org.kde.breeze".into(), frontend: "XPLuna".into() });
            assert_eq!(next(&mut heard).await, Heard::Current { theme: "aurorae-svg:XBoomer".into(), frontend: "XPLuna".into() });
            assert_eq!(fake.state().theme.unwrap().to_string(), "aurorae-svg:XBoomer");

            // Installing from an archive: the list grows, nothing is chosen
            let source = tmp.path().join("src");
            theme(&source, "Glass");
            let archive = tmp.path().join("Glass.tar.xz");
            assert!(std::process::Command::new("tar").current_dir(&source).arg("-cJf").arg(&archive).arg("Glass").status().unwrap().success());
            let mut install = decorations.install_request();
            install.get().set_path(archive.to_str().unwrap());
            let installed = install.send().promise.await.unwrap();
            assert_eq!(error_of(installed.get().unwrap().get_result().unwrap()), ErrorCode::None);
            assert_eq!(installed.get().unwrap().get_theme_id().unwrap().to_str().unwrap(), "aurorae-svg:Glass");
            assert_eq!(
                next(&mut heard).await,
                Heard::Themes(vec!["aurorae-svg:Glass".into(), "kdecoration:org.kde.breeze".into(), "aurorae-svg:XBoomer".into()])
            );

            // Errors are results, not exceptions
            let mut set = decorations.set_request();
            set.get().set_theme_id("aurorae-svg:Missing");
            assert_eq!(error_of(set.send().promise.await.unwrap().get().unwrap().get_result().unwrap()), ErrorCode::NotFound);
            let mut remove = decorations.remove_request();
            remove.get().set_theme_id("aurorae-svg:XBoomer");
            assert_eq!(error_of(remove.send().promise.await.unwrap().get().unwrap().get_result().unwrap()), ErrorCode::NotAllowed);

            // Releasing the activation ends the frontend's turn (the response holds it too)
            drop(activation);
            drop(activated);
            assert_eq!(next(&mut heard).await, Heard::Current { theme: "aurorae-svg:XBoomer".into(), frontend: String::new() });

            // The user's theme can be removed when it is not in use
            let mut remove = decorations.remove_request();
            remove.get().set_theme_id("aurorae-svg:Glass");
            assert_eq!(error_of(remove.send().promise.await.unwrap().get().unwrap().get_result().unwrap()), ErrorCode::None);
            assert_eq!(next(&mut heard).await, Heard::Themes(vec!["kdecoration:org.kde.breeze".into(), "aurorae-svg:XBoomer".into()]));
        })
        .await;
}

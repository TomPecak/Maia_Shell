//! The service over a real Cap'n Proto connection, with a fake backend instead of KWin.
//!
//! Each test builds the service like main.rs does, connects a client through a socket pair and
//! plays the compositor by sending BackendEvents and reading Commands.

use std::path::PathBuf;
use std::rc::Rc;
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::Duration;

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use tokio::sync::mpsc;
use tokio_util::compat::TokioAsyncReadCompatExt;

use maia_windows::apps::AppIndex;
use maia_windows::backend::{BackendEvent, BackendInfo, Command};
use maia_windows::model::Window;
use maia_windows::rpc::{Hub, HubRef, WindowService};
use maia_windows::windows_capnp::{self as w, window_listener, window_service};

const TIMEOUT: Duration = Duration::from_secs(5);

/// What the test listener received, in a form easy to compare
#[derive(Debug, PartialEq)]
enum Heard {
    Snapshot(Vec<String>),
    Added(String, String),
    Changed(String, String),
    Removed(String),
}

struct Listener(mpsc::UnboundedSender<Heard>);

fn describe(window: w::window::Reader) -> capnp::Result<(String, String)> {
    Ok((window.get_id()?.to_string()?, window.get_title()?.to_string()?))
}

impl window_listener::Server for Listener {
    async fn snapshot(
        self: Rc<Self>,
        params: window_listener::SnapshotParams,
        _: window_listener::SnapshotResults,
    ) -> Result<(), capnp::Error> {
        let mut ids = Vec::new();
        for window in params.get()?.get_windows()? {
            ids.push(window.get_id()?.to_string()?);
        }
        let _ = self.0.send(Heard::Snapshot(ids));
        Ok(())
    }

    async fn added(
        self: Rc<Self>,
        params: window_listener::AddedParams,
        _: window_listener::AddedResults,
    ) -> Result<(), capnp::Error> {
        let (id, title) = describe(params.get()?.get_window()?)?;
        let _ = self.0.send(Heard::Added(id, title));
        Ok(())
    }

    async fn changed(
        self: Rc<Self>,
        params: window_listener::ChangedParams,
        _: window_listener::ChangedResults,
    ) -> Result<(), capnp::Error> {
        let (id, title) = describe(params.get()?.get_window()?)?;
        let _ = self.0.send(Heard::Changed(id, title));
        Ok(())
    }

    async fn removed(
        self: Rc<Self>,
        params: window_listener::RemovedParams,
        _: window_listener::RemovedResults,
    ) -> Result<(), capnp::Error> {
        let _ = self.0.send(Heard::Removed(params.get()?.get_id()?.to_string()?));
        Ok(())
    }
}

/// The service with a fake backend and one connected client
struct Setup {
    hub: HubRef,
    client: window_service::Client,
    commands: mpsc::UnboundedReceiver<Command>,
}

fn applications() -> PathBuf {
    static COUNTER: AtomicU32 = AtomicU32::new(0);
    let dir = std::env::temp_dir().join(format!(
        "maia-windows-service-test-{}-{}",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(
        dir.join("org.kde.konsole.desktop"),
        "[Desktop Entry]\nType=Application\nName=Konsole\nIcon=utilities-terminal\nExec=konsole\n",
    )
    .unwrap();
    dir
}

fn setup() -> Setup {
    let hub = Hub::new(AppIndex::new(vec![applications()], "C"));
    let (command_sender, commands) = mpsc::unbounded_channel();
    let info = BackendInfo { name: "fake".into(), capabilities: w::CAP_ACTIVATE | w::CAP_MINIMIZE };
    let service = WindowService::client(hub.clone(), command_sender, info);

    let (server_end, client_end) = tokio::net::UnixStream::pair().unwrap();
    maia_windows::rpc::serve(server_end, service);
    let (reader, writer) = client_end.compat().split();
    let network = twoparty::VatNetwork::new(
        futures::io::BufReader::new(reader),
        futures::io::BufWriter::new(writer),
        rpc_twoparty_capnp::Side::Client,
        Default::default(),
    );
    let mut rpc_system = RpcSystem::new(Box::new(network), None);
    let client: window_service::Client = rpc_system.bootstrap(rpc_twoparty_capnp::Side::Server);
    tokio::task::spawn_local(rpc_system);
    Setup { hub, client, commands }
}

fn window(id: &str, title: &str) -> Window {
    Window { id: id.into(), title: title.into(), raw_app_id: "org.kde.konsole".into(), ..Default::default() }
}

async fn next<T>(receiver: &mut mpsc::UnboundedReceiver<T>) -> T {
    tokio::time::timeout(TIMEOUT, receiver.recv()).await.expect("timed out").expect("channel closed")
}

/// Everything heard until nothing more comes for a while
async fn heard_until_quiet(receiver: &mut mpsc::UnboundedReceiver<Heard>) -> Vec<Heard> {
    let mut heard = Vec::new();
    while let Ok(Some(item)) = tokio::time::timeout(Duration::from_millis(100), receiver.recv()).await {
        heard.push(item);
    }
    heard
}

/// The id of the window a message is about
fn window_of(heard: &Heard) -> &str {
    match heard {
        Heard::Added(id, _) | Heard::Changed(id, _) | Heard::Removed(id) => id,
        Heard::Snapshot(_) => "",
    }
}

/// A watching listener, after its snapshot
async fn watch(setup: &Setup) -> (mpsc::UnboundedReceiver<Heard>, w::subscription::Client) {
    let (sender, mut heard) = mpsc::unbounded_channel();
    let mut request = setup.client.watch_request();
    request.get().set_listener(capnp_rpc::new_client(Listener(sender)));
    let response = request.send().promise.await.unwrap();
    let subscription = response.get().unwrap().get_subscription().unwrap();
    assert!(matches!(next(&mut heard).await, Heard::Snapshot(_)));
    (heard, subscription)
}

/// Runs a test inside a LocalSet, like the service runs
fn local_test(test: impl std::future::Future<Output = ()>) {
    let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
    tokio::task::LocalSet::new().block_on(&runtime, test);
}

#[test]
fn info_reports_backend_and_capabilities() {
    local_test(async {
        let setup = setup();
        let response = setup.client.info_request().send().promise.await.unwrap();
        let info = response.get().unwrap();
        assert_eq!(info.get_backend().unwrap().to_str().unwrap(), "fake");
        assert_eq!(info.get_capabilities(), w::CAP_ACTIVATE | w::CAP_MINIMIZE | w::CAP_LAUNCH);
    });
}

#[test]
fn listener_gets_snapshot_then_changes_in_order() {
    local_test(async {
        let setup = setup();
        Hub::apply(&setup.hub, BackendEvent::Window(window("a", "first")));

        let (sender, mut heard) = mpsc::unbounded_channel();
        let mut request = setup.client.watch_request();
        request.get().set_listener(capnp_rpc::new_client(Listener(sender)));
        let response = request.send().promise.await.unwrap();
        let _subscription = response.get().unwrap().get_subscription().unwrap();
        assert_eq!(next(&mut heard).await, Heard::Snapshot(vec!["a".into()]));

        Hub::apply(&setup.hub, BackendEvent::Window(window("b", "second")));
        Hub::apply(&setup.hub, BackendEvent::Window(window("a", "first"))); // no real change
        Hub::apply(&setup.hub, BackendEvent::Window(window("a", "renamed")));
        Hub::apply(&setup.hub, BackendEvent::Removed("b".into()));
        Hub::apply(&setup.hub, BackendEvent::Removed("unknown".into())); // nothing to tell

        // The messages of one window keep their order; those of different windows need not (a
        // change may wait for the end of a frame, see throttle.rs)
        let heard = heard_until_quiet(&mut heard).await;
        let of = |id: &str| heard.iter().filter(|h| window_of(h) == id).collect::<Vec<_>>();
        assert_eq!(of("a"), [&Heard::Changed("a".into(), "renamed".into())]);
        assert_eq!(of("b"), [&Heard::Added("b".into(), "second".into()), &Heard::Removed("b".into())]);
        assert_eq!(heard.len(), 3, "nothing more expected: {heard:?}");
    });
}

#[test]
fn a_burst_of_changes_arrives_as_the_latest_state() {
    local_test(async {
        let setup = setup();
        Hub::apply(&setup.hub, BackendEvent::Window(window("a", "start")));
        let (mut heard, _subscription) = watch(&setup).await;

        // Like a window being dragged: many changes within one frame
        for i in 0..100 {
            Hub::apply(&setup.hub, BackendEvent::Window(window("a", &format!("t{i}"))));
        }

        let heard = heard_until_quiet(&mut heard).await;
        // The first change may go out at once, the rest arrives as one change with the last state
        assert!(heard.len() <= 2, "{heard:?}");
        assert_eq!(heard.last(), Some(&Heard::Changed("a".into(), "t99".into())));
    });
}

#[test]
fn a_removed_window_drops_its_waiting_change() {
    local_test(async {
        let setup = setup();
        Hub::apply(&setup.hub, BackendEvent::Window(window("a", "start")));
        let (mut heard, _subscription) = watch(&setup).await;

        Hub::apply(&setup.hub, BackendEvent::Window(window("a", "one")));
        Hub::apply(&setup.hub, BackendEvent::Window(window("a", "two"))); // waits for the frame
        Hub::apply(&setup.hub, BackendEvent::Removed("a".into()));

        let heard = heard_until_quiet(&mut heard).await;
        assert_eq!(heard.last(), Some(&Heard::Removed("a".into())), "{heard:?}");
        assert!(!heard.contains(&Heard::Changed("a".into(), "two".into())), "{heard:?}");
    });
}

#[test]
fn windows_carry_the_identified_application() {
    local_test(async {
        let setup = setup();
        Hub::apply(&setup.hub, BackendEvent::Window(window("a", "Terminal")));

        struct Capture(mpsc::UnboundedSender<(String, String, String, bool)>);
        impl window_listener::Server for Capture {
            async fn snapshot(
                self: Rc<Self>,
                params: window_listener::SnapshotParams,
                _: window_listener::SnapshotResults,
            ) -> Result<(), capnp::Error> {
                let window = params.get()?.get_windows()?.get(0);
                let _ = self.0.send((
                    window.get_app_id()?.to_string()?,
                    window.get_icon_name()?.to_string()?,
                    window.get_launcher_url()?.to_string()?,
                    window.get_can_launch_new_instance(),
                ));
                Ok(())
            }
        }

        let (sender, mut heard) = mpsc::unbounded_channel();
        let mut request = setup.client.watch_request();
        request.get().set_listener(capnp_rpc::new_client(Capture(sender)));
        let _response = request.send().promise.await.unwrap();
        let (app_id, icon, launcher, can_launch) = next(&mut heard).await;
        assert_eq!(app_id, "org.kde.konsole.desktop");
        assert_eq!(icon, "utilities-terminal");
        assert_eq!(launcher, "applications:org.kde.konsole.desktop");
        assert!(can_launch);
    });
}

#[test]
fn released_subscription_stops_the_listener() {
    local_test(async {
        let setup = setup();
        let (sender, mut heard) = mpsc::unbounded_channel();
        let mut request = setup.client.watch_request();
        request.get().set_listener(capnp_rpc::new_client(Listener(sender)));
        let response = request.send().promise.await.unwrap();
        let subscription = response.get().unwrap().get_subscription().unwrap();
        assert_eq!(next(&mut heard).await, Heard::Snapshot(vec![]));
        assert_eq!(setup.hub.borrow().listener_count(), 1);

        drop(subscription);
        drop(response);
        // The release travels to the service; ask something to be sure it arrived
        setup.client.info_request().send().promise.await.unwrap();
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert_eq!(setup.hub.borrow().listener_count(), 0);
    });
}

#[test]
fn control_turns_calls_into_backend_commands() {
    local_test(async {
        let mut setup = setup();
        Hub::apply(&setup.hub, BackendEvent::Window(window("a", "x")));
        let response = setup.client.control_request().send().promise.await.unwrap();
        let control = response.get().unwrap().get_control().unwrap();

        let mut activate = control.activate_request();
        activate.get().set_id("a");
        activate.send().promise.await.unwrap();
        match next(&mut setup.commands).await {
            Command::SetState { id, flags, state } => {
                assert_eq!((id.as_str(), flags, state), ("a", w::STATE_ACTIVE, w::STATE_ACTIVE))
            }
            other => panic!("unexpected {other:?}"),
        }

        let mut restore = control.set_minimized_request();
        restore.get().set_id("a");
        restore.get().set_minimized(false);
        restore.send().promise.await.unwrap();
        match next(&mut setup.commands).await {
            Command::SetState { flags, state, .. } => assert_eq!((flags, state), (w::STATE_MINIMIZED, 0)),
            other => panic!("unexpected {other:?}"),
        }

        let mut close = control.close_request();
        close.get().set_id("a");
        close.send().promise.await.unwrap();
        assert!(matches!(next(&mut setup.commands).await, Command::Close(id) if id == "a"));

        // An unknown window is an error for the caller, and nothing reaches the backend
        let mut unknown = control.close_request();
        unknown.get().set_id("nope");
        assert!(unknown.send().promise.await.is_err());
        assert!(setup.commands.try_recv().is_err());
    });
}

#[test]
fn icon_is_fetched_from_the_backend() {
    local_test(async {
        let mut setup = setup();
        let mut with_icon = window("a", "x");
        with_icon.icon_serial = 3;
        Hub::apply(&setup.hub, BackendEvent::Window(with_icon));

        // The fake compositor answers the icon request
        let mut commands = std::mem::replace(&mut setup.commands, mpsc::unbounded_channel().1);
        tokio::task::spawn_local(async move {
            while let Some(command) = commands.recv().await {
                if let Command::FetchIcon { reply, .. } = command {
                    let _ = reply.send(vec![1, 2, 3]);
                }
            }
        });

        let mut request = setup.client.icon_request();
        request.get().set_id("a");
        let response = request.send().promise.await.unwrap();
        let icon = response.get().unwrap();
        assert_eq!(icon.get_data().unwrap(), &[1, 2, 3]);
        assert_eq!(icon.get_serial(), 3);
    });
}

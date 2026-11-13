//! The battery warnings reach the notification service: the power service with the fake backend
//! sends them to a stand-in of the notification service's Notifier on a real socket, which records
//! what it gets. Also without that service the power service goes on.

mod common;

use std::cell::{Cell, RefCell};
use std::path::PathBuf;
use std::rc::Rc;
use std::time::{Duration, Instant};

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use tokio::sync::mpsc;
use tokio_util::compat::TokioAsyncReadCompatExt;

use maia_power::backend::Commands;
use maia_power::fake::{self, FakeAction, FakeHandle, Timing};
use maia_power::notifications_capnp as n;
use maia_power::rpc::{Hub, PowerService};

use common::{connect, local};

/// What the stand-in got, one line per call: "notify 1 Battery low (Normal)", "update 1 …", "close 1"
type Log = Rc<RefCell<Vec<String>>>;

fn line(verb: &str, id: u32, r: n::notification_request::Reader) -> String {
    format!(
        "{verb} {id} {} ({:?}) {}",
        r.get_summary().unwrap().to_str().unwrap(),
        r.get_urgency().unwrap(),
        r.get_body().unwrap().to_str().unwrap()
    )
}

struct StandIn {
    log: Log,
    next: Rc<Cell<u32>>,
}

struct Handle {
    log: Log,
    id: u32,
}

impl n::notification_handle::Server for Handle {
    async fn update(
        self: Rc<Self>,
        params: n::notification_handle::UpdateParams,
        mut results: n::notification_handle::UpdateResults,
    ) -> Result<(), capnp::Error> {
        self.log.borrow_mut().push(line("update", self.id, params.get()?.get_notification()?));
        results.get().init_result().set_error(n::ErrorCode::None);
        Ok(())
    }

    async fn close(
        self: Rc<Self>,
        _: n::notification_handle::CloseParams,
        _: n::notification_handle::CloseResults,
    ) -> Result<(), capnp::Error> {
        self.log.borrow_mut().push(format!("close {}", self.id));
        Ok(())
    }
}

impl n::notifier::Server for StandIn {
    async fn notify(
        self: Rc<Self>,
        params: n::notifier::NotifyParams,
        mut results: n::notifier::NotifyResults,
    ) -> Result<(), capnp::Error> {
        let id = self.next.get() + 1;
        self.next.set(id);
        let request = params.get()?.get_notification()?;
        assert_eq!(request.get_app_name()?.to_str()?, "Power");
        self.log.borrow_mut().push(line("notify", id, request));
        results.get().set_id(id);
        results.get().set_handle(capnp_rpc::new_client(Handle { log: self.log.clone(), id }));
        Ok(())
    }
}

fn socket(name: &str) -> PathBuf {
    std::env::temp_dir().join(format!("maia-power-{name}-{}.sock", std::process::id()))
}

/// The stand-in of the notification service, listening on `path`
fn stand_in(path: &PathBuf) -> Log {
    let _ = std::fs::remove_file(path);
    let listener = tokio::net::UnixListener::bind(path).unwrap();
    let log: Log = Rc::default();
    let notifier: n::notifier::Client = capnp_rpc::new_client(StandIn { log: log.clone(), next: Rc::default() });
    tokio::task::spawn_local(async move {
        while let Ok((stream, _)) = listener.accept().await {
            let (reader, writer) = stream.compat().split();
            let network = twoparty::VatNetwork::new(
                futures::io::BufReader::new(reader),
                futures::io::BufWriter::new(writer),
                rpc_twoparty_capnp::Side::Server,
                Default::default(),
            );
            let rpc = RpcSystem::new(Box::new(network), Some(notifier.clone().client));
            tokio::task::spawn_local(async move {
                let _ = rpc.await;
            });
        }
    });
    log
}

/// The power service with the fake backend, its warnings going to `path`
fn start(path: PathBuf) -> (maia_power::power_capnp::power_service::Client, FakeHandle) {
    let (events_tx, events_rx) = mpsc::unbounded_channel();
    let (commands, receiver) = Commands::single();
    let (handle, actions) = mpsc::unbounded_channel();
    let hub = Hub::new();
    let (notices, notice_receiver) = mpsc::unbounded_channel();
    hub.borrow_mut().set_event_sink(notices);
    tokio::task::spawn_local(maia_power::notify::run(notice_receiver, path));
    tokio::task::spawn_local(Hub::run(hub.clone(), events_rx));
    tokio::task::spawn_local(fake::run(events_tx, receiver, actions, Timing::instant()));
    (PowerService::client(hub, commands, fake::NAME), handle)
}

async fn logged(log: &Log, expected: &[&str]) {
    let start = Instant::now();
    loop {
        if log.borrow().len() >= expected.len() {
            assert_eq!(log.borrow().as_slice(), expected);
            return;
        }
        assert!(start.elapsed() < common::TIMEOUT, "waiting for {expected:?}, got {:?}", log.borrow());
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
}

#[test]
fn a_draining_battery_is_one_notification_that_the_charger_takes_away() {
    local(async {
        let path = socket("notify");
        let log = stand_in(&path);
        let (service, machine) = start(path.clone());
        let client = connect(service).await;
        client.wait("the snapshot", |s| s.snapshots == 1).await;

        machine.send(FakeAction::Charger(false)).unwrap();
        for percentage in [30.0, 9.0, 4.0] {
            machine.send(FakeAction::Percentage(percentage)).unwrap();
        }
        logged(
            &log,
            &[
                "notify 1 Battery low (Normal) 9 % left. Connect the charger.",
                "update 1 Battery critically low (Critical) 4 % left. Connect the charger now.",
            ],
        )
        .await;
        machine.send(FakeAction::Charger(true)).unwrap();
        machine.send(FakeAction::Percentage(100.0)).unwrap();
        logged(
            &log,
            &[
                "notify 1 Battery low (Normal) 9 % left. Connect the charger.",
                "update 1 Battery critically low (Critical) 4 % left. Connect the charger now.",
                "close 1",
                "notify 2 Battery charged (Low) You can unplug the charger.",
            ],
        )
        .await;
        let _ = std::fs::remove_file(path);
    });
}

#[test]
fn without_the_notification_service_the_power_service_goes_on() {
    local(async {
        let path = socket("none");
        let _ = std::fs::remove_file(&path);
        let (service, machine) = start(path);
        let client = connect(service).await;
        client.wait("the snapshot", |s| s.snapshots == 1).await;
        machine.send(FakeAction::Charger(false)).unwrap();
        machine.send(FakeAction::Percentage(9.0)).unwrap();
        client.wait("the warning level", |s| s.summary_level == Some(maia_power::power_capnp::WarningLevel::Low)).await;
        // Still serving
        machine.send(FakeAction::Percentage(50.0)).unwrap();
        client.wait("the new level", |s| s.summary_percentage == 50.0).await;
    });
}

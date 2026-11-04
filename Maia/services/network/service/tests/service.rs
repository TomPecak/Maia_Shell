//! The service over a real Cap'n Proto connection, with the fake backend (fake.rs) instead of
//! NetworkManager.
//!
//! Each test builds the service like main.rs does, connects a client through a socket pair, watches
//! the state and acts as the user: it connects, answers password requests, forgets networks.

use std::cell::RefCell;
use std::collections::VecDeque;
use std::rc::Rc;
use std::time::Duration;

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use tokio::sync::mpsc;
use tokio_util::compat::TokioAsyncReadCompatExt;

use maia_network::fake;
use maia_network::model::{Security, network_id};
use maia_network::network_capnp::{self as n, network_listener, network_service, secret_prompter};
use maia_network::prompt::Prompter;
use maia_network::rpc::{Hub, NetworkService};

const TIMEOUT: Duration = Duration::from_secs(5);

/// What the test listener received, in a form easy to compare
#[derive(Clone, Debug, PartialEq)]
enum Heard {
    Snapshot { networks: Vec<String>, connections: Vec<String> },
    Status { wireless_enabled: bool, connectivity: n::Connectivity },
    Device { state: n::DeviceState, reason: n::StateReason, active_network: String },
    Network { name: String, active: bool, known: bool },
    NetworkRemoved(String),
    Connection { uuid: String, name: String },
    ConnectionRemoved(String),
    Failed(n::StateReason),
    Connected(String),
}

struct Listener(mpsc::UnboundedSender<Heard>);

impl network_listener::Server for Listener {
    async fn snapshot(
        self: Rc<Self>,
        params: network_listener::SnapshotParams,
        _: network_listener::SnapshotResults,
    ) -> Result<(), capnp::Error> {
        let snapshot = params.get()?.get_snapshot()?;
        let mut networks = Vec::new();
        for network in snapshot.get_networks()? {
            networks.push(network.get_name()?.to_string()?);
        }
        networks.sort();
        let mut connections = Vec::new();
        for connection in snapshot.get_connections()? {
            connections.push(connection.get_name()?.to_string()?);
        }
        let _ = self.0.send(Heard::Snapshot { networks, connections });
        Ok(())
    }

    async fn status_changed(
        self: Rc<Self>,
        params: network_listener::StatusChangedParams,
        _: network_listener::StatusChangedResults,
    ) -> Result<(), capnp::Error> {
        let status = params.get()?.get_status()?;
        let _ = self
            .0
            .send(Heard::Status { wireless_enabled: status.get_wireless_enabled(), connectivity: status.get_connectivity()? });
        Ok(())
    }

    async fn device_changed(
        self: Rc<Self>,
        params: network_listener::DeviceChangedParams,
        _: network_listener::DeviceChangedResults,
    ) -> Result<(), capnp::Error> {
        let device = params.get()?.get_device()?;
        let _ = self.0.send(Heard::Device {
            state: device.get_state()?,
            reason: device.get_state_reason()?,
            active_network: device.get_active_network_id()?.to_string()?,
        });
        Ok(())
    }

    async fn device_removed(
        self: Rc<Self>,
        _: network_listener::DeviceRemovedParams,
        _: network_listener::DeviceRemovedResults,
    ) -> Result<(), capnp::Error> {
        Ok(())
    }

    async fn network_changed(
        self: Rc<Self>,
        params: network_listener::NetworkChangedParams,
        _: network_listener::NetworkChangedResults,
    ) -> Result<(), capnp::Error> {
        let network = params.get()?.get_network()?;
        let _ = self.0.send(Heard::Network {
            name: network.get_name()?.to_string()?,
            active: network.get_active(),
            known: network.get_connection_uuids()?.len() > 0,
        });
        Ok(())
    }

    async fn network_removed(
        self: Rc<Self>,
        params: network_listener::NetworkRemovedParams,
        _: network_listener::NetworkRemovedResults,
    ) -> Result<(), capnp::Error> {
        let _ = self.0.send(Heard::NetworkRemoved(params.get()?.get_id()?.to_string()?));
        Ok(())
    }

    async fn connection_changed(
        self: Rc<Self>,
        params: network_listener::ConnectionChangedParams,
        _: network_listener::ConnectionChangedResults,
    ) -> Result<(), capnp::Error> {
        let connection = params.get()?.get_connection()?;
        let _ = self.0.send(Heard::Connection {
            uuid: connection.get_uuid()?.to_string()?,
            name: connection.get_name()?.to_string()?,
        });
        Ok(())
    }

    async fn connection_removed(
        self: Rc<Self>,
        params: network_listener::ConnectionRemovedParams,
        _: network_listener::ConnectionRemovedResults,
    ) -> Result<(), capnp::Error> {
        let _ = self.0.send(Heard::ConnectionRemoved(params.get()?.get_uuid()?.to_string()?));
        Ok(())
    }

    async fn event(
        self: Rc<Self>,
        params: network_listener::EventParams,
        _: network_listener::EventResults,
    ) -> Result<(), capnp::Error> {
        let event = params.get()?.get_event()?;
        let heard = match event.which()? {
            n::event::ActivationFailed(failed) => Heard::Failed(failed?.get_reason()?),
            n::event::Connected(uuid) => Heard::Connected(uuid?.to_string()?),
        };
        let _ = self.0.send(heard);
        Ok(())
    }
}

/// How the test prompter answers, one answer per request
#[derive(Clone)]
enum Answer {
    Password(&'static str),
    Cancel,
}

/// A shell that answers password requests from a list, and remembers what it was asked
struct TestPrompter {
    answers: RefCell<VecDeque<Answer>>,
    asked: mpsc::UnboundedSender<(String, Vec<n::SecretKey>, Vec<n::Validation>)>,
}

impl secret_prompter::Server for TestPrompter {
    async fn ask(
        self: Rc<Self>,
        params: secret_prompter::AskParams,
        mut results: secret_prompter::AskResults,
    ) -> Result<(), capnp::Error> {
        let request = params.get()?.get_request()?;
        let mut keys = Vec::new();
        let mut validations = Vec::new();
        for field in request.get_fields()? {
            keys.push(field.get_key()?);
            validations.push(field.get_validation()?);
        }
        let _ = self.asked.send((request.get_name()?.to_string()?, keys, validations));
        let answer = self.answers.borrow_mut().pop_front().unwrap_or(Answer::Cancel);
        let reply = results.get().init_reply();
        match answer {
            Answer::Cancel => {
                let mut reply = reply;
                reply.set_cancelled(());
            }
            Answer::Password(password) => {
                let mut list = reply.init_secrets(1);
                let mut secret = list.reborrow().get(0);
                secret.set_key(n::SecretKey::WifiPassword);
                secret.set_value(password);
            }
        }
        Ok(())
    }

    async fn cancel(
        self: Rc<Self>,
        _: secret_prompter::CancelParams,
        _: secret_prompter::CancelResults,
    ) -> Result<(), capnp::Error> {
        Ok(())
    }
}

/// The service with the fake backend and one connected client
struct Setup {
    client: network_service::Client,
}

fn setup() -> Setup {
    let hub = Hub::new();
    let (event_sender, events) = mpsc::unbounded_channel();
    let (command_sender, commands) = mpsc::unbounded_channel();
    let (prompter, prompts) = Prompter::new();
    let service = NetworkService::client(hub.clone(), command_sender, fake::NAME);
    tokio::task::spawn_local(Hub::run(hub.clone(), events));
    tokio::task::spawn_local(Hub::run_prompts(hub, prompts));
    tokio::task::spawn_local(fake::run(event_sender, commands, prompter, fake::Timing::fast()));

    let (server_end, client_end) = tokio::net::UnixStream::pair().unwrap();
    maia_network::rpc::serve(server_end, service);
    let (reader, writer) = client_end.compat().split();
    let network = twoparty::VatNetwork::new(
        futures::io::BufReader::new(reader),
        futures::io::BufWriter::new(writer),
        rpc_twoparty_capnp::Side::Client,
        Default::default(),
    );
    let mut rpc_system = RpcSystem::new(Box::new(network), None);
    let client: network_service::Client = rpc_system.bootstrap(rpc_twoparty_capnp::Side::Server);
    tokio::task::spawn_local(rpc_system);
    Setup { client }
}

/// A watching listener and its first message (the snapshot)
async fn watch(setup: &Setup) -> (mpsc::UnboundedReceiver<Heard>, n::subscription::Client, Heard) {
    // The fake backend publishes its start state in its first turn
    tokio::time::sleep(Duration::from_millis(5)).await;
    let (sender, mut heard) = mpsc::unbounded_channel();
    let mut request = setup.client.watch_request();
    request.get().set_listener(capnp_rpc::new_client(Listener(sender)));
    let response = request.send().promise.await.unwrap();
    let subscription = response.get().unwrap().get_subscription().unwrap();
    let snapshot = tokio::time::timeout(TIMEOUT, heard.recv()).await.unwrap().unwrap();
    (heard, subscription, snapshot)
}

/// Waits until something matching comes; returns it
async fn wait_for(heard: &mut mpsc::UnboundedReceiver<Heard>, what: impl Fn(&Heard) -> bool) -> Heard {
    tokio::time::timeout(TIMEOUT, async {
        loop {
            let item = heard.recv().await.expect("listener closed");
            if what(&item) {
                return item;
            }
        }
    })
    .await
    .expect("timed out")
}

/// Everything heard until nothing more comes for a while
async fn heard_until_quiet(heard: &mut mpsc::UnboundedReceiver<Heard>) -> Vec<Heard> {
    let mut all = Vec::new();
    while let Ok(Some(item)) = tokio::time::timeout(Duration::from_millis(400), heard.recv()).await {
        all.push(item);
    }
    all
}

async fn register_prompter(
    setup: &Setup,
    answers: Vec<Answer>,
) -> (n::subscription::Client, mpsc::UnboundedReceiver<(String, Vec<n::SecretKey>, Vec<n::Validation>)>) {
    let (asked, questions) = mpsc::unbounded_channel();
    let prompter = TestPrompter { answers: RefCell::new(answers.into()), asked };
    let mut request = setup.client.register_prompter_request();
    request.get().set_prompter(capnp_rpc::new_client(prompter));
    let response = request.send().promise.await.unwrap();
    (response.get().unwrap().get_registration().unwrap(), questions)
}

async fn control(setup: &Setup) -> n::network_control::Client {
    let response = setup.client.control_request().send().promise.await.unwrap();
    response.get().unwrap().get_control().unwrap()
}

async fn connect(control: &n::network_control::Client, ssid: &str, security: Security) -> n::ErrorCode {
    let mut request = control.connect_request();
    request.get().set_network_id(network_id("wlan0", ssid.as_bytes(), security));
    let response = request.send().promise.await.unwrap();
    response.get().unwrap().get_result().unwrap().get_error().unwrap()
}

fn connected_to(network: &'static str) -> impl Fn(&Heard) -> bool {
    move |heard| {
        matches!(heard, Heard::Device { state: n::DeviceState::Connected, active_network, .. }
            if active_network.contains(&hex(network)))
    }
}

fn hex(text: &str) -> String {
    text.bytes().map(|b| format!("{b:02x}")).collect()
}

/// Runs a test inside a LocalSet, like the service runs
fn local_test(test: impl std::future::Future<Output = ()>) {
    let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
    tokio::task::LocalSet::new().block_on(&runtime, test);
}

#[test]
fn info_names_the_backend() {
    local_test(async {
        let setup = setup();
        let response = setup.client.info_request().send().promise.await.unwrap();
        assert_eq!(response.get().unwrap().get_backend().unwrap().to_str().unwrap(), "fake");
    });
}

#[test]
fn snapshot_lists_networks_merged_and_the_home_network_connects() {
    local_test(async {
        let setup = setup();
        let (mut heard, _subscription, snapshot) = watch(&setup).await;
        assert_eq!(
            snapshot,
            Heard::Snapshot {
                networks: ["Cafe Lumen", "Far Away", "Hotel Guest", "Maia Home", "Neighbour 5G", "Office"]
                    .map(String::from)
                    .to_vec(),
                connections: vec!["Maia Home".into()],
            },
            "two access points of Maia Home are one network, the hidden one is left out"
        );
        wait_for(&mut heard, connected_to("Maia Home")).await;
    });
}

#[test]
fn a_new_secured_network_asks_for_its_password() {
    local_test(async {
        let setup = setup();
        let (_registration, mut questions) = register_prompter(&setup, vec![Answer::Password("neighbour-pw")]).await;
        let (mut heard, _subscription, _) = watch(&setup).await;
        let control = control(&setup).await;
        assert_eq!(connect(&control, "Neighbour 5G", Security::Wpa3Personal).await, n::ErrorCode::None);

        let (name, keys, validations) = tokio::time::timeout(TIMEOUT, questions.recv()).await.unwrap().unwrap();
        assert_eq!(name, "Neighbour 5G");
        assert_eq!(keys, vec![n::SecretKey::WifiPassword]);
        assert_eq!(validations, vec![n::Validation::WpaPassword]);
        wait_for(&mut heard, connected_to("Neighbour 5G")).await;
        wait_for(&mut heard, |h| matches!(h, Heard::Network { name, known: true, .. } if name == "Neighbour 5G")).await;
    });
}

#[test]
fn a_wrong_password_fails_with_its_reason() {
    local_test(async {
        let setup = setup();
        let (_registration, _questions) = register_prompter(&setup, vec![Answer::Password("wrong-password")]).await;
        let (mut heard, _subscription, _) = watch(&setup).await;
        let control = control(&setup).await;
        connect(&control, "Neighbour 5G", Security::Wpa3Personal).await;
        assert_eq!(wait_for(&mut heard, |h| matches!(h, Heard::Failed(_))).await, Heard::Failed(n::StateReason::WrongSecrets));
    });
}

#[test]
fn cancelling_the_password_dialog_is_no_failure_and_removes_the_new_profile() {
    local_test(async {
        let setup = setup();
        let (_registration, _questions) = register_prompter(&setup, vec![Answer::Cancel]).await;
        let (mut heard, _subscription, _) = watch(&setup).await;
        wait_for(&mut heard, connected_to("Maia Home")).await;
        let control = control(&setup).await;
        connect(&control, "Far Away", Security::WpaPersonal).await;

        let all = heard_until_quiet(&mut heard).await;
        let new_uuid = all.iter().find_map(|h| match h {
            Heard::Connection { uuid, name } if name == "Far Away" => Some(uuid.clone()),
            _ => None,
        });
        let new_uuid = new_uuid.expect("a profile was made for the new network");
        assert!(all.contains(&Heard::ConnectionRemoved(new_uuid)), "and removed after the cancel: {all:?}");
        assert!(!all.iter().any(|h| matches!(h, Heard::Failed(_))), "no failure message: {all:?}");
        assert!(all.iter().any(|h| matches!(h, Heard::Device { reason: n::StateReason::NoSecrets, .. })));
    });
}

#[test]
fn without_a_prompter_requests_are_cancelled() {
    local_test(async {
        let setup = setup();
        let (mut heard, _subscription, _) = watch(&setup).await;
        let control = control(&setup).await;
        connect(&control, "Neighbour 5G", Security::Wpa3Personal).await;
        wait_for(&mut heard, |h| matches!(h, Heard::Device { reason: n::StateReason::NoSecrets, .. })).await;
    });
}

#[test]
fn enterprise_networks_need_their_details_first() {
    local_test(async {
        let setup = setup();
        let control = control(&setup).await;
        tokio::time::sleep(Duration::from_millis(5)).await;
        assert_eq!(connect(&control, "Office", Security::WpaEnterprise).await, n::ErrorCode::InvalidArgument);
        assert_eq!(connect(&control, "Nowhere", Security::None).await, n::ErrorCode::NotFound);
    });
}

#[test]
fn wifi_off_empties_the_list_and_on_again_reconnects() {
    local_test(async {
        let setup = setup();
        let (mut heard, _subscription, _) = watch(&setup).await;
        wait_for(&mut heard, connected_to("Maia Home")).await;
        let control = control(&setup).await;

        let mut request = control.set_wireless_enabled_request();
        request.get().set_enabled(false);
        request.send().promise.await.unwrap();
        let all = heard_until_quiet(&mut heard).await;
        assert_eq!(all.iter().filter(|h| matches!(h, Heard::NetworkRemoved(_))).count(), 6);
        assert!(all.contains(&Heard::Status { wireless_enabled: false, connectivity: n::Connectivity::None }));

        let mut request = control.set_wireless_enabled_request();
        request.get().set_enabled(true);
        request.send().promise.await.unwrap();
        wait_for(&mut heard, connected_to("Maia Home")).await;
    });
}

#[test]
fn forgetting_the_active_network_disconnects() {
    local_test(async {
        let setup = setup();
        let (mut heard, _subscription, _) = watch(&setup).await;
        wait_for(&mut heard, connected_to("Maia Home")).await;
        let control = control(&setup).await;

        let mut request = control.forget_request();
        request.get().set_uuid("5f1d4c3e-0000-4000-8000-000000000001");
        let response = request.send().promise.await.unwrap();
        assert_eq!(response.get().unwrap().get_result().unwrap().get_error().unwrap(), n::ErrorCode::None);
        let all = heard_until_quiet(&mut heard).await;
        assert!(all.contains(&Heard::ConnectionRemoved("5f1d4c3e-0000-4000-8000-000000000001".into())));
        assert!(all.iter().any(|h| matches!(h, Heard::Device { state: n::DeviceState::Disconnected, .. })));
        assert!(all.iter().any(|h| matches!(h, Heard::Network { name, known: false, .. } if name == "Maia Home")));
    });
}

#[test]
fn a_captive_portal_clears_after_checking_again() {
    local_test(async {
        let setup = setup();
        let (mut heard, _subscription, _) = watch(&setup).await;
        wait_for(&mut heard, connected_to("Maia Home")).await;
        let control = control(&setup).await;
        connect(&control, "Hotel Guest", Security::None).await;
        wait_for(&mut heard, |h| matches!(h, Heard::Status { connectivity: n::Connectivity::Portal, .. })).await;

        control.check_connectivity_request().send().promise.await.unwrap();
        wait_for(&mut heard, |h| matches!(h, Heard::Status { connectivity: n::Connectivity::Full, .. })).await;
    });
}

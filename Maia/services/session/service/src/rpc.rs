//! The Cap'n Proto side of the service (contract ../contract/session.capnp).
//!
//! `Hub` holds what the clients see (model::View) and who listens. The session (session.rs) changes
//! it only through the Hub's setters, which send every real change to every listener; a new
//! listener first gets the whole state (snapshot). Cap'n Proto keeps the calls on one capability in
//! order, so a client never sees a change before the snapshot.
//!
//! The requests of SessionControl and the ready helper's compositorReady go to the session's event
//! loop as Events; a control call waits for the session's answer (logout answers at once, power off
//! once logind accepted).

use std::cell::RefCell;
use std::rc::{Rc, Weak};

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use tokio::sync::{mpsc, oneshot};
use tokio_util::compat::TokioAsyncReadCompatExt;

use crate::model::{ChildKind, ChildState, ChildView, EndAction, Ending, ErrorCode, Info, Initiator, Outcome, Request, State, View};
use crate::power::{Ability, Action, Capabilities};
use crate::session::Event;
use crate::session_capnp::{self as s, session_control, session_listener, session_service, subscription};

pub struct Hub {
    view: View,
    info: Info,
    listeners: Vec<(u64, session_listener::Client)>,
    next_listener: u64,
}

pub type HubRef = Rc<RefCell<Hub>>;

impl Hub {
    pub fn new(info: Info) -> HubRef {
        Rc::new(RefCell::new(Hub {
            view: View { state: State::Starting, ending: None, capabilities: Capabilities::NONE, children: Vec::new() },
            info,
            listeners: Vec::new(),
            next_listener: 0,
        }))
    }

    pub fn view(&self) -> &View {
        &self.view
    }

    pub fn set_info_backend(&mut self, backend: &str) {
        self.info.backend = backend.to_string();
    }

    pub fn set_state(hub: &HubRef, state: State, ending: Option<Ending>) {
        let mut this = hub.borrow_mut();
        if this.view.state == state && this.view.ending == ending {
            return;
        }
        this.view.state = state;
        this.view.ending = ending;
        for (id, listener) in &this.listeners {
            let mut request = listener.state_changed_request();
            request.get().set_state(write_state(state));
            write_ending(request.get().init_ending(), ending);
            deliver(hub, *id, request.send().promise);
        }
    }

    pub fn set_capabilities(hub: &HubRef, capabilities: Capabilities) {
        let mut this = hub.borrow_mut();
        if this.view.capabilities == capabilities {
            return;
        }
        this.view.capabilities = capabilities;
        for (id, listener) in &this.listeners {
            let mut request = listener.capabilities_changed_request();
            write_capabilities(request.get().init_capabilities(), &capabilities);
            deliver(hub, *id, request.send().promise);
        }
    }

    /// Adds or replaces the child of that name
    pub fn set_child(hub: &HubRef, child: ChildView) {
        let mut this = hub.borrow_mut();
        match this.view.children.iter_mut().find(|c| c.name == child.name) {
            Some(existing) if *existing == child => return,
            Some(existing) => *existing = child.clone(),
            None => this.view.children.push(child.clone()),
        }
        for (id, listener) in &this.listeners {
            let mut request = listener.child_changed_request();
            write_child(request.get().init_child(), &child);
            deliver(hub, *id, request.send().promise);
        }
    }

    fn add_listener(hub: &HubRef, client: session_listener::Client) -> u64 {
        let mut this = hub.borrow_mut();
        this.next_listener += 1;
        let id = this.next_listener;
        let mut request = client.snapshot_request();
        {
            let mut params = request.get();
            params.set_state(write_state(this.view.state));
            write_ending(params.reborrow().init_ending(), this.view.ending);
            write_capabilities(params.reborrow().init_capabilities(), &this.view.capabilities);
            let mut list = params.init_children(this.view.children.len() as u32);
            for (i, child) in this.view.children.iter().enumerate() {
                write_child(list.reborrow().get(i as u32), child);
            }
        }
        deliver(hub, id, request.send().promise);
        this.listeners.push((id, client));
        id
    }

    fn remove_listener(&mut self, id: u64) {
        self.listeners.retain(|(other, _)| *other != id);
    }
}

/// Runs the call in the background; when it fails, the listener is gone
fn deliver<T: 'static>(hub: &HubRef, id: u64, promise: capnp::capability::Promise<T, capnp::Error>) {
    let hub = Rc::downgrade(hub);
    tokio::task::spawn_local(async move {
        if promise.await.is_err() {
            if let Some(hub) = hub.upgrade() {
                hub.borrow_mut().remove_listener(id);
            }
        }
    });
}

// --- Plain values into the contract ---

fn write_state(state: State) -> s::State {
    match state {
        State::Starting => s::State::Starting,
        State::Running => s::State::Running,
        State::Ending => s::State::Ending,
        State::Sleeping => s::State::Sleeping,
    }
}

fn write_ending(mut builder: s::ending::Builder, ending: Option<Ending>) {
    // Without an ending the default values stand (logout, user); the state says it is not ending
    let Some(ending) = ending else { return };
    builder.set_action(match ending.action {
        EndAction::Logout => s::EndAction::Logout,
        EndAction::Reboot => s::EndAction::Reboot,
        EndAction::PowerOff => s::EndAction::PowerOff,
    });
    builder.set_initiator(match ending.initiator {
        Initiator::User => s::Initiator::User,
        Initiator::System => s::Initiator::System,
    });
}

fn write_ability(ability: Ability) -> s::Ability {
    match ability {
        Ability::No => s::Ability::No,
        Ability::Yes => s::Ability::Yes,
        Ability::Challenge => s::Ability::Challenge,
    }
}

fn write_capabilities(mut builder: s::capabilities::Builder, caps: &Capabilities) {
    builder.set_logout(true);
    builder.set_power_off(write_ability(caps.power_off));
    builder.set_reboot(write_ability(caps.reboot));
    builder.set_suspend(write_ability(caps.suspend));
    builder.set_hibernate(write_ability(caps.hibernate));
    builder.set_hybrid_sleep(write_ability(caps.hybrid_sleep));
    builder.set_suspend_then_hibernate(write_ability(caps.suspend_then_hibernate));
}

fn write_child(mut builder: s::child::Builder, child: &ChildView) {
    builder.set_name(&child.name);
    builder.set_kind(match child.kind {
        ChildKind::Compositor => s::ChildKind::Compositor,
        ChildKind::Shell => s::ChildKind::Shell,
        ChildKind::MaiaService => s::ChildKind::MaiaService,
        ChildKind::KdeService => s::ChildKind::KdeService,
        ChildKind::Helper => s::ChildKind::Helper,
    });
    builder.set_state(match child.state {
        ChildState::Waiting => s::ChildState::Waiting,
        ChildState::Running => s::ChildState::Running,
        ChildState::Restarting => s::ChildState::Restarting,
        ChildState::Failed => s::ChildState::Failed,
        ChildState::Stopped => s::ChildState::Stopped,
    });
    builder.set_pid(child.pid);
    builder.set_restarts(child.restarts);
    builder.set_last_exit(&child.last_exit);
}

fn write_result(mut builder: s::result::Builder, outcome: &Outcome) {
    builder.set_error(match outcome.error {
        ErrorCode::None => s::ErrorCode::None,
        ErrorCode::NotAllowed => s::ErrorCode::NotAllowed,
        ErrorCode::NotSupported => s::ErrorCode::NotSupported,
        ErrorCode::Busy => s::ErrorCode::Busy,
        ErrorCode::NotFound => s::ErrorCode::NotFound,
        ErrorCode::Failed => s::ErrorCode::Failed,
    });
    builder.set_message(&outcome.message);
}

// --- SessionService: the bootstrap capability of every connection ---

pub struct SessionService {
    hub: HubRef,
    events: mpsc::UnboundedSender<Event>,
}

impl SessionService {
    pub fn client(hub: HubRef, events: mpsc::UnboundedSender<Event>) -> session_service::Client {
        capnp_rpc::new_client(SessionService { hub, events })
    }
}

/// Released by the client (or with its connection): the listener stops getting calls
struct SubscriptionImpl {
    hub: Weak<RefCell<Hub>>,
    id: u64,
}

impl Drop for SubscriptionImpl {
    fn drop(&mut self) {
        if let Some(hub) = self.hub.upgrade() {
            hub.borrow_mut().remove_listener(self.id);
        }
    }
}

impl subscription::Server for SubscriptionImpl {}

impl session_service::Server for SessionService {
    async fn info(
        self: Rc<Self>,
        _: session_service::InfoParams,
        mut results: session_service::InfoResults,
    ) -> Result<(), capnp::Error> {
        let hub = self.hub.borrow();
        let mut info = results.get().init_info();
        info.set_service_version(env!("CARGO_PKG_VERSION"));
        info.set_maia_version(&hub.info.maia_version);
        info.set_compositor(&hub.info.compositor);
        info.set_session_id(&hub.info.session_id);
        info.set_backend(&hub.info.backend);
        Ok(())
    }

    async fn watch(
        self: Rc<Self>,
        params: session_service::WatchParams,
        mut results: session_service::WatchResults,
    ) -> Result<(), capnp::Error> {
        let listener = params.get()?.get_listener()?;
        let id = Hub::add_listener(&self.hub, listener);
        results.get().set_subscription(capnp_rpc::new_client(SubscriptionImpl { hub: Rc::downgrade(&self.hub), id }));
        Ok(())
    }

    async fn control(
        self: Rc<Self>,
        _: session_service::ControlParams,
        mut results: session_service::ControlResults,
    ) -> Result<(), capnp::Error> {
        results.get().set_control(capnp_rpc::new_client(Control { events: self.events.clone() }));
        Ok(())
    }

    async fn compositor_ready(
        self: Rc<Self>,
        params: session_service::CompositorReadyParams,
        _: session_service::CompositorReadyResults,
    ) -> Result<(), capnp::Error> {
        let mut environment = Vec::new();
        for variable in params.get()?.get_environment()? {
            environment.push((variable.get_name()?.to_string()?, variable.get_value()?.to_string()?));
        }
        let _ = self.events.send(Event::CompositorReady(environment));
        Ok(())
    }
}

// --- SessionControl ---

struct Control {
    events: mpsc::UnboundedSender<Event>,
}

impl Control {
    async fn ask(&self, request: Request) -> Outcome {
        let (reply, answer) = oneshot::channel();
        if self.events.send(Event::Request(request, reply)).is_err() {
            return Outcome::error(ErrorCode::Busy, "the session is ending");
        }
        answer.await.unwrap_or_else(|_| Outcome::error(ErrorCode::Busy, "the session is ending"))
    }
}

macro_rules! power_method {
    ($name:ident, $params:ident, $results:ident, $action:expr) => {
        async fn $name(
            self: Rc<Self>,
            _: session_control::$params,
            mut results: session_control::$results,
        ) -> Result<(), capnp::Error> {
            let outcome = self.ask(Request::Power($action)).await;
            write_result(results.get().init_result(), &outcome);
            Ok(())
        }
    };
}

impl session_control::Server for Control {
    async fn logout(
        self: Rc<Self>,
        _: session_control::LogoutParams,
        mut results: session_control::LogoutResults,
    ) -> Result<(), capnp::Error> {
        let outcome = self.ask(Request::Logout).await;
        write_result(results.get().init_result(), &outcome);
        Ok(())
    }

    power_method!(reboot, RebootParams, RebootResults, Action::Reboot);
    power_method!(power_off, PowerOffParams, PowerOffResults, Action::PowerOff);
    power_method!(suspend, SuspendParams, SuspendResults, Action::Suspend);
    power_method!(hibernate, HibernateParams, HibernateResults, Action::Hibernate);
    power_method!(hybrid_sleep, HybridSleepParams, HybridSleepResults, Action::HybridSleep);
    power_method!(suspend_then_hibernate, SuspendThenHibernateParams, SuspendThenHibernateResults,
                  Action::SuspendThenHibernate);

    async fn restart_child(
        self: Rc<Self>,
        params: session_control::RestartChildParams,
        mut results: session_control::RestartChildResults,
    ) -> Result<(), capnp::Error> {
        let name = params.get()?.get_name()?.to_string()?;
        let outcome = self.ask(Request::RestartChild(name)).await;
        write_result(results.get().init_result(), &outcome);
        Ok(())
    }
}

// --- Connections ---

/// Serves one client connection in the background
pub fn serve(stream: tokio::net::UnixStream, service: session_service::Client) {
    let (reader, writer) = stream.compat().split();
    let network = twoparty::VatNetwork::new(
        futures::io::BufReader::new(reader),
        futures::io::BufWriter::new(writer),
        rpc_twoparty_capnp::Side::Server,
        Default::default(),
    );
    let rpc_system = RpcSystem::new(Box::new(network), Some(service.client));
    tokio::task::spawn_local(async move {
        let _ = rpc_system.await;
    });
}

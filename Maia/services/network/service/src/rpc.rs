//! The Cap'n Proto side of the service (contract ../contract/network.capnp).
//!
//! `Hub` is the state shared by all connections: status, devices, the networks made from their
//! access points, saved connections, the listeners and the registered SecretPrompter. Backend events
//! go in through `Hub::apply`, which updates the state and sends every real change to every
//! listener. A new listener first gets the whole state (snapshot) and then only the changes; Cap'n
//! Proto keeps the calls on one capability in order, so a client never sees a change before the
//! snapshot.
//!
//! Changes of one object go out at most every `CHANGE_INTERVAL`, with its latest state
//! (throttle.rs). Sending never waits for a client: every call is its own local task. A listener
//! whose call fails (the client went away) is dropped; so is one whose Subscription was released.
//!
//! Control calls become `Command`s for the backend; each call waits for the backend's answer
//! without blocking anything else (the hub stays free, other calls go on).

use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};
use std::rc::{Rc, Weak};
use std::time::{Duration, Instant};

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use tokio::sync::{mpsc, oneshot};
use tokio_util::compat::TokioAsyncReadCompatExt;

use crate::backend::{BackendEvent, Command, ErrorCode, HotspotPassword, OpError, OpResult};
use crate::model::{
    AccessPoint, Change, ConnectionType, Connectivity, DeviceState, Event, IpAddress, IpInfo, KeyedStore, Metered,
    Permission, SavedConnection, Security, StateReason, Status, WifiDevice, WifiMode, WifiNetwork, networks_of_device,
};
use crate::network_capnp::{self as n, network_control, network_listener, network_service, secret_prompter, subscription};
use crate::prompt::PromptMessage;
use crate::qr;
use crate::settings::{
    ClonedMac, ConnectionSettings, Eap8021xSettings, EapMethod, InnerAuth, IpMethod, IpSettings, Route, Secret, SecretKey,
    SecretReply, SecretRequest, SecuritySettings, Validation, WifiSettings,
};
use crate::throttle::ChangeThrottle;

/// The changes of one object reach the clients at most this often
pub const CHANGE_INTERVAL: Duration = Duration::from_millis(250);

/// What a listener gets told
#[derive(Clone, Debug)]
enum Outgoing {
    Status(Status),
    Device(WifiDevice),
    DeviceRemoved(String),
    Network(WifiNetwork),
    NetworkRemoved(String),
    Connection(SavedConnection),
    ConnectionRemoved(String),
    Event(Event),
}

/// The state and who listens to it, shared by all connections
pub struct Hub {
    status: Status,
    /// Devices as the backend reports them; `devices` adds the active network
    reported_devices: BTreeMap<String, WifiDevice>,
    devices: KeyedStore<WifiDevice>,
    access_points: HashMap<String, Vec<AccessPoint>>,
    networks: KeyedStore<WifiNetwork>,
    connections: KeyedStore<SavedConnection>,
    listeners: Vec<(u64, network_listener::Client)>,
    next_id: u64,
    throttle: ChangeThrottle,
    flush_scheduled: bool,
    prompter: Option<(u64, secret_prompter::Client)>,
    /// Requests the prompter is asked, by request id
    pending_prompts: HashMap<String, oneshot::Sender<SecretReply>>,
}

pub type HubRef = Rc<RefCell<Hub>>;

impl Hub {
    pub fn new() -> HubRef {
        Rc::new(RefCell::new(Hub {
            status: Status::default(),
            reported_devices: BTreeMap::new(),
            devices: KeyedStore::default(),
            access_points: HashMap::new(),
            networks: KeyedStore::default(),
            connections: KeyedStore::default(),
            listeners: Vec::new(),
            next_id: 0,
            throttle: ChangeThrottle::new(CHANGE_INTERVAL),
            flush_scheduled: false,
            prompter: None,
            pending_prompts: HashMap::new(),
        }))
    }

    pub fn status(&self) -> &Status {
        &self.status
    }

    pub fn networks(&self) -> impl Iterator<Item = &WifiNetwork> {
        self.networks.values()
    }

    pub fn devices(&self) -> impl Iterator<Item = &WifiDevice> {
        self.devices.values()
    }

    pub fn listener_count(&self) -> usize {
        self.listeners.len()
    }

    pub fn has_prompter(&self) -> bool {
        self.prompter.is_some()
    }

    /// One event from the backend: update the state and tell the listeners what really changed
    pub fn apply(hub: &HubRef, event: BackendEvent) {
        let mut this = hub.borrow_mut();
        let mut out = Vec::new();
        match event {
            BackendEvent::Status(status) => {
                if this.status != status {
                    this.status = status.clone();
                    out.push(Outgoing::Status(status));
                }
            }
            BackendEvent::Device(device) => {
                let id = device.id.clone();
                this.reported_devices.insert(id.clone(), device);
                this.refresh_device(&id, &mut out);
            }
            BackendEvent::DeviceRemoved(id) => {
                this.reported_devices.remove(&id);
                this.access_points.remove(&id);
                this.refresh_device(&id, &mut out);
            }
            BackendEvent::AccessPoints { device_id, access_points } => {
                this.access_points.insert(device_id.clone(), access_points);
                this.refresh_device(&device_id, &mut out);
            }
            BackendEvent::Connection(connection) => {
                let uuid = connection.uuid.clone();
                if let Some(change) = this.connections.upsert(&uuid, connection) {
                    out.push(outgoing_connection(change));
                    this.refresh_all_devices(&mut out);
                }
            }
            BackendEvent::ConnectionRemoved(uuid) => {
                if let Some(change) = this.connections.remove(&uuid) {
                    out.push(outgoing_connection(change));
                    this.refresh_all_devices(&mut out);
                }
            }
            BackendEvent::Event(event) => out.push(Outgoing::Event(event)),
        }
        for change in out {
            this.send(hub, change);
        }
    }

    /// Recomputes the networks of a device and its active network
    fn refresh_device(&mut self, id: &str, out: &mut Vec<Outgoing>) {
        let Some(reported) = self.reported_devices.get(id).cloned() else {
            let prefix = format!("{id}/");
            let gone: Vec<String> = self.networks.ids().filter(|n| n.starts_with(&prefix)).cloned().collect();
            for network in gone {
                out.extend(self.networks.remove(&network).map(outgoing_network));
            }
            out.extend(self.devices.remove(id).map(outgoing_device));
            return;
        };
        let connections: Vec<SavedConnection> = self.connections.values().cloned().collect();
        let empty = Vec::new();
        let aps = self.access_points.get(id).unwrap_or(&empty);
        let networks = networks_of_device(&reported, aps, &connections);

        let prefix = format!("{id}/");
        let current: Vec<String> = networks.iter().map(|n| n.id.clone()).collect();
        let gone: Vec<String> =
            self.networks.ids().filter(|n| n.starts_with(&prefix) && !current.contains(n)).cloned().collect();
        for network in gone {
            out.extend(self.networks.remove(&network).map(outgoing_network));
        }
        let mut device = reported;
        device.active_network_id = networks.iter().find(|n| n.active).map(|n| n.id.clone()).unwrap_or_default();
        for network in networks {
            let id = network.id.clone();
            out.extend(self.networks.upsert(&id, network).map(outgoing_network));
        }
        out.extend(self.devices.upsert(id, device).map(outgoing_device));
    }

    fn refresh_all_devices(&mut self, out: &mut Vec<Outgoing>) {
        let ids: Vec<String> = self.reported_devices.keys().cloned().collect();
        for id in ids {
            self.refresh_device(&id, out);
        }
    }

    /// Sends a change now, or later when its object changed less than CHANGE_INTERVAL ago
    fn send(&mut self, hub: &HubRef, change: Outgoing) {
        let now = Instant::now();
        let send_now = match &change {
            Outgoing::Event(_) => true,
            Outgoing::DeviceRemoved(id) => {
                self.throttle.removed(&format!("device:{id}"));
                true
            }
            Outgoing::NetworkRemoved(id) => {
                self.throttle.removed(&format!("network:{id}"));
                true
            }
            Outgoing::ConnectionRemoved(uuid) => {
                self.throttle.removed(&format!("connection:{uuid}"));
                true
            }
            other => self.throttle.changed(&throttle_key(other), now),
        };
        if send_now {
            self.broadcast(hub, &change);
        } else {
            schedule_flush(hub, self);
        }
    }

    fn broadcast(&self, hub: &HubRef, change: &Outgoing) {
        for (id, listener) in &self.listeners {
            send_change(hub, *id, listener, change);
        }
    }

    /// Sends the waiting changes that are due, each with the latest state of its object
    fn flush(hub: &HubRef) {
        let mut this = hub.borrow_mut();
        this.flush_scheduled = false;
        for key in this.throttle.take_due(Instant::now()) {
            let change = if key == "status" {
                Some(Outgoing::Status(this.status.clone()))
            } else if let Some(id) = key.strip_prefix("device:") {
                this.devices.get(id).cloned().map(Outgoing::Device)
            } else if let Some(id) = key.strip_prefix("network:") {
                this.networks.get(id).cloned().map(Outgoing::Network)
            } else if let Some(uuid) = key.strip_prefix("connection:") {
                this.connections.get(uuid).cloned().map(Outgoing::Connection)
            } else {
                None
            };
            if let Some(change) = change {
                this.broadcast(hub, &change);
            }
        }
        schedule_flush(hub, &mut this);
    }

    /// Feeds the hub from the backend until the backend ends
    pub async fn run(hub: HubRef, mut events: mpsc::UnboundedReceiver<BackendEvent>) {
        while let Some(event) = events.recv().await {
            Hub::apply(&hub, event);
        }
    }

    /// Passes the backend's password requests to the registered prompter
    pub async fn run_prompts(hub: HubRef, mut messages: mpsc::UnboundedReceiver<PromptMessage>) {
        while let Some(message) = messages.recv().await {
            match message {
                PromptMessage::Ask { request, reply } => Hub::ask(&hub, request, reply),
                PromptMessage::Cancel(id) => {
                    let mut this = hub.borrow_mut();
                    if let Some(reply) = this.pending_prompts.remove(&id) {
                        let _ = reply.send(SecretReply::Cancelled);
                    }
                    if let Some((_, prompter)) = &this.prompter {
                        let mut request = prompter.cancel_request();
                        request.get().set_id(&id);
                        let promise = request.send().promise;
                        tokio::task::spawn_local(async move {
                            let _ = promise.await;
                        });
                    }
                }
            }
        }
    }

    fn ask(hub: &HubRef, request: SecretRequest, reply: oneshot::Sender<SecretReply>) {
        let mut this = hub.borrow_mut();
        let Some((_, prompter)) = &this.prompter else {
            let _ = reply.send(SecretReply::Cancelled);
            return;
        };
        let mut call = prompter.ask_request();
        write_secret_request(call.get().init_request(), &request);
        let promise = call.send().promise;
        let id = request.id.clone();
        this.pending_prompts.insert(id.clone(), reply);
        let hub = Rc::downgrade(hub);
        tokio::task::spawn_local(async move {
            let answer = match promise.await {
                Ok(response) => read_secret_reply(&response).unwrap_or(SecretReply::Cancelled),
                Err(_) => SecretReply::Cancelled,
            };
            if let Some(hub) = hub.upgrade() {
                if let Some(reply) = hub.borrow_mut().pending_prompts.remove(&id) {
                    let _ = reply.send(answer);
                }
            }
        });
    }

    fn add_listener(hub: &HubRef, client: network_listener::Client) -> u64 {
        let mut this = hub.borrow_mut();
        this.next_id += 1;
        let id = this.next_id;
        let mut request = client.snapshot_request();
        {
            let mut snapshot = request.get().init_snapshot();
            write_status(snapshot.reborrow().init_status(), &this.status);
            let mut list = snapshot.reborrow().init_devices(this.devices.len() as u32);
            for (i, device) in this.devices.values().enumerate() {
                write_device(list.reborrow().get(i as u32), device);
            }
            let mut list = snapshot.reborrow().init_networks(this.networks.len() as u32);
            for (i, network) in this.networks.values().enumerate() {
                write_network(list.reborrow().get(i as u32), network);
            }
            let mut list = snapshot.init_connections(this.connections.len() as u32);
            for (i, connection) in this.connections.values().enumerate() {
                write_connection(list.reborrow().get(i as u32), connection);
            }
        }
        deliver(hub, id, request.send().promise);
        this.listeners.push((id, client));
        id
    }

    fn remove_listener(&mut self, id: u64) {
        self.listeners.retain(|(other, _)| *other != id);
    }

    fn set_prompter(hub: &HubRef, client: secret_prompter::Client) -> u64 {
        let mut this = hub.borrow_mut();
        this.next_id += 1;
        let id = this.next_id;
        this.prompter = Some((id, client));
        id
    }

    fn remove_prompter(&mut self, id: u64) {
        if self.prompter.as_ref().is_some_and(|(current, _)| *current == id) {
            self.prompter = None;
            // Questions to the gone prompter will never be answered
            for (_, reply) in self.pending_prompts.drain() {
                let _ = reply.send(SecretReply::Cancelled);
            }
        }
    }
}

fn throttle_key(change: &Outgoing) -> String {
    match change {
        Outgoing::Status(_) => "status".into(),
        Outgoing::Device(d) => format!("device:{}", d.id),
        Outgoing::Network(n) => format!("network:{}", n.id),
        Outgoing::Connection(c) => format!("connection:{}", c.uuid),
        Outgoing::DeviceRemoved(id) => format!("device:{id}"),
        Outgoing::NetworkRemoved(id) => format!("network:{id}"),
        Outgoing::ConnectionRemoved(uuid) => format!("connection:{uuid}"),
        Outgoing::Event(_) => String::new(),
    }
}

fn outgoing_device(change: Change<WifiDevice>) -> Outgoing {
    match change {
        Change::Changed(device) => Outgoing::Device(device),
        Change::Removed(id) => Outgoing::DeviceRemoved(id),
    }
}

fn outgoing_network(change: Change<WifiNetwork>) -> Outgoing {
    match change {
        Change::Changed(network) => Outgoing::Network(network),
        Change::Removed(id) => Outgoing::NetworkRemoved(id),
    }
}

fn outgoing_connection(change: Change<SavedConnection>) -> Outgoing {
    match change {
        Change::Changed(connection) => Outgoing::Connection(connection),
        Change::Removed(uuid) => Outgoing::ConnectionRemoved(uuid),
    }
}

/// Starts the timer for the next waiting change, unless one runs or nothing waits
fn schedule_flush(hub: &HubRef, this: &mut Hub) {
    if this.flush_scheduled {
        return;
    }
    let Some(deadline) = this.throttle.next_deadline() else { return };
    this.flush_scheduled = true;
    let hub = Rc::downgrade(hub);
    tokio::task::spawn_local(async move {
        tokio::time::sleep_until(tokio::time::Instant::from_std(deadline)).await;
        if let Some(hub) = hub.upgrade() {
            Hub::flush(&hub);
        }
    });
}

fn send_change(hub: &HubRef, id: u64, listener: &network_listener::Client, change: &Outgoing) {
    match change {
        Outgoing::Status(status) => {
            let mut request = listener.status_changed_request();
            write_status(request.get().init_status(), status);
            deliver(hub, id, request.send().promise);
        }
        Outgoing::Device(device) => {
            let mut request = listener.device_changed_request();
            write_device(request.get().init_device(), device);
            deliver(hub, id, request.send().promise);
        }
        Outgoing::DeviceRemoved(device_id) => {
            let mut request = listener.device_removed_request();
            request.get().set_id(device_id);
            deliver(hub, id, request.send().promise);
        }
        Outgoing::Network(network) => {
            let mut request = listener.network_changed_request();
            write_network(request.get().init_network(), network);
            deliver(hub, id, request.send().promise);
        }
        Outgoing::NetworkRemoved(network_id) => {
            let mut request = listener.network_removed_request();
            request.get().set_id(network_id);
            deliver(hub, id, request.send().promise);
        }
        Outgoing::Connection(connection) => {
            let mut request = listener.connection_changed_request();
            write_connection(request.get().init_connection(), connection);
            deliver(hub, id, request.send().promise);
        }
        Outgoing::ConnectionRemoved(uuid) => {
            let mut request = listener.connection_removed_request();
            request.get().set_uuid(uuid);
            deliver(hub, id, request.send().promise);
        }
        Outgoing::Event(event) => {
            let mut request = listener.event_request();
            write_event(request.get().init_event(), event);
            deliver(hub, id, request.send().promise);
        }
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

// --- Writing the state into the contract ---

fn write_permission(permission: Permission) -> n::Permission {
    match permission {
        Permission::No => n::Permission::No,
        Permission::Auth => n::Permission::Auth,
        Permission::Yes => n::Permission::Yes,
    }
}

pub fn write_status(mut b: n::status::Builder, status: &Status) {
    b.set_running(status.running);
    b.set_networking_enabled(status.networking_enabled);
    b.set_wireless_enabled(status.wireless_enabled);
    b.set_wireless_hardware_enabled(status.wireless_hardware_enabled);
    b.set_connectivity(match status.connectivity {
        Connectivity::Unknown => n::Connectivity::Unknown,
        Connectivity::None => n::Connectivity::None,
        Connectivity::Portal => n::Connectivity::Portal,
        Connectivity::Limited => n::Connectivity::Limited,
        Connectivity::Full => n::Connectivity::Full,
    });
    b.set_connectivity_check_uri(&status.connectivity_check_uri);
    {
        let mut p = b.reborrow().init_primary();
        p.set_type(match status.primary.kind {
            ConnectionType::None => n::ConnectionType::None,
            ConnectionType::Wifi => n::ConnectionType::Wifi,
            ConnectionType::Ethernet => n::ConnectionType::Ethernet,
            ConnectionType::Vpn => n::ConnectionType::Vpn,
            ConnectionType::Other => n::ConnectionType::Other,
        });
        p.set_name(&status.primary.name);
        p.set_uuid(&status.primary.uuid);
        p.set_device_id(&status.primary.device_id);
        p.set_activating(status.primary.activating);
    }
    let permissions = &status.permissions;
    let mut p = b.init_permissions();
    p.set_enable_disable_wifi(write_permission(permissions.enable_disable_wifi));
    p.set_network_control(write_permission(permissions.network_control));
    p.set_modify_own(write_permission(permissions.modify_own));
    p.set_modify_system(write_permission(permissions.modify_system));
    p.set_wifi_share_open(write_permission(permissions.wifi_share_open));
    p.set_wifi_share_protected(write_permission(permissions.wifi_share_protected));
}

fn write_device_state(state: DeviceState) -> n::DeviceState {
    match state {
        DeviceState::Unknown => n::DeviceState::Unknown,
        DeviceState::Unmanaged => n::DeviceState::Unmanaged,
        DeviceState::Unavailable => n::DeviceState::Unavailable,
        DeviceState::Disconnected => n::DeviceState::Disconnected,
        DeviceState::Connecting => n::DeviceState::Connecting,
        DeviceState::NeedAuth => n::DeviceState::NeedAuth,
        DeviceState::Connected => n::DeviceState::Connected,
        DeviceState::Disconnecting => n::DeviceState::Disconnecting,
        DeviceState::Failed => n::DeviceState::Failed,
    }
}

fn write_reason(reason: StateReason) -> n::StateReason {
    match reason {
        StateReason::None => n::StateReason::None,
        StateReason::Other => n::StateReason::Other,
        StateReason::NoSecrets => n::StateReason::NoSecrets,
        StateReason::WrongSecrets => n::StateReason::WrongSecrets,
        StateReason::SupplicantFailed => n::StateReason::SupplicantFailed,
        StateReason::SupplicantTimeout => n::StateReason::SupplicantTimeout,
        StateReason::ConfigFailed => n::StateReason::ConfigFailed,
        StateReason::IpConfigFailed => n::StateReason::IpConfigFailed,
        StateReason::IpConfigExpired => n::StateReason::IpConfigExpired,
        StateReason::ConnectionRemoved => n::StateReason::ConnectionRemoved,
        StateReason::SsidNotFound => n::StateReason::SsidNotFound,
        StateReason::FirmwareMissing => n::StateReason::FirmwareMissing,
        StateReason::UserRequested => n::StateReason::UserRequested,
        StateReason::CarrierLost => n::StateReason::CarrierLost,
    }
}

fn write_ip_addresses(mut list: capnp::struct_list::Builder<n::ip_address::Owned>, addresses: &[IpAddress]) {
    for (i, address) in addresses.iter().enumerate() {
        let mut b = list.reborrow().get(i as u32);
        b.set_address(&address.address);
        b.set_prefix(address.prefix);
    }
}

fn write_text_list(mut list: capnp::text_list::Builder, values: &[String]) {
    for (i, value) in values.iter().enumerate() {
        list.set(i as u32, value);
    }
}

fn write_ip_info(mut b: n::ip_info::Builder, info: &IpInfo) {
    write_ip_addresses(b.reborrow().init_addresses(info.addresses.len() as u32), &info.addresses);
    b.set_gateway(&info.gateway);
    write_text_list(b.init_dns(info.dns.len() as u32), &info.dns);
}

pub fn write_device(mut b: n::wifi_device::Builder, device: &WifiDevice) {
    b.set_id(&device.id);
    b.set_name(&device.name);
    b.set_hw_address(&device.hw_address);
    b.set_perm_hw_address(&device.perm_hw_address);
    b.set_state(write_device_state(device.state));
    b.set_state_reason(write_reason(device.state_reason));
    b.set_active_network_id(&device.active_network_id);
    b.set_active_connection_uuid(&device.active_connection_uuid);
    b.set_hotspot(device.hotspot);
    b.set_bitrate(device.bitrate);
    b.set_bands(device.bands);
    b.set_can_hotspot(device.can_hotspot);
    b.set_scanning(device.scanning);
    b.set_last_scan(device.last_scan);
    write_ip_info(b.reborrow().init_ip4(), &device.ip4);
    write_ip_info(b.init_ip6(), &device.ip6);
}

pub fn write_security(security: Security) -> n::Security {
    match security {
        Security::None => n::Security::None,
        Security::EnhancedOpen => n::Security::EnhancedOpen,
        Security::Wep => n::Security::Wep,
        Security::Leap => n::Security::Leap,
        Security::WpaPersonal => n::Security::WpaPersonal,
        Security::Wpa3Personal => n::Security::Wpa3Personal,
        Security::WpaEnterprise => n::Security::WpaEnterprise,
        Security::Wpa3Enterprise => n::Security::Wpa3Enterprise,
    }
}

pub fn read_security(security: n::Security) -> Security {
    match security {
        n::Security::None => Security::None,
        n::Security::EnhancedOpen => Security::EnhancedOpen,
        n::Security::Wep => Security::Wep,
        n::Security::Leap => Security::Leap,
        n::Security::WpaPersonal => Security::WpaPersonal,
        n::Security::Wpa3Personal => Security::Wpa3Personal,
        n::Security::WpaEnterprise => Security::WpaEnterprise,
        n::Security::Wpa3Enterprise => Security::Wpa3Enterprise,
    }
}

pub fn write_network(mut b: n::wifi_network::Builder, network: &WifiNetwork) {
    b.set_id(&network.id);
    b.set_device_id(&network.device_id);
    b.set_ssid(&network.ssid);
    b.set_name(&network.name);
    b.set_security(write_security(network.security));
    b.set_mode(match network.mode {
        WifiMode::Infrastructure => n::WifiMode::Infrastructure,
        WifiMode::Adhoc => n::WifiMode::Adhoc,
        WifiMode::AccessPoint => n::WifiMode::AccessPoint,
    });
    b.set_strength(network.strength);
    b.set_frequency(network.frequency);
    b.set_bands(network.bands);
    write_text_list(b.reborrow().init_connection_uuids(network.connection_uuids.len() as u32), &network.connection_uuids);
    b.set_active(network.active);
    let mut list = b.init_access_points(network.access_points.len() as u32);
    for (i, ap) in network.access_points.iter().enumerate() {
        let mut a = list.reborrow().get(i as u32);
        a.set_bssid(&ap.bssid);
        a.set_strength(ap.strength);
        a.set_frequency(ap.frequency);
        a.set_max_bitrate(ap.max_bitrate);
        a.set_last_seen(ap.last_seen);
    }
}

fn write_metered(metered: Metered) -> n::Metered {
    match metered {
        Metered::Unknown => n::Metered::Unknown,
        Metered::Yes => n::Metered::Yes,
        Metered::No => n::Metered::No,
    }
}

fn read_metered(metered: n::Metered) -> Metered {
    match metered {
        n::Metered::Unknown => Metered::Unknown,
        n::Metered::Yes => Metered::Yes,
        n::Metered::No => Metered::No,
    }
}

pub fn write_connection(mut b: n::saved_connection::Builder, connection: &SavedConnection) {
    b.set_uuid(&connection.uuid);
    b.set_name(&connection.name);
    b.set_ssid(&connection.ssid);
    b.set_ssid_text(connection.ssid_text());
    b.set_security(write_security(connection.security));
    b.set_hidden(connection.hidden);
    b.set_hotspot(connection.hotspot);
    b.set_autoconnect(connection.autoconnect);
    b.set_metered(write_metered(connection.metered));
    b.set_available_to_all(connection.available_to_all);
    b.set_last_used(connection.last_used);
    b.set_active_device_id(&connection.active_device_id);
    b.set_qr_supported(connection.qr_supported());
}

fn write_event(b: n::event::Builder, event: &Event) {
    match event {
        Event::ActivationFailed { device_id, connection_uuid, name, reason } => {
            let mut f = b.init_activation_failed();
            f.set_device_id(device_id);
            f.set_connection_uuid(connection_uuid);
            f.set_name(name);
            f.set_reason(write_reason(*reason));
        }
        Event::Connected(uuid) => {
            let mut b = b;
            b.set_connected(uuid);
        }
    }
}

// --- Settings and secrets, both ways ---

fn write_secret_key(key: SecretKey) -> n::SecretKey {
    match key {
        SecretKey::WifiPassword => n::SecretKey::WifiPassword,
        SecretKey::WepKey => n::SecretKey::WepKey,
        SecretKey::LeapPassword => n::SecretKey::LeapPassword,
        SecretKey::EapPassword => n::SecretKey::EapPassword,
        SecretKey::EapPrivateKeyPassword => n::SecretKey::EapPrivateKeyPassword,
        SecretKey::EapIdentity => n::SecretKey::EapIdentity,
    }
}

fn read_secret_key(key: n::SecretKey) -> SecretKey {
    match key {
        n::SecretKey::WifiPassword => SecretKey::WifiPassword,
        n::SecretKey::WepKey => SecretKey::WepKey,
        n::SecretKey::LeapPassword => SecretKey::LeapPassword,
        n::SecretKey::EapPassword => SecretKey::EapPassword,
        n::SecretKey::EapPrivateKeyPassword => SecretKey::EapPrivateKeyPassword,
        n::SecretKey::EapIdentity => SecretKey::EapIdentity,
    }
}

fn write_secrets(mut list: capnp::struct_list::Builder<n::secret::Owned>, secrets: &[Secret]) {
    for (i, secret) in secrets.iter().enumerate() {
        let mut b = list.reborrow().get(i as u32);
        b.set_key(write_secret_key(secret.key));
        b.set_value(&secret.value);
    }
}

fn read_secrets(list: capnp::struct_list::Reader<n::secret::Owned>) -> capnp::Result<Vec<Secret>> {
    let mut secrets = Vec::new();
    for secret in list.iter() {
        secrets.push(Secret { key: read_secret_key(secret.get_key()?), value: secret.get_value()?.to_string()? });
    }
    Ok(secrets)
}

fn write_secret_request(mut b: n::secret_request::Builder, request: &SecretRequest) {
    b.set_id(&request.id);
    b.set_connection_uuid(&request.connection_uuid);
    b.set_name(&request.name);
    b.set_device_id(&request.device_id);
    b.set_security(write_security(request.security));
    b.set_retry(request.retry);
    b.set_wps_push_button(request.wps_push_button);
    let mut list = b.init_fields(request.fields.len() as u32);
    for (i, field) in request.fields.iter().enumerate() {
        let mut f = list.reborrow().get(i as u32);
        f.set_key(write_secret_key(field.key));
        f.set_value(&field.value);
        f.set_hidden(field.hidden);
        f.set_validation(match field.validation {
            Validation::NotEmpty => n::Validation::NotEmpty,
            Validation::WpaPassword => n::Validation::WpaPassword,
            Validation::WepKey => n::Validation::WepKey,
            Validation::WepPassphrase => n::Validation::WepPassphrase,
        });
    }
}

fn read_secret_reply(
    response: &capnp::capability::Response<secret_prompter::ask_results::Owned>,
) -> capnp::Result<SecretReply> {
    let reply = response.get()?.get_reply()?;
    Ok(match reply.which()? {
        n::secret_reply::Cancelled(()) => SecretReply::Cancelled,
        n::secret_reply::Secrets(list) => SecretReply::Secrets(read_secrets(list?)?),
    })
}

fn read_text_list(list: capnp::text_list::Reader) -> capnp::Result<Vec<String>> {
    let mut values = Vec::new();
    for value in list.iter() {
        values.push(value?.to_string()?);
    }
    Ok(values)
}

fn read_ip_addresses(list: capnp::struct_list::Reader<n::ip_address::Owned>) -> capnp::Result<Vec<IpAddress>> {
    let mut addresses = Vec::new();
    for a in list.iter() {
        addresses.push(IpAddress { address: a.get_address()?.to_string()?, prefix: a.get_prefix() });
    }
    Ok(addresses)
}

fn ip_method_pairs() -> [(IpMethod, n::IpMethod); 6] {
    [
        (IpMethod::Auto, n::IpMethod::Auto),
        (IpMethod::DhcpOnly, n::IpMethod::DhcpOnly),
        (IpMethod::Manual, n::IpMethod::Manual),
        (IpMethod::LinkLocal, n::IpMethod::LinkLocal),
        (IpMethod::Shared, n::IpMethod::Shared),
        (IpMethod::Disabled, n::IpMethod::Disabled),
    ]
}

fn write_ip_settings(mut b: n::ip_settings::Builder, ip: &IpSettings) {
    b.set_method(ip_method_pairs().iter().find(|(m, _)| *m == ip.method).map(|(_, c)| *c).unwrap_or(n::IpMethod::Auto));
    write_ip_addresses(b.reborrow().init_addresses(ip.addresses.len() as u32), &ip.addresses);
    b.set_gateway(&ip.gateway);
    b.set_auto_dns(ip.auto_dns);
    write_text_list(b.reborrow().init_dns(ip.dns.len() as u32), &ip.dns);
    write_text_list(b.reborrow().init_dns_search(ip.dns_search.len() as u32), &ip.dns_search);
    b.set_auto_routes(ip.auto_routes);
    b.set_never_default(ip.never_default);
    let mut routes = b.init_routes(ip.routes.len() as u32);
    for (i, route) in ip.routes.iter().enumerate() {
        let mut r = routes.reborrow().get(i as u32);
        r.set_destination(&route.destination);
        r.set_prefix(route.prefix);
        r.set_gateway(&route.gateway);
        r.set_metric(route.metric);
    }
}

fn read_ip_settings(r: n::ip_settings::Reader) -> capnp::Result<IpSettings> {
    let method = r.get_method()?;
    let mut routes = Vec::new();
    for route in r.get_routes()?.iter() {
        routes.push(Route {
            destination: route.get_destination()?.to_string()?,
            prefix: route.get_prefix(),
            gateway: route.get_gateway()?.to_string()?,
            metric: route.get_metric(),
        });
    }
    Ok(IpSettings {
        method: ip_method_pairs().iter().find(|(_, c)| *c == method).map(|(m, _)| *m).unwrap_or_default(),
        addresses: read_ip_addresses(r.get_addresses()?)?,
        gateway: r.get_gateway()?.to_string()?,
        auto_dns: r.get_auto_dns(),
        dns: read_text_list(r.get_dns()?)?,
        dns_search: read_text_list(r.get_dns_search()?)?,
        auto_routes: r.get_auto_routes(),
        routes,
        never_default: r.get_never_default(),
    })
}

fn cloned_mac_pairs() -> [(ClonedMac, n::ClonedMac); 7] {
    [
        (ClonedMac::Default, n::ClonedMac::Default),
        (ClonedMac::Preserve, n::ClonedMac::Preserve),
        (ClonedMac::Permanent, n::ClonedMac::Permanent),
        (ClonedMac::Random, n::ClonedMac::Random),
        (ClonedMac::Stable, n::ClonedMac::Stable),
        (ClonedMac::StableSsid, n::ClonedMac::StableSsid),
        (ClonedMac::Address, n::ClonedMac::Address),
    ]
}

fn eap_method_pairs() -> [(EapMethod, n::EapMethod); 6] {
    [
        (EapMethod::Tls, n::EapMethod::Tls),
        (EapMethod::Peap, n::EapMethod::Peap),
        (EapMethod::Ttls, n::EapMethod::Ttls),
        (EapMethod::Pwd, n::EapMethod::Pwd),
        (EapMethod::Fast, n::EapMethod::Fast),
        (EapMethod::Leap, n::EapMethod::Leap),
    ]
}

fn inner_auth_pairs() -> [(InnerAuth, n::InnerAuth); 6] {
    [
        (InnerAuth::Mschapv2, n::InnerAuth::Mschapv2),
        (InnerAuth::Mschap, n::InnerAuth::Mschap),
        (InnerAuth::Pap, n::InnerAuth::Pap),
        (InnerAuth::Chap, n::InnerAuth::Chap),
        (InnerAuth::Gtc, n::InnerAuth::Gtc),
        (InnerAuth::Md5, n::InnerAuth::Md5),
    ]
}

/// Looks a value up in a table of (service value, contract value) pairs
fn to_contract<A: PartialEq + Copy, B: Copy>(pairs: &[(A, B)], value: A) -> B {
    pairs.iter().find(|(a, _)| *a == value).map(|(_, b)| *b).unwrap_or(pairs[0].1)
}

fn from_contract<A: Copy, B: PartialEq + Copy>(pairs: &[(A, B)], value: B) -> A {
    pairs.iter().find(|(_, b)| *b == value).map(|(a, _)| *a).unwrap_or(pairs[0].0)
}

pub fn write_settings(mut b: n::connection_settings::Builder, s: &ConnectionSettings) {
    b.set_name(&s.name);
    b.set_autoconnect(s.autoconnect);
    b.set_metered(write_metered(s.metered));
    b.set_available_to_all(s.available_to_all);
    {
        let mut w = b.reborrow().init_wifi();
        w.set_ssid(&s.wifi.ssid);
        w.set_hidden(s.wifi.hidden);
        w.set_bssid(&s.wifi.bssid);
        w.set_mac_address(&s.wifi.mac_address);
        w.set_cloned_mac(to_contract(&cloned_mac_pairs(), s.wifi.cloned_mac));
        w.set_cloned_mac_address(&s.wifi.cloned_mac_address);
    }
    {
        let mut sec = b.reborrow().init_security();
        sec.set_security(write_security(s.security.security));
        sec.set_wep_key_index(s.security.wep_key_index);
        sec.set_wep_passphrase(s.security.wep_passphrase);
        sec.set_leap_username(&s.security.leap_username);
        let eap = &s.security.eap;
        let mut e = sec.init_eap();
        e.set_method(to_contract(&eap_method_pairs(), eap.method));
        e.set_identity(&eap.identity);
        e.set_anonymous_identity(&eap.anonymous_identity);
        e.set_ca_certificate(&eap.ca_certificate);
        e.set_no_ca_certificate(eap.no_ca_certificate);
        e.set_domain(&eap.domain);
        e.set_client_certificate(&eap.client_certificate);
        e.set_private_key(&eap.private_key);
        e.set_inner_auth(to_contract(&inner_auth_pairs(), eap.inner_auth));
        e.set_pac_file(&eap.pac_file);
        e.set_peap_version(eap.peap_version);
    }
    write_ip_settings(b.reborrow().init_ip4(), &s.ip4);
    write_ip_settings(b.init_ip6(), &s.ip6);
}

pub fn read_settings(r: n::connection_settings::Reader) -> capnp::Result<ConnectionSettings> {
    let w = r.get_wifi()?;
    let sec = r.get_security()?;
    let e = sec.get_eap()?;
    Ok(ConnectionSettings {
        name: r.get_name()?.to_string()?,
        autoconnect: r.get_autoconnect(),
        metered: read_metered(r.get_metered()?),
        available_to_all: r.get_available_to_all(),
        wifi: WifiSettings {
            ssid: w.get_ssid()?.to_vec(),
            hidden: w.get_hidden(),
            bssid: w.get_bssid()?.to_string()?,
            mac_address: w.get_mac_address()?.to_string()?,
            cloned_mac: from_contract(&cloned_mac_pairs(), w.get_cloned_mac()?),
            cloned_mac_address: w.get_cloned_mac_address()?.to_string()?,
        },
        security: SecuritySettings {
            security: read_security(sec.get_security()?),
            wep_key_index: sec.get_wep_key_index(),
            wep_passphrase: sec.get_wep_passphrase(),
            leap_username: sec.get_leap_username()?.to_string()?,
            eap: Eap8021xSettings {
                method: from_contract(&eap_method_pairs(), e.get_method()?),
                identity: e.get_identity()?.to_string()?,
                anonymous_identity: e.get_anonymous_identity()?.to_string()?,
                ca_certificate: e.get_ca_certificate()?.to_string()?,
                no_ca_certificate: e.get_no_ca_certificate(),
                domain: e.get_domain()?.to_string()?,
                client_certificate: e.get_client_certificate()?.to_string()?,
                private_key: e.get_private_key()?.to_string()?,
                inner_auth: from_contract(&inner_auth_pairs(), e.get_inner_auth()?),
                pac_file: e.get_pac_file()?.to_string()?,
                peap_version: e.get_peap_version(),
            },
        },
        ip4: read_ip_settings(r.get_ip4()?)?,
        ip6: read_ip_settings(r.get_ip6()?)?,
    })
}

fn write_result(mut b: n::result::Builder, result: &OpResult<impl Sized>) {
    match result {
        Ok(_) => b.set_error(n::ErrorCode::None),
        Err(error) => {
            b.set_error(match error.code {
                ErrorCode::NotFound => n::ErrorCode::NotFound,
                ErrorCode::NotAllowed => n::ErrorCode::NotAllowed,
                ErrorCode::InvalidArgument => n::ErrorCode::InvalidArgument,
                ErrorCode::NotSupported => n::ErrorCode::NotSupported,
                ErrorCode::Unavailable => n::ErrorCode::Unavailable,
                ErrorCode::Failed => n::ErrorCode::Failed,
            });
            b.set_message(&error.message);
        }
    }
}

// --- NetworkService: the bootstrap capability of every connection ---

pub struct NetworkService {
    hub: HubRef,
    commands: mpsc::UnboundedSender<Command>,
    backend: String,
}

impl NetworkService {
    pub fn client(hub: HubRef, commands: mpsc::UnboundedSender<Command>, backend: &str) -> network_service::Client {
        capnp_rpc::new_client(NetworkService { hub, commands, backend: backend.to_string() })
    }
}

/// Released by the client (or with its connection): the listener stops getting calls
struct ListenerSubscription {
    hub: Weak<RefCell<Hub>>,
    id: u64,
}

impl Drop for ListenerSubscription {
    fn drop(&mut self) {
        if let Some(hub) = self.hub.upgrade() {
            hub.borrow_mut().remove_listener(self.id);
        }
    }
}

impl subscription::Server for ListenerSubscription {}

/// Released by the shell (or with its connection): no more password requests go to it
struct PrompterRegistration {
    hub: Weak<RefCell<Hub>>,
    id: u64,
}

impl Drop for PrompterRegistration {
    fn drop(&mut self) {
        if let Some(hub) = self.hub.upgrade() {
            hub.borrow_mut().remove_prompter(self.id);
        }
    }
}

impl subscription::Server for PrompterRegistration {}

impl network_service::Server for NetworkService {
    async fn info(
        self: Rc<Self>,
        _: network_service::InfoParams,
        mut results: network_service::InfoResults,
    ) -> Result<(), capnp::Error> {
        let mut builder = results.get();
        builder.set_backend(&self.backend);
        builder.set_service_version(env!("CARGO_PKG_VERSION"));
        Ok(())
    }

    async fn watch(
        self: Rc<Self>,
        params: network_service::WatchParams,
        mut results: network_service::WatchResults,
    ) -> Result<(), capnp::Error> {
        let listener = params.get()?.get_listener()?;
        let id = Hub::add_listener(&self.hub, listener);
        results.get().set_subscription(capnp_rpc::new_client(ListenerSubscription { hub: Rc::downgrade(&self.hub), id }));
        Ok(())
    }

    async fn control(
        self: Rc<Self>,
        _: network_service::ControlParams,
        mut results: network_service::ControlResults,
    ) -> Result<(), capnp::Error> {
        let control = Control { hub: self.hub.clone(), commands: self.commands.clone() };
        results.get().set_control(capnp_rpc::new_client(control));
        Ok(())
    }

    async fn register_prompter(
        self: Rc<Self>,
        params: network_service::RegisterPrompterParams,
        mut results: network_service::RegisterPrompterResults,
    ) -> Result<(), capnp::Error> {
        let prompter = params.get()?.get_prompter()?;
        let id = Hub::set_prompter(&self.hub, prompter);
        results.get().set_registration(capnp_rpc::new_client(PrompterRegistration { hub: Rc::downgrade(&self.hub), id }));
        Ok(())
    }
}

// --- NetworkControl ---

struct Control {
    hub: HubRef,
    commands: mpsc::UnboundedSender<Command>,
}

impl Control {
    /// Sends a command and waits for the backend's answer
    async fn run<T>(&self, command: impl FnOnce(oneshot::Sender<OpResult<T>>) -> Command) -> OpResult<T> {
        let (reply, answer) = oneshot::channel();
        self.commands
            .send(command(reply))
            .map_err(|_| OpError::new(ErrorCode::Unavailable, "the backend has stopped"))?;
        answer.await.unwrap_or_else(|_| Err(OpError::new(ErrorCode::Failed, "the backend dropped the request")))
    }
}

impl network_control::Server for Control {
    async fn set_wireless_enabled(
        self: Rc<Self>,
        params: network_control::SetWirelessEnabledParams,
        mut results: network_control::SetWirelessEnabledResults,
    ) -> Result<(), capnp::Error> {
        let enabled = params.get()?.get_enabled();
        let result = self.run(|reply| Command::SetWirelessEnabled { enabled, reply }).await;
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn request_scan(
        self: Rc<Self>,
        params: network_control::RequestScanParams,
        mut results: network_control::RequestScanResults,
    ) -> Result<(), capnp::Error> {
        let device_id = params.get()?.get_device_id()?.to_string()?;
        let result = self.run(|reply| Command::RequestScan { device_id, reply }).await;
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn connect(
        self: Rc<Self>,
        params: network_control::ConnectParams,
        mut results: network_control::ConnectResults,
    ) -> Result<(), capnp::Error> {
        let id = params.get()?.get_network_id()?.to_string()?;
        let network = self.hub.borrow().networks.get(&id).cloned();
        let result = match network {
            None => Err(OpError::new(ErrorCode::NotFound, format!("no network {id}"))),
            Some(network) if network.connection_uuids.is_empty() && network.security.is_enterprise() => Err(OpError::new(
                ErrorCode::InvalidArgument,
                "an Enterprise network needs its 802.1X details: connectWithSettings",
            )),
            Some(network) => {
                let bssid = network.access_points.first().map(|ap| ap.bssid.clone()).unwrap_or_default();
                self.run(|reply| Command::ConnectNetwork {
                    device_id: network.device_id.clone(),
                    ssid: network.ssid.clone(),
                    security: network.security,
                    bssid,
                    connection_uuid: network.connection_uuids.first().cloned(),
                    reply,
                })
                .await
            }
        };
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn activate(
        self: Rc<Self>,
        params: network_control::ActivateParams,
        mut results: network_control::ActivateResults,
    ) -> Result<(), capnp::Error> {
        let p = params.get()?;
        let (uuid, device_id) = (p.get_uuid()?.to_string()?, p.get_device_id()?.to_string()?);
        let result = self.run(|reply| Command::Activate { uuid, device_id, reply }).await;
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn connect_with_settings(
        self: Rc<Self>,
        params: network_control::ConnectWithSettingsParams,
        mut results: network_control::ConnectWithSettingsResults,
    ) -> Result<(), capnp::Error> {
        let p = params.get()?;
        let device_id = p.get_device_id()?.to_string()?;
        let settings = read_settings(p.get_settings()?)?;
        let secrets = read_secrets(p.get_secrets()?)?;
        let result = self.run(|reply| Command::ConnectWithSettings { device_id, settings, secrets, reply }).await;
        let mut b = results.get();
        write_result(b.reborrow().init_result(), &result);
        if let Ok(uuid) = &result {
            b.set_uuid(uuid);
        }
        Ok(())
    }

    async fn disconnect(
        self: Rc<Self>,
        params: network_control::DisconnectParams,
        mut results: network_control::DisconnectResults,
    ) -> Result<(), capnp::Error> {
        let device_id = params.get()?.get_device_id()?.to_string()?;
        let result = self.run(|reply| Command::Disconnect { device_id, reply }).await;
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn forget(
        self: Rc<Self>,
        params: network_control::ForgetParams,
        mut results: network_control::ForgetResults,
    ) -> Result<(), capnp::Error> {
        let uuid = params.get()?.get_uuid()?.to_string()?;
        let result = self.run(|reply| Command::Forget { uuid, reply }).await;
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn settings(
        self: Rc<Self>,
        params: network_control::SettingsParams,
        mut results: network_control::SettingsResults,
    ) -> Result<(), capnp::Error> {
        let uuid = params.get()?.get_uuid()?.to_string()?;
        let result = self.run(|reply| Command::Settings { uuid, reply }).await;
        let mut b = results.get();
        write_result(b.reborrow().init_result(), &result);
        if let Ok(settings) = &result {
            write_settings(b.init_settings(), settings);
        }
        Ok(())
    }

    async fn update_settings(
        self: Rc<Self>,
        params: network_control::UpdateSettingsParams,
        mut results: network_control::UpdateSettingsResults,
    ) -> Result<(), capnp::Error> {
        let p = params.get()?;
        let uuid = p.get_uuid()?.to_string()?;
        let settings = read_settings(p.get_settings()?)?;
        let secrets = read_secrets(p.get_secrets()?)?;
        let result = self.run(|reply| Command::UpdateSettings { uuid, settings, secrets, reply }).await;
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn secrets(
        self: Rc<Self>,
        params: network_control::SecretsParams,
        mut results: network_control::SecretsResults,
    ) -> Result<(), capnp::Error> {
        let uuid = params.get()?.get_uuid()?.to_string()?;
        let result = self.run(|reply| Command::Secrets { uuid, reply }).await;
        let mut b = results.get();
        write_result(b.reborrow().init_result(), &result);
        if let Ok(secrets) = &result {
            write_secrets(b.init_secrets(secrets.len() as u32), secrets);
        }
        Ok(())
    }

    async fn qr_code(
        self: Rc<Self>,
        params: network_control::QrCodeParams,
        mut results: network_control::QrCodeResults,
    ) -> Result<(), capnp::Error> {
        let uuid = params.get()?.get_uuid()?.to_string()?;
        let connection = self.hub.borrow().connections.get(&uuid).cloned();
        let result = match connection {
            None => Err(OpError::new(ErrorCode::NotFound, format!("no connection {uuid}"))),
            Some(connection) if !connection.qr_supported() => {
                Err(OpError::new(ErrorCode::NotSupported, "no QR code for this security type"))
            }
            Some(connection) => self
                .run(|reply| Command::Secrets { uuid: uuid.clone(), reply })
                .await
                .and_then(|secrets| qr::wifi_code(&connection, &secrets)),
        };
        let mut b = results.get();
        write_result(b.reborrow().init_result(), &result);
        if let Ok(code) = &result {
            b.set_text(&code.text);
            b.set_size(code.size);
            b.set_modules(&code.modules);
        }
        Ok(())
    }

    async fn start_hotspot(
        self: Rc<Self>,
        params: network_control::StartHotspotParams,
        mut results: network_control::StartHotspotResults,
    ) -> Result<(), capnp::Error> {
        let p = params.get()?;
        let device_id = p.get_device_id()?.to_string()?;
        let ssid = p.get_ssid()?.to_string()?;
        let password = match p.get_password_kind()? {
            n::HotspotPasswordKind::Generate => HotspotPassword::Generate,
            n::HotspotPasswordKind::Given => HotspotPassword::Given(p.get_password()?.to_string()?),
        };
        let result = self.run(|reply| Command::StartHotspot { device_id, ssid, password, reply }).await;
        let mut b = results.get();
        write_result(b.reborrow().init_result(), &result);
        if let Ok((uuid, password)) = &result {
            b.set_uuid(uuid);
            b.set_password(password);
        }
        Ok(())
    }

    async fn stop_hotspot(
        self: Rc<Self>,
        params: network_control::StopHotspotParams,
        mut results: network_control::StopHotspotResults,
    ) -> Result<(), capnp::Error> {
        let device_id = params.get()?.get_device_id()?.to_string()?;
        let result = self.run(|reply| Command::StopHotspot { device_id, reply }).await;
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn check_connectivity(
        self: Rc<Self>,
        _: network_control::CheckConnectivityParams,
        mut results: network_control::CheckConnectivityResults,
    ) -> Result<(), capnp::Error> {
        let result = self.run(|reply| Command::CheckConnectivity { reply }).await;
        write_result(results.get().init_result(), &result);
        Ok(())
    }
}

/// Serves one client connection in the background
pub fn serve(stream: tokio::net::UnixStream, service: network_service::Client) {
    let (reader, writer) = stream.compat().split();
    let network = twoparty::VatNetwork::new(reader, writer, rpc_twoparty_capnp::Side::Server, Default::default());
    let rpc = RpcSystem::new(Box::new(network), Some(service.client));
    tokio::task::spawn_local(async move {
        let _ = rpc.await;
    });
}

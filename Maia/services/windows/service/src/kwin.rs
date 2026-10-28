//! Backend for KWin: the Wayland protocol org_kde_plasma_window_management (plasma-wayland-protocols),
//! the same protocol the task manager of Plasma (libtaskmanager, WaylandTasksModel) uses.
//!
//! KWin announces every window (window_with_uuid), the backend asks for its object
//! (get_window_by_uuid) and collects its properties until initial_state; from then on every change
//! of a window is sent on as the whole `Window`. Commands (activate, minimize, close, ...) become
//! requests on the window object.
//!
//! KWin gives this protocol only to privileged clients: X-KDE-Wayland-Interfaces in the .desktop file
//! of the program, or KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 in development sessions.
//!
//! The Wayland socket is polled by tokio (AsyncFd), so the backend shares the thread with the
//! Cap'n Proto side and never blocks it.

use std::collections::HashMap;
use std::error::Error;
use std::io::ErrorKind;
use std::os::fd::{AsFd, AsRawFd, OwnedFd, RawFd};
use std::time::Duration;

use tokio::io::AsyncReadExt;
use tokio::io::unix::AsyncFd;
use tokio::sync::{mpsc, oneshot};
use wayland_client::globals::{GlobalListContents, registry_queue_init};
use wayland_client::protocol::wl_registry;
use wayland_client::backend::WaylandError;
use wayland_client::{Connection, Dispatch, Proxy, QueueHandle};
use wayland_protocols_plasma::plasma_window_management::client::org_kde_plasma_window::{
    self, OrgKdePlasmaWindow,
};
use wayland_protocols_plasma::plasma_window_management::client::org_kde_plasma_window_management::{
    self, OrgKdePlasmaWindowManagement,
};

use crate::backend::{BackendEvent, BackendInfo, Command};
use crate::model::{Rect, Window};
use crate::windows_capnp as w;

/// What this backend can do (contract cap* bits)
const CAPABILITIES: u32 = w::CAP_ACTIVATE
    | w::CAP_CLOSE
    | w::CAP_MINIMIZE
    | w::CAP_MAXIMIZE
    | w::CAP_FULLSCREEN
    | w::CAP_KEEP_ABOVE_BELOW
    | w::CAP_MOVE_RESIZE
    | w::CAP_BITMAP_ICONS;

pub fn info() -> BackendInfo {
    BackendInfo { name: "kwin".into(), capabilities: CAPABILITIES }
}

/// get_window_by_uuid exists since version 12, window_with_uuid since 13
const MIN_VERSION: u32 = 13;
/// The newest version whose events this backend handles
const MAX_VERSION: u32 = 18;

const ICON_TIMEOUT: Duration = Duration::from_secs(2);

/// Connects to the compositor and runs until the connection ends or `events` is closed. An error
/// means the service could not start (no compositor, no permission for the protocol).
pub async fn run(
    events: mpsc::UnboundedSender<BackendEvent>,
    commands: mpsc::UnboundedReceiver<Command>,
) -> Result<(), Box<dyn Error>> {
    let connection = Connection::connect_to_env()?;
    let (globals, mut queue) = registry_queue_init::<State>(&connection)?;
    let qh = queue.handle();
    let _manager: OrgKdePlasmaWindowManagement = globals.bind(&qh, MIN_VERSION..=MAX_VERSION, ()).map_err(|error| {
        format!(
            "the compositor does not offer org_kde_plasma_window_management {MIN_VERSION}+ ({error}); \
             is it KWin, and may this program use privileged protocols?"
        )
    })?;

    // SAFETY: the descriptor belongs to `connection`, which outlives `socket` (both live in this
    // function, `socket` is declared later and dropped first)
    let socket = unsafe {
        AsyncFd::register_with_interest(
            PollFd(connection.backend().poll_fd().as_raw_fd()),
            tokio::io::Interest::READABLE,
        )?
    };
    // From here on an error means the compositor went away (normally: the session ends), which is
    // the regular end of the service, not a failure
    if let Err(error) = serve(&connection, &mut queue, &socket, events, commands).await {
        eprintln!("maia-windows: the compositor connection ended: {error}");
    }
    Ok(())
}

async fn serve(
    connection: &Connection,
    queue: &mut wayland_client::EventQueue<State>,
    socket: &AsyncFd<PollFd>,
    events: mpsc::UnboundedSender<BackendEvent>,
    mut commands: mpsc::UnboundedReceiver<Command>,
) -> Result<(), Box<dyn Error>> {
    let mut state = State::default();

    loop {
        queue.dispatch_pending(&mut state)?;
        for event in state.events.drain(..) {
            if events.send(event).is_err() {
                return Ok(());
            }
        }
        match connection.flush() {
            Err(WaylandError::Io(error)) if error.kind() == ErrorKind::WouldBlock => {}
            other => other?,
        }

        // Events already read but not dispatched yet: dispatch them first
        let Some(guard) = queue.prepare_read() else { continue };
        tokio::select! {
            ready = socket.readable() => {
                let mut ready = ready?;
                match guard.read() {
                    Ok(_) => {}
                    Err(WaylandError::Io(error)) if error.kind() == ErrorKind::WouldBlock => ready.clear_ready(),
                    Err(error) => return Err(error.into()),
                }
            }
            command = commands.recv() => {
                drop(guard);
                match command {
                    Some(command) => state.execute(command),
                    None => return Ok(()),
                }
            }
        }
    }
}

/// The Wayland socket for AsyncFd (owned by the Connection, which outlives it)
struct PollFd(RawFd);

impl AsRawFd for PollFd {
    fn as_raw_fd(&self) -> RawFd {
        self.0
    }
}

struct Tracked {
    proxy: OrgKdePlasmaWindow,
    window: Window,
    /// initial_state received: the window is complete and known to the rest of the service
    announced: bool,
}

#[derive(Default)]
struct State {
    windows: HashMap<String, Tracked>,
    events: Vec<BackendEvent>,
}

impl State {
    fn execute(&mut self, command: Command) {
        let tracked = |id: &str| self.windows.get(id).filter(|t| t.announced);
        match command {
            Command::SetState { id, flags, state } => {
                if let Some(t) = tracked(&id) {
                    t.proxy.set_state(flags, state);
                }
            }
            Command::Close(id) => {
                if let Some(t) = tracked(&id) {
                    t.proxy.close();
                }
            }
            Command::RequestMove(id) => {
                if let Some(t) = tracked(&id) {
                    t.proxy.request_move();
                }
            }
            Command::RequestResize(id) => {
                if let Some(t) = tracked(&id) {
                    t.proxy.request_resize();
                }
            }
            Command::FetchIcon { id, reply } => match tracked(&id) {
                Some(t) => fetch_icon(&t.proxy, reply),
                None => drop(reply),
            },
        }
    }

    /// A property of a window changed: send the window on, once it is complete
    fn changed(&mut self, id: &str, update: impl FnOnce(&mut Window)) {
        let Some(tracked) = self.windows.get_mut(id) else { return };
        update(&mut tracked.window);
        if tracked.announced {
            self.events.push(BackendEvent::Window(tracked.window.clone()));
        }
    }
}

/// KWin writes the icon into a pipe; it is read without blocking and sent to `reply`
fn fetch_icon(proxy: &OrgKdePlasmaWindow, reply: oneshot::Sender<Vec<u8>>) {
    let Ok((reader, writer)) = std::io::pipe() else {
        return;
    };
    proxy.get_icon(writer.as_fd());
    // The request keeps its own copy of the descriptor; ours must be closed, or the read never ends
    drop(writer);
    let Ok(mut reader) = tokio::net::unix::pipe::Receiver::from_owned_fd(OwnedFd::from(reader)) else {
        return;
    };
    tokio::task::spawn_local(async move {
        let mut data = Vec::new();
        if let Ok(Ok(_)) = tokio::time::timeout(ICON_TIMEOUT, reader.read_to_end(&mut data)).await {
            let _ = reply.send(data);
        }
    });
}

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for State {
    fn event(
        _: &mut Self,
        _: &wl_registry::WlRegistry,
        _: wl_registry::Event,
        _: &GlobalListContents,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<OrgKdePlasmaWindowManagement, ()> for State {
    fn event(
        state: &mut Self,
        manager: &OrgKdePlasmaWindowManagement,
        event: org_kde_plasma_window_management::Event,
        _: &(),
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        if let org_kde_plasma_window_management::Event::WindowWithUuid { uuid, .. } = event {
            let proxy = manager.get_window_by_uuid(uuid.clone(), qh, uuid.clone());
            let window = Window { id: uuid.clone(), ..Default::default() };
            state.windows.insert(uuid, Tracked { proxy, window, announced: false });
        }
    }
}

impl Dispatch<OrgKdePlasmaWindow, String> for State {
    fn event(
        state: &mut Self,
        proxy: &OrgKdePlasmaWindow,
        event: org_kde_plasma_window::Event,
        id: &String,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        use org_kde_plasma_window::Event as E;
        match event {
            E::TitleChanged { title } => state.changed(id, |w| w.title = title),
            E::AppIdChanged { app_id } => state.changed(id, |w| w.raw_app_id = app_id),
            E::ResourceNameChanged { resource_name } => state.changed(id, |w| w.resource_name = resource_name),
            E::PidChanged { pid } => state.changed(id, |w| w.pid = pid),
            E::StateChanged { flags } => state.changed(id, |w| w.states = flags),
            E::ThemedIconNameChanged { name } => state.changed(id, |w| w.theme_icon = name),
            E::IconChanged => state.changed(id, |w| w.icon_serial = w.icon_serial.wrapping_add(1).max(1)),
            E::Geometry { x, y, width, height } => {
                state.changed(id, |w| w.geometry = Rect { x, y, width, height })
            }
            E::VirtualDesktopEntered { id: desktop } => state.changed(id, |w| {
                if !w.virtual_desktops.contains(&desktop) {
                    w.virtual_desktops.push(desktop);
                }
            }),
            E::VirtualDesktopLeft { is: desktop } => state.changed(id, |w| w.virtual_desktops.retain(|d| *d != desktop)),
            E::ParentWindow { parent } => {
                let parent_id = parent.and_then(|p| p.data::<String>().cloned()).unwrap_or_default();
                state.changed(id, |w| w.parent_id = parent_id);
            }
            E::InitialState => {
                if let Some(tracked) = state.windows.get_mut(id) {
                    tracked.announced = true;
                    state.events.push(BackendEvent::Window(tracked.window.clone()));
                }
            }
            E::Unmapped => {
                if let Some(tracked) = state.windows.remove(id) {
                    if tracked.announced {
                        state.events.push(BackendEvent::Removed(id.clone()));
                    }
                }
                if proxy.version() >= 4 {
                    proxy.destroy();
                }
            }
            // Not part of the contract (yet): activities, application menu, client geometry,
            // the virtual desktop by number (deprecated)
            _ => {}
        }
    }
}

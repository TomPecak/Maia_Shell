//! The Decorations interface (decorations.capnp) over the decorations area: parameters in,
//! results out, the area's events to every listener, frontend activations as capabilities.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::{Rc, Weak};

use super::{text, write_result};
use crate::common_capnp::subscription;
use crate::decorations::theme::{BorderSize, Current, Engine, Origin, Theme};
use crate::decorations::{Decorations, Event};
use crate::decorations_capnp::{self as d, decorations, decorations_listener, frontend_activation};

// --- Writing values into the contract ---

fn engine(engine: Engine) -> d::Engine {
    match engine {
        Engine::AuroraeSvg => d::Engine::AuroraeSvg,
        Engine::AuroraeQml => d::Engine::AuroraeQml,
        Engine::Kdecoration => d::Engine::Kdecoration,
        Engine::Wayfire => d::Engine::Wayfire,
    }
}

fn border(size: BorderSize) -> d::BorderSize {
    match size {
        BorderSize::Theme => d::BorderSize::Theme,
        BorderSize::None => d::BorderSize::None,
        BorderSize::NoSides => d::BorderSize::NoSides,
        BorderSize::Tiny => d::BorderSize::Tiny,
        BorderSize::Normal => d::BorderSize::Normal,
        BorderSize::Large => d::BorderSize::Large,
        BorderSize::VeryLarge => d::BorderSize::VeryLarge,
        BorderSize::Huge => d::BorderSize::Huge,
        BorderSize::VeryHuge => d::BorderSize::VeryHuge,
        BorderSize::Oversized => d::BorderSize::Oversized,
    }
}

fn border_from(size: d::BorderSize) -> BorderSize {
    match size {
        d::BorderSize::Theme => BorderSize::Theme,
        d::BorderSize::None => BorderSize::None,
        d::BorderSize::NoSides => BorderSize::NoSides,
        d::BorderSize::Tiny => BorderSize::Tiny,
        d::BorderSize::Normal => BorderSize::Normal,
        d::BorderSize::Large => BorderSize::Large,
        d::BorderSize::VeryLarge => BorderSize::VeryLarge,
        d::BorderSize::Huge => BorderSize::Huge,
        d::BorderSize::VeryHuge => BorderSize::VeryHuge,
        d::BorderSize::Oversized => BorderSize::Oversized,
    }
}

fn write_theme(mut b: d::theme::Builder, theme: &Theme) {
    b.set_id(theme.id.to_string());
    b.set_engine(engine(theme.id.engine));
    b.set_name(&theme.name);
    b.set_description(&theme.description);
    b.set_author(&theme.author);
    b.set_origin(match theme.origin {
        Origin::System => d::Origin::System,
        Origin::Maia => d::Origin::Maia,
        Origin::User => d::Origin::User,
    });
    b.set_available(theme.available);
    b.set_unavailable_reason(&theme.unavailable_reason);
    b.set_path(theme.path.to_string_lossy().as_ref());
}

fn write_themes(mut list: capnp::struct_list::Builder<d::theme::Owned>, themes: &[Theme]) {
    for (i, theme) in themes.iter().enumerate() {
        write_theme(list.reborrow().get(i as u32), theme);
    }
}

fn write_current(mut b: d::current::Builder, current: &Current) {
    b.set_theme_id(current.theme.as_ref().map(ToString::to_string).unwrap_or_default());
    b.set_border_size(border(current.border_size));
    b.set_confirmed(current.confirmed);
    b.set_frontend(&current.frontend);
}

// --- Listeners ---

#[derive(Default)]
struct Listeners {
    next_id: u64,
    clients: HashMap<u64, decorations_listener::Client>,
}

type ListenersRef = Rc<RefCell<Listeners>>;

/// Sends a call; a listener whose call fails is gone
fn deliver<T: 'static>(listeners: &ListenersRef, id: u64, promise: capnp::capability::Promise<T, capnp::Error>) {
    let listeners = Rc::downgrade(listeners);
    tokio::task::spawn_local(async move {
        if promise.await.is_err() {
            if let Some(listeners) = listeners.upgrade() {
                listeners.borrow_mut().clients.remove(&id);
            }
        }
    });
}

fn broadcast(listeners: &ListenersRef, event: &Event) {
    let clients: Vec<(u64, decorations_listener::Client)> = listeners.borrow().clients.iter().map(|(i, c)| (*i, c.clone())).collect();
    for (id, client) in clients {
        match event {
            Event::ThemesChanged(themes) => {
                let mut request = client.themes_changed_request();
                write_themes(request.get().init_themes(themes.len() as u32), themes);
                deliver(listeners, id, request.send().promise);
            }
            Event::CurrentChanged(current) => {
                let mut request = client.current_changed_request();
                write_current(request.get().init_current(), current);
                deliver(listeners, id, request.send().promise);
            }
        }
    }
}

struct ListenerSubscription {
    listeners: Weak<RefCell<Listeners>>,
    id: u64,
}

impl Drop for ListenerSubscription {
    fn drop(&mut self) {
        if let Some(listeners) = self.listeners.upgrade() {
            listeners.borrow_mut().clients.remove(&self.id);
        }
    }
}

impl subscription::Server for ListenerSubscription {}

/// Released by the frontend's shell (or with its connection): the frontend's turn ends
struct Activation {
    area: Weak<Decorations>,
    token: u64,
}

impl Drop for Activation {
    fn drop(&mut self) {
        if let Some(area) = self.area.upgrade() {
            area.deactivate_frontend(self.token);
        }
    }
}

impl frontend_activation::Server for Activation {}

// --- The interface ---

pub struct DecorationsServer {
    area: Rc<Decorations>,
    listeners: ListenersRef,
}

impl DecorationsServer {
    /// One server for all clients; its events go to every listener
    pub fn client(area: Rc<Decorations>) -> decorations::Client {
        let listeners: ListenersRef = Rc::default();
        let mut events = area.subscribe();
        let weak = Rc::downgrade(&listeners);
        tokio::task::spawn_local(async move {
            while let Some(event) = events.recv().await {
                let Some(listeners) = weak.upgrade() else { return };
                broadcast(&listeners, &event);
            }
        });
        capnp_rpc::new_client(DecorationsServer { area, listeners })
    }
}

impl decorations::Server for DecorationsServer {
    async fn capabilities(
        self: Rc<Self>,
        _: decorations::CapabilitiesParams,
        mut results: decorations::CapabilitiesResults,
    ) -> Result<(), capnp::Error> {
        let info = self.area.info();
        let mut b = results.get().init_capabilities();
        b.set_compositor(&info.name);
        let mut engines = b.reborrow().init_engines(info.engines.len() as u32);
        for (i, e) in info.engines.iter().enumerate() {
            engines.set(i as u32, engine(*e));
        }
        b.set_border_sizes(info.border_sizes);
        b.set_install(info.engines.contains(&Engine::AuroraeSvg));
        Ok(())
    }

    async fn list(self: Rc<Self>, _: decorations::ListParams, mut results: decorations::ListResults) -> Result<(), capnp::Error> {
        let themes = self.area.themes();
        write_themes(results.get().init_themes(themes.len() as u32), &themes);
        Ok(())
    }

    async fn current(
        self: Rc<Self>,
        _: decorations::CurrentParams,
        mut results: decorations::CurrentResults,
    ) -> Result<(), capnp::Error> {
        write_current(results.get().init_current(), &self.area.current());
        Ok(())
    }

    async fn watch(self: Rc<Self>, params: decorations::WatchParams, mut results: decorations::WatchResults) -> Result<(), capnp::Error> {
        let client = params.get()?.get_listener()?;
        let id = {
            let mut listeners = self.listeners.borrow_mut();
            listeners.next_id += 1;
            let id = listeners.next_id;
            listeners.clients.insert(id, client.clone());
            id
        };
        // The snapshot goes first; later events follow it on the same capability, in order
        let themes = self.area.themes();
        let mut request = client.snapshot_request();
        write_themes(request.get().init_themes(themes.len() as u32), &themes);
        write_current(request.get().init_current(), &self.area.current());
        deliver(&self.listeners, id, request.send().promise);
        results.get().set_subscription(capnp_rpc::new_client(ListenerSubscription { listeners: Rc::downgrade(&self.listeners), id }));
        Ok(())
    }

    async fn set(self: Rc<Self>, params: decorations::SetParams, mut results: decorations::SetResults) -> Result<(), capnp::Error> {
        let id = text(params.get()?.get_theme_id())?;
        let result = self.area.set(&id).await;
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn set_border_size(
        self: Rc<Self>,
        params: decorations::SetBorderSizeParams,
        mut results: decorations::SetBorderSizeResults,
    ) -> Result<(), capnp::Error> {
        let size = border_from(params.get()?.get_size()?);
        let result = self.area.set_border_size(size).await;
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn install(self: Rc<Self>, params: decorations::InstallParams, mut results: decorations::InstallResults) -> Result<(), capnp::Error> {
        let path = text(params.get()?.get_path())?;
        let result = self.area.install(&path).await;
        let mut b = results.get();
        write_result(b.reborrow().init_result(), &result);
        if let Ok(id) = &result {
            b.set_theme_id(id.to_string());
        }
        Ok(())
    }

    async fn remove(self: Rc<Self>, params: decorations::RemoveParams, mut results: decorations::RemoveResults) -> Result<(), capnp::Error> {
        let id = text(params.get()?.get_theme_id())?;
        let result = self.area.remove(&id).await;
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn activate_frontend(
        self: Rc<Self>,
        params: decorations::ActivateFrontendParams,
        mut results: decorations::ActivateFrontendResults,
    ) -> Result<(), capnp::Error> {
        let p = params.get()?;
        let frontend = text(p.get_frontend())?;
        let default = text(p.get_default_theme_id())?;
        let mut b = results.get();
        match self.area.activate_frontend(&frontend, &default).await {
            Ok((token, applied)) => {
                write_result(b.reborrow().init_result(), &applied);
                b.set_activation(capnp_rpc::new_client(Activation { area: Rc::downgrade(&self.area), token }));
            }
            Err(error) => write_result(b.reborrow().init_result(), &Err::<(), _>(error)),
        }
        Ok(())
    }

    async fn refresh(self: Rc<Self>, _: decorations::RefreshParams, _: decorations::RefreshResults) -> Result<(), capnp::Error> {
        self.area.rescan().await;
        Ok(())
    }
}

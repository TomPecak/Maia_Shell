//! The Cap'n Proto side of the service (contract ../contract/tray.capnp): the TrayHost of the
//! shells, the bootstrap capability of the service's socket.

use std::cell::RefCell;
use std::rc::{Rc, Weak};

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use tokio_util::compat::TokioAsyncReadCompatExt;

use crate::hub::{ErrorCode, Hub, HubRef, OpError};
use crate::menu::{self, OpenMenu, Toggle};
use crate::model::{Category, Icon, Item, Status};
use crate::tray_capnp::{self as t, subscription, tray_host};

// --- Plain values into the contract ---

fn write_icon(mut b: t::icon::Builder, icon: &Icon) {
    b.set_name(&icon.name);
    b.set_url(&icon.url);
}

pub fn write_item(mut b: t::item::Builder, item: &Item) {
    b.set_id(item.id);
    b.set_key(&item.key);
    b.set_title(&item.title);
    b.set_status(match item.status {
        Status::Passive => t::Status::Passive,
        Status::Active => t::Status::Active,
        Status::NeedsAttention => t::Status::NeedsAttention,
    });
    b.set_category(match item.category {
        Category::ApplicationStatus => t::Category::ApplicationStatus,
        Category::Communications => t::Category::Communications,
        Category::SystemServices => t::Category::SystemServices,
        Category::Hardware => t::Category::Hardware,
    });
    write_icon(b.reborrow().init_icon(), &item.icon);
    write_icon(b.reborrow().init_attention_icon(), &item.attention_icon);
    write_icon(b.reborrow().init_overlay_icon(), &item.overlay_icon);
    {
        let mut tip = b.reborrow().init_tool_tip();
        tip.set_title(&item.tool_tip.title);
        tip.set_text(&item.tool_tip.text);
        write_icon(tip.init_icon(), &item.tool_tip.icon);
    }
    b.set_has_menu(item.has_menu);
    b.set_item_is_menu(item.item_is_menu);
    b.set_desktop_entry(&item.desktop_entry);
    b.set_app_name(&item.app_name);
    b.set_app_icon(&item.app_icon);
}

pub fn write_menu(mut list: capnp::struct_list::Builder<t::menu_entry::Owned>, entries: &[menu::Entry]) {
    for (i, entry) in entries.iter().enumerate() {
        let mut b = list.reborrow().get(i as u32);
        b.set_id(entry.id);
        b.set_separator(entry.separator);
        b.set_label(&entry.label);
        b.set_enabled(entry.enabled);
        write_icon(b.reborrow().init_icon(), &entry.icon);
        b.set_toggle(match entry.toggle {
            Toggle::None => t::Toggle::None,
            Toggle::Checkmark => t::Toggle::Checkmark,
            Toggle::Radio => t::Toggle::Radio,
        });
        b.set_checked(entry.checked);
        b.set_shortcut(&entry.shortcut);
        b.set_submenu(entry.submenu);
        write_menu(b.init_children(entry.children.len() as u32), &entry.children);
    }
}

fn write_result(mut b: t::result::Builder, result: &Result<(), OpError>) {
    match result {
        Ok(()) => b.set_error(t::ErrorCode::None),
        Err(error) => {
            b.set_error(match error.code {
                ErrorCode::NotFound => t::ErrorCode::NotFound,
                ErrorCode::InvalidArgument => t::ErrorCode::InvalidArgument,
                ErrorCode::Unavailable => t::ErrorCode::Unavailable,
            });
            b.set_message(&error.message);
        }
    }
}

fn text(reader: capnp::Result<capnp::text::Reader>) -> capnp::Result<String> {
    Ok(reader?.to_string()?)
}

// --- TrayHost: the shells ---

pub struct Host {
    hub: HubRef,
}

impl Host {
    pub fn client(hub: HubRef) -> tray_host::Client {
        capnp_rpc::new_client(Host { hub })
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

/// A shell's open menu; dropping it closes the menu for the application
struct MenuImpl {
    menu: Rc<OpenMenu>,
}

impl t::menu::Server for MenuImpl {
    async fn about_to_show(self: Rc<Self>, params: t::menu::AboutToShowParams, _: t::menu::AboutToShowResults) -> Result<(), capnp::Error> {
        self.menu.about_to_show(params.get()?.get_entry_id());
        Ok(())
    }

    async fn submenu_closed(self: Rc<Self>, params: t::menu::SubmenuClosedParams, _: t::menu::SubmenuClosedResults) -> Result<(), capnp::Error> {
        self.menu.submenu_closed(params.get()?.get_entry_id());
        Ok(())
    }

    async fn activate(self: Rc<Self>, params: t::menu::ActivateParams, mut results: t::menu::ActivateResults) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let result = self.menu.activate(params.get_entry_id(), &text(params.get_activation_token())?);
        write_result(results.get().init_result(), &result);
        Ok(())
    }
}

impl tray_host::Server for Host {
    async fn info(self: Rc<Self>, _: tray_host::InfoParams, mut results: tray_host::InfoResults) -> Result<(), capnp::Error> {
        results.get().set_service_version(env!("CARGO_PKG_VERSION"));
        Ok(())
    }

    async fn watch(self: Rc<Self>, params: tray_host::WatchParams, mut results: tray_host::WatchResults) -> Result<(), capnp::Error> {
        let listener = params.get()?.get_listener()?;
        let id = Hub::add_listener(&self.hub, listener);
        results.get().set_subscription(capnp_rpc::new_client(SubscriptionImpl { hub: Rc::downgrade(&self.hub), id }));
        Ok(())
    }

    async fn activate(self: Rc<Self>, params: tray_host::ActivateParams, mut results: tray_host::ActivateResults) -> Result<(), capnp::Error> {
        let p = params.get()?;
        let result = Hub::activate(&self.hub, p.get_id(), p.get_x(), p.get_y(), &text(p.get_activation_token())?, false);
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn secondary_activate(
        self: Rc<Self>,
        params: tray_host::SecondaryActivateParams,
        mut results: tray_host::SecondaryActivateResults,
    ) -> Result<(), capnp::Error> {
        let p = params.get()?;
        let result = Hub::activate(&self.hub, p.get_id(), p.get_x(), p.get_y(), &text(p.get_activation_token())?, true);
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn context_menu(self: Rc<Self>, params: tray_host::ContextMenuParams, mut results: tray_host::ContextMenuResults) -> Result<(), capnp::Error> {
        let p = params.get()?;
        let result = Hub::context_menu(&self.hub, p.get_id(), p.get_x(), p.get_y());
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn scroll(self: Rc<Self>, params: tray_host::ScrollParams, mut results: tray_host::ScrollResults) -> Result<(), capnp::Error> {
        let p = params.get()?;
        let horizontal = p.get_orientation()? == t::Orientation::Horizontal;
        let result = Hub::scroll(&self.hub, p.get_id(), p.get_delta(), horizontal);
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn open_menu(self: Rc<Self>, params: tray_host::OpenMenuParams, mut results: tray_host::OpenMenuResults) -> Result<(), capnp::Error> {
        let p = params.get()?;
        let listener = p.get_listener()?;
        match OpenMenu::open(&self.hub, p.get_id(), listener) {
            Ok(menu) => {
                let mut b = results.get();
                b.set_menu(capnp_rpc::new_client(MenuImpl { menu }));
                write_result(b.init_result(), &Ok(()));
            }
            Err(error) => write_result(results.get().init_result(), &Err(error)),
        }
        Ok(())
    }
}

// --- Connections ---

/// Serves one client connection in the background, with `bootstrap` as its first capability
pub fn serve(stream: tokio::net::UnixStream, bootstrap: capnp::capability::Client) {
    let (reader, writer) = stream.compat().split();
    let network = twoparty::VatNetwork::new(
        futures::io::BufReader::new(reader),
        futures::io::BufWriter::new(writer),
        rpc_twoparty_capnp::Side::Server,
        Default::default(),
    );
    let rpc_system = RpcSystem::new(Box::new(network), Some(bootstrap));
    tokio::task::spawn_local(async move {
        let _ = rpc_system.await;
    });
}

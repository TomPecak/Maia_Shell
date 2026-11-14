//! The Cap'n Proto side of the service (contract ../contract/notifications.capnp): the
//! NotificationCenter of the shells and the Notifier of Maia's programs, each the bootstrap
//! capability of its own socket.

use std::cell::RefCell;
use std::rc::{Rc, Weak};

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use tokio_util::compat::TokioAsyncReadCompatExt;

use crate::hub::{ErrorCode, Hub, HubRef, OpError, Origin};
use crate::markup;
use crate::model::{
    Action, CloseReason, DoNotDisturb, ImageSource, MAX_ACTIONS, MAX_BODY_CHARS, MAX_SUMMARY_CHARS, Notification,
    Request, Store, Urgency, limit_chars,
};
use crate::jobs::{self, JobRequest, JobUpdate, Unit};
use crate::notifications_capnp::{
    self as n, job_handle, notification_center, notification_handle, notifier, subscription,
};

// --- Plain values into the contract ---

pub fn write_urgency(urgency: Urgency) -> n::Urgency {
    match urgency {
        Urgency::Low => n::Urgency::Low,
        Urgency::Normal => n::Urgency::Normal,
        Urgency::Critical => n::Urgency::Critical,
    }
}

pub fn read_urgency(urgency: n::Urgency) -> Urgency {
    match urgency {
        n::Urgency::Low => Urgency::Low,
        n::Urgency::Normal => Urgency::Normal,
        n::Urgency::Critical => Urgency::Critical,
    }
}

pub fn write_reason(reason: CloseReason) -> n::CloseReason {
    match reason {
        CloseReason::Expired => n::CloseReason::Expired,
        CloseReason::Dismissed => n::CloseReason::Dismissed,
        CloseReason::ClosedByApp => n::CloseReason::ClosedByApp,
        CloseReason::Other => n::CloseReason::Other,
    }
}

pub fn write_notification(mut b: n::notification::Builder, notification: &Notification) {
    b.set_id(notification.id);
    b.set_app_name(&notification.app_name);
    b.set_desktop_entry(&notification.desktop_entry);
    b.set_app_icon(&notification.app_icon);
    b.set_summary(&notification.summary);
    b.set_body(&notification.body);
    b.set_image(&notification.image);
    {
        let mut actions = b.reborrow().init_actions(notification.actions.len() as u32);
        for (i, action) in notification.actions.iter().enumerate() {
            let mut a = actions.reborrow().get(i as u32);
            a.set_key(&action.key);
            a.set_label(&action.label);
        }
    }
    b.set_action_icons(notification.action_icons);
    b.set_urgency(write_urgency(notification.urgency));
    b.set_category(&notification.category);
    b.set_timeout(notification.timeout);
    b.set_time(notification.time);
    b.set_transient(notification.transient);
    b.set_resident(notification.resident);
    b.set_popup(notification.popup);
    b.set_expired(notification.expired);
    b.set_inline_reply(notification.inline_reply);
    b.set_reply_placeholder(&notification.reply_placeholder);
    b.set_reply_submit_text(&notification.reply_submit_text);
    b.set_origin_name(&notification.origin_name);
    {
        let mut urls = b.reborrow().init_urls(notification.urls.len() as u32);
        for (i, url) in notification.urls.iter().enumerate() {
            urls.set(i as u32, url);
        }
    }
    b.set_sound_name(&notification.sound_name);
    b.set_sound_file(&notification.sound_file);
    b.set_suppress_sound(notification.suppress_sound);
}

pub fn write_do_not_disturb(mut b: n::do_not_disturb::Builder, dnd: &DoNotDisturb, now: i64) {
    b.set_enabled(dnd.enabled_at(now));
    b.set_until(if dnd.enabled_at(now) { dnd.until } else { 0 });
    b.set_active(dnd.active_at(now));
    let mut inhibitors = b.init_inhibitors(dnd.inhibitors.len() as u32);
    for (i, inhibitor) in dnd.inhibitors.values().enumerate() {
        let mut b = inhibitors.reborrow().get(i as u32);
        b.set_desktop_entry(&inhibitor.desktop_entry);
        b.set_app_name(&inhibitor.app_name);
        b.set_reason(&inhibitor.reason);
    }
}

pub fn write_job(mut b: n::job::Builder, job: &crate::jobs::Job) {
    use crate::jobs::JobState;
    b.set_id(job.id);
    b.set_app_name(&job.app_name);
    b.set_desktop_entry(&job.desktop_entry);
    b.set_app_icon(&job.app_icon);
    b.set_title(&job.title);
    b.set_info_message(&job.info_message);
    b.set_state(match job.state {
        JobState::Running => n::JobState::Running,
        JobState::Suspended => n::JobState::Suspended,
        JobState::Finished => n::JobState::Finished,
        JobState::Failed => n::JobState::Failed,
    });
    b.set_percent(job.percent);
    b.set_processed_bytes(job.processed_bytes);
    b.set_total_bytes(job.total_bytes);
    b.set_processed_files(job.processed_files);
    b.set_total_files(job.total_files);
    b.set_processed_directories(job.processed_directories);
    b.set_total_directories(job.total_directories);
    b.set_processed_items(job.processed_items);
    b.set_total_items(job.total_items);
    b.set_speed(job.speed);
    b.set_elapsed(job.elapsed);
    {
        let mut fields = b.reborrow().init_fields(job.fields.len() as u32);
        for (i, field) in job.fields.values().enumerate() {
            let mut f = fields.reborrow().get(i as u32);
            f.set_label(&field.label);
            f.set_value(&field.value);
        }
    }
    b.set_destination(&job.destination);
    b.set_error_code(job.error_code);
    b.set_error_text(&job.error_text);
    b.set_owner_gone(job.owner_gone);
    b.set_killable(job.killable);
    b.set_suspendable(job.suspendable);
    b.set_started(job.started);
    b.set_updated(job.updated);
}

pub fn write_snapshot(mut b: n::snapshot::Builder, store: &Store<Origin>, jobs: &crate::jobs::JobStore, now: i64) {
    {
        let visible = jobs.visible();
        let mut list = b.reborrow().init_jobs(visible.len() as u32);
        for (i, job) in visible.iter().enumerate() {
            write_job(list.reborrow().get(i as u32), job);
        }
    }
    let ready = store.ready();
    {
        let mut list = b.reborrow().init_notifications(ready.len() as u32);
        for (i, notification) in ready.iter().enumerate() {
            write_notification(list.reborrow().get(i as u32), notification);
        }
    }
    write_do_not_disturb(b.init_do_not_disturb(), &store.dnd, now);
}

fn write_result(mut b: n::result::Builder, result: &Result<(), OpError>) {
    match result {
        Ok(()) => b.set_error(n::ErrorCode::None),
        Err(error) => {
            b.set_error(match error.code {
                ErrorCode::NotFound => n::ErrorCode::NotFound,
                ErrorCode::InvalidArgument => n::ErrorCode::InvalidArgument,
                ErrorCode::Unavailable => n::ErrorCode::Unavailable,
            });
            b.set_message(&error.message);
        }
    }
}

fn text(reader: capnp::Result<capnp::text::Reader>) -> capnp::Result<String> {
    Ok(reader?.to_string()?)
}

/// A request of a Notifier client in the service's terms: the same checks as on D-Bus
pub fn read_request(r: n::notification_request::Reader) -> capnp::Result<Request> {
    let mut actions = Vec::new();
    for action in r.get_actions()? {
        let key = text(action.get_key())?;
        if !key.is_empty() && actions.len() < MAX_ACTIONS {
            actions.push(Action { key, label: text(action.get_label())? });
        }
    }
    let image = crate::image::url_from_path(&text(r.get_image())?);
    Ok(Request {
        app_name: text(r.get_app_name())?,
        desktop_entry: text(r.get_desktop_entry())?.trim_end_matches(".desktop").to_string(),
        app_icon: crate::image::icon(&text(r.get_app_icon())?),
        summary: limit_chars(markup::plain(&text(r.get_summary())?), MAX_SUMMARY_CHARS),
        body: markup::sanitize(&limit_chars(text(r.get_body())?, MAX_BODY_CHARS)),
        image: if image.is_empty() { ImageSource::None } else { ImageSource::Url(image) },
        actions,
        action_icons: r.get_action_icons(),
        urgency: read_urgency(r.get_urgency()?),
        category: text(r.get_category())?,
        timeout: r.get_timeout().max(-1),
        transient: r.get_transient(),
        resident: r.get_resident(),
        inline_reply: r.get_inline_reply(),
        reply_placeholder: text(r.get_reply_placeholder())?,
        reply_submit_text: text(r.get_reply_submit_text())?,
        origin_name: String::new(),
        urls: Vec::new(),
        sound_name: text(r.get_sound_name())?,
        sound_file: String::new(),
        suppress_sound: r.get_suppress_sound(),
    })
}

/// The most detail lines of a Maia sender's job
pub const MAX_JOB_FIELDS: usize = 8;

/// A Maia sender's whole state of its job, as a change that replaces everything
pub fn read_progress(p: n::job_progress::Reader) -> capnp::Result<JobUpdate> {
    let mut fields = Vec::new();
    for (i, field) in p.get_fields()?.iter().take(MAX_JOB_FIELDS).enumerate() {
        fields.push((i as u32, text(field.get_label())?, text(field.get_value())?));
    }
    Ok(JobUpdate {
        title: Some(text(p.get_title())?),
        info_message: Some(text(p.get_info_message())?),
        percent: Some(p.get_percent()),
        processed: vec![
            (Unit::Bytes, p.get_processed_bytes()),
            (Unit::Files, p.get_processed_files()),
            (Unit::Directories, p.get_processed_directories()),
            (Unit::Items, p.get_processed_items()),
        ],
        total: vec![
            (Unit::Bytes, p.get_total_bytes()),
            (Unit::Files, p.get_total_files()),
            (Unit::Directories, p.get_total_directories()),
            (Unit::Items, p.get_total_items()),
        ],
        speed: Some(p.get_speed()),
        elapsed: None,
        fields,
        all_fields: true,
        destination: Some(text(p.get_destination())?),
        suspended: Some(p.get_suspended()),
    })
}

fn write_info(mut capabilities: capnp::text_list::Builder) {
    for (i, capability) in crate::CAPABILITIES.iter().enumerate() {
        capabilities.set(i as u32, capability);
    }
}

// --- NotificationCenter: the shells ---

pub struct Center {
    hub: HubRef,
}

impl Center {
    pub fn client(hub: HubRef) -> notification_center::Client {
        capnp_rpc::new_client(Center { hub })
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

impl notification_center::Server for Center {
    async fn info(
        self: Rc<Self>,
        _: notification_center::InfoParams,
        mut results: notification_center::InfoResults,
    ) -> Result<(), capnp::Error> {
        let mut b = results.get();
        b.set_service_version(env!("CARGO_PKG_VERSION"));
        write_info(b.init_capabilities(crate::CAPABILITIES.len() as u32));
        Ok(())
    }

    async fn watch(
        self: Rc<Self>,
        params: notification_center::WatchParams,
        mut results: notification_center::WatchResults,
    ) -> Result<(), capnp::Error> {
        let listener = params.get()?.get_listener()?;
        let id = Hub::add_listener(&self.hub, listener);
        results.get().set_subscription(capnp_rpc::new_client(SubscriptionImpl { hub: Rc::downgrade(&self.hub), id }));
        Ok(())
    }

    async fn invoke_action(
        self: Rc<Self>,
        params: notification_center::InvokeActionParams,
        mut results: notification_center::InvokeActionResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let result = Hub::invoke_action(&self.hub, params.get_id(), &text(params.get_key())?, &text(params.get_activation_token())?);
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn reply(
        self: Rc<Self>,
        params: notification_center::ReplyParams,
        mut results: notification_center::ReplyResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let result = Hub::reply(&self.hub, params.get_id(), &text(params.get_text())?, &text(params.get_activation_token())?);
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn dismiss(
        self: Rc<Self>,
        params: notification_center::DismissParams,
        mut results: notification_center::DismissResults,
    ) -> Result<(), capnp::Error> {
        let result = Hub::dismiss(&self.hub, params.get()?.get_id());
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn expire(
        self: Rc<Self>,
        params: notification_center::ExpireParams,
        mut results: notification_center::ExpireResults,
    ) -> Result<(), capnp::Error> {
        let result = Hub::expire(&self.hub, params.get()?.get_id());
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn dismiss_all(
        self: Rc<Self>,
        _: notification_center::DismissAllParams,
        _: notification_center::DismissAllResults,
    ) -> Result<(), capnp::Error> {
        Hub::dismiss_all(&self.hub);
        Ok(())
    }

    async fn set_do_not_disturb(
        self: Rc<Self>,
        params: notification_center::SetDoNotDisturbParams,
        _: notification_center::SetDoNotDisturbResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        Hub::set_do_not_disturb(&self.hub, params.get_enabled(), params.get_until());
        Ok(())
    }

    async fn cancel_job(
        self: Rc<Self>,
        params: notification_center::CancelJobParams,
        mut results: notification_center::CancelJobResults,
    ) -> Result<(), capnp::Error> {
        let result = Hub::cancel_job(&self.hub, params.get()?.get_id());
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn suspend_job(
        self: Rc<Self>,
        params: notification_center::SuspendJobParams,
        mut results: notification_center::SuspendJobResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let result = Hub::suspend_job(&self.hub, params.get_id(), params.get_suspended());
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn dismiss_job(
        self: Rc<Self>,
        params: notification_center::DismissJobParams,
        mut results: notification_center::DismissJobResults,
    ) -> Result<(), capnp::Error> {
        let result = Hub::dismiss_job(&self.hub, params.get()?.get_id());
        write_result(results.get().init_result(), &result);
        Ok(())
    }
}

// --- Notifier: Maia's programs ---

pub struct NotifierImpl {
    hub: HubRef,
}

impl NotifierImpl {
    pub fn client(hub: HubRef) -> notifier::Client {
        capnp_rpc::new_client(NotifierImpl { hub })
    }
}

/// A sender's hold on its notification; dropping it changes nothing
struct HandleImpl {
    hub: Weak<RefCell<Hub>>,
    id: u32,
    origin: Origin,
}

impl notification_handle::Server for HandleImpl {
    async fn update(
        self: Rc<Self>,
        params: notification_handle::UpdateParams,
        mut results: notification_handle::UpdateResults,
    ) -> Result<(), capnp::Error> {
        let request = read_request(params.get()?.get_notification()?)?;
        let result = match self.hub.upgrade() {
            Some(hub) if hub.borrow().store().get(self.id).is_some() => {
                Hub::notify(&hub, self.id, request, self.origin.clone());
                Ok(())
            }
            Some(_) => Err(OpError::new(ErrorCode::NotFound, format!("notification {} is closed", self.id))),
            None => Err(OpError::new(ErrorCode::Unavailable, "the service is ending")),
        };
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn close(
        self: Rc<Self>,
        _: notification_handle::CloseParams,
        _: notification_handle::CloseResults,
    ) -> Result<(), capnp::Error> {
        if let Some(hub) = self.hub.upgrade() {
            Hub::close_by_app(&hub, self.id);
        }
        Ok(())
    }
}

/// A sender's hold on its job; dropping it before the end fails the job
struct JobHandleImpl {
    hub: Weak<RefCell<Hub>>,
    id: u32,
}

impl JobHandleImpl {
    fn end(&self, code: u32, text: &str) {
        if let Some(hub) = self.hub.upgrade() {
            Hub::terminate_job(&hub, self.id, code, text);
        }
    }
}

impl Drop for JobHandleImpl {
    fn drop(&mut self) {
        // Nothing when it has ended already
        if let Some(hub) = self.hub.upgrade() {
            Hub::abandon_job(&hub, self.id);
        }
    }
}

impl job_handle::Server for JobHandleImpl {
    async fn update(
        self: Rc<Self>,
        params: job_handle::UpdateParams,
        mut results: job_handle::UpdateResults,
    ) -> Result<(), capnp::Error> {
        let update = read_progress(params.get()?.get_progress()?)?;
        let result = match self.hub.upgrade() {
            Some(hub) if hub.borrow().job_running(self.id) => {
                Hub::update_job(&hub, self.id, update);
                Ok(())
            }
            Some(_) => Err(OpError::new(ErrorCode::NotFound, format!("job {} has ended", self.id))),
            None => Err(OpError::new(ErrorCode::Unavailable, "the service is ending")),
        };
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn finish(
        self: Rc<Self>,
        params: job_handle::FinishParams,
        _: job_handle::FinishResults,
    ) -> Result<(), capnp::Error> {
        let error = text(params.get()?.get_error_text())?;
        self.end(if error.is_empty() { 0 } else { jobs::ERR_FAILED }, &error);
        Ok(())
    }

    async fn canceled(
        self: Rc<Self>,
        _: job_handle::CanceledParams,
        _: job_handle::CanceledResults,
    ) -> Result<(), capnp::Error> {
        self.end(jobs::ERR_USER_CANCELED, "");
        Ok(())
    }
}

impl notifier::Server for NotifierImpl {
    async fn info(
        self: Rc<Self>,
        _: notifier::InfoParams,
        mut results: notifier::InfoResults,
    ) -> Result<(), capnp::Error> {
        let mut b = results.get();
        b.set_service_version(env!("CARGO_PKG_VERSION"));
        write_info(b.init_capabilities(crate::CAPABILITIES.len() as u32));
        Ok(())
    }

    async fn notify(
        self: Rc<Self>,
        params: notifier::NotifyParams,
        mut results: notifier::NotifyResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let request = read_request(params.get_notification()?)?;
        let origin = match params.get_listener() {
            Ok(listener) => Origin::Maia(listener),
            Err(_) => Origin::Nobody,
        };
        let id = Hub::notify(&self.hub, 0, request, origin.clone());
        let mut b = results.get();
        b.set_id(id);
        b.set_handle(capnp_rpc::new_client(HandleImpl { hub: Rc::downgrade(&self.hub), id, origin }));
        Ok(())
    }

    async fn start_job(
        self: Rc<Self>,
        params: notifier::StartJobParams,
        mut results: notifier::StartJobResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let listener = params.get_listener()?;
        let r = params.get_job()?;
        let desktop_entry = text(r.get_desktop_entry())?.trim_end_matches(".desktop").to_string();
        let mut app_name = text(r.get_app_name())?;
        let mut app_icon = crate::image::icon(&text(r.get_app_icon())?);
        let capabilities = if r.get_killable() { jobs::CAP_KILLABLE } else { 0 } | if r.get_suspendable() { jobs::CAP_SUSPENDABLE } else { 0 };
        let (immediate, transient) = (r.get_immediate(), r.get_transient());
        let initial = read_progress(r.get_progress()?)?;
        crate::dbus_jobs::complete_from_entry(&desktop_entry, &mut app_name, &mut app_icon).await;
        let request = JobRequest { app_name, desktop_entry, app_icon, capabilities, immediate, transient, initial };
        let id = Hub::create_maia_job(&self.hub, request, listener);
        let mut b = results.get();
        b.set_id(id);
        b.set_handle(capnp_rpc::new_client(JobHandleImpl { hub: Rc::downgrade(&self.hub), id }));
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

//! The jobs' side of D-Bus: KDE's org.kde.JobViewServer, through which KDE applications report the
//! progress of long operations (KIO's copies in Dolphin, Ark's archives, downloads). It is what
//! Plasma's notification applet serves; the interfaces are those of
//! plasma-workspace/libnotificationmanager/dbus/:
//!
//! - /JobViewServer: org.kde.JobViewServerV2.requestView(desktopEntry, capabilities, hints), used by
//!   KJobWidgets (KUiServerV2JobTracker), and the old org.kde.JobViewServer.requestView(appName,
//!   appIconName, capabilities); bus names org.kde.JobViewServer and org.kde.kuiserver;
//! - /JobViewServer also: org.kde.kuiserver, which KIO asks before it reports a job
//!   (KDynamicJobTracker: without it, or with requiresJobTracker() true, KIO keeps its own progress
//!   dialog), and jobUrlsChanged for file managers;
//! - one object per job, /org/kde/notificationmanager/jobs/JobView_<id>, with org.kde.JobViewV3
//!   (update(properties), terminate(code, message, hints)) and the old org.kde.JobViewV2 (one setter
//!   per value); both emit cancelRequested, suspendRequested and resumeRequested.
//!
//! As for notifications, the methods only hand a `DbusCall` to the hub's task; requestView waits
//! for the job's number, which comes in the same turn of the loop.

use std::collections::HashMap;

use tokio::sync::{mpsc, oneshot};
use zbus::message::Header;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};

use crate::dbus::DbusCall;
use crate::jobs::{JobRequest, JobUpdate, Unit};

pub const SERVER_PATH: &str = "/JobViewServer";
pub const NAMES: [&str; 2] = ["org.kde.JobViewServer", "org.kde.kuiserver"];

pub fn job_path(id: u32) -> String {
    format!("/org/kde/notificationmanager/jobs/JobView_{id}")
}

fn gone() -> zbus::fdo::Error {
    zbus::fdo::Error::Failed("the notification service is ending".into())
}

fn sender_of(header: &Header<'_>) -> String {
    header.sender().map(|s| s.to_string()).unwrap_or_default()
}

// --- Properties ---

fn str_of(value: &Value<'_>) -> Option<String> {
    match value {
        Value::Str(s) => Some(s.as_str().to_string()),
        Value::Value(inner) => str_of(inner),
        _ => None,
    }
}

fn u64_of(value: &Value<'_>) -> Option<u64> {
    match value {
        Value::U8(v) => Some(*v as u64),
        Value::U16(v) => Some(*v as u64),
        Value::U32(v) => Some(*v as u64),
        Value::U64(v) => Some(*v),
        Value::I16(v) => u64::try_from(*v).ok(),
        Value::I32(v) => u64::try_from(*v).ok(),
        Value::I64(v) => u64::try_from(*v).ok(),
        Value::Value(inner) => u64_of(inner),
        _ => None,
    }
}

fn bool_of(value: &Value<'_>) -> Option<bool> {
    match value {
        Value::Bool(b) => Some(*b),
        Value::Value(inner) => bool_of(inner),
        other => u64_of(other).map(|v| v != 0),
    }
}

/// The properties of JobViewV3.update (and of requestView's hints) as a change
pub fn update_from(properties: &HashMap<String, OwnedValue>) -> JobUpdate {
    let get = |key: &str| properties.get(key).map(|v| &**v);
    let mut update = JobUpdate {
        title: get("title").and_then(str_of),
        info_message: get("infoMessage").and_then(str_of),
        percent: get("percent").and_then(u64_of).map(|p| p.min(100) as u32),
        speed: get("speed").and_then(u64_of),
        elapsed: get("elapsedTime").and_then(u64_of).map(|e| e as i64),
        destination: get("destUrl").and_then(str_of),
        suspended: get("suspended").and_then(bool_of),
        ..Default::default()
    };
    for (key, unit) in [("Bytes", Unit::Bytes), ("Files", Unit::Files), ("Directories", Unit::Directories), ("Items", Unit::Items)] {
        if let Some(amount) = get(&format!("processed{key}")).and_then(u64_of) {
            update.processed.push((unit, amount));
        }
        if let Some(amount) = get(&format!("total{key}")).and_then(u64_of) {
            update.total.push((unit, amount));
        }
    }
    for number in [1u32, 2] {
        let label = get(&format!("descriptionLabel{number}")).and_then(str_of);
        let value = get(&format!("descriptionValue{number}")).and_then(str_of);
        if label.is_some() || value.is_some() {
            update.fields.push((number - 1, label.unwrap_or_default(), value.unwrap_or_default()));
        }
    }
    update
}

/// Name= and Icon= of a desktop entry, from the applications directories (a few small reads)
fn desktop_entry_info(entry: &str) -> (String, String) {
    let mut dirs: Vec<std::path::PathBuf> = Vec::new();
    if let Some(home) = std::env::var_os("XDG_DATA_HOME").map(std::path::PathBuf::from).or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".local/share"))) {
        dirs.push(home);
    }
    let data_dirs = std::env::var("XDG_DATA_DIRS").unwrap_or_else(|_| "/usr/local/share:/usr/share".into());
    dirs.extend(data_dirs.split(':').filter(|d| !d.is_empty()).map(std::path::PathBuf::from));
    for dir in dirs {
        let Ok(text) = std::fs::read_to_string(dir.join("applications").join(format!("{entry}.desktop"))) else { continue };
        let (mut name, mut icon, mut in_entry) = (String::new(), String::new(), false);
        for line in text.lines() {
            let line = line.trim();
            if line.starts_with('[') {
                in_entry = line == "[Desktop Entry]";
            } else if in_entry {
                if let Some(v) = line.strip_prefix("Name=") {
                    name = v.to_string();
                } else if let Some(v) = line.strip_prefix("Icon=") {
                    icon = v.to_string();
                }
            }
        }
        return (name, icon);
    }
    (String::new(), String::new())
}

/// What requestView says, completed from the application's desktop entry
async fn request_from(desktop_entry: String, capabilities: i32, hints: &HashMap<String, OwnedValue>) -> JobRequest {
    let get = |key: &str| hints.get(key).map(|v| &**v);
    let mut app_name = get("application-display-name").and_then(str_of).unwrap_or_default();
    let mut app_icon = get("application-icon-name").and_then(str_of).unwrap_or_default();
    let desktop_entry = desktop_entry.trim_end_matches(".desktop").to_string();
    if (app_name.is_empty() || app_icon.is_empty()) && !desktop_entry.is_empty() {
        let entry = desktop_entry.clone();
        let (name, icon) = tokio::task::spawn_blocking(move || desktop_entry_info(&entry)).await.unwrap_or_default();
        if app_name.is_empty() {
            app_name = name;
        }
        if app_icon.is_empty() {
            app_icon = icon;
        }
    }
    JobRequest {
        app_name,
        desktop_entry,
        app_icon,
        capabilities,
        immediate: get("immediate").and_then(bool_of).unwrap_or(false),
        transient: get("transient").and_then(bool_of).unwrap_or(false),
        initial: update_from(hints),
    }
}

// --- The server ---

pub struct JobViewServerV2 {
    pub(crate) calls: mpsc::UnboundedSender<DbusCall>,
}

pub struct JobViewServerV1 {
    pub(crate) calls: mpsc::UnboundedSender<DbusCall>,
}

pub struct Kuiserver {
    pub(crate) calls: mpsc::UnboundedSender<DbusCall>,
}

/// Makes the job, puts its objects on the bus, answers with their path
async fn create(
    calls: &mpsc::UnboundedSender<DbusCall>,
    connection: &zbus::Connection,
    owner: String,
    request: JobRequest,
) -> zbus::fdo::Result<OwnedObjectPath> {
    let (reply, answer) = oneshot::channel();
    calls.send(DbusCall::JobCreate { owner, request, reply }).map_err(|_| gone())?;
    let id = answer.await.map_err(|_| gone())?;
    let path = job_path(id);
    let server = connection.object_server();
    server.at(path.as_str(), JobViewV3 { id, calls: calls.clone() }).await?;
    server.at(path.as_str(), JobViewV2 { id, calls: calls.clone() }).await?;
    OwnedObjectPath::try_from(path).map_err(|e| zbus::fdo::Error::Failed(e.to_string()))
}

#[zbus::interface(name = "org.kde.JobViewServerV2")]
impl JobViewServerV2 {
    #[zbus(name = "requestView")]
    async fn request_view(
        &self,
        #[zbus(header)] header: Header<'_>,
        #[zbus(connection)] connection: &zbus::Connection,
        desktop_entry: String,
        capabilities: i32,
        hints: HashMap<String, OwnedValue>,
    ) -> zbus::fdo::Result<OwnedObjectPath> {
        let request = request_from(desktop_entry, capabilities, &hints).await;
        create(&self.calls, connection, sender_of(&header), request).await
    }
}

#[zbus::interface(name = "org.kde.JobViewServer")]
impl JobViewServerV1 {
    #[zbus(name = "requestView")]
    async fn request_view(
        &self,
        #[zbus(header)] header: Header<'_>,
        #[zbus(connection)] connection: &zbus::Connection,
        app_name: String,
        app_icon_name: String,
        capabilities: i32,
    ) -> zbus::fdo::Result<OwnedObjectPath> {
        // The old API names only the program: its desktop entry is guessed as Plasma does
        let candidate = if app_name.contains('.') { app_name.clone() } else { format!("org.kde.{app_name}") };
        let entry = candidate.clone();
        let known = tokio::task::spawn_blocking(move || !desktop_entry_info(&entry).0.is_empty()).await.unwrap_or(false);
        let mut hints: HashMap<String, OwnedValue> = HashMap::new();
        if !app_name.is_empty() {
            hints.insert("application-display-name".into(), OwnedValue::from(zbus::zvariant::Str::from(app_name.clone())));
        }
        if !app_icon_name.is_empty() {
            hints.insert("application-icon-name".into(), OwnedValue::from(zbus::zvariant::Str::from(app_icon_name)));
        }
        let mut request = request_from(if known { candidate } else { String::new() }, capabilities, &hints).await;
        if known && !app_name.is_empty() {
            // The program's own name is better than nothing, the entry's Name= better still
            if request.app_name.is_empty() {
                request.app_name = app_name;
            }
        }
        create(&self.calls, connection, sender_of(&header), request).await
    }
}

#[zbus::interface(name = "org.kde.kuiserver")]
impl Kuiserver {
    /// kuiserver's proxying of other job servers; gone in Plasma too
    #[zbus(name = "registerService")]
    fn register_service(&self, _service: String, _object_path: String) -> zbus::fdo::Result<()> {
        Err(zbus::fdo::Error::NotSupported("kuiserver proxying capabilities are deprecated and defunct.".into()))
    }

    #[zbus(name = "emitJobUrlsChanged")]
    fn emit_job_urls_changed(&self) {
        let _ = self.calls.send(DbusCall::JobUrls);
    }

    /// False: the jobs are shown here, the application needs no window of its own for them
    #[zbus(name = "requiresJobTracker")]
    fn requires_job_tracker(&self) -> bool {
        false
    }

    #[zbus(name = "registeredJobContacts")]
    fn registered_job_contacts(&self) -> Vec<String> {
        Vec::new()
    }

    #[zbus(signal, name = "jobUrlsChanged")]
    async fn job_urls_changed(emitter: &SignalEmitter<'_>, urls: Vec<String>) -> zbus::Result<()>;

    #[zbus(signal, name = "requiresJobTrackerChanged")]
    async fn requires_job_tracker_changed(emitter: &SignalEmitter<'_>, required: bool) -> zbus::Result<()>;
}

/// Where the running jobs write to, to everyone listening
pub async fn emit_urls(connection: &zbus::Connection, urls: Vec<String>) -> zbus::Result<()> {
    let emitter = SignalEmitter::new(connection, SERVER_PATH)?;
    Kuiserver::job_urls_changed(&emitter, urls).await
}

// --- One job ---

pub struct JobViewV3 {
    id: u32,
    calls: mpsc::UnboundedSender<DbusCall>,
}

pub struct JobViewV2 {
    id: u32,
    calls: mpsc::UnboundedSender<DbusCall>,
}

#[zbus::interface(name = "org.kde.JobViewV3")]
impl JobViewV3 {
    #[zbus(name = "terminate")]
    fn terminate(&self, error_code: u32, error_message: String, _hints: HashMap<String, OwnedValue>) -> zbus::fdo::Result<()> {
        self.calls.send(DbusCall::JobTerminate { id: self.id, code: error_code, text: error_message }).map_err(|_| gone())
    }

    #[zbus(name = "update")]
    fn update(&self, properties: HashMap<String, OwnedValue>) -> zbus::fdo::Result<()> {
        self.calls.send(DbusCall::JobUpdate { id: self.id, update: update_from(&properties) }).map_err(|_| gone())
    }

    #[zbus(signal, name = "updateRequested")]
    async fn update_requested(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
    #[zbus(signal, name = "suspendRequested")]
    async fn suspend_requested(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
    #[zbus(signal, name = "resumeRequested")]
    async fn resume_requested(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
    #[zbus(signal, name = "cancelRequested")]
    async fn cancel_requested(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
}

impl JobViewV2 {
    fn send(&self, update: JobUpdate) -> zbus::fdo::Result<()> {
        self.calls.send(DbusCall::JobUpdate { id: self.id, update }).map_err(|_| gone())
    }
}

#[zbus::interface(name = "org.kde.JobViewV2")]
impl JobViewV2 {
    #[zbus(name = "terminate")]
    fn terminate(&self, error_message: String) -> zbus::fdo::Result<()> {
        // The code came before with setError
        self.calls.send(DbusCall::JobTerminate { id: self.id, code: 0, text: error_message }).map_err(|_| gone())
    }

    #[zbus(name = "setSuspended")]
    fn set_suspended(&self, suspended: bool) -> zbus::fdo::Result<()> {
        self.send(JobUpdate { suspended: Some(suspended), ..Default::default() })
    }

    #[zbus(name = "setTotalAmount")]
    fn set_total_amount(&self, amount: u64, unit: String) -> zbus::fdo::Result<()> {
        match Unit::parse(&unit) {
            Some(unit) => self.send(JobUpdate { total: vec![(unit, amount)], ..Default::default() }),
            None => Ok(()),
        }
    }

    #[zbus(name = "setProcessedAmount")]
    fn set_processed_amount(&self, amount: u64, unit: String) -> zbus::fdo::Result<()> {
        match Unit::parse(&unit) {
            Some(unit) => self.send(JobUpdate { processed: vec![(unit, amount)], ..Default::default() }),
            None => Ok(()),
        }
    }

    #[zbus(name = "setPercent")]
    fn set_percent(&self, percent: u32) -> zbus::fdo::Result<()> {
        self.send(JobUpdate { percent: Some(percent), ..Default::default() })
    }

    #[zbus(name = "setSpeed")]
    fn set_speed(&self, bytes_per_second: u64) -> zbus::fdo::Result<()> {
        self.send(JobUpdate { speed: Some(bytes_per_second), ..Default::default() })
    }

    #[zbus(name = "setInfoMessage")]
    fn set_info_message(&self, message: String) -> zbus::fdo::Result<()> {
        // The old API has no title: its info message is what the job does
        self.send(JobUpdate { title: Some(message), ..Default::default() })
    }

    #[zbus(name = "setDescriptionField")]
    fn set_description_field(&self, number: u32, name: String, value: String) -> zbus::fdo::Result<bool> {
        self.send(JobUpdate { fields: vec![(number, name, value)], ..Default::default() })?;
        Ok(true)
    }

    #[zbus(name = "clearDescriptionField")]
    fn clear_description_field(&self, number: u32) -> zbus::fdo::Result<()> {
        self.send(JobUpdate { fields: vec![(number, String::new(), String::new())], ..Default::default() })
    }

    #[zbus(name = "setDestUrl")]
    fn set_dest_url(&self, dest_url: OwnedValue) -> zbus::fdo::Result<()> {
        match str_of(&dest_url) {
            Some(url) => self.send(JobUpdate { destination: Some(url), ..Default::default() }),
            None => Ok(()),
        }
    }

    #[zbus(name = "setError")]
    fn set_error(&self, error_code: u32) -> zbus::fdo::Result<()> {
        self.calls.send(DbusCall::JobSetError { id: self.id, code: error_code }).map_err(|_| gone())
    }

    #[zbus(signal, name = "suspendRequested")]
    async fn suspend_requested(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
    #[zbus(signal, name = "resumeRequested")]
    async fn resume_requested(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
    #[zbus(signal, name = "cancelRequested")]
    async fn cancel_requested(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
}

/// What the shell asks of a job's application
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum JobRequestKind {
    Cancel,
    Suspend,
    Resume,
}

/// Tells the application (on both interfaces: an old client listens on V2, a new one on V3)
pub async fn emit(connection: &zbus::Connection, id: u32, kind: JobRequestKind) -> zbus::Result<()> {
    let path = job_path(id);
    let emitter = SignalEmitter::new(connection, path.as_str())?;
    match kind {
        JobRequestKind::Cancel => {
            JobViewV3::cancel_requested(&emitter).await?;
            JobViewV2::cancel_requested(&emitter).await
        }
        JobRequestKind::Suspend => {
            JobViewV3::suspend_requested(&emitter).await?;
            JobViewV2::suspend_requested(&emitter).await
        }
        JobRequestKind::Resume => {
            JobViewV3::resume_requested(&emitter).await?;
            JobViewV2::resume_requested(&emitter).await
        }
    }
}

/// The job is over for its application: its objects leave the bus
pub async fn remove(connection: &zbus::Connection, id: u32) {
    let path = job_path(id);
    let server = connection.object_server();
    let _ = server.remove::<JobViewV3, _>(path.as_str()).await;
    let _ = server.remove::<JobViewV2, _>(path.as_str()).await;
}

/// Serves /JobViewServer (the bus names are taken with `crate::dbus::take_name`)
pub async fn serve(connection: &zbus::Connection, calls: mpsc::UnboundedSender<DbusCall>) -> zbus::Result<()> {
    let server = connection.object_server();
    server.at(SERVER_PATH, JobViewServerV2 { calls: calls.clone() }).await?;
    server.at(SERVER_PATH, JobViewServerV1 { calls: calls.clone() }).await?;
    server.at(SERVER_PATH, Kuiserver { calls }).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn props(pairs: &[(&str, Value<'static>)]) -> HashMap<String, OwnedValue> {
        pairs.iter().map(|(k, v)| (k.to_string(), OwnedValue::try_from(v.clone()).unwrap())).collect()
    }

    #[test]
    fn the_properties_of_kjobwidgets() {
        let p = props(&[
            ("title", Value::from("Copying")),
            ("infoMessage", Value::from("Copying photo.jpg")),
            ("percent", Value::U32(42)),
            ("processedBytes", Value::U64(420)),
            ("totalBytes", Value::U64(1000)),
            ("totalFiles", Value::U64(3)),
            ("speed", Value::U64(100)),
            ("elapsedTime", Value::I64(1500)),
            ("descriptionLabel1", Value::from("Source")),
            ("descriptionValue1", Value::from("/home/a/x")),
            ("destUrl", Value::from("file:///home/a/Pictures")),
            ("suspended", Value::Bool(false)),
        ]);
        let u = update_from(&p);
        assert_eq!(u.title.as_deref(), Some("Copying"));
        assert_eq!(u.info_message.as_deref(), Some("Copying photo.jpg"));
        assert_eq!(u.percent, Some(42));
        assert!(u.processed.contains(&(Unit::Bytes, 420)));
        assert!(u.total.contains(&(Unit::Bytes, 1000)) && u.total.contains(&(Unit::Files, 3)));
        assert_eq!((u.speed, u.elapsed), (Some(100), Some(1500)));
        assert_eq!(u.fields, [(0, "Source".to_string(), "/home/a/x".to_string())]);
        assert_eq!(u.destination.as_deref(), Some("file:///home/a/Pictures"));
        assert_eq!(u.suspended, Some(false));
    }

    #[test]
    fn nothing_given_changes_nothing() {
        assert_eq!(update_from(&HashMap::new()), JobUpdate::default());
    }
}

//! Jobs over D-Bus against a private dbus-daemon: a client does what KJobWidgets does for KIO in
//! Dolphin (org.kde.JobViewServerV2.requestView, then JobViewV3.update and terminate), or what an
//! old application does (JobViewServer V1, JobViewV2 setters); a shell watches the jobs and asks
//! for cancel and pause.

mod common;

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::time::{Duration, Instant};

use common::{Bus, Shell, TempDir, local};
use futures::StreamExt;
use maia_notifications::dbus;
use maia_notifications::hub::HubRef;
use maia_notifications::notifications_capnp as n;
use zbus::zvariant::{OwnedObjectPath, Value};

#[zbus::proxy(interface = "org.kde.JobViewServerV2", default_service = "org.kde.JobViewServer", default_path = "/JobViewServer")]
trait JobViewServerV2 {
    #[zbus(name = "requestView")]
    fn request_view(&self, desktop_entry: &str, capabilities: i32, hints: HashMap<&str, Value<'_>>) -> zbus::Result<OwnedObjectPath>;
}

#[zbus::proxy(interface = "org.kde.JobViewServer", default_service = "org.kde.kuiserver", default_path = "/JobViewServer")]
trait JobViewServerV1 {
    #[zbus(name = "requestView")]
    fn request_view(&self, app_name: &str, app_icon_name: &str, capabilities: i32) -> zbus::Result<OwnedObjectPath>;
}

#[zbus::proxy(interface = "org.kde.JobViewV3", default_service = "org.kde.JobViewServer")]
trait JobViewV3 {
    #[zbus(name = "update")]
    fn update(&self, properties: HashMap<&str, Value<'_>>) -> zbus::Result<()>;
    #[zbus(name = "terminate")]
    fn terminate(&self, error_code: u32, error_message: &str, hints: HashMap<&str, Value<'_>>) -> zbus::Result<()>;
}

#[zbus::proxy(interface = "org.kde.JobViewV2", default_service = "org.kde.kuiserver")]
trait JobViewV2 {
    #[zbus(name = "setInfoMessage")]
    fn set_info_message(&self, message: &str) -> zbus::Result<()>;
    #[zbus(name = "setPercent")]
    fn set_percent(&self, percent: u32) -> zbus::Result<()>;
    #[zbus(name = "setTotalAmount")]
    fn set_total_amount(&self, amount: u64, unit: &str) -> zbus::Result<()>;
    #[zbus(name = "setProcessedAmount")]
    fn set_processed_amount(&self, amount: u64, unit: &str) -> zbus::Result<()>;
    #[zbus(name = "setDescriptionField")]
    fn set_description_field(&self, number: u32, name: &str, value: &str) -> zbus::Result<bool>;
    #[zbus(name = "setError")]
    fn set_error(&self, error_code: u32) -> zbus::Result<()>;
    #[zbus(name = "terminate")]
    fn terminate(&self, error_message: &str) -> zbus::Result<()>;
}

#[zbus::proxy(interface = "org.kde.kuiserver", default_service = "org.kde.kuiserver", default_path = "/JobViewServer")]
trait Kuiserver {
    #[zbus(name = "requiresJobTracker")]
    fn requires_job_tracker(&self) -> zbus::Result<bool>;
    #[zbus(name = "emitJobUrlsChanged")]
    fn emit_job_urls_changed(&self) -> zbus::Result<()>;
    #[zbus(signal, name = "jobUrlsChanged")]
    fn job_urls_changed(&self, urls: Vec<String>) -> zbus::Result<()>;
}

const KILLABLE_SUSPENDABLE: i32 = 0x3;

struct Service {
    hub: HubRef,
    _connection: zbus::Connection,
}

async fn service(bus: &Bus, dir: &TempDir) -> Service {
    let connection = bus.connect().await;
    let hub = common::hub(dir);
    dbus::serve(&connection, &hub).await.unwrap();
    assert!(dbus::take_job_names(&connection).await.unwrap());
    Service { hub, _connection: connection }
}

/// An application with a job: its connection, its job's object, the signals the job got
struct App {
    connection: zbus::Connection,
    path: OwnedObjectPath,
    requests: Rc<RefCell<Vec<String>>>,
}

impl App {
    /// Starts a job the way KJobWidgets does for a copy in Dolphin
    async fn copy(bus: &Bus, hints: HashMap<&str, Value<'_>>) -> App {
        let connection = bus.connect().await;
        let server = JobViewServerV2Proxy::new(&connection).await.unwrap();
        let path = server.request_view("org.kde.dolphin", KILLABLE_SUSPENDABLE, hints).await.unwrap();
        App::listening(connection, path).await
    }

    async fn listening(connection: zbus::Connection, path: OwnedObjectPath) -> App {
        let requests = Rc::new(RefCell::new(Vec::new()));
        let rule = zbus::MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .path(path.clone())
            .unwrap()
            .interface("org.kde.JobViewV3")
            .unwrap()
            .build();
        let mut stream = zbus::MessageStream::for_match_rule(rule, &connection, None).await.unwrap();
        let recorded = requests.clone();
        tokio::task::spawn_local(async move {
            while let Some(Ok(message)) = stream.next().await {
                if let Some(member) = message.header().member() {
                    recorded.borrow_mut().push(member.to_string());
                }
            }
        });
        App { connection, path, requests }
    }

    async fn v3(&self) -> JobViewV3Proxy<'static> {
        JobViewV3Proxy::builder(&self.connection).path(self.path.clone()).unwrap().build().await.unwrap()
    }

    async fn update(&self, properties: HashMap<&str, Value<'_>>) {
        self.v3().await.update(properties).await.unwrap();
    }

    async fn terminate(&self, code: u32, message: &str) {
        self.v3().await.terminate(code, message, HashMap::new()).await.unwrap();
    }

    async fn heard(&self, what: &str) {
        common::eventually(what, || self.requests.borrow().iter().any(|r| r == what)).await;
    }
}

fn title(text: &str) -> HashMap<&'static str, Value<'static>> {
    HashMap::from([("title", Value::from(text.to_string()))])
}

async fn only_job(shell: &Shell) -> (u32, common::ShownJob) {
    shell.wait("a job", |s| s.jobs.len() == 1).await;
    let seen = shell.seen.borrow();
    let (id, job) = seen.jobs.iter().next().unwrap();
    (*id, job.clone())
}

/// What KIO asks before it reports a job (KDynamicJobTracker): without the V2 interface in the
/// introspection or with requiresJobTracker() true it keeps its own progress dialog
#[test]
fn kio_finds_a_server_that_shows_its_jobs() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("jobs-kio-probe");
        let _service = service(&bus, &dir).await;
        let connection = bus.connect().await;
        let introspectable = zbus::fdo::IntrospectableProxy::builder(&connection)
            .destination("org.kde.kuiserver")
            .unwrap()
            .path("/JobViewServer")
            .unwrap()
            .build()
            .await
            .unwrap();
        let xml = introspectable.introspect().await.unwrap();
        assert!(xml.contains("org.kde.JobViewServerV2"));
        assert!(!KuiserverProxy::new(&connection).await.unwrap().requires_job_tracker().await.unwrap());
    });
}

/// File managers mark the folders jobs write to: jobUrlsChanged while a job runs, again when it ends
#[test]
fn the_folders_jobs_write_to_go_to_file_managers() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("jobs-urls");
        let _service = service(&bus, &dir).await;
        let connection = bus.connect().await;
        let kuiserver = KuiserverProxy::new(&connection).await.unwrap();
        let mut changes = kuiserver.receive_job_urls_changed().await.unwrap();
        let mut next = async || changes.next().await.unwrap().args().unwrap().urls;

        kuiserver.emit_job_urls_changed().await.unwrap();
        assert!(next().await.is_empty());
        let app = App::copy(&bus, HashMap::from([("title", Value::from("Copying")), ("destUrl", Value::from("file:///media/usb/"))])).await;
        assert_eq!(next().await, ["file:///media/usb"]);
        kuiserver.emit_job_urls_changed().await.unwrap();
        assert_eq!(next().await, ["file:///media/usb"]);
        app.terminate(0, "").await;
        assert!(next().await.is_empty());
    });
}

#[test]
fn a_copy_appears_after_its_delay_and_its_progress_reaches_the_shell() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("jobs-copy");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let start = Instant::now();
        let app = App::copy(&bus, title("Copying")).await;
        assert!(app.path.as_str().starts_with("/org/kde/notificationmanager/jobs/JobView_"));
        // Not before half a second: a short job never flickers
        tokio::time::sleep(Duration::from_millis(300)).await;
        assert!(shell.seen.borrow().jobs.is_empty());
        let (_, job) = only_job(&shell).await;
        assert!(start.elapsed() >= Duration::from_millis(450));
        assert_eq!((job.title.as_str(), job.desktop_entry.as_str(), job.state), ("Copying", "org.kde.dolphin", n::JobState::Running));
        assert!(job.killable && job.suspendable);

        app.update(HashMap::from([
            ("infoMessage", Value::from("Copying film.mkv")),
            ("percent", Value::U32(40)),
            ("processedBytes", Value::U64(400)),
            ("totalBytes", Value::U64(1000)),
            ("totalFiles", Value::U64(1)),
            ("speed", Value::U64(25_000_000)),
            ("descriptionLabel1", Value::from("Source")),
            ("descriptionValue1", Value::from("/home/a/film.mkv")),
            ("descriptionLabel2", Value::from("Destination")),
            ("descriptionValue2", Value::from("/media/usb/film.mkv")),
            ("destUrl", Value::from("file:///media/usb")),
        ]))
        .await;
        shell.wait("the progress", |s| s.jobs.values().any(|j| j.percent == 40)).await;
        let (_, job) = only_job(&shell).await;
        assert_eq!((job.processed_bytes, job.total_bytes, job.total_files, job.speed), (400, 1000, 1, 25_000_000));
        assert_eq!(job.fields.len(), 2);
        assert_eq!(job.destination, "file:///media/usb");
        assert_eq!(job.info_message, "Copying film.mkv");

        app.terminate(0, "").await;
        shell.wait("finished", |s| s.jobs.values().any(|j| j.state == n::JobState::Finished && j.percent == 100)).await;
        // The finished job stays until dismissed
        let (id, _) = only_job(&shell).await;
        assert_eq!(shell.dismiss_job(id).await, n::ErrorCode::None);
        shell.wait("dismissed", |s| s.jobs.is_empty()).await;
    });
}

#[test]
fn many_updates_reach_the_shell_a_few_times_a_second() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("jobs-throttle");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::copy(&bus, HashMap::from([("title", Value::from("Copying")), ("immediate", Value::Bool(true))])).await;
        only_job(&shell).await;
        let before = shell.seen.borrow().job_batches;
        let v3 = app.v3().await;
        let start = Instant::now();
        // An update every 5 ms for a second, as a fast copy does
        for percent in 0..=100u32 {
            v3.update(HashMap::from([("percent", Value::U32(percent))])).await.unwrap();
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
        let elapsed = start.elapsed();
        shell.wait("the last value", |s| s.jobs.values().any(|j| j.percent == 100)).await;
        let batches = shell.seen.borrow().job_batches - before;
        let most = (elapsed.as_millis() / 250) as u32 + 3;
        assert!(batches <= most, "{batches} batches in {elapsed:?}");
    });
}

#[test]
fn a_short_job_never_shows_and_a_canceled_one_goes() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("jobs-short");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let transient = App::copy(&bus, HashMap::from([("title", Value::from("Reading")), ("transient", Value::Bool(true))])).await;
        transient.terminate(0, "").await;
        let canceled = App::copy(&bus, title("Copying")).await;
        only_job(&shell).await;
        canceled.terminate(1, "Canceled").await; // KIO's ERR_USER_CANCELED
        shell.wait("nothing left", |s| s.jobs.is_empty()).await;
        tokio::time::sleep(Duration::from_millis(700)).await;
        assert!(shell.seen.borrow().jobs.is_empty());
    });
}

#[test]
fn cancel_and_pause_are_asked_of_the_application() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("jobs-cancel");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::copy(&bus, title("Copying")).await;
        let (id, _) = only_job(&shell).await;

        assert_eq!(shell.suspend_job(id, true).await, n::ErrorCode::None);
        app.heard("suspendRequested").await;
        app.update(HashMap::from([("suspended", Value::Bool(true))])).await;
        shell.wait("paused", |s| s.jobs.values().any(|j| j.state == n::JobState::Suspended)).await;
        assert_eq!(shell.suspend_job(id, false).await, n::ErrorCode::None);
        app.heard("resumeRequested").await;

        assert_eq!(shell.cancel_job(id).await, n::ErrorCode::None);
        app.heard("cancelRequested").await;
        app.terminate(1, "").await;
        shell.wait("gone", |s| s.jobs.is_empty()).await;
        assert_eq!(shell.cancel_job(id).await, n::ErrorCode::NotFound);
    });
}

#[test]
fn a_cancel_without_an_answer_ends_the_job_after_two_seconds() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("jobs-stuck");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let _app = App::copy(&bus, title("Copying")).await;
        let (id, _) = only_job(&shell).await;
        let start = Instant::now();
        shell.cancel_job(id).await;
        shell.wait("gone after the grace", |s| s.jobs.is_empty()).await;
        assert!(start.elapsed() >= Duration::from_millis(1900), "{:?}", start.elapsed());
    });
}

#[test]
fn a_job_whose_application_quits_has_failed() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("jobs-quit");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::copy(&bus, title("Copying")).await;
        only_job(&shell).await;
        app.connection.close().await.unwrap();
        shell.wait("failed", |s| s.jobs.values().any(|j| j.state == n::JobState::Failed && j.owner_gone)).await;
    });
}

#[test]
fn an_error_stays_with_its_text() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("jobs-error");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::copy(&bus, title("Copying")).await;
        only_job(&shell).await;
        app.terminate(28, "There is not enough space on the disk").await;
        shell.wait("failed", |s| s.jobs.values().any(|j| j.state == n::JobState::Failed)).await;
        let (id, job) = only_job(&shell).await;
        assert_eq!((job.error_code, job.error_text.as_str(), job.owner_gone), (28, "There is not enough space on the disk", false));
        // Running jobs cannot be dismissed, ended ones can
        assert_eq!(shell.dismiss_job(id).await, n::ErrorCode::None);
    });
}

#[test]
fn the_old_api_works_too() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("jobs-v1");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let connection = bus.connect().await;
        let server = JobViewServerV1Proxy::new(&connection).await.unwrap();
        let path = server.request_view("ark", "ark", 1).await.unwrap();
        let v2 = JobViewV2Proxy::builder(&connection).path(path.clone()).unwrap().build().await.unwrap();
        v2.set_info_message("Extracting").await.unwrap();
        v2.set_total_amount(2000, "bytes").await.unwrap();
        v2.set_processed_amount(500, "bytes").await.unwrap();
        v2.set_percent(25).await.unwrap();
        assert!(v2.set_description_field(0, "Archive", "backup.zip").await.unwrap());
        shell.wait("the job", |s| s.jobs.values().any(|j| j.percent == 25)).await;
        let (_, job) = only_job(&shell).await;
        assert_eq!((job.title.as_str(), job.app_name.as_str(), job.processed_bytes, job.total_bytes), ("Extracting", "ark", 500, 2000));
        assert!(job.killable && !job.suspendable);
        v2.set_error(13).await.unwrap();
        v2.terminate("Could not write").await.unwrap();
        shell.wait("failed", |s| s.jobs.values().any(|j| j.state == n::JobState::Failed && j.error_code == 13)).await;
    });
}

#[test]
fn a_reconnecting_shell_gets_the_jobs() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("jobs-snapshot");
        let service = service(&bus, &dir).await;
        let first = Shell::connect(&service.hub).await;
        let _app = App::copy(&bus, title("Copying")).await;
        only_job(&first).await;
        let later = Shell::connect(&service.hub).await;
        assert_eq!(later.seen.borrow().jobs.len(), 1);
    });
}

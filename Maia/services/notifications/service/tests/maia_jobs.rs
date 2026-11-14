//! Jobs of Maia's programs (Notifier.startJob) over real Cap'n Proto connections, without D-Bus: a
//! program reports its progress through its JobHandle, a shell sees the job next to those of KDE
//! applications and asks for pause and cancel, which only the program hears (its JobListener).

mod common;

use std::cell::RefCell;
use std::rc::Rc;
use std::time::{Duration, Instant};

use common::{Sender, Shell, TempDir, local};
use maia_notifications::notifications_capnp::{self as n, job_listener};

/// What a program has heard about its job
struct Recorder(Rc<RefCell<Vec<&'static str>>>);

impl job_listener::Server for Recorder {
    async fn cancel_requested(
        self: Rc<Self>,
        _: job_listener::CancelRequestedParams,
        _: job_listener::CancelRequestedResults,
    ) -> Result<(), capnp::Error> {
        self.0.borrow_mut().push("cancel");
        Ok(())
    }

    async fn suspend_requested(
        self: Rc<Self>,
        _: job_listener::SuspendRequestedParams,
        _: job_listener::SuspendRequestedResults,
    ) -> Result<(), capnp::Error> {
        self.0.borrow_mut().push("suspend");
        Ok(())
    }

    async fn resume_requested(
        self: Rc<Self>,
        _: job_listener::ResumeRequestedParams,
        _: job_listener::ResumeRequestedResults,
    ) -> Result<(), capnp::Error> {
        self.0.borrow_mut().push("resume");
        Ok(())
    }
}

#[derive(Clone, Default)]
struct Progress {
    title: &'static str,
    percent: i32,
    processed: u64,
    total: u64,
    suspended: bool,
}

fn write_progress(mut b: n::job_progress::Builder, p: &Progress) {
    b.set_title(p.title);
    b.set_info_message("Exporting holiday.mkv");
    b.set_percent(p.percent);
    b.set_processed_bytes(p.processed);
    b.set_total_bytes(p.total);
    b.set_total_files(1);
    b.set_speed(1_000_000);
    b.set_destination("file:///home/a/Videos/");
    b.set_suspended(p.suspended);
    let mut fields = b.init_fields(1);
    fields.reborrow().get(0).set_label("Format");
    fields.reborrow().get(0).set_value("AV1");
}

struct MaiaJob {
    id: u32,
    handle: n::job_handle::Client,
    heard: Rc<RefCell<Vec<&'static str>>>,
}

impl MaiaJob {
    async fn start(sender: &Sender, immediate: bool, transient: bool, progress: Progress) -> MaiaJob {
        let heard = Rc::new(RefCell::new(Vec::new()));
        let mut request = sender.notifier.start_job_request();
        {
            let mut job = request.get().init_job();
            job.set_app_name("Video Editor");
            job.set_app_icon("video-x-generic");
            job.set_desktop_entry("org.maia.videoeditor.desktop");
            job.set_killable(true);
            job.set_suspendable(true);
            job.set_immediate(immediate);
            job.set_transient(transient);
            write_progress(job.init_progress(), &progress);
        }
        request.get().set_listener(capnp_rpc::new_client(Recorder(heard.clone())));
        let reply = request.send().promise.await.unwrap();
        let reply = reply.get().unwrap();
        MaiaJob { id: reply.get_id(), handle: reply.get_handle().unwrap(), heard }
    }

    async fn update(&self, progress: &Progress) -> n::ErrorCode {
        let mut request = self.handle.update_request();
        write_progress(request.get().init_progress(), progress);
        let reply = request.send().promise.await.unwrap();
        reply.get().unwrap().get_result().unwrap().get_error().unwrap()
    }

    async fn finish(&self, error: &str) {
        let mut request = self.handle.finish_request();
        request.get().set_error_text(error);
        request.send().promise.await.unwrap();
    }

    async fn heard(&self, what: &str) {
        common::eventually(what, || self.heard.borrow().iter().any(|h| *h == what)).await;
    }
}

fn exporting(percent: i32) -> Progress {
    Progress { title: "Exporting", percent, processed: percent as u64 * 10, total: 1000, suspended: false }
}

#[test]
fn a_maia_job_reaches_the_shell_after_its_delay() {
    local(async {
        let dir = TempDir::new("maia-job");
        let hub = common::hub(&dir);
        let shell = Shell::connect(&hub).await;
        let sender = Sender::connect(&hub).await;
        let start = Instant::now();
        let job = MaiaJob::start(&sender, false, false, exporting(0)).await;
        tokio::time::sleep(Duration::from_millis(300)).await;
        assert!(shell.seen.borrow().jobs.is_empty(), "not before half a second");
        shell.wait("the job", |s| s.jobs.contains_key(&job.id)).await;
        assert!(start.elapsed() >= Duration::from_millis(450));

        assert_eq!(job.update(&exporting(40)).await, n::ErrorCode::None);
        shell.wait("its progress", |s| s.jobs[&job.id].percent == 40).await;
        let shown = shell.seen.borrow().jobs[&job.id].clone();
        assert_eq!((shown.app_name.as_str(), shown.desktop_entry.as_str(), shown.app_icon.as_str()), ("Video Editor", "org.maia.videoeditor", "video-x-generic"));
        assert_eq!((shown.title.as_str(), shown.info_message.as_str()), ("Exporting", "Exporting holiday.mkv"));
        assert_eq!((shown.processed_bytes, shown.total_bytes, shown.total_files, shown.speed), (400, 1000, 1, 1_000_000));
        assert_eq!(shown.fields, [("Format".to_string(), "AV1".to_string())]);
        assert_eq!(shown.destination, "file:///home/a/Videos");
        assert!(shown.killable && shown.suspendable && shown.state == n::JobState::Running);

        job.finish("").await;
        shell.wait("finished", |s| s.jobs[&job.id].state == n::JobState::Finished).await;
        assert_eq!(shell.seen.borrow().jobs[&job.id].percent, 100);
        // Over: a late update is refused, the job stays as it ended
        assert_eq!(job.update(&exporting(50)).await, n::ErrorCode::NotFound);
        assert_eq!(shell.dismiss_job(job.id).await, n::ErrorCode::None);
        shell.wait("dismissed", |s| s.jobs.is_empty()).await;
    });
}

#[test]
fn pause_and_cancel_go_to_the_program_alone() {
    local(async {
        let dir = TempDir::new("maia-job-ask");
        let hub = common::hub(&dir);
        let shell = Shell::connect(&hub).await;
        let sender = Sender::connect(&hub).await;
        let job = MaiaJob::start(&sender, true, false, exporting(10)).await;
        let other = MaiaJob::start(&sender, true, false, exporting(10)).await;
        shell.wait("both", |s| s.jobs.len() == 2).await;

        assert_eq!(shell.suspend_job(job.id, true).await, n::ErrorCode::None);
        job.heard("suspend").await;
        // Paused when the program says so
        assert_eq!(shell.seen.borrow().jobs[&job.id].state, n::JobState::Running);
        job.update(&Progress { suspended: true, ..exporting(10) }).await;
        shell.wait("paused", |s| s.jobs[&job.id].state == n::JobState::Suspended).await;
        assert_eq!(shell.suspend_job(job.id, false).await, n::ErrorCode::None);
        job.heard("resume").await;

        assert_eq!(shell.cancel_job(job.id).await, n::ErrorCode::None);
        job.heard("cancel").await;
        let request = job.handle.canceled_request();
        request.send().promise.await.unwrap();
        shell.wait("gone without a trace", |s| !s.jobs.contains_key(&job.id)).await;
        assert!(other.heard.borrow().is_empty(), "the other job heard {:?}", other.heard.borrow());
    });
}

#[test]
fn a_program_that_lets_go_of_its_job_has_failed() {
    local(async {
        let dir = TempDir::new("maia-job-gone");
        let hub = common::hub(&dir);
        let shell = Shell::connect(&hub).await;
        let sender = Sender::connect(&hub).await;
        let job = MaiaJob::start(&sender, true, false, exporting(30)).await;
        shell.wait("the job", |s| s.jobs.contains_key(&job.id)).await;
        let id = job.id;
        drop(job);
        shell.wait("failed", |s| s.jobs[&id].state == n::JobState::Failed).await;
        assert!(shell.seen.borrow().jobs[&id].owner_gone);

        // One that ended first stays as it ended
        let done = MaiaJob::start(&sender, true, false, exporting(30)).await;
        done.finish("The disk is full").await;
        shell.wait("failed with a text", |s| s.jobs.get(&done.id).is_some_and(|j| j.state == n::JobState::Failed)).await;
        let done_id = done.id;
        drop(done);
        tokio::time::sleep(Duration::from_millis(50)).await;
        let shown = shell.seen.borrow().jobs[&done_id].clone();
        assert_eq!((shown.error_text.as_str(), shown.owner_gone), ("The disk is full", false));
    });
}

#[test]
fn a_transient_job_goes_when_done_and_the_percent_may_be_unknown() {
    local(async {
        let dir = TempDir::new("maia-job-transient");
        let hub = common::hub(&dir);
        let shell = Shell::connect(&hub).await;
        let sender = Sender::connect(&hub).await;
        let job = MaiaJob::start(&sender, true, true, exporting(-1)).await;
        shell.wait("the job", |s| s.jobs.contains_key(&job.id)).await;
        assert_eq!(shell.seen.borrow().jobs[&job.id].percent, -1);
        job.finish("").await;
        shell.wait("gone", |s| s.jobs.is_empty()).await;
    });
}

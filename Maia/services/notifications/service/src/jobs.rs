//! Jobs: the progress of a long operation of an application (a copy in Dolphin, an archive, a
//! download), as KDE's applications report it through org.kde.JobViewServer (dbus_jobs.rs). Plain
//! values and the rules, without I/O; the hub (hub.rs) runs the timers and tells the shells.
//!
//! The rules are Plasma's (libnotificationmanager), so that applications behave as they do there:
//! - a job is shown only after SHOW_DELAY (a short job, e.g. reading a folder, never flickers),
//!   or at once with the hint "immediate" as soon as it has a title or ends;
//! - a job the user canceled (KIO's ERR_USER_CANCELED) and a "transient" one that finished well go
//!   without a trace; any other ended job stays (finished or failed) until dismissed;
//! - a job whose application leaves the bus while it runs has failed (ownerGone);
//! - a job that does not end within CANCEL_GRACE after a cancel request is ended as canceled.

use std::collections::BTreeMap;
use std::time::Duration;

use crate::model::now_ms;

pub const SHOW_DELAY: Duration = Duration::from_millis(500);
pub const SHOW_DELAY_IMMEDIATE: Duration = Duration::from_millis(50);
pub const CANCEL_GRACE: Duration = Duration::from_secs(2);
/// KIO's ERR_USER_CANCELED (KJob::KilledJobError)
pub const ERR_USER_CANCELED: u32 = 1;
/// At most this many ended jobs are kept; the oldest go first
pub const MAX_ENDED: usize = 50;
pub const MAX_TEXT_CHARS: usize = 1000;

/// KJob::Capability
pub const CAP_KILLABLE: i32 = 0x1;
pub const CAP_SUSPENDABLE: i32 = 0x2;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum JobState {
    #[default]
    Running,
    Suspended,
    Finished,
    Failed,
}

impl JobState {
    pub fn ended(self) -> bool {
        matches!(self, JobState::Finished | JobState::Failed)
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct JobField {
    pub label: String,
    pub value: String,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Job {
    pub id: u32,
    pub app_name: String,
    pub desktop_entry: String,
    pub app_icon: String,
    pub title: String,
    pub info_message: String,
    pub state: JobState,
    pub percent: i32,
    pub processed_bytes: u64,
    pub total_bytes: u64,
    pub processed_files: u64,
    pub total_files: u64,
    pub processed_directories: u64,
    pub total_directories: u64,
    pub processed_items: u64,
    pub total_items: u64,
    pub speed: u64,
    pub elapsed: i64,
    /// Description fields by their number (the API numbers them, 0 and 1 in practice)
    pub fields: BTreeMap<u32, JobField>,
    pub destination: String,
    pub error_code: u32,
    pub error_text: String,
    pub owner_gone: bool,
    pub killable: bool,
    pub suspendable: bool,
    pub started: i64,
    pub updated: i64,
}

/// Amounts of the old API (setTotalAmount / setProcessedAmount): their unit
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Unit {
    Bytes,
    Files,
    Directories,
    Items,
}

impl Unit {
    pub fn parse(unit: &str) -> Option<Unit> {
        match unit {
            "bytes" => Some(Unit::Bytes),
            "files" => Some(Unit::Files),
            "dirs" | "directories" => Some(Unit::Directories),
            "items" => Some(Unit::Items),
            _ => None,
        }
    }
}

/// A change an application sends (JobViewV3.update, or one setter of JobViewV2); None = unchanged
#[derive(Clone, Debug, Default, PartialEq)]
pub struct JobUpdate {
    pub title: Option<String>,
    pub info_message: Option<String>,
    pub percent: Option<u32>,
    pub processed: Vec<(Unit, u64)>,
    pub total: Vec<(Unit, u64)>,
    pub speed: Option<u64>,
    pub elapsed: Option<i64>,
    /// (number, label, value); an empty label and value clears the field
    pub fields: Vec<(u32, String, String)>,
    pub destination: Option<String>,
    pub suspended: Option<bool>,
}

/// What the application said about itself when it asked for a view
#[derive(Clone, Debug, Default, PartialEq)]
pub struct JobRequest {
    pub app_name: String,
    pub desktop_entry: String,
    pub app_icon: String,
    pub capabilities: i32,
    pub immediate: bool,
    pub transient: bool,
    pub initial: JobUpdate,
}

pub struct Entry {
    pub job: Job,
    /// The D-Bus name of its application
    pub owner: String,
    /// Shown to the shells (after SHOW_DELAY, see the module's documentation)
    pub visible: bool,
    pub immediate: bool,
    pub transient: bool,
    /// A cancel was asked for and has not been answered
    pub cancel_pending: bool,
    seq: u64,
}

/// What the end of a job did
#[derive(Debug, PartialEq, Eq)]
pub enum Ended {
    NotFound,
    /// Gone without a trace (canceled, transient); true when the shells had it
    Removed { was_visible: bool },
    /// Stays as finished or failed; true when it was not visible before (it is now)
    Kept { newly_visible: bool },
}

#[derive(Default)]
pub struct JobStore {
    entries: BTreeMap<u32, Entry>,
    next_id: u32,
    next_seq: u64,
}

impl JobStore {
    pub fn new() -> JobStore {
        JobStore { entries: BTreeMap::new(), next_id: 1, next_seq: 1 }
    }

    pub fn get(&self, id: u32) -> Option<&Entry> {
        self.entries.get(&id)
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// The jobs the shells see, the newest first
    pub fn visible(&self) -> Vec<&Job> {
        let mut list: Vec<&Entry> = self.entries.values().filter(|e| e.visible).collect();
        list.sort_by(|a, b| b.seq.cmp(&a.seq));
        list.into_iter().map(|e| &e.job).collect()
    }

    /// A new job of `owner`; it is not visible until `show` (the hub's timer) or a reason below
    pub fn create(&mut self, request: JobRequest, owner: &str) -> u32 {
        let id = self.next_id;
        self.next_id = self.next_id.wrapping_add(1).max(1);
        let seq = self.next_seq;
        self.next_seq += 1;
        let now = now_ms();
        let job = Job {
            id,
            app_name: request.app_name,
            desktop_entry: request.desktop_entry.trim_end_matches(".desktop").to_string(),
            app_icon: request.app_icon,
            percent: -1,
            killable: request.capabilities & CAP_KILLABLE != 0,
            suspendable: request.capabilities & CAP_SUSPENDABLE != 0,
            started: now,
            updated: now,
            ..Default::default()
        };
        let entry = Entry {
            job,
            owner: owner.to_string(),
            visible: false,
            immediate: request.immediate,
            transient: request.transient,
            cancel_pending: false,
            seq,
        };
        self.entries.insert(id, entry);
        self.update(id, request.initial);
        id
    }

    /// Its show delay has passed: visible (false when it is gone or was visible already)
    pub fn show(&mut self, id: u32) -> bool {
        match self.entries.get_mut(&id) {
            Some(entry) if !entry.visible => {
                entry.visible = true;
                true
            }
            _ => false,
        }
    }

    /// Applies a change; returns whether a visible job changed (the shells are to be told)
    pub fn update(&mut self, id: u32, update: JobUpdate) -> bool {
        let Some(entry) = self.entries.get_mut(&id) else { return false };
        let job = &mut entry.job;
        let before = job.clone();
        if let Some(title) = update.title {
            job.title = crate::model::limit_chars(title, MAX_TEXT_CHARS);
        }
        if let Some(info) = update.info_message {
            job.info_message = crate::model::limit_chars(info, MAX_TEXT_CHARS);
        }
        if let Some(percent) = update.percent {
            job.percent = percent.min(100) as i32;
        }
        for (unit, amount) in update.processed {
            *amount_of(job, unit, true) = amount;
        }
        for (unit, amount) in update.total {
            *amount_of(job, unit, false) = amount;
        }
        if let Some(speed) = update.speed {
            job.speed = speed;
        }
        if let Some(elapsed) = update.elapsed {
            job.elapsed = elapsed.max(0);
        }
        for (number, label, value) in update.fields {
            if label.is_empty() && value.is_empty() {
                job.fields.remove(&number);
            } else {
                job.fields.insert(number, JobField { label, value: crate::model::limit_chars(value, MAX_TEXT_CHARS) });
            }
        }
        if let Some(destination) = update.destination {
            job.destination = destination.trim_end_matches('/').to_string();
        }
        if let Some(suspended) = update.suspended {
            if !job.state.ended() {
                job.state = if suspended { JobState::Suspended } else { JobState::Running };
            }
        }
        if *job == before {
            return false;
        }
        job.updated = now_ms();
        // "immediate": shown as soon as it says what it does
        if entry.immediate && !entry.visible && !entry.job.title.is_empty() {
            entry.visible = true;
        }
        entry.visible
    }

    /// The application set an error before ending (JobViewV2.setError)
    pub fn set_error(&mut self, id: u32, code: u32) {
        if let Some(entry) = self.entries.get_mut(&id) {
            entry.job.error_code = code;
        }
    }

    /// The application ended the job
    pub fn terminate(&mut self, id: u32, error_code: u32, error_text: &str) -> Ended {
        let Some(entry) = self.entries.get_mut(&id) else { return Ended::NotFound };
        if entry.job.state.ended() {
            return Ended::Kept { newly_visible: false };
        }
        let code = if error_code != 0 { error_code } else { entry.job.error_code };
        let canceled = code == ERR_USER_CANCELED || entry.cancel_pending && code != 0;
        if canceled || (code == 0 && entry.transient) {
            let was_visible = entry.visible;
            self.entries.remove(&id);
            return Ended::Removed { was_visible };
        }
        let job = &mut entry.job;
        job.error_code = code;
        job.error_text = crate::model::limit_chars(error_text.to_string(), MAX_TEXT_CHARS);
        job.state = if code == 0 { JobState::Finished } else { JobState::Failed };
        if code == 0 && job.percent >= 0 {
            job.percent = 100;
        }
        job.speed = 0;
        job.updated = now_ms();
        // An ended job is worth seeing even when it was short
        let newly_visible = !entry.visible;
        entry.visible = true;
        Ended::Kept { newly_visible }
    }

    /// The user asked to cancel; false when there is nothing to cancel
    pub fn request_cancel(&mut self, id: u32) -> bool {
        match self.entries.get_mut(&id) {
            Some(entry) if !entry.job.state.ended() && entry.job.killable => {
                entry.cancel_pending = true;
                true
            }
            _ => false,
        }
    }

    /// The application did not answer a cancel request in time: canceled
    pub fn cancel_timed_out(&mut self, id: u32) -> Ended {
        match self.entries.get(&id) {
            Some(entry) if entry.cancel_pending && !entry.job.state.ended() => self.terminate(id, ERR_USER_CANCELED, ""),
            _ => Ended::NotFound,
        }
    }

    /// The user dismissed an ended job
    pub fn dismiss(&mut self, id: u32) -> Option<bool> {
        match self.entries.get(&id) {
            Some(entry) if entry.job.state.ended() => self.entries.remove(&id).map(|e| e.visible),
            _ => None,
        }
    }

    /// An application left the bus: its running jobs have failed
    pub fn owner_gone(&mut self, owner: &str) -> Vec<u32> {
        let ids: Vec<u32> = self
            .entries
            .values()
            .filter(|e| e.owner == owner && !e.job.state.ended())
            .map(|e| e.job.id)
            .collect();
        for id in &ids {
            if let Some(entry) = self.entries.get_mut(id) {
                entry.job.owner_gone = true;
            }
            self.terminate(*id, u32::MAX, "");
        }
        ids
    }

    /// Ended jobs beyond MAX_ENDED, the oldest first: removed; their ids (those the shells had)
    pub fn trim(&mut self) -> Vec<u32> {
        let mut ended: Vec<(u64, u32)> =
            self.entries.values().filter(|e| e.job.state.ended()).map(|e| (e.seq, e.job.id)).collect();
        if ended.len() <= MAX_ENDED {
            return Vec::new();
        }
        ended.sort();
        let excess = ended.len() - MAX_ENDED;
        ended.into_iter().take(excess).filter_map(|(_, id)| self.entries.remove(&id).filter(|e| e.visible).map(|_| id)).collect()
    }
}

fn amount_of(job: &mut Job, unit: Unit, processed: bool) -> &mut u64 {
    match (unit, processed) {
        (Unit::Bytes, true) => &mut job.processed_bytes,
        (Unit::Bytes, false) => &mut job.total_bytes,
        (Unit::Files, true) => &mut job.processed_files,
        (Unit::Files, false) => &mut job.total_files,
        (Unit::Directories, true) => &mut job.processed_directories,
        (Unit::Directories, false) => &mut job.total_directories,
        (Unit::Items, true) => &mut job.processed_items,
        (Unit::Items, false) => &mut job.total_items,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn copy() -> JobRequest {
        JobRequest {
            app_name: "Dolphin".into(),
            desktop_entry: "org.kde.dolphin.desktop".into(),
            app_icon: "system-file-manager".into(),
            capabilities: CAP_KILLABLE | CAP_SUSPENDABLE,
            ..Default::default()
        }
    }

    fn titled(title: &str) -> JobUpdate {
        JobUpdate { title: Some(title.into()), ..Default::default() }
    }

    #[test]
    fn a_job_is_hidden_until_its_delay_has_passed() {
        let mut store = JobStore::new();
        let id = store.create(copy(), ":1.5");
        assert!(!store.update(id, titled("Copying")));
        assert!(store.visible().is_empty());
        assert!(store.show(id));
        assert!(!store.show(id));
        let job = store.visible()[0];
        assert_eq!((job.title.as_str(), job.desktop_entry.as_str(), job.percent), ("Copying", "org.kde.dolphin", -1));
        assert!(job.killable && job.suspendable);
        assert!(store.update(id, JobUpdate { percent: Some(40), ..Default::default() }));
    }

    #[test]
    fn an_immediate_job_shows_as_soon_as_it_has_a_title() {
        let mut store = JobStore::new();
        let id = store.create(JobRequest { immediate: true, ..copy() }, ":1.5");
        assert!(store.visible().is_empty());
        assert!(store.update(id, titled("Extracting")));
        assert_eq!(store.visible().len(), 1);
    }

    #[test]
    fn amounts_fields_and_the_destination() {
        let mut store = JobStore::new();
        let id = store.create(copy(), ":1.5");
        store.show(id);
        store.update(
            id,
            JobUpdate {
                processed: vec![(Unit::Bytes, 300), (Unit::Files, 2)],
                total: vec![(Unit::Bytes, 1000), (Unit::Files, 10), (Unit::Directories, 1)],
                speed: Some(50),
                fields: vec![(0, "Source".into(), "/home/a/x.iso".into()), (1, "Destination".into(), "/media/usb".into())],
                destination: Some("file:///media/usb/".into()),
                ..Default::default()
            },
        );
        store.update(id, JobUpdate { fields: vec![(1, String::new(), String::new())], ..Default::default() });
        let job = store.visible()[0];
        assert_eq!((job.processed_bytes, job.total_bytes, job.processed_files, job.total_files, job.total_directories), (300, 1000, 2, 10, 1));
        assert_eq!(job.speed, 50);
        assert_eq!(job.fields.len(), 1);
        assert_eq!(job.destination, "file:///media/usb");
        assert_eq!(Unit::parse("dirs"), Some(Unit::Directories));
        assert_eq!(Unit::parse("parsecs"), None);
    }

    #[test]
    fn suspending_and_resuming() {
        let mut store = JobStore::new();
        let id = store.create(copy(), ":1.5");
        store.show(id);
        store.update(id, JobUpdate { suspended: Some(true), ..Default::default() });
        assert_eq!(store.visible()[0].state, JobState::Suspended);
        store.update(id, JobUpdate { suspended: Some(false), ..Default::default() });
        assert_eq!(store.visible()[0].state, JobState::Running);
    }

    #[test]
    fn a_finished_job_stays_and_a_short_one_becomes_visible() {
        let mut store = JobStore::new();
        let id = store.create(copy(), ":1.5");
        store.update(id, JobUpdate { percent: Some(97), ..Default::default() });
        assert_eq!(store.terminate(id, 0, ""), Ended::Kept { newly_visible: true });
        let job = store.visible()[0];
        assert_eq!((job.state, job.percent, job.speed), (JobState::Finished, 100, 0));
        // Ending twice changes nothing
        assert_eq!(store.terminate(id, 5, "late"), Ended::Kept { newly_visible: false });
        assert_eq!(store.dismiss(id), Some(true));
        assert!(store.is_empty());
    }

    #[test]
    fn a_canceled_job_and_a_transient_one_go_without_a_trace() {
        let mut store = JobStore::new();
        let canceled = store.create(copy(), ":1.5");
        store.show(canceled);
        assert_eq!(store.terminate(canceled, ERR_USER_CANCELED, "Canceled"), Ended::Removed { was_visible: true });
        let transient = store.create(JobRequest { transient: true, ..copy() }, ":1.5");
        assert_eq!(store.terminate(transient, 0, ""), Ended::Removed { was_visible: false });
        // A transient one that fails stays: the error matters
        let failing = store.create(JobRequest { transient: true, ..copy() }, ":1.5");
        assert_eq!(store.terminate(failing, 13, "No space left"), Ended::Kept { newly_visible: true });
        let job = store.visible()[0];
        assert_eq!((job.state, job.error_code, job.error_text.as_str()), (JobState::Failed, 13, "No space left"));
    }

    #[test]
    fn the_old_api_sets_the_error_before_terminating() {
        let mut store = JobStore::new();
        let id = store.create(copy(), ":1.5");
        store.set_error(id, 7);
        store.terminate(id, 0, "Could not write");
        assert_eq!(store.visible()[0].state, JobState::Failed);
    }

    #[test]
    fn a_cancel_without_an_answer_ends_the_job() {
        let mut store = JobStore::new();
        let id = store.create(copy(), ":1.5");
        store.show(id);
        assert!(store.request_cancel(id));
        assert_eq!(store.cancel_timed_out(id), Ended::Removed { was_visible: true });
        // Only killable jobs can be canceled
        let stubborn = store.create(JobRequest { capabilities: 0, ..copy() }, ":1.5");
        assert!(!store.request_cancel(stubborn));
        assert_eq!(store.cancel_timed_out(stubborn), Ended::NotFound);
    }

    #[test]
    fn a_job_whose_application_quits_has_failed() {
        let mut store = JobStore::new();
        let mine = store.create(copy(), ":1.5");
        let other = store.create(copy(), ":1.6");
        let ended = store.create(copy(), ":1.5");
        store.terminate(ended, 0, "");
        assert_eq!(store.owner_gone(":1.5"), [mine]);
        let job = &store.get(mine).unwrap().job;
        assert!(job.owner_gone && job.state == JobState::Failed);
        assert!(!store.get(other).unwrap().job.state.ended());
    }

    #[test]
    fn running_jobs_cannot_be_dismissed_and_old_ended_ones_are_dropped() {
        let mut store = JobStore::new();
        let running = store.create(copy(), ":1.5");
        assert_eq!(store.dismiss(running), None);
        for _ in 0..MAX_ENDED + 3 {
            let id = store.create(copy(), ":1.5");
            store.terminate(id, 0, "");
        }
        assert_eq!(store.trim().len(), 3);
        assert_eq!(store.len(), MAX_ENDED + 1);
        assert!(store.get(running).is_some());
    }
}

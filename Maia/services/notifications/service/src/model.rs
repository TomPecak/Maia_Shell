//! The notifications as plain values, and the rules of the list without any I/O: ids, replacing,
//! the limit, which notifications pop up, what an action, a dismissal or the end of a popup does,
//! do not disturb. The hub (hub.rs) applies them and tells the shells and the senders.
//!
//! The store is generic over `O`, the origin of a notification (who gets its events: a D-Bus client
//! or a Notifier listener), so that the rules can be tested without either.

use std::collections::BTreeMap;
use std::time::{SystemTime, UNIX_EPOCH};

/// At most this many notifications are kept; the oldest go first (critical ones last)
pub const MAX_NOTIFICATIONS: usize = 200;
pub const MAX_ACTIONS: usize = 8;
pub const MAX_SUMMARY_CHARS: usize = 400;
pub const MAX_BODY_CHARS: usize = 8000;
pub const MAX_URLS: usize = 32;
pub const MAX_URL_CHARS: usize = 4096;

/// Schemes never passed on: they run code or carry their content inline
const REFUSED_SCHEMES: [&str; 4] = ["javascript", "data", "vbscript", "about"];

/// The files and places a notification is about (x-kde-urls, NotificationRequest.urls), as the
/// shells may use them (show, open, drag): URLs with a scheme, an absolute path as a file:// URL; no
/// spaces or control characters, not longer than MAX_URL_CHARS, no REFUSED_SCHEMES, no duplicates,
/// at most MAX_URLS. Anything else is dropped.
pub fn urls(list: Vec<String>) -> Vec<String> {
    let mut kept: Vec<String> = Vec::new();
    for item in list {
        if kept.len() == MAX_URLS {
            break;
        }
        let item = item.trim();
        let url = if item.starts_with('/') { crate::image::url_from_path(item) } else { item.to_string() };
        if url.len() > MAX_URL_CHARS || url.chars().any(|c| c.is_whitespace() || c.is_control()) {
            continue;
        }
        let Some((scheme, rest)) = url.split_once(':') else { continue };
        let valid_scheme = scheme.len() >= 2
            && scheme.starts_with(|c: char| c.is_ascii_alphabetic())
            && scheme.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.'));
        if !valid_scheme || rest.is_empty() || REFUSED_SCHEMES.contains(&scheme.to_ascii_lowercase().as_str()) {
            continue;
        }
        if !kept.contains(&url) {
            kept.push(url);
        }
    }
    kept
}

pub fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Urgency {
    Low,
    #[default]
    Normal,
    Critical,
}

impl Urgency {
    /// The "urgency" hint of the specification: 0 low, 1 normal, 2 critical
    pub fn from_level(level: i64) -> Urgency {
        match level {
            0 => Urgency::Low,
            2 => Urgency::Critical,
            _ => Urgency::Normal,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CloseReason {
    Expired,
    Dismissed,
    ClosedByApp,
    Other,
}

impl CloseReason {
    /// The reason of NotificationClosed on D-Bus
    pub fn dbus_code(self) -> u32 {
        match self {
            CloseReason::Expired => 1,
            CloseReason::Dismissed => 2,
            CloseReason::ClosedByApp => 3,
            CloseReason::Other => 4,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Action {
    pub key: String,
    pub label: String,
}

/// Raw pixels of the "image-data" hint (GdkPixbuf layout)
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Pixels {
    pub width: i32,
    pub height: i32,
    pub rowstride: i32,
    pub has_alpha: bool,
    pub bits_per_sample: i32,
    pub channels: i32,
    pub data: Vec<u8>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub enum ImageSource {
    #[default]
    None,
    /// A file:// URL, ready to show
    Url(String),
    /// Pixels still to be written as PNG
    Pixels(Pixels),
}

/// What a sender asks for (from D-Bus or the Notifier), already checked and in the contract's terms
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Request {
    pub app_name: String,
    pub desktop_entry: String,
    pub app_icon: String,
    pub summary: String,
    /// Already made safe (markup.rs)
    pub body: String,
    pub image: ImageSource,
    pub actions: Vec<Action>,
    pub action_icons: bool,
    pub urgency: Urgency,
    pub category: String,
    pub timeout: i32,
    pub transient: bool,
    pub resident: bool,
    pub inline_reply: bool,
    pub reply_placeholder: String,
    pub reply_submit_text: String,
    pub origin_name: String,
    pub urls: Vec<String>,
    pub sound_name: String,
    pub sound_file: String,
    pub suppress_sound: bool,
}

/// A notification as the shells see it
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Notification {
    pub id: u32,
    pub app_name: String,
    pub desktop_entry: String,
    pub app_icon: String,
    pub summary: String,
    pub body: String,
    pub image: String,
    pub actions: Vec<Action>,
    pub action_icons: bool,
    pub urgency: Urgency,
    pub category: String,
    pub timeout: i32,
    pub time: i64,
    pub transient: bool,
    pub resident: bool,
    pub popup: bool,
    pub expired: bool,
    pub inline_reply: bool,
    pub reply_placeholder: String,
    pub reply_submit_text: String,
    pub origin_name: String,
    pub urls: Vec<String>,
    pub sound_name: String,
    pub sound_file: String,
    pub suppress_sound: bool,
}

impl Notification {
    pub fn has_action(&self, key: &str) -> bool {
        self.actions.iter().any(|a| a.key == key)
    }
}

pub struct Entry<O> {
    pub notification: Notification,
    pub origin: O,
    /// Shown to the shells: false while its image is still being written
    pub ready: bool,
    /// Bumped by every replacement: an image written for an older content is thrown away
    pub generation: u64,
    /// The PNG file the service wrote for it, removed with it
    pub image_file: Option<std::path::PathBuf>,
    /// Order of the list: higher = newer
    seq: u64,
}

/// What `add` did
#[derive(Debug, PartialEq)]
pub struct Added<O> {
    pub id: u32,
    pub replaced: bool,
    pub generation: u64,
    /// Pixels to write before the notification is shown (it is not ready meanwhile)
    pub pixels: Option<Pixels>,
    /// The file of the replaced content, to delete
    pub old_image_file: Option<std::path::PathBuf>,
    /// Notifications dropped because the list was full: (id, origin, its image file)
    pub dropped: Vec<(u32, O, Option<std::path::PathBuf>)>,
}

/// What the end of a popup did
#[derive(Debug, PartialEq)]
pub enum Expired<O> {
    NotFound,
    /// Marked as expired, stays in the list
    Kept,
    /// A transient notification: gone, its sender is told
    Removed(Entry<O>),
}

impl<O: std::fmt::Debug> std::fmt::Debug for Entry<O> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Entry").field("notification", &self.notification).field("ready", &self.ready).finish()
    }
}

impl<O: PartialEq> PartialEq for Entry<O> {
    fn eq(&self, other: &Self) -> bool {
        self.notification == other.notification && self.origin == other.origin && self.ready == other.ready
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Inhibitor {
    pub desktop_entry: String,
    pub app_name: String,
    pub reason: String,
    /// The D-Bus name of the application that asked: the inhibition ends when it leaves the bus
    pub owner: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct DoNotDisturb {
    pub enabled: bool,
    pub until: i64,
    pub inhibitors: BTreeMap<u32, Inhibitor>,
}

impl DoNotDisturb {
    /// The user's choice is on (and its time has not run out)
    pub fn enabled_at(&self, now: i64) -> bool {
        self.enabled && (self.until == 0 || now < self.until)
    }

    /// Quiet now: the user's choice or any application
    pub fn active_at(&self, now: i64) -> bool {
        self.enabled_at(now) || !self.inhibitors.is_empty()
    }
}

pub struct Store<O> {
    entries: BTreeMap<u32, Entry<O>>,
    next_id: u32,
    next_seq: u64,
    next_generation: u64,
    next_cookie: u32,
    pub dnd: DoNotDisturb,
    limit: usize,
}

impl<O: Clone> Default for Store<O> {
    fn default() -> Self {
        Store::new()
    }
}

impl<O: Clone> Store<O> {
    pub fn new() -> Store<O> {
        Store::with_limit(MAX_NOTIFICATIONS)
    }

    pub fn with_limit(limit: usize) -> Store<O> {
        Store {
            entries: BTreeMap::new(),
            next_id: 1,
            next_seq: 1,
            next_generation: 1,
            next_cookie: 1,
            dnd: DoNotDisturb::default(),
            limit: limit.max(1),
        }
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn get(&self, id: u32) -> Option<&Entry<O>> {
        self.entries.get(&id)
    }

    pub fn get_mut(&mut self, id: u32) -> Option<&mut Entry<O>> {
        self.entries.get_mut(&id)
    }

    /// The notifications the shells see, the newest first
    pub fn ready(&self) -> Vec<&Notification> {
        let mut list: Vec<&Entry<O>> = self.entries.values().filter(|e| e.ready).collect();
        list.sort_by(|a, b| b.seq.cmp(&a.seq));
        list.into_iter().map(|e| &e.notification).collect()
    }

    pub fn ids(&self) -> Vec<u32> {
        self.entries.keys().copied().collect()
    }

    /// An id for a notification that is not kept (its application is turned off): never one in use
    pub fn reserve_id(&mut self) -> u32 {
        self.take_id()
    }

    fn take_id(&mut self) -> u32 {
        loop {
            let id = self.next_id;
            self.next_id = self.next_id.wrapping_add(1).max(1);
            if !self.entries.contains_key(&id) {
                return id;
            }
        }
    }

    /// Whether a new notification pops up: not in do not disturb (unless critical), not low urgency
    /// (as Plasma by default: low urgency only goes into the list)
    pub fn pops_up(&self, urgency: Urgency, now: i64) -> bool {
        match urgency {
            Urgency::Critical => true,
            Urgency::Low => false,
            Urgency::Normal => !self.dnd.active_at(now),
        }
    }

    /// A new notification, or a replacement of `replaces` when it exists (it keeps its id, comes to
    /// the top and pops up again)
    pub fn add(&mut self, replaces: u32, request: Request, origin: O, now: i64) -> Added<O> {
        let replaced = replaces != 0 && self.entries.contains_key(&replaces);
        let id = if replaced { replaces } else { self.take_id() };
        let generation = self.next_generation;
        self.next_generation += 1;
        let seq = self.next_seq;
        self.next_seq += 1;

        let (image, pixels) = match request.image {
            ImageSource::None => (String::new(), None),
            ImageSource::Url(url) => (url, None),
            ImageSource::Pixels(pixels) => (String::new(), Some(pixels)),
        };
        let notification = Notification {
            id,
            popup: self.pops_up(request.urgency, now),
            app_name: request.app_name,
            desktop_entry: request.desktop_entry,
            app_icon: request.app_icon,
            summary: request.summary,
            body: request.body,
            image,
            actions: request.actions,
            action_icons: request.action_icons,
            urgency: request.urgency,
            category: request.category,
            timeout: request.timeout,
            time: now,
            transient: request.transient,
            resident: request.resident,
            expired: false,
            inline_reply: request.inline_reply,
            reply_placeholder: request.reply_placeholder,
            reply_submit_text: request.reply_submit_text,
            origin_name: request.origin_name,
            urls: request.urls,
            sound_name: request.sound_name,
            sound_file: request.sound_file,
            suppress_sound: request.suppress_sound,
        };
        let ready = pixels.is_none();
        let old = self.entries.insert(
            id,
            Entry { notification, origin, ready, generation, image_file: None, seq },
        );
        let old_image_file = old.and_then(|e| e.image_file);

        let mut dropped = Vec::new();
        while self.entries.len() > self.limit {
            // The oldest first, critical ones only when nothing else is left; never the new one
            let victim = self
                .entries
                .values()
                .filter(|e| e.notification.id != id)
                .min_by_key(|e| (e.notification.urgency == Urgency::Critical, e.seq))
                .map(|e| e.notification.id);
            let Some(victim) = victim else { break };
            if let Some(entry) = self.entries.remove(&victim) {
                dropped.push((victim, entry.origin, entry.image_file));
            }
        }
        Added { id, replaced, generation, pixels, old_image_file, dropped }
    }

    /// The image of a notification has been written; false when the notification is gone or has
    /// been replaced meanwhile (the file is then not used)
    pub fn set_image(&mut self, id: u32, generation: u64, url: String, file: std::path::PathBuf) -> bool {
        match self.entries.get_mut(&id) {
            Some(entry) if entry.generation == generation => {
                entry.notification.image = url;
                entry.image_file = Some(file);
                entry.ready = true;
                true
            }
            _ => false,
        }
    }

    /// The image could not be written: the notification is shown without it
    pub fn image_failed(&mut self, id: u32, generation: u64) -> bool {
        match self.entries.get_mut(&id) {
            Some(entry) if entry.generation == generation => {
                entry.ready = true;
                true
            }
            _ => false,
        }
    }

    pub fn remove(&mut self, id: u32) -> Option<Entry<O>> {
        self.entries.remove(&id)
    }

    /// The popup has ended: a transient notification goes, any other stays in the list
    pub fn expire(&mut self, id: u32) -> Expired<O> {
        match self.entries.get_mut(&id) {
            None => Expired::NotFound,
            Some(entry) if entry.notification.transient => match self.entries.remove(&id) {
                Some(entry) => Expired::Removed(entry),
                None => Expired::NotFound,
            },
            Some(entry) => {
                entry.notification.expired = true;
                entry.notification.popup = false;
                Expired::Kept
            }
        }
    }

    /// The ids "Clear all" removes: everything but critical notifications
    pub fn dismissable(&self) -> Vec<u32> {
        self.entries.values().filter(|e| e.notification.urgency != Urgency::Critical).map(|e| e.notification.id).collect()
    }

    pub fn inhibit(&mut self, inhibitor: Inhibitor) -> u32 {
        let cookie = self.next_cookie;
        self.next_cookie = self.next_cookie.wrapping_add(1).max(1);
        self.dnd.inhibitors.insert(cookie, inhibitor);
        cookie
    }

    pub fn uninhibit(&mut self, cookie: u32) -> bool {
        self.dnd.inhibitors.remove(&cookie).is_some()
    }

    /// An application left the bus: its inhibitions end
    pub fn owner_gone(&mut self, owner: &str) -> bool {
        let before = self.dnd.inhibitors.len();
        self.dnd.inhibitors.retain(|_, i| i.owner != owner);
        before != self.dnd.inhibitors.len()
    }
}

/// Text cut to at most `max` characters (not bytes), without splitting a character
pub fn limit_chars(text: String, max: usize) -> String {
    match text.char_indices().nth(max) {
        Some((cut, _)) => {
            let mut text = text;
            text.truncate(cut);
            text.push('…');
            text
        }
        None => text,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn urls_are_urls_and_nothing_else() {
        let strings = |list: &[&str]| list.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        let kept = urls(strings(&[
            "/home/a/Pictures/Screenshot 1.png",
            "file:///home/a/x.pdf",
            "https://example.org/report",
            "smb://server/share/doc.odt",
            "javascript:alert(1)",
            "DATA:text/html,<b>x</b>",
            "not a url",
            "c:\\windows",
            "mailto:",
            "file:///home/a/x.pdf",
            "",
        ]));
        assert_eq!(kept, [
            "file:///home/a/Pictures/Screenshot%201.png",
            "file:///home/a/x.pdf",
            "https://example.org/report",
            "smb://server/share/doc.odt",
        ]);
        let many: Vec<String> = (0..100).map(|i| format!("file:///tmp/{i}")).collect();
        assert_eq!(urls(many).len(), MAX_URLS);
        assert!(urls(vec![format!("https://example.org/{}", "a".repeat(MAX_URL_CHARS))]).is_empty());
    }

    fn request(summary: &str) -> Request {
        Request { summary: summary.into(), timeout: -1, ..Default::default() }
    }

    #[test]
    fn ids_start_at_one_and_never_repeat_while_in_use() {
        let mut store: Store<u8> = Store::new();
        let a = store.add(0, request("a"), 0, 1).id;
        let b = store.add(0, request("b"), 0, 2).id;
        assert_eq!((a, b), (1, 2));
        store.remove(a);
        assert_eq!(store.add(0, request("c"), 0, 3).id, 3);
    }

    #[test]
    fn ids_wrap_around_without_zero_and_skip_ids_in_use() {
        let mut store: Store<u8> = Store::new();
        store.next_id = u32::MAX;
        let last = store.add(0, request("a"), 0, 1).id;
        assert_eq!(last, u32::MAX);
        let next = store.add(0, request("b"), 0, 1).id;
        assert_eq!(next, 1);
        store.next_id = u32::MAX;
        assert_eq!(store.add(0, request("c"), 0, 1).id, 2); // MAX and 1 are taken
    }

    #[test]
    fn a_replacement_keeps_the_id_comes_to_the_top_and_pops_up_again() {
        let mut store: Store<u8> = Store::new();
        let first = store.add(0, request("1 new message"), 7, 10).id;
        let other = store.add(0, request("other"), 7, 11).id;
        assert!(matches!(store.expire(first), Expired::Kept));
        let added = store.add(first, request("2 new messages"), 7, 12);
        assert_eq!((added.id, added.replaced), (first, true));
        let list = store.ready();
        assert_eq!(list.iter().map(|n| n.id).collect::<Vec<_>>(), [first, other]);
        assert_eq!(list[0].summary, "2 new messages");
        assert!(list[0].popup && !list[0].expired);
        assert_eq!(list[0].time, 12);
    }

    #[test]
    fn replacing_an_unknown_id_makes_a_new_notification() {
        let mut store: Store<u8> = Store::new();
        let added = store.add(42, request("x"), 0, 1);
        assert!(!added.replaced);
        assert_eq!(added.id, 1);
    }

    #[test]
    fn the_list_drops_the_oldest_and_keeps_critical_ones() {
        let mut store: Store<u8> = Store::with_limit(3);
        let critical = store.add(0, Request { urgency: Urgency::Critical, ..request("battery") }, 1, 1).id;
        let a = store.add(0, request("a"), 2, 2).id;
        let b = store.add(0, request("b"), 3, 3).id;
        let added = store.add(0, request("c"), 4, 4);
        assert_eq!(added.dropped.iter().map(|(id, origin, _)| (*id, *origin)).collect::<Vec<_>>(), [(a, 2)]);
        assert!(store.get(critical).is_some() && store.get(b).is_some());
        assert_eq!(store.len(), 3);
    }

    #[test]
    fn do_not_disturb_keeps_normal_notifications_out_of_popups_but_not_critical_ones() {
        let mut store: Store<u8> = Store::new();
        store.dnd.enabled = true;
        let normal = store.add(0, request("mail"), 0, 1).id;
        let critical = store.add(0, Request { urgency: Urgency::Critical, ..request("battery") }, 0, 1).id;
        let low = store.add(0, Request { urgency: Urgency::Low, ..request("charged") }, 0, 1).id;
        assert!(!store.get(normal).unwrap().notification.popup);
        assert!(store.get(critical).unwrap().notification.popup);
        assert!(!store.get(low).unwrap().notification.popup);
        assert_eq!(store.len(), 3); // all in the list
    }

    #[test]
    fn do_not_disturb_ends_at_its_time_and_applications_can_ask_for_it() {
        let mut dnd = DoNotDisturb { enabled: true, until: 100, ..Default::default() };
        assert!(dnd.active_at(99));
        assert!(!dnd.active_at(100));
        dnd.enabled = false;
        dnd.inhibitors.insert(1, Inhibitor { desktop_entry: "impress".into(), app_name: "Impress".into(), reason: "Presenting".into(), owner: ":1.5".into() });
        assert!(dnd.active_at(0) && !dnd.enabled_at(0));
    }

    #[test]
    fn inhibitions_end_with_their_application() {
        let mut store: Store<u8> = Store::new();
        let inhibitor = |owner: &str| Inhibitor { desktop_entry: String::new(), app_name: String::new(), reason: String::new(), owner: owner.into() };
        let a = store.inhibit(inhibitor(":1.5"));
        store.inhibit(inhibitor(":1.6"));
        assert!(store.owner_gone(":1.6"));
        assert!(!store.owner_gone(":1.6"));
        assert!(store.uninhibit(a));
        assert!(store.dnd.inhibitors.is_empty());
    }

    #[test]
    fn the_end_of_a_popup_keeps_the_notification_but_removes_a_transient_one() {
        let mut store: Store<u8> = Store::new();
        let kept = store.add(0, request("mail"), 0, 1).id;
        let transient = store.add(0, Request { transient: true, ..request("volume") }, 9, 1).id;
        assert!(matches!(store.expire(kept), Expired::Kept));
        let n = &store.get(kept).unwrap().notification;
        assert!(n.expired && !n.popup);
        match store.expire(transient) {
            Expired::Removed(entry) => assert_eq!(entry.origin, 9),
            other => panic!("{other:?}"),
        }
        assert!(matches!(store.expire(transient), Expired::NotFound));
    }

    #[test]
    fn a_notification_with_pixels_waits_for_its_image() {
        let mut store: Store<u8> = Store::new();
        let pixels = Pixels { width: 1, height: 1, rowstride: 4, has_alpha: true, bits_per_sample: 8, channels: 4, data: vec![0; 4] };
        let added = store.add(0, Request { image: ImageSource::Pixels(pixels), ..request("photo") }, 0, 1);
        assert!(added.pixels.is_some());
        assert!(store.ready().is_empty());
        // An image written for an older content is not used
        let newer = store.add(added.id, request("text only"), 0, 2);
        assert!(!store.set_image(added.id, added.generation, "file:///old.png".into(), "/old.png".into()));
        assert_eq!(store.ready().len(), 1);
        assert!(store.set_image(added.id, newer.generation, "file:///new.png".into(), "/new.png".into()));
        assert_eq!(store.ready()[0].image, "file:///new.png");
    }

    #[test]
    fn clear_all_keeps_critical_notifications() {
        let mut store: Store<u8> = Store::new();
        store.add(0, request("a"), 0, 1);
        let critical = store.add(0, Request { urgency: Urgency::Critical, ..request("battery") }, 0, 1).id;
        assert!(!store.dismissable().contains(&critical));
        assert_eq!(store.dismissable().len(), 1);
    }

    #[test]
    fn texts_are_cut_by_characters() {
        assert_eq!(limit_chars("żółw".into(), 2), "żó…");
        assert_eq!(limit_chars("abc".into(), 3), "abc");
    }
}

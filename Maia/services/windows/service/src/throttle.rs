//! How often the changes of one window go out to the clients.
//!
//! The compositor reports some properties on every frame: the geometry of a window being dragged
//! or resized changes 60–144 times per second. Sending each of them to every client would make the
//! shell busiest exactly while it should animate smoothly. So the changes of one window go out at
//! most once per interval (one frame), always with its latest state:
//!
//! - a change after a quiet period goes out at once (no added latency for e.g. activation);
//! - further changes within the interval wait, and only the last state is sent when it ends;
//! - a removed window drops its waiting change (the removal says everything).
//!
//! Pure logic without I/O: the caller passes the time in and runs the timer (see rpc.rs).

use std::collections::HashMap;
use std::time::{Duration, Instant};

pub struct ChangeThrottle {
    interval: Duration,
    /// When each window was last sent to the clients
    last_sent: HashMap<String, Instant>,
    /// Windows with a change that waits, in the order they changed
    pending: Vec<String>,
}

impl ChangeThrottle {
    pub fn new(interval: Duration) -> Self {
        Self { interval, last_sent: HashMap::new(), pending: Vec::new() }
    }

    /// A new window was sent to the clients
    pub fn added(&mut self, id: &str, now: Instant) {
        self.last_sent.insert(id.to_string(), now);
    }

    /// A window changed. Returns true when the change is to be sent now; otherwise it waits until
    /// `next_deadline()`, and `take_due()` returns it then.
    pub fn changed(&mut self, id: &str, now: Instant) -> bool {
        let due = self.last_sent.get(id).is_none_or(|&sent| now.duration_since(sent) >= self.interval);
        if due {
            self.pending.retain(|other| other != id);
            self.last_sent.insert(id.to_string(), now);
        } else if !self.pending.iter().any(|other| other == id) {
            self.pending.push(id.to_string());
        }
        due
    }

    /// A window is gone: nothing of it waits any longer
    pub fn removed(&mut self, id: &str) {
        self.last_sent.remove(id);
        self.pending.retain(|other| other != id);
    }

    /// When the next waiting change is due, if any waits
    pub fn next_deadline(&self) -> Option<Instant> {
        self.pending.iter().filter_map(|id| self.last_sent.get(id)).min().map(|&sent| sent + self.interval)
    }

    /// The windows whose waiting change is due now, in the order they changed; they count as sent
    pub fn take_due(&mut self, now: Instant) -> Vec<String> {
        let mut due = Vec::new();
        let interval = self.interval;
        let last_sent = &mut self.last_sent;
        self.pending.retain(|id| {
            let ready = last_sent.get(id).is_none_or(|&sent| now.duration_since(sent) >= interval);
            if ready {
                last_sent.insert(id.clone(), now);
                due.push(id.clone());
            }
            !ready
        });
        due
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FRAME: Duration = Duration::from_millis(16);

    fn ms(start: Instant, ms: u64) -> Instant {
        start + Duration::from_millis(ms)
    }

    #[test]
    fn first_change_after_a_quiet_period_goes_out_at_once() {
        let t = Instant::now();
        let mut throttle = ChangeThrottle::new(FRAME);
        throttle.added("a", t);
        assert!(throttle.changed("a", ms(t, 100)));
        assert_eq!(throttle.next_deadline(), None);
    }

    #[test]
    fn a_burst_becomes_one_change_per_frame() {
        let t = Instant::now();
        let mut throttle = ChangeThrottle::new(FRAME);
        throttle.added("a", t);
        // A drag: a change every 7 ms, from 7 to 70 ms (without the timer that would send the
        // waiting change earlier)
        let sent_at_once: Vec<u64> = (1..=10).map(|i| i * 7).filter(|&at| throttle.changed("a", ms(t, at))).collect();
        assert_eq!(sent_at_once, [21, 42, 63]); // at least 16 ms after the previous send
        assert_eq!(throttle.next_deadline(), Some(ms(t, 79))); // the change at 70 waits
        assert!(throttle.take_due(ms(t, 75)).is_empty());
        assert_eq!(throttle.take_due(ms(t, 79)), ["a"]);
        assert_eq!(throttle.next_deadline(), None);
    }

    #[test]
    fn deadline_is_one_interval_after_the_last_send() {
        let t = Instant::now();
        let mut throttle = ChangeThrottle::new(FRAME);
        throttle.added("a", t);
        assert!(!throttle.changed("a", ms(t, 5)));
        assert_eq!(throttle.next_deadline(), Some(ms(t, 16)));
    }

    #[test]
    fn windows_are_throttled_independently() {
        let t = Instant::now();
        let mut throttle = ChangeThrottle::new(FRAME);
        throttle.added("a", t);
        throttle.added("b", ms(t, 10));
        assert!(!throttle.changed("b", ms(t, 12)));
        assert!(!throttle.changed("a", ms(t, 13)));
        assert_eq!(throttle.next_deadline(), Some(ms(t, 16))); // the deadline of "a"
        assert_eq!(throttle.take_due(ms(t, 16)), ["a"]);
        assert_eq!(throttle.take_due(ms(t, 26)), ["b"]);
    }

    #[test]
    fn removal_drops_the_waiting_change() {
        let t = Instant::now();
        let mut throttle = ChangeThrottle::new(FRAME);
        throttle.added("a", t);
        assert!(!throttle.changed("a", ms(t, 1)));
        throttle.removed("a");
        assert_eq!(throttle.next_deadline(), None);
        assert!(throttle.take_due(ms(t, 100)).is_empty());
    }
}

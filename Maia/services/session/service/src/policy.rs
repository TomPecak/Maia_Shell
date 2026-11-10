//! When a child that ended is started again: the waits and the limits of session.toml, as a pure
//! function of the times of its ends (tested without a clock).
//!
//! The waits double from 1 s with every end inside the give_up window (or the last two minutes
//! without one), up to max_delay: a process that crashes at once does not spin, and one that ran
//! for a long time comes back after a second.

use std::collections::VecDeque;
use std::time::{Duration, Instant};

use crate::manifest::{GiveUpAction, Process, Restart};

/// The window for the doubling when a process has no give_up
const DEFAULT_WINDOW: Duration = Duration::from_secs(120);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Decision {
    /// Start it again after this wait
    Restart(Duration),
    /// It ended as it may (restart "on-failure" after exit code 0, or "never")
    Done,
    /// Too many ends in too short a time
    GiveUp(GiveUpAction),
}

/// The ends of one child, newest last
#[derive(Clone, Debug, Default)]
pub struct History {
    ends: VecDeque<Instant>,
}

impl History {
    pub fn clear(&mut self) {
        self.ends.clear();
    }

    /// The child ended at `now` (successfully or not): what to do
    pub fn decide(&mut self, process: &Process, success: bool, now: Instant) -> Decision {
        match process.restart {
            Restart::Never => return Decision::Done,
            Restart::OnFailure if success => return Decision::Done,
            _ => {}
        }
        let window = process.give_up.map(|g| Duration::from_secs(g.within)).unwrap_or(DEFAULT_WINDOW);
        self.ends.push_back(now);
        while let Some(first) = self.ends.front() {
            if now.duration_since(*first) > window {
                self.ends.pop_front();
            } else {
                break;
            }
        }
        let recent = self.ends.len() as u32;
        if let Some(give_up) = process.give_up {
            if recent >= give_up.crashes {
                return Decision::GiveUp(give_up.then);
            }
        }
        let doubling = recent.saturating_sub(1).min(16);
        Decision::Restart(Duration::from_secs(1u64 << doubling).min(process.max_delay))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::{GiveUp, Kind};

    fn process(restart: Restart, give_up: Option<GiveUp>) -> Process {
        Process {
            name: "p".into(),
            kind: Kind::MaiaService,
            command: vec!["p".into()],
            search: vec![],
            unit: None,
            autostart: None,
            compositors: vec![],
            skip_if_bus_name: None,
            environment: Default::default(),
            unset_environment: vec![],
            restart,
            give_up,
            max_delay: Duration::from_secs(30),
            stop_timeout: Duration::from_secs(5),
            test_mode: true,
        }
    }

    #[test]
    fn waits_double_up_to_the_limit() {
        let p = process(Restart::Always, None);
        let mut h = History::default();
        let t0 = Instant::now();
        let waits: Vec<_> = (0..8)
            .map(|i| match h.decide(&p, false, t0 + Duration::from_millis(100 * i)) {
                Decision::Restart(d) => d.as_secs(),
                other => panic!("{other:?}"),
            })
            .collect();
        assert_eq!(waits, [1, 2, 4, 8, 16, 30, 30, 30]);
    }

    #[test]
    fn a_long_run_starts_from_one_second_again() {
        let p = process(Restart::Always, None);
        let mut h = History::default();
        let t0 = Instant::now();
        h.decide(&p, false, t0);
        h.decide(&p, false, t0 + Duration::from_secs(1));
        assert_eq!(h.decide(&p, false, t0 + Duration::from_secs(600)), Decision::Restart(Duration::from_secs(1)));
    }

    #[test]
    fn the_shell_gives_up_after_five_crashes_in_two_minutes() {
        let give_up = GiveUp { crashes: 5, within: 120, then: GiveUpAction::EndSession };
        let p = process(Restart::Always, Some(give_up));
        let mut h = History::default();
        let t0 = Instant::now();
        for i in 0..4 {
            assert!(matches!(h.decide(&p, false, t0 + Duration::from_secs(10 * i)), Decision::Restart(_)));
        }
        assert_eq!(h.decide(&p, false, t0 + Duration::from_secs(50)), Decision::GiveUp(GiveUpAction::EndSession));
        // Spread over more than the window: it goes on
        let mut h = History::default();
        for i in 0..10 {
            assert!(matches!(h.decide(&p, false, t0 + Duration::from_secs(40 * i)), Decision::Restart(_)));
        }
    }

    #[test]
    fn on_failure_and_never() {
        let mut h = History::default();
        let now = Instant::now();
        assert_eq!(h.decide(&process(Restart::OnFailure, None), true, now), Decision::Done);
        assert!(matches!(h.decide(&process(Restart::OnFailure, None), false, now), Decision::Restart(_)));
        assert_eq!(h.decide(&process(Restart::Never, None), false, now), Decision::Done);
        // "always" starts again after exit code 0 too (a service must not end on its own)
        assert!(matches!(h.decide(&process(Restart::Always, None), true, now), Decision::Restart(_)));
    }
}

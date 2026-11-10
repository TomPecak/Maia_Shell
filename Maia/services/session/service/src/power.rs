//! systemd-logind: power off, reboot, sleep, what the system offers, and its signals.
//!
//! The only place in Maia that talks to org.freedesktop.login1 (system D-Bus, zbus). Calls are
//! interactive: when logind needs the administrator's password (another user is logged in), polkit
//! asks through the session's agent (plasma-polkit-agent), so they are made while the compositor
//! and the agent still run.
//!
//! The fake backend (MAIA_SESSION_BACKEND=fake) never reaches the machine: it logs what would be
//! done and answers like logind. Tests and nested sessions use it. MAIA_SESSION_FAKE_LOGIND=deny
//! makes every action fail with notAllowed (the cancelled password dialog).

use std::time::Duration;

use futures::StreamExt;
use tokio::sync::mpsc;
use zbus::{Connection, MatchRule};

pub const LOGIND: &str = "logind";
pub const FAKE: &str = "fake";

const DEST: &str = "org.freedesktop.login1";
const PATH: &str = "/org/freedesktop/login1";
const MANAGER: &str = "org.freedesktop.login1.Manager";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Ability {
    No,
    Yes,
    Challenge,
}

impl Ability {
    /// logind's answer to Can*(): "yes", "no", "challenge", "na"
    pub fn from_logind(answer: &str) -> Ability {
        match answer {
            "yes" => Ability::Yes,
            "challenge" => Ability::Challenge,
            _ => Ability::No,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Capabilities {
    pub power_off: Ability,
    pub reboot: Ability,
    pub suspend: Ability,
    pub hibernate: Ability,
    pub hybrid_sleep: Ability,
    pub suspend_then_hibernate: Ability,
}

impl Capabilities {
    pub const NONE: Capabilities = Capabilities {
        power_off: Ability::No,
        reboot: Ability::No,
        suspend: Ability::No,
        hibernate: Ability::No,
        hybrid_sleep: Ability::No,
        suspend_then_hibernate: Ability::No,
    };

    pub fn of(&self, action: Action) -> Ability {
        match action {
            Action::PowerOff => self.power_off,
            Action::Reboot => self.reboot,
            Action::Suspend => self.suspend,
            Action::Hibernate => self.hibernate,
            Action::HybridSleep => self.hybrid_sleep,
            Action::SuspendThenHibernate => self.suspend_then_hibernate,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    PowerOff,
    Reboot,
    Suspend,
    Hibernate,
    HybridSleep,
    SuspendThenHibernate,
}

impl Action {
    pub const ALL: [Action; 6] = [
        Action::PowerOff,
        Action::Reboot,
        Action::Suspend,
        Action::Hibernate,
        Action::HybridSleep,
        Action::SuspendThenHibernate,
    ];

    fn method(&self) -> &'static str {
        match self {
            Action::PowerOff => "PowerOff",
            Action::Reboot => "Reboot",
            Action::Suspend => "Suspend",
            Action::Hibernate => "Hibernate",
            Action::HybridSleep => "HybridSleep",
            Action::SuspendThenHibernate => "SuspendThenHibernate",
        }
    }

    fn can_method(&self) -> &'static str {
        match self {
            Action::PowerOff => "CanPowerOff",
            Action::Reboot => "CanReboot",
            Action::Suspend => "CanSuspend",
            Action::Hibernate => "CanHibernate",
            Action::HybridSleep => "CanHybridSleep",
            Action::SuspendThenHibernate => "CanSuspendThenHibernate",
        }
    }

    /// Ends the session (the others put the machine to sleep)
    pub fn ends_session(&self) -> bool {
        matches!(self, Action::PowerOff | Action::Reboot)
    }
}

/// Why an action failed
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PowerError {
    /// polkit refused, or the user cancelled the password dialog
    NotAllowed(String),
    Failed(String),
}

/// What logind tells about the whole system
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PowerSignal {
    /// true: the machine goes to sleep now; false: it woke up
    PrepareForSleep(bool),
    /// true: the machine is being shut down (also from outside the session)
    PrepareForShutdown(bool),
}

pub enum Power {
    Logind(Connection),
    Fake { deny: bool, signals: mpsc::UnboundedSender<PowerSignal> },
    /// logind cannot be reached (no system bus): the session runs, without power actions
    Unavailable(String),
}

impl Power {
    /// The backend by name; signals of logind go to `signals`
    pub async fn connect(backend: &str, signals: mpsc::UnboundedSender<PowerSignal>) -> Result<Power, String> {
        match backend {
            LOGIND => {
                let conn = Connection::system().await.map_err(|e| format!("system D-Bus: {e}"))?;
                tokio::task::spawn_local(watch_signals(conn.clone(), signals));
                Ok(Power::Logind(conn))
            }
            FAKE => {
                let deny = std::env::var("MAIA_SESSION_FAKE_LOGIND").is_ok_and(|v| v == "deny");
                Ok(Power::Fake { deny, signals })
            }
            other => Err(format!("unknown backend \"{other}\" ({LOGIND} or {FAKE})")),
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Power::Logind(_) => LOGIND,
            Power::Fake { .. } => FAKE,
            Power::Unavailable(_) => "unavailable",
        }
    }

    pub async fn capabilities(&self) -> Capabilities {
        let mut caps = Capabilities::NONE;
        for action in Action::ALL {
            let ability = match self {
                Power::Logind(conn) => {
                    let reply = conn.call_method(Some(DEST), PATH, Some(MANAGER), action.can_method(), &()).await;
                    match reply.and_then(|r| r.body().deserialize::<String>()) {
                        Ok(answer) => Ability::from_logind(&answer),
                        Err(error) => {
                            eprintln!("maia-session-service: logind {}: {error}", action.can_method());
                            Ability::No
                        }
                    }
                }
                Power::Fake { .. } => Ability::Yes,
                Power::Unavailable(_) => Ability::No,
            };
            match action {
                Action::PowerOff => caps.power_off = ability,
                Action::Reboot => caps.reboot = ability,
                Action::Suspend => caps.suspend = ability,
                Action::Hibernate => caps.hibernate = ability,
                Action::HybridSleep => caps.hybrid_sleep = ability,
                Action::SuspendThenHibernate => caps.suspend_then_hibernate = ability,
            }
        }
        caps
    }

    /// Asks logind to do it; returns once logind accepted (after the password, when one is asked)
    pub async fn act(&self, action: Action) -> Result<(), PowerError> {
        match self {
            Power::Logind(conn) => {
                // interactive = true: polkit may ask for the administrator's password
                conn.call_method(Some(DEST), PATH, Some(MANAGER), action.method(), &(true,))
                    .await
                    .map(|_| ())
                    .map_err(|error| match &error {
                        zbus::Error::MethodError(name, _, _)
                            if name.as_str().contains("AccessDenied") || name.as_str().contains("NotAuthorized")
                                || name.as_str().contains("Interactive") =>
                        {
                            PowerError::NotAllowed(error.to_string())
                        }
                        _ => PowerError::Failed(error.to_string()),
                    })
            }
            Power::Unavailable(why) => Err(PowerError::Failed(why.clone())),
            Power::Fake { deny, signals } => {
                eprintln!("maia-session-service: fake logind: {}{}", action.method(), if *deny { " (denied)" } else { "" });
                if *deny {
                    return Err(PowerError::NotAllowed("fake logind denies every action".into()));
                }
                if !action.ends_session() {
                    // A short nap, so that the user interface sees both signals
                    let signals = signals.clone();
                    let _ = signals.send(PowerSignal::PrepareForSleep(true));
                    tokio::task::spawn_local(async move {
                        tokio::time::sleep(Duration::from_secs(2)).await;
                        let _ = signals.send(PowerSignal::PrepareForSleep(false));
                    });
                }
                Ok(())
            }
        }
    }
}

async fn watch_signals(conn: Connection, signals: mpsc::UnboundedSender<PowerSignal>) {
    let rule = match MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender(DEST)
        .and_then(|b| b.interface(MANAGER))
        .and_then(|b| b.path(PATH))
    {
        Ok(builder) => builder.build(),
        Err(error) => {
            eprintln!("maia-session-service: logind signals: {error}");
            return;
        }
    };
    let mut stream = match zbus::MessageStream::for_match_rule(rule, &conn, None).await {
        Ok(stream) => stream,
        Err(error) => {
            eprintln!("maia-session-service: logind signals: {error}");
            return;
        }
    };
    while let Some(Ok(message)) = stream.next().await {
        let header = message.header();
        let Some(member) = header.member() else { continue };
        let Ok(value) = message.body().deserialize::<bool>() else { continue };
        let signal = match member.as_str() {
            "PrepareForSleep" => PowerSignal::PrepareForSleep(value),
            "PrepareForShutdown" => PowerSignal::PrepareForShutdown(value),
            _ => continue,
        };
        if signals.send(signal).is_err() {
            break;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn logind_answers() {
        assert_eq!(Ability::from_logind("yes"), Ability::Yes);
        assert_eq!(Ability::from_logind("challenge"), Ability::Challenge);
        assert_eq!(Ability::from_logind("no"), Ability::No);
        assert_eq!(Ability::from_logind("na"), Ability::No);
    }
}

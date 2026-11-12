//! power-profiles-daemon (system D-Bus): the power profile, its holds and why performance is limited.
//!
//! The daemon is known under two names: org.freedesktop.UPower.PowerProfiles (since 0.20) and
//! net.hadess.PowerProfiles (older; newer versions keep it as an alias). The first that has an owner
//! is used. Its properties are read again after every signal it sends.
//!
//! Commands run as tasks of their own, so a profile change waiting for the administrator's password
//! (polkit) holds up neither the daemon's signals nor the other commands.
//!
//! Holds (HoldProfile) belong to the D-Bus connection that made them: the daemon releases them when
//! this service ends, so a crashed client of Maia never leaves a profile held for good.

use std::time::Duration;

use futures::StreamExt;
use tokio::sync::mpsc;
use zbus::proxy::MethodFlags;
use zbus::zvariant::Value;
use zbus::{Connection, MatchRule, MessageStream, Proxy};

use super::dbus::{self, Props, dicts_of, string_of};
use crate::backend::{BackendEvent, Command, ErrorCode, OpError};
use crate::model::{Degradation, HeldProfile, Profile, Profiles};

/// (bus name, object path, interface)
pub const NAMES: [(&str, &str, &str); 2] = [
    ("org.freedesktop.UPower.PowerProfiles", "/org/freedesktop/UPower/PowerProfiles", "org.freedesktop.UPower.PowerProfiles"),
    ("net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "net.hadess.PowerProfiles"),
];

const SETTLE: Duration = Duration::from_millis(30);

/// The daemon's properties as plain values
pub fn profiles_from(props: &Props) -> Profiles {
    let mut offered: Vec<Profile> = dicts_of(props, "Profiles")
        .iter()
        .filter_map(|p| Profile::from_ppd(&string_of(p, "Profile")))
        .collect();
    offered.sort_by_key(|p| *p as u8);
    offered.dedup();
    let holds = dicts_of(props, "ActiveProfileHolds")
        .iter()
        .filter_map(|h| {
            Some(HeldProfile {
                profile: Profile::from_ppd(&string_of(h, "Profile"))?,
                reason: string_of(h, "Reason"),
                application_id: string_of(h, "ApplicationId"),
            })
        })
        .collect();
    Profiles {
        available: true,
        active: Profile::from_ppd(&string_of(props, "ActiveProfile")).unwrap_or(Profile::Balanced),
        offered,
        degraded: Degradation::from_ppd(&string_of(props, "PerformanceDegraded")),
        holds,
    }
}

fn op_error(error: zbus::Error) -> OpError {
    match &error {
        zbus::Error::MethodError(name, _, _)
            if name.as_str().contains("AccessDenied") || name.as_str().contains("NotAuthorized") =>
        {
            OpError::new(ErrorCode::NotAllowed, error.to_string())
        }
        zbus::Error::MethodError(name, _, _) if name.as_str().contains("ServiceUnknown") => {
            OpError::new(ErrorCode::Unavailable, error.to_string())
        }
        _ => OpError::new(ErrorCode::Failed, error.to_string()),
    }
}

struct Source {
    conn: Connection,
    events: mpsc::UnboundedSender<BackendEvent>,
    /// The name in use, from NAMES
    target: Option<(&'static str, &'static str, &'static str)>,
    sent: Option<Profiles>,
}

impl Source {
    async fn refresh(&mut self) {
        self.target = None;
        for name in NAMES {
            if dbus::has_owner(&self.conn, name.0).await {
                self.target = Some(name);
                break;
            }
        }
        let profiles = match self.target {
            Some((dest, path, iface)) => match dbus::get_all(&self.conn, dest, path, iface).await {
                Ok(props) => profiles_from(&props),
                Err(_) => Profiles::unavailable(),
            },
            None => Profiles::unavailable(),
        };
        if self.sent.as_ref() != Some(&profiles) {
            let _ = self.events.send(BackendEvent::Profiles(profiles.clone()));
            self.sent = Some(profiles);
        }
    }
}

type Target = Option<(&'static str, &'static str, &'static str)>;

async fn proxy(conn: &Connection, target: Target) -> Result<Proxy<'static>, OpError> {
    let (dest, path, iface) = target.ok_or_else(|| OpError::new(ErrorCode::Unavailable, "power-profiles-daemon does not run"))?;
    Proxy::new(conn, dest, path, iface).await.map_err(op_error)
}

/// Carries out one command. Runs as a task of its own: setting a profile may wait for the
/// administrator's password (polkit) as long as the dialog is open, and meanwhile the daemon's
/// signals and the other commands go on.
async fn execute(conn: Connection, target: Target, command: Command) {
    match command {
        Command::SetProfile { profile, reply } => {
            let result = async {
                let (dest, path, iface) =
                    target.ok_or_else(|| OpError::new(ErrorCode::Unavailable, "power-profiles-daemon does not run"))?;
                let props = Proxy::new(&conn, dest, path, dbus::PROPERTIES).await.map_err(op_error)?;
                props
                    .call_with_flags::<_, _, ()>(
                        "Set",
                        MethodFlags::AllowInteractiveAuth.into(),
                        &(iface, "ActiveProfile", Value::from(profile.ppd_name())),
                    )
                    .await
                    .map(|_| ())
                    .map_err(op_error)
            }
            .await;
            let _ = reply.send(result);
        }
        Command::HoldProfile { profile, reason, application_id, reply } => {
            let result = async {
                proxy(&conn, target)
                    .await?
                    .call::<_, _, u32>("HoldProfile", &(profile.ppd_name(), reason.as_str(), application_id.as_str()))
                    .await
                    .map_err(op_error)
            }
            .await;
            let _ = reply.send(result);
        }
        Command::ReleaseProfile { cookie } => {
            if let Ok(proxy) = proxy(&conn, target).await {
                if let Err(error) = proxy.call::<_, _, ()>("ReleaseProfile", &(cookie,)).await {
                    eprintln!("maia-power-service: releasing profile hold {cookie}: {error}");
                }
            }
        }
        other => eprintln!("maia-power-service: profiles got a command it does not handle: {other:?}"),
    }
}

pub async fn run(conn: Connection, events: mpsc::UnboundedSender<BackendEvent>, mut commands: mpsc::UnboundedReceiver<Command>) {
    // Signals of either name; and their owners coming and going
    let mut streams = Vec::new();
    for (name, _, _) in NAMES {
        let rule = MatchRule::builder().msg_type(zbus::message::Type::Signal).sender(name).map(|b| b.build());
        let owner = MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .sender("org.freedesktop.DBus")
            .and_then(|b| b.interface("org.freedesktop.DBus"))
            .and_then(|b| b.member("NameOwnerChanged"))
            .and_then(|b| b.arg(0, name))
            .map(|b| b.build());
        for rule in [rule, owner].into_iter().flatten() {
            if let Ok(stream) = MessageStream::for_match_rule(rule, &conn, Some(64)).await {
                streams.push(stream);
            }
        }
    }
    let mut signals = futures::stream::select_all(streams);
    let (done, mut finished) = mpsc::unbounded_channel::<()>();
    let mut source = Source { conn, events, target: None, sent: None };
    source.refresh().await;
    let mut settle: Option<tokio::time::Instant> = None;
    loop {
        tokio::select! {
            Some(_) = signals.next() => {
                settle.get_or_insert(tokio::time::Instant::now() + SETTLE);
            }
            // A command finished: read the state again (the daemon may not signal everything)
            Some(()) = finished.recv() => {
                settle.get_or_insert(tokio::time::Instant::now() + SETTLE);
            }
            _ = async { tokio::time::sleep_until(settle.unwrap()).await }, if settle.is_some() => {
                settle = None;
                source.refresh().await;
            }
            command = commands.recv() => match command {
                Some(command) => {
                    let (conn, target, done) = (source.conn.clone(), source.target, done.clone());
                    tokio::task::spawn_local(async move {
                        execute(conn, target, command).await;
                        let _ = done.send(());
                    });
                }
                None => return,
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use zbus::zvariant::{OwnedValue, Str};

    fn text(value: &str) -> OwnedValue {
        OwnedValue::from(Str::from(value.to_string()))
    }

    fn dict(values: &[(&str, &str)]) -> Props {
        values.iter().map(|(k, v)| (k.to_string(), text(v))).collect()
    }

    #[test]
    fn the_daemon_properties() {
        let mut props = Props::new();
        props.insert("ActiveProfile".into(), text("performance"));
        props.insert("PerformanceDegraded".into(), text("lap-detected"));
        let profiles = vec![
            dict(&[("Profile", "power-saver"), ("Driver", "placeholder")]),
            dict(&[("Profile", "balanced"), ("Driver", "intel_pstate")]),
            dict(&[("Profile", "performance"), ("Driver", "intel_pstate")]),
        ];
        props.insert("Profiles".into(), OwnedValue::try_from(Value::from(profiles)).unwrap());
        let holds = vec![dict(&[("Profile", "performance"), ("Reason", "Compiling"), ("ApplicationId", "org.kde.konsole")])];
        props.insert("ActiveProfileHolds".into(), OwnedValue::try_from(Value::from(holds)).unwrap());

        let p = profiles_from(&props);
        assert!(p.available);
        assert_eq!(p.active, Profile::Performance);
        assert_eq!(p.offered, [Profile::PowerSaver, Profile::Balanced, Profile::Performance]);
        assert_eq!(p.degraded, Degradation::LapDetected);
        assert_eq!(p.holds.len(), 1);
        assert_eq!(p.holds[0].reason, "Compiling");
        assert_eq!(p.holds[0].application_id, "org.kde.konsole");
    }

    #[test]
    fn a_machine_without_performance() {
        let mut props = Props::new();
        props.insert("ActiveProfile".into(), text("balanced"));
        let profiles = vec![dict(&[("Profile", "power-saver")]), dict(&[("Profile", "balanced")])];
        props.insert("Profiles".into(), OwnedValue::try_from(Value::from(profiles)).unwrap());
        let p = profiles_from(&props);
        assert_eq!(p.offered, [Profile::PowerSaver, Profile::Balanced]);
        assert!(p.holds.is_empty());
        assert_eq!(p.degraded, Degradation::None);
    }
}

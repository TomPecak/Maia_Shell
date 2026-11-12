//! The brightness of the built-in panel: the kernel's backlight devices.
//!
//! - Which device: /sys/class/backlight has one or more for a panel; like powerdevil, the first of
//!   type firmware, then platform, then raw is used (the firmware's own interface is the one that
//!   works on most laptops; raw drivers like intel_backlight are the fallback).
//! - Reading: the sysfs attributes brightness and max_brightness.
//! - Writing: systemd-logind's Session.SetBrightness("backlight", <device>, <value>) on the session
//!   of this process: no administrator rights, no helper, and only for the active session (a user in
//!   the background cannot change the screen of the one in front). When logind cannot (an old
//!   systemd), the attribute is written directly if the user may (some distributions give the video
//!   group the right).
//! - Requests are coalesced: while a write runs, newer requests replace each other and only the
//!   last one is written next (a dragged slider sends dozens); every request is answered.
//! - Changes made by others (the brightness keys through powerdevil, the firmware): a write to the
//!   attribute sends no kernel event, so the value is read again every `POLL`; the kernel's uevents
//!   (netlink) tell at once about backlight devices that appear, disappear or change by hardware keys.
//!
//! The sysfs root is $MAIA_POWER_SYSFS_ROOT (tests point it at a directory of their own), "/sys"
//! otherwise.

use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::path::{Path, PathBuf};
use std::time::Duration;

use tokio::io::unix::AsyncFd;
use tokio::sync::mpsc;
use zbus::Connection;

use crate::backend::{BackendEvent, Command, ErrorCode, OpError, Reply};
use crate::model::{Display, DisplayKind};

pub const POLL: Duration = Duration::from_secs(1);
const LOGIND: &str = "org.freedesktop.login1";
const SESSION_PATH: &str = "/org/freedesktop/login1/session/auto";
const SESSION: &str = "org.freedesktop.login1.Session";

pub fn sysfs_root() -> PathBuf {
    std::env::var_os("MAIA_POWER_SYSFS_ROOT").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/sys"))
}

/// A backlight device as found in sysfs
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Device {
    pub name: String,
    pub kind: String,
}

fn read_trimmed(path: &Path) -> Option<String> {
    std::fs::read_to_string(path).ok().map(|s| s.trim().to_string())
}

/// The backlight devices under <root>/class/backlight
pub fn scan(root: &Path) -> Vec<Device> {
    let Ok(entries) = std::fs::read_dir(root.join("class/backlight")) else { return Vec::new() };
    let mut devices: Vec<Device> = entries
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().to_str()?.to_string();
            let kind = read_trimmed(&entry.path().join("type")).unwrap_or_default();
            Some(Device { name, kind })
        })
        .collect();
    devices.sort_by(|a, b| a.name.cmp(&b.name));
    devices
}

/// The device to use: firmware, then platform, then raw (like powerdevil's backlight helper)
pub fn choose(devices: &[Device]) -> Option<&Device> {
    ["firmware", "platform", "raw"].iter().find_map(|kind| devices.iter().find(|d| d.kind == *kind))
}

/// The display of a device now; None when its attributes cannot be read
pub fn read_display(root: &Path, device: &Device) -> Option<Display> {
    let dir = root.join("class/backlight").join(&device.name);
    let raw_max: u32 = read_trimmed(&dir.join("max_brightness"))?.parse().ok()?;
    let raw: u32 = read_trimmed(&dir.join("brightness"))?.parse().ok()?;
    Some(Display {
        id: format!("backlight:{}", device.name),
        kind: DisplayKind::BuiltIn,
        device: device.name.clone(),
        raw: raw.min(raw_max),
        raw_max,
    })
}

/// Requests while a write runs: only the newest value is written, every request is answered
#[derive(Default)]
pub struct Coalescer {
    pending: Option<u32>,
    waiting: Vec<Reply>,
}

impl Coalescer {
    pub fn push(&mut self, raw: u32, reply: Reply) {
        self.pending = Some(raw);
        self.waiting.push(reply);
    }

    /// The value to write next and the requests its result answers
    pub fn take(&mut self) -> Option<(u32, Vec<Reply>)> {
        let raw = self.pending.take()?;
        Some((raw, std::mem::take(&mut self.waiting)))
    }
}

async fn write(conn: Option<&Connection>, root: &Path, device: &str, raw: u32) -> Result<(), OpError> {
    let logind_error = match conn {
        Some(conn) => match conn
            .call_method(Some(LOGIND), SESSION_PATH, Some(SESSION), "SetBrightness", &("backlight", device, raw))
            .await
        {
            Ok(_) => return Ok(()),
            Err(error) => error,
        },
        None => zbus::Error::Failure("no system bus".into()),
    };
    // logind could not: the attribute itself, if this user may write it
    let path = root.join("class/backlight").join(device).join("brightness");
    match tokio::fs::write(&path, raw.to_string()).await {
        Ok(()) => Ok(()),
        Err(_) => {
            let code = match &logind_error {
                zbus::Error::MethodError(name, _, _)
                    if name.as_str().contains("AccessDenied") || name.as_str().contains("NotInControl") =>
                {
                    ErrorCode::NotAllowed
                }
                _ => ErrorCode::Failed,
            };
            Err(OpError::new(code, format!("logind SetBrightness: {logind_error}")))
        }
    }
}

/// The kernel's uevents (netlink), as a readable fd; None where netlink is not allowed
fn uevent_socket() -> Option<AsyncFd<OwnedFd>> {
    // SAFETY: plain socket calls; the fd is owned right after it is created
    unsafe {
        let fd = libc::socket(
            libc::AF_NETLINK,
            libc::SOCK_DGRAM | libc::SOCK_CLOEXEC | libc::SOCK_NONBLOCK,
            libc::NETLINK_KOBJECT_UEVENT,
        );
        if fd < 0 {
            return None;
        }
        let fd = OwnedFd::from_raw_fd(fd);
        let mut address: libc::sockaddr_nl = std::mem::zeroed();
        address.nl_family = libc::AF_NETLINK as u16;
        address.nl_groups = 1; // the kernel's events
        let bound = libc::bind(
            fd.as_raw_fd(),
            &address as *const libc::sockaddr_nl as *const libc::sockaddr,
            std::mem::size_of::<libc::sockaddr_nl>() as u32,
        );
        if bound != 0 {
            return None;
        }
        // SAFETY: the fd is open and owned by the AsyncFd from here on
        AsyncFd::register(fd).ok()
    }
}

/// Whether a uevent message ("ACTION@devpath\0KEY=value\0…") is about a backlight device
pub fn is_backlight_uevent(message: &[u8]) -> bool {
    message.split(|b| *b == 0).any(|field| field == b"SUBSYSTEM=backlight")
}

/// Reads all pending uevents; true when one was about a backlight
fn drain_uevents(fd: &OwnedFd) -> bool {
    let mut buffer = [0u8; 8192];
    let mut backlight = false;
    loop {
        // SAFETY: recv into a buffer of its size
        let n = unsafe { libc::recv(fd.as_raw_fd(), buffer.as_mut_ptr().cast(), buffer.len(), 0) };
        if n <= 0 {
            break;
        }
        backlight |= is_backlight_uevent(&buffer[..n as usize]);
    }
    backlight
}

struct Source {
    root: PathBuf,
    conn: Option<Connection>,
    events: mpsc::UnboundedSender<BackendEvent>,
    device: Option<Device>,
    sent: Option<Display>,
}

impl Source {
    /// Finds the device again (it may come and go) and sends its state when it changed
    fn refresh(&mut self) {
        let device = choose(&scan(&self.root)).cloned();
        let display = device.as_ref().and_then(|d| read_display(&self.root, d));
        if let Some(old) = &self.sent {
            if display.as_ref().map(|d| &d.id) != Some(&old.id) {
                let _ = self.events.send(BackendEvent::DisplayRemoved(old.id.clone()));
                self.sent = None;
            }
        }
        if let Some(display) = display {
            if self.sent.as_ref() != Some(&display) {
                let _ = self.events.send(BackendEvent::Display(display.clone()));
                self.sent = Some(display);
            }
        }
        self.device = device;
    }
}

/// Runs until the command channel closes; root is the sysfs root (sysfs_root(), or a test's)
pub async fn run(
    conn: Option<Connection>,
    root: PathBuf,
    events: mpsc::UnboundedSender<BackendEvent>,
    mut commands: mpsc::UnboundedReceiver<Command>,
) {
    let mut source = Source { root, conn, events, device: None, sent: None };
    source.refresh();
    let uevents = uevent_socket();
    let mut poll = tokio::time::interval(POLL);
    poll.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let mut coalescer = Coalescer::default();
    let mut writing: Option<std::pin::Pin<Box<dyn std::future::Future<Output = Result<(), OpError>>>>> = None;
    let mut answering: Vec<Reply> = Vec::new();

    loop {
        // Start the next write when none runs
        if writing.is_none() {
            if let Some((raw, replies)) = coalescer.take() {
                match source.device.clone() {
                    Some(device) => {
                        let conn = source.conn.clone();
                        let root = source.root.clone();
                        writing = Some(Box::pin(async move { write(conn.as_ref(), &root, &device.name, raw).await }));
                        answering = replies;
                    }
                    None => {
                        for reply in replies {
                            let _ = reply.send(Err(OpError::new(ErrorCode::NotFound, "no backlight device")));
                        }
                    }
                }
            }
        }
        tokio::select! {
            result = async { writing.as_mut().unwrap().await }, if writing.is_some() => {
                writing = None;
                for reply in answering.drain(..) {
                    let _ = reply.send(result.clone());
                }
                source.refresh();
            }
            command = commands.recv() => match command {
                Some(Command::SetBrightness { display_id, raw, reply }) => {
                    let ours = source.sent.as_ref().is_some_and(|d| d.id == display_id);
                    if ours {
                        coalescer.push(raw, reply);
                    } else {
                        let _ = reply.send(Err(OpError::new(ErrorCode::NotFound, format!("no display {display_id}"))));
                    }
                }
                Some(other) => eprintln!("maia-power-service: backlight got a command it does not handle: {other:?}"),
                None => return,
            },
            _ = poll.tick() => source.refresh(),
            ready = async { uevents.as_ref().unwrap().readable().await }, if uevents.is_some() => {
                if let Ok(mut guard) = ready {
                    let backlight = drain_uevents(guard.get_inner());
                    guard.clear_ready();
                    if backlight {
                        source.refresh();
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sysfs(devices: &[(&str, &str, u32, u32)]) -> PathBuf {
        let root = std::env::temp_dir().join(format!("maia-power-sysfs-{}-{}", std::process::id(), rand_suffix()));
        for (name, kind, value, max) in devices {
            let dir = root.join("class/backlight").join(name);
            std::fs::create_dir_all(&dir).unwrap();
            std::fs::write(dir.join("type"), format!("{kind}\n")).unwrap();
            std::fs::write(dir.join("brightness"), format!("{value}\n")).unwrap();
            std::fs::write(dir.join("max_brightness"), format!("{max}\n")).unwrap();
        }
        root
    }

    fn rand_suffix() -> u64 {
        use std::sync::atomic::{AtomicU64, Ordering};
        static N: AtomicU64 = AtomicU64::new(0);
        N.fetch_add(1, Ordering::SeqCst)
    }

    #[test]
    fn firmware_before_platform_before_raw() {
        let root = sysfs(&[("intel_backlight", "raw", 10, 100), ("acpi_video0", "firmware", 5, 15), ("dell", "platform", 1, 7)]);
        let devices = scan(&root);
        assert_eq!(devices.len(), 3);
        assert_eq!(choose(&devices).unwrap().name, "acpi_video0");
        let root2 = sysfs(&[("intel_backlight", "raw", 86400, 96000)]);
        let display = read_display(&root2, choose(&scan(&root2)).unwrap()).unwrap();
        assert_eq!(display.id, "backlight:intel_backlight");
        assert_eq!((display.raw, display.raw_max), (86400, 96000));
        assert_eq!(display.kind, DisplayKind::BuiltIn);
        std::fs::remove_dir_all(root).ok();
        std::fs::remove_dir_all(root2).ok();
    }

    #[test]
    fn no_backlight_on_a_desktop() {
        let root = std::env::temp_dir().join(format!("maia-power-empty-{}", std::process::id()));
        assert!(scan(&root).is_empty());
        assert!(choose(&[]).is_none());
    }

    #[test]
    fn a_broken_attribute_is_no_display() {
        let root = sysfs(&[("x", "raw", 1, 1)]);
        std::fs::write(root.join("class/backlight/x/max_brightness"), "garbage").unwrap();
        assert!(read_display(&root, &Device { name: "x".into(), kind: "raw".into() }).is_none());
        std::fs::remove_dir_all(root).ok();
    }

    #[test]
    fn coalescing_keeps_the_newest_and_answers_all() {
        let mut c = Coalescer::default();
        assert!(c.take().is_none());
        let (a, _ra) = tokio::sync::oneshot::channel();
        let (b, _rb) = tokio::sync::oneshot::channel();
        let (d, _rd) = tokio::sync::oneshot::channel();
        c.push(10, a);
        c.push(20, b);
        c.push(30, d);
        let (raw, replies) = c.take().unwrap();
        assert_eq!(raw, 30);
        assert_eq!(replies.len(), 3);
        assert!(c.take().is_none());
    }

    #[test]
    fn uevents_of_backlights() {
        assert!(is_backlight_uevent(b"change@/devices/pci/backlight/intel_backlight\0ACTION=change\0SUBSYSTEM=backlight\0"));
        assert!(!is_backlight_uevent(b"change@/devices/pci/power_supply/BAT0\0ACTION=change\0SUBSYSTEM=power_supply\0"));
    }
}

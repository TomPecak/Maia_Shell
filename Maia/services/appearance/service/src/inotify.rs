//! Watching directories without blocking (Linux inotify on the tokio reactor).
//!
//! Used to notice what other programs change: kwinrc written by KDE's own settings, themes
//! installed by KDE's "Get New Decorations". Events come in bursts (an atomic save is a create
//! and a rename), so consumers wait a little after the first one (`settle`) and then re-read.

use std::ffi::{CString, OsStr, OsString};
use std::io;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::ffi::OsStrExt;
use std::path::Path;
use std::time::Duration;

use tokio::io::unix::AsyncFd;

pub struct Watcher {
    fd: AsyncFd<OwnedFd>,
}

impl Watcher {
    pub fn new() -> io::Result<Watcher> {
        // SAFETY: inotify_init1 has no preconditions; the result is checked
        #[allow(unsafe_code)]
        let raw = unsafe { libc::inotify_init1(libc::IN_NONBLOCK | libc::IN_CLOEXEC) };
        if raw < 0 {
            return Err(io::Error::last_os_error());
        }
        // SAFETY: raw is a new, valid descriptor owned by nobody else
        #[allow(unsafe_code)]
        let fd = unsafe { OwnedFd::from_raw_fd(raw) };
        // SAFETY: the OwnedFd is moved into the AsyncFd and stays open (and the same) until it drops
        #[allow(unsafe_code)]
        let fd = unsafe { AsyncFd::register_with_interest(fd, tokio::io::Interest::READABLE) }.map_err(|e| e.into_parts().1)?;
        Ok(Watcher { fd })
    }

    /// Watches a directory for files created, written, moved or removed in it (not recursive).
    /// A directory that does not exist is skipped (false).
    pub fn add_dir(&self, dir: &Path) -> bool {
        let Ok(path) = CString::new(dir.as_os_str().as_bytes()) else { return false };
        let mask = libc::IN_CLOSE_WRITE | libc::IN_MOVED_TO | libc::IN_MOVED_FROM | libc::IN_CREATE | libc::IN_DELETE;
        // SAFETY: path is a valid C string, the descriptor is ours
        #[allow(unsafe_code)]
        let watch = unsafe { libc::inotify_add_watch(self.fd.as_raw_fd(), path.as_ptr(), mask) };
        watch >= 0
    }

    /// Waits for the next burst of events about names `accept` takes: returns after the first
    /// such event plus `settle` of quiet (what comes in between belongs to the same burst)
    pub async fn next_burst(&self, settle: Duration, accept: impl Fn(&OsStr) -> bool) -> io::Result<()> {
        loop {
            self.wait_readable().await?;
            if self.drain()?.iter().any(|name| accept(name)) {
                break;
            }
        }
        loop {
            match tokio::time::timeout(settle, self.wait_readable()).await {
                Ok(result) => {
                    result?;
                    self.drain()?;
                }
                Err(_) => return Ok(()),
            }
        }
    }

    async fn wait_readable(&self) -> io::Result<()> {
        loop {
            let mut guard = self.fd.readable().await?;
            if Self::pending(guard.get_inner())? {
                return Ok(());
            }
            guard.clear_ready();
        }
    }

    fn pending(fd: &OwnedFd) -> io::Result<bool> {
        let mut available: libc::c_int = 0;
        // SAFETY: FIONREAD writes one int
        #[allow(unsafe_code)]
        let result = unsafe { libc::ioctl(fd.as_raw_fd(), libc::FIONREAD, &mut available) };
        if result < 0 { Err(io::Error::last_os_error()) } else { Ok(available > 0) }
    }

    /// Reads the waiting events; returns the file names they are about
    fn drain(&self) -> io::Result<Vec<OsString>> {
        let mut names = Vec::new();
        let mut buffer = [0u8; 8192];
        loop {
            // SAFETY: the buffer is valid for its length
            #[allow(unsafe_code)]
            let read = unsafe { libc::read(self.fd.as_raw_fd(), buffer.as_mut_ptr().cast(), buffer.len()) };
            if read < 0 {
                let error = io::Error::last_os_error();
                return if error.kind() == io::ErrorKind::WouldBlock { Ok(names) } else { Err(error) };
            }
            if read == 0 {
                return Ok(names);
            }
            // struct inotify_event { int wd; uint32_t mask, cookie, len; char name[len]; }
            let mut at = 0usize;
            let read = read as usize;
            while at + 16 <= read {
                let len = u32::from_ne_bytes(buffer[at + 12..at + 16].try_into().expect("4 bytes")) as usize;
                let name = &buffer[at + 16..(at + 16 + len).min(read)];
                let end = name.iter().position(|b| *b == 0).unwrap_or(name.len());
                names.push(OsStr::from_bytes(&name[..end]).to_os_string());
                at += 16 + len;
            }
        }
    }
}

//! Processes: starting them, reaping them, ending them.
//!
//! - Every child runs in its own process group and gets SIGTERM when this service dies
//!   (PR_SET_PDEATHSIG), so nothing of a session outlives it. PDEATHSIG belongs to the thread that
//!   forked: children are started only from the main thread (the runtime is current_thread).
//! - The service is a child subreaper (PR_SET_CHILD_SUBREAPER): processes orphaned inside the
//!   session (Wayfire's [autostart] forks twice, maia-windows-service starts applications in their
//!   own process groups) end up here, not at systemd --user, and are reaped here.
//! - Children are reaped with waitpid(-1) after SIGCHLD, so every exit is seen, also of processes
//!   this service did not start itself. Nothing else in the process may wait for children
//!   (no std::process::Child::wait, no tokio::process).
//! - The output of a child goes to the log of the session (the service's stderr) line by line, with
//!   the name of the child in front: "[maia-network-service] …".

use std::collections::BTreeMap;
use std::io::{BufRead, BufReader, Read};
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};

pub type Pid = i32;

/// How a process ended
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Exit {
    Code(i32),
    Signal(i32),
}

impl Exit {
    pub fn success(&self) -> bool {
        *self == Exit::Code(0)
    }

    pub fn describe(&self) -> String {
        match self {
            Exit::Code(code) => format!("exit code {code}"),
            Exit::Signal(signal) => format!("signal {signal} ({})", signal_name(*signal)),
        }
    }
}

pub fn signal_name(signal: i32) -> &'static str {
    match signal {
        libc::SIGHUP => "SIGHUP",
        libc::SIGINT => "SIGINT",
        libc::SIGQUIT => "SIGQUIT",
        libc::SIGILL => "SIGILL",
        libc::SIGTRAP => "SIGTRAP",
        libc::SIGABRT => "SIGABRT",
        libc::SIGBUS => "SIGBUS",
        libc::SIGFPE => "SIGFPE",
        libc::SIGKILL => "SIGKILL",
        libc::SIGSEGV => "SIGSEGV",
        libc::SIGPIPE => "SIGPIPE",
        libc::SIGTERM => "SIGTERM",
        _ => "?",
    }
}

/// Makes this process the subreaper of everything started below it
pub fn become_subreaper() -> std::io::Result<()> {
    // SAFETY: prctl with integer arguments only
    if unsafe { libc::prctl(libc::PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0) } != 0 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(())
}

/// The full environment of a child
pub type Environment = BTreeMap<String, String>;

/// Where the output of a child goes
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Output {
    /// Into the log, each line marked with the child's name
    Forward,
    /// Nowhere (tools whose answer is their exit code)
    Discard,
}

/// Starts `program` with `args` and exactly `env`; `name` marks its output in the log
pub fn spawn(name: &str, program: &str, args: &[String], env: &Environment, output: Output) -> std::io::Result<Pid> {
    let mut command = Command::new(program);
    command.args(args).env_clear().envs(env).stdin(Stdio::null());
    match output {
        Output::Forward => command.stdout(Stdio::piped()).stderr(Stdio::piped()),
        Output::Discard => command.stdout(Stdio::null()).stderr(Stdio::null()),
    };
    // SAFETY: getpid before the fork; in the child only async-signal-safe calls
    let parent = unsafe { libc::getpid() };
    unsafe {
        command.pre_exec(move || {
            if libc::setpgid(0, 0) != 0 {
                return Err(std::io::Error::last_os_error());
            }
            if libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM, 0, 0, 0) != 0 {
                return Err(std::io::Error::last_os_error());
            }
            // The service died before prctl: the signal would never come
            if libc::getppid() != parent {
                libc::_exit(1);
            }
            Ok(())
        });
    }
    let mut child = command.spawn()?;
    let pid = child.id() as Pid;
    if output == Output::Forward {
        if let Some(out) = child.stdout.take() {
            forward(name, out);
        }
        if let Some(err) = child.stderr.take() {
            forward(name, err);
        }
    }
    // Not waited for through Child: reap() sees its exit
    drop(child);
    Ok(pid)
}

/// Copies the lines of a child's pipe to the log, until the child closes it
fn forward(name: &str, pipe: impl Read + Send + 'static) {
    let prefix = format!("[{name}] ");
    let _ = std::thread::Builder::new().name(format!("log {name}")).spawn(move || {
        let mut reader = BufReader::new(pipe);
        let mut line = Vec::new();
        loop {
            line.clear();
            match reader.read_until(b'\n', &mut line) {
                Ok(0) | Err(_) => break,
                Ok(_) => {
                    while line.last().is_some_and(|b| *b == b'\n' || *b == b'\r') {
                        line.pop();
                    }
                    eprintln!("{prefix}{}", String::from_utf8_lossy(&line));
                }
            }
        }
    });
}

/// Every child that has ended since the last call (also orphans this service adopted)
pub fn reap() -> Vec<(Pid, Exit)> {
    let mut ended = Vec::new();
    loop {
        let mut status = 0;
        // SAFETY: waitpid with a valid pointer
        let pid = unsafe { libc::waitpid(-1, &mut status, libc::WNOHANG) };
        if pid <= 0 {
            break;
        }
        let exit = if libc::WIFEXITED(status) {
            Exit::Code(libc::WEXITSTATUS(status))
        } else if libc::WIFSIGNALED(status) {
            Exit::Signal(libc::WTERMSIG(status))
        } else {
            continue;
        };
        ended.push((pid, exit));
    }
    ended
}

/// Sends `signal` to the process
pub fn signal(pid: Pid, signal: i32) {
    if pid > 0 {
        // SAFETY: kill with plain values
        unsafe { libc::kill(pid, signal) };
    }
}

/// Sends `signal` to the process group of `pid` (every child leads its own group)
pub fn signal_group(pid: Pid, signal: i32) {
    if pid > 0 {
        // SAFETY: kill with plain values
        unsafe { libc::kill(-pid, signal) };
    }
}

/// The processes whose parent is `parent` (from /proc)
pub fn children_of(parent: Pid) -> Vec<Pid> {
    let Ok(entries) = std::fs::read_dir("/proc") else { return Vec::new() };
    let mut out = Vec::new();
    for entry in entries.flatten() {
        let Some(pid) = entry.file_name().to_str().and_then(|s| s.parse::<Pid>().ok()) else { continue };
        let Ok(stat) = std::fs::read_to_string(entry.path().join("stat")) else { continue };
        if parent_of_stat(&stat) == Some(parent) {
            out.push(pid);
        }
    }
    out
}

/// The parent from /proc/<pid>/stat: "pid (name) state ppid …"; the name may contain ") "
fn parent_of_stat(stat: &str) -> Option<Pid> {
    let after = &stat[stat.rfind(')')? + 1..];
    after.split_whitespace().nth(1)?.parse().ok()
}

/// The first of `candidates` that is an executable file
pub fn first_executable(candidates: &[String]) -> Option<String> {
    use std::os::unix::fs::PermissionsExt;
    candidates
        .iter()
        .find(|path| {
            std::fs::metadata(path).map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0).unwrap_or(false)
        })
        .cloned()
}

/// `program` found in PATH, or as given when it contains a slash
pub fn find_program(program: &str, path: Option<&str>) -> Option<String> {
    if program.contains('/') {
        return first_executable(&[program.to_string()]);
    }
    let candidates: Vec<String> = path.unwrap_or("/usr/local/bin:/usr/bin:/bin").split(':').filter(|d| !d.is_empty())
        .map(|dir| format!("{dir}/{program}")).collect();
    first_executable(&candidates)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stat_with_a_strange_name() {
        assert_eq!(parent_of_stat("42 (a) b) S 7 42 42 0"), Some(7));
        assert_eq!(parent_of_stat("1 (systemd) S 0 1 1 0"), Some(0));
        assert_eq!(parent_of_stat("garbage"), None);
    }

    #[test]
    fn exits_in_words() {
        assert_eq!(Exit::Code(1).describe(), "exit code 1");
        assert_eq!(Exit::Signal(11).describe(), "signal 11 (SIGSEGV)");
        assert!(Exit::Code(0).success() && !Exit::Signal(15).success());
    }

    #[test]
    fn programs_in_path() {
        assert!(find_program("sh", Some("/usr/bin:/bin")).is_some());
        assert_eq!(find_program("no-such-program-maia", Some("/usr/bin")), None);
        assert_eq!(find_program("/bin/sh", None).as_deref(), Some("/bin/sh"));
    }
}

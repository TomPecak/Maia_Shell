//! session.toml: what a session runs, read once at the start (the format is described in the
//! installed file itself, Maia/DeployFiles/etc/maia/session.toml).
//!
//! Every value is expanded (expand.rs) while reading, so a mistake is reported before anything
//! starts, with the name of the entry.

use std::collections::BTreeMap;
use std::path::Path;
use std::time::Duration;

use serde::Deserialize;

use crate::expand::expand;

pub const FORMAT_VERSION: u32 = 1;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Ready {
    /// The ready helper is appended to the command (KWin starts it as an application)
    Argument,
    /// The compositor's configuration runs $MAIA_SESSION_SCRIPT (Wayfire's [autostart])
    Autostart,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Kind {
    Shell,
    MaiaService,
    KdeService,
    Helper,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Restart {
    Always,
    OnFailure,
    Never,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum GiveUpAction {
    /// The session cannot go on without it (the shell)
    EndSession,
    /// The session goes on without it
    Stop,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GiveUp {
    pub crashes: u32,
    /// Seconds
    pub within: u64,
    pub then: GiveUpAction,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawCompositor {
    command: Vec<String>,
    ready: Ready,
    ready_timeout: Option<u64>,
    stop_timeout: Option<u64>,
    #[serde(default)]
    environment: BTreeMap<String, String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawProcess {
    name: String,
    kind: Kind,
    #[serde(default)]
    command: Vec<String>,
    #[serde(default)]
    search: Vec<String>,
    unit: Option<String>,
    autostart: Option<String>,
    compositors: Option<Vec<String>>,
    skip_if_bus_name: Option<String>,
    #[serde(default)]
    environment: BTreeMap<String, String>,
    #[serde(default)]
    unset_environment: Vec<String>,
    restart: Option<Restart>,
    give_up: Option<GiveUp>,
    max_delay: Option<u64>,
    stop_timeout: Option<u64>,
    test_mode: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawManifest {
    version: u32,
    compositor: BTreeMap<String, RawCompositor>,
    #[serde(default)]
    process: Vec<RawProcess>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Compositor {
    pub name: String,
    pub command: Vec<String>,
    pub ready: Ready,
    pub ready_timeout: Duration,
    pub stop_timeout: Duration,
    pub environment: BTreeMap<String, String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Process {
    pub name: String,
    pub kind: Kind,
    /// Empty for a systemd unit
    pub command: Vec<String>,
    pub search: Vec<String>,
    pub unit: Option<String>,
    pub autostart: Option<String>,
    /// Empty: under every compositor
    pub compositors: Vec<String>,
    pub skip_if_bus_name: Option<String>,
    pub environment: BTreeMap<String, String>,
    pub unset_environment: Vec<String>,
    pub restart: Restart,
    pub give_up: Option<GiveUp>,
    pub max_delay: Duration,
    pub stop_timeout: Duration,
    /// Started when MAIA_SESSION_TEST=1
    pub test_mode: bool,
}

impl Process {
    pub fn runs_under(&self, compositor: &str) -> bool {
        self.compositors.is_empty() || self.compositors.iter().any(|c| c == compositor)
    }

    pub fn is_unit(&self) -> bool {
        self.unit.is_some()
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Manifest {
    pub compositors: BTreeMap<String, Compositor>,
    /// In the order of the file: the order of the start
    pub processes: Vec<Process>,
}

impl Manifest {
    pub fn load(path: &Path, lookup: &dyn Fn(&str) -> Option<String>) -> Result<Manifest, String> {
        let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
        Manifest::parse(&text, lookup).map_err(|e| format!("{}: {e}", path.display()))
    }

    pub fn parse(text: &str, lookup: &dyn Fn(&str) -> Option<String>) -> Result<Manifest, String> {
        let raw: RawManifest = toml::from_str(text).map_err(|e| e.to_string())?;
        if raw.version != FORMAT_VERSION {
            return Err(format!("version {} is not supported (this service reads version {FORMAT_VERSION})", raw.version));
        }
        let x = |what: &str, value: &str| expand(value, lookup).map_err(|e| format!("{what}: {e}"));
        let xs = |what: &str, values: &[String]| values.iter().map(|v| x(what, v)).collect::<Result<Vec<_>, _>>();
        let xmap = |what: &str, values: &BTreeMap<String, String>| {
            values
                .iter()
                .map(|(k, v)| Ok((k.clone(), x(what, v)?)))
                .collect::<Result<BTreeMap<_, _>, String>>()
        };

        let mut compositors = BTreeMap::new();
        for (name, c) in raw.compositor {
            let what = format!("compositor.{name}");
            if c.command.is_empty() {
                return Err(format!("{what}: the command is empty"));
            }
            compositors.insert(name.clone(), Compositor {
                command: xs(&what, &c.command)?,
                ready: c.ready,
                ready_timeout: Duration::from_secs(c.ready_timeout.unwrap_or(20)),
                stop_timeout: Duration::from_secs(c.stop_timeout.unwrap_or(5)),
                environment: xmap(&what, &c.environment)?,
                name,
            });
        }

        let mut processes: Vec<Process> = Vec::new();
        for p in raw.process {
            let what = format!("process \"{}\"", p.name);
            if p.name.is_empty() {
                return Err("a process without a name".into());
            }
            if processes.iter().any(|other| other.name == p.name) {
                return Err(format!("{what} is there twice"));
            }
            match (p.kind, &p.unit, p.command.is_empty()) {
                (Kind::KdeService, Some(_), true) => {}
                (Kind::KdeService, _, _) => return Err(format!("{what}: a kde-service has a unit and no command")),
                (_, Some(_), _) => return Err(format!("{what}: only a kde-service has a unit")),
                (_, None, true) => return Err(format!("{what}: the command is empty")),
                _ => {}
            }
            if let Some(give_up) = &p.give_up {
                if give_up.crashes == 0 || give_up.within == 0 {
                    return Err(format!("{what}: give_up needs crashes and within above 0"));
                }
            }
            processes.push(Process {
                command: xs(&what, &p.command)?,
                search: xs(&what, &p.search)?,
                unit: p.unit,
                autostart: p.autostart,
                compositors: p.compositors.unwrap_or_default(),
                skip_if_bus_name: p.skip_if_bus_name,
                environment: xmap(&what, &p.environment)?,
                unset_environment: p.unset_environment,
                restart: p.restart.unwrap_or(Restart::Never),
                give_up: p.give_up,
                max_delay: Duration::from_secs(p.max_delay.unwrap_or(30).max(1)),
                stop_timeout: Duration::from_secs(p.stop_timeout.unwrap_or(5)),
                test_mode: p.test_mode.unwrap_or(true),
                kind: p.kind,
                name: p.name,
            });
        }
        Ok(Manifest { compositors, processes })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn env(name: &str) -> Option<String> {
        match name {
            "MAIA_PREFIX" => Some("/opt/Maia/Maia_0.2.0".into()),
            "MAIA_VERSION" => Some("0.2.0".into()),
            "MAIA_CONFIG_DIR" => Some("/home/u/.config/maia/0.2.0".into()),
            "HOME" => Some("/home/u".into()),
            _ => None,
        }
    }

    /// The file that is installed must always be readable
    #[test]
    fn the_installed_manifest() {
        let text = include_str!("../../../../DeployFiles/etc/maia/session.toml");
        let manifest = Manifest::parse(text, &env).expect("session.toml");
        let kwin = &manifest.compositors["kwin"];
        assert_eq!(kwin.ready, Ready::Argument);
        assert_eq!(manifest.compositors["wayfire"].command,
                   ["wayfire", "-c", "/home/u/.config/maia/0.2.0/wayfire.ini"]);
        // Under KWin: the shell last, the services before it
        let under_kwin: Vec<_> = manifest.processes.iter().filter(|p| p.runs_under("kwin")).collect();
        assert_eq!(under_kwin.last().map(|p| p.name.as_str()), Some("appMaiaServer"));
        let shell = *under_kwin.last().unwrap();
        assert_eq!(shell.kind, Kind::Shell);
        assert_eq!(shell.command[0], "/opt/Maia/Maia_0.2.0/bin/appMaiaServer");
        assert_eq!(shell.environment["MAIA_LOG_FILE"], "/home/u/maia_0.2.0_server.log");
        assert!(shell.give_up.is_some());
        let appearance = manifest.processes.iter().find(|p| p.name == "maia-appearance-service").unwrap();
        assert!(appearance.runs_under("kwin") && !appearance.runs_under("wayfire"));
        let kwallet = manifest.processes.iter().find(|p| p.name == "plasma-kwallet-pam").unwrap();
        assert!(kwallet.is_unit() && !kwallet.test_mode);
        // Only in the nested session; its shell code keeps its own $variables
        let env_file = manifest.processes.iter().find(|p| p.name == "nested-env-file").unwrap();
        assert!(env_file.runs_under("kwin-nested") && !env_file.runs_under("kwin"));
        assert!(env_file.command[2].contains("> \"$MAIA_NESTED_ENV_FILE\""), "{}", env_file.command[2]);
    }

    #[test]
    fn mistakes_name_the_entry() {
        let base = "version = 1\n[compositor.k]\ncommand = [\"k\"]\nready = \"argument\"\n";
        let e = Manifest::parse(&format!("{base}[[process]]\nname = \"a\"\nkind = \"helper\"\n"), &env).unwrap_err();
        assert!(e.contains("process \"a\"") && e.contains("empty"), "{e}");
        let e = Manifest::parse(&format!("{base}[[process]]\nname = \"a\"\nkind = \"kde-service\"\ncommand = [\"x\"]\n"), &env)
            .unwrap_err();
        assert!(e.contains("unit"), "{e}");
        let twice = format!("{base}[[process]]\nname = \"a\"\nkind = \"helper\"\ncommand = [\"x\"]\n");
        let e = Manifest::parse(&format!("{twice}{}", &twice[base.len()..]), &env).unwrap_err();
        assert!(e.contains("twice"), "{e}");
        let e = Manifest::parse("version = 2\n[compositor]\n", &env).unwrap_err();
        assert!(e.contains("version 2"), "{e}");
        let e = Manifest::parse(&format!("{base}[[process]]\nname = \"a\"\nkind = \"helper\"\ncommand = [\"x\"]\nrestrat = \"always\"\n"), &env)
            .unwrap_err();
        assert!(e.contains("restrat"), "{e}");
    }
}

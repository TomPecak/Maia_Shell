//! Installing and removing the user's own decoration themes.
//!
//! What can be installed: an Aurorae SVG theme (a directory with metadata.desktop and
//! decoration.svg or .svgz), given as a directory or an archive (.tar.gz/.tgz, .tar.xz, .tar.zst,
//! .tar.bz2, .tar, .zip; KDE Store themes are such archives). Aurorae QML themes are refused: they
//! are programs run inside the compositor, not pictures.
//!
//! The archive is untrusted. Before anything is unpacked its listing is checked (only files and
//! directories, no absolute paths or "..", at most MAX_FILES entries and MAX_BYTES), it is unpacked
//! by the system's tar or unzip into a private staging directory, the result is checked again
//! (no links, nothing special, the same limits), and only then the theme is moved into
//! `$XDG_DATA_HOME/aurorae/themes/<name>` with one rename. The staging directory lives next to
//! it (same filesystem) and is always removed.
//!
//! Everything is asynchronous: tar and unzip run through tokio::process, the tree walks through
//! spawn_blocking.

use std::collections::HashSet;
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use tokio::process::Command;

use super::theme::{Engine, Origin, Theme, ThemeId};
use crate::error::{ErrorCode, OpError, OpResult};
use crate::paths::Paths;

pub const MAX_FILES: usize = 2000;
pub const MAX_BYTES: u64 = 64 * 1024 * 1024;
const MAX_DEPTH: usize = 8;
const TOOL_TIMEOUT: Duration = Duration::from_secs(60);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Archive {
    Tar,
    Zip,
}

fn archive_kind(path: &Path) -> Option<Archive> {
    let name = path.file_name()?.to_str()?.to_ascii_lowercase();
    if name.ends_with(".zip") {
        Some(Archive::Zip)
    } else if [".tar", ".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.zst", ".tzst", ".tar.bz2", ".tbz2"].iter().any(|s| name.ends_with(s)) {
        Some(Archive::Tar)
    } else {
        None
    }
}

/// The archive's name without its extensions ("Sweet-dark.tar.gz" -> "Sweet-dark")
fn archive_stem(path: &Path) -> String {
    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("theme");
    let lower = name.to_ascii_lowercase();
    for suffix in [".tar.gz", ".tar.xz", ".tar.zst", ".tar.bz2", ".tgz", ".txz", ".tzst", ".tbz2", ".tar", ".zip"] {
        if lower.ends_with(suffix) {
            return name[..name.len() - suffix.len()].to_string();
        }
    }
    name.to_string()
}

/// A theme name usable as a directory name and in kwinrc
pub fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 100
        && !name.starts_with('.')
        && name.chars().all(|c| c.is_alphanumeric() || " -_.+()".contains(c))
}

/// An entry name of an archive that stays inside it
fn safe_entry(name: &str) -> bool {
    if name.is_empty() || name.len() > 512 || name.contains('\\') || name.chars().any(char::is_control) {
        return false;
    }
    let path = Path::new(name);
    path.components().count() <= MAX_DEPTH + 1
        && path.components().all(|c| matches!(c, Component::Normal(_) | Component::CurDir))
}

async fn run(program: &str, args: &[&std::ffi::OsStr]) -> OpResult<String> {
    let mut command = Command::new(program);
    command.args(args).env("LC_ALL", "C").stdin(std::process::Stdio::null()).kill_on_drop(true);
    let output = tokio::time::timeout(TOOL_TIMEOUT, command.output())
        .await
        .map_err(|_| OpError::failed(format!("{program} took too long")))?
        .map_err(|e| OpError::new(ErrorCode::NotSupported, format!("running {program}: {e}")))?;
    if !output.status.success() {
        let error = String::from_utf8_lossy(&output.stderr);
        return Err(OpError::invalid(format!("{program} refused the archive: {}", error.trim())));
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

/// (type character of `ls -l`, size) of each entry of a verbose listing
fn verbose_entries(listing: &str, size_field: usize) -> Vec<(char, u64)> {
    listing
        .lines()
        .filter_map(|line| {
            let fields: Vec<&str> = line.split_whitespace().collect();
            let mode = *fields.first()?;
            if mode.len() != 10 || !"-dlhbcps?".contains(mode.chars().next()?) {
                return None;
            }
            Some((mode.chars().next()?, fields.get(size_field)?.parse().unwrap_or(u64::MAX)))
        })
        .collect()
}

/// Checks the listing of an archive before it is unpacked
async fn check_listing(kind: Archive, file: &Path) -> OpResult {
    let f = file.as_os_str();
    let (names, verbose, size_field) = match kind {
        Archive::Tar => {
            let names = run("tar", &["--list".as_ref(), "--file".as_ref(), f]).await?;
            let verbose = run("tar", &["--list".as_ref(), "--verbose".as_ref(), "--file".as_ref(), f]).await?;
            (names, verbose, 2)
        }
        Archive::Zip => {
            let names = run("unzip", &["-Z1".as_ref(), f]).await?;
            let verbose = run("unzip", &["-Z".as_ref(), f]).await?;
            (names, verbose, 3)
        }
    };
    let names: Vec<&str> = names.lines().filter(|l| !l.is_empty()).collect();
    let entries = verbose_entries(&verbose, size_field);
    if names.is_empty() {
        return Err(OpError::invalid("the archive is empty"));
    }
    if names.len() > MAX_FILES {
        return Err(OpError::invalid(format!("more than {MAX_FILES} entries")));
    }
    if entries.len() != names.len() {
        return Err(OpError::invalid("the archive listing could not be read"));
    }
    if let Some(bad) = names.iter().find(|n| !safe_entry(n)) {
        return Err(OpError::invalid(format!("entry \"{bad}\" leaves the archive")));
    }
    if let Some((kind, _)) = entries.iter().find(|(kind, _)| *kind != '-' && *kind != 'd') {
        return Err(OpError::invalid(format!("the archive holds a link or a special file ({kind})")));
    }
    let total: u64 = entries.iter().map(|(_, size)| *size).fold(0u64, u64::saturating_add);
    if total > MAX_BYTES {
        return Err(OpError::invalid(format!("more than {} MB unpacked", MAX_BYTES / 1024 / 1024)));
    }
    Ok(())
}

async fn unpack(kind: Archive, file: &Path, into: &Path) -> OpResult {
    match kind {
        Archive::Tar => {
            let args: [&std::ffi::OsStr; 7] = [
                "--extract".as_ref(),
                "--file".as_ref(),
                file.as_os_str(),
                "--directory".as_ref(),
                into.as_os_str(),
                "--no-same-owner".as_ref(),
                "--no-same-permissions".as_ref(),
            ];
            run("tar", &args).await.map(|_| ())
        }
        Archive::Zip => run("unzip", &["-qq".as_ref(), "-o".as_ref(), file.as_os_str(), "-d".as_ref(), into.as_os_str()]).await.map(|_| ()),
    }
}

/// Walks a tree (blocking): only files and directories, within the limits
fn check_tree(root: &Path) -> OpResult {
    let mut files = 0usize;
    let mut bytes = 0u64;
    let mut stack = vec![(root.to_path_buf(), 0usize)];
    while let Some((dir, depth)) = stack.pop() {
        if depth > MAX_DEPTH {
            return Err(OpError::invalid("the theme is nested too deep"));
        }
        let entries = std::fs::read_dir(&dir).map_err(|e| OpError::io("reading the theme", e))?;
        for entry in entries {
            let entry = entry.map_err(|e| OpError::io("reading the theme", e))?;
            let metadata = entry.path().symlink_metadata().map_err(|e| OpError::io("reading the theme", e))?;
            files += 1;
            if metadata.is_dir() {
                stack.push((entry.path(), depth + 1));
            } else if metadata.is_file() {
                bytes = bytes.saturating_add(metadata.len());
            } else {
                return Err(OpError::invalid(format!("{} is a link or a special file", entry.path().display())));
            }
        }
        if files > MAX_FILES || bytes > MAX_BYTES {
            return Err(OpError::invalid("the theme is too large"));
        }
    }
    Ok(())
}

/// Copies a checked directory tree (blocking)
fn copy_tree(from: &Path, to: &Path) -> OpResult {
    std::fs::create_dir_all(to).map_err(|e| OpError::io("copying the theme", e))?;
    for entry in std::fs::read_dir(from).map_err(|e| OpError::io("copying the theme", e))? {
        let entry = entry.map_err(|e| OpError::io("copying the theme", e))?;
        let target = to.join(entry.file_name());
        if entry.file_type().map_err(|e| OpError::io("copying the theme", e))?.is_dir() {
            copy_tree(&entry.path(), &target)?;
        } else {
            std::fs::copy(entry.path(), &target).map_err(|e| OpError::io("copying the theme", e))?;
        }
    }
    Ok(())
}

/// The directory of the theme in an unpacked tree (blocking): the one directory with
/// metadata.desktop and decoration.svg(z), at most two levels down
fn find_theme_root(staging: &Path) -> OpResult<PathBuf> {
    let mut roots = Vec::new();
    let mut qml = false;
    let mut stack = vec![(staging.to_path_buf(), 0usize)];
    while let Some((dir, depth)) = stack.pop() {
        let has = |name: &str| dir.join(name).is_file();
        if has("metadata.desktop") && (has("decoration.svg") || has("decoration.svgz")) {
            roots.push(dir.clone());
            continue;
        }
        if has("metadata.json") && std::fs::read_to_string(dir.join("metadata.json")).is_ok_and(|t| t.contains("KWin/Decoration")) {
            qml = true;
        }
        if depth < 2 {
            if let Ok(entries) = std::fs::read_dir(&dir) {
                for entry in entries.flatten() {
                    if entry.file_type().is_ok_and(|t| t.is_dir()) {
                        stack.push((entry.path(), depth + 1));
                    }
                }
            }
        }
    }
    match roots.len() {
        1 => Ok(roots.remove(0)),
        0 if qml => Err(OpError::new(
            ErrorCode::NotSupported,
            "an Aurorae QML theme: it would run its code inside the compositor, so it is not installed",
        )),
        0 => Err(OpError::invalid("no Aurorae theme (metadata.desktop and decoration.svg) in it")),
        _ => Err(OpError::invalid("more than one theme in it; install them one by one")),
    }
}

static STAGING_COUNTER: AtomicU64 = AtomicU64::new(0);

fn staging_dir(paths: &Paths, purpose: &str) -> PathBuf {
    let n = STAGING_COUNTER.fetch_add(1, Ordering::Relaxed);
    paths.data_home.join("aurorae").join(format!(".maia-{purpose}-{}-{n}", std::process::id()))
}

async fn blocking<T: Send + 'static>(f: impl FnOnce() -> OpResult<T> + Send + 'static) -> OpResult<T> {
    tokio::task::spawn_blocking(f).await.map_err(|e| OpError::failed(format!("worker failed: {e}")))?
}

/// Installs a theme for the user. `taken`: the names of the Aurorae themes that exist (any origin).
pub async fn install(paths: &Paths, source: &Path, taken: &HashSet<String>) -> OpResult<ThemeId> {
    let metadata = tokio::fs::metadata(source).await.map_err(|e| OpError::io(&format!("{}", source.display()), e))?;
    let staging = staging_dir(paths, "install");
    tokio::fs::create_dir_all(&staging).await.map_err(|e| OpError::io("creating the staging directory", e))?;
    let result = install_staged(paths, source, metadata.is_dir(), &staging, taken).await;
    let _ = tokio::fs::remove_dir_all(&staging).await;
    result
}

async fn install_staged(paths: &Paths, source: &Path, is_dir: bool, staging: &Path, taken: &HashSet<String>) -> OpResult<ThemeId> {
    let fallback_name;
    if is_dir {
        let from = source.to_path_buf();
        let to = staging.join(source.file_name().unwrap_or_else(|| "theme".as_ref()));
        fallback_name = archive_stem(source);
        blocking(move || {
            check_tree(&from)?;
            copy_tree(&from, &to)
        })
        .await?;
    } else {
        let kind = archive_kind(source).ok_or_else(|| OpError::invalid("not a theme directory or a known archive"))?;
        check_listing(kind, source).await?;
        unpack(kind, source, staging).await?;
        fallback_name = archive_stem(source);
    }

    let root = {
        let staging = staging.to_path_buf();
        blocking(move || {
            check_tree(&staging)?;
            find_theme_root(&staging)
        })
        .await?
    };
    // The directory's name is the theme's name; a theme packed without a directory gets the
    // archive's name
    let name = if root == staging { fallback_name } else { root.file_name().and_then(|n| n.to_str()).unwrap_or_default().to_string() };
    if !valid_name(&name) {
        return Err(OpError::invalid(format!("\"{name}\" cannot be a theme name")));
    }
    if taken.contains(&name) {
        return Err(OpError::new(ErrorCode::AlreadyExists, format!("a theme \"{name}\" exists")));
    }
    let themes = paths.data_home.join("aurorae/themes");
    tokio::fs::create_dir_all(&themes).await.map_err(|e| OpError::io("creating aurorae/themes", e))?;
    let target = themes.join(&name);
    if tokio::fs::symlink_metadata(&target).await.is_ok() {
        return Err(OpError::new(ErrorCode::AlreadyExists, format!("{} exists", target.display())));
    }
    tokio::fs::rename(&root, &target).await.map_err(|e| OpError::io("moving the theme into place", e))?;
    Ok(ThemeId::new(Engine::AuroraeSvg, name))
}

/// Removes a theme the user installed: moved aside first (so it is gone at once for KWin and
/// the catalog), then deleted
pub async fn remove(paths: &Paths, theme: &Theme) -> OpResult {
    let themes = paths.data_home.join("aurorae/themes");
    if theme.origin != Origin::User || theme.id.engine != Engine::AuroraeSvg || theme.path.parent() != Some(themes.as_path()) {
        return Err(OpError::new(ErrorCode::NotAllowed, format!("{} is not a theme the user installed", theme.id)));
    }
    let aside = staging_dir(paths, "remove");
    tokio::fs::rename(&theme.path, &aside).await.map_err(|e| OpError::io("removing the theme", e))?;
    tokio::fs::remove_dir_all(&aside).await.map_err(|e| OpError::io("deleting the theme", e))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;

    fn paths_in(tmp: &TempDir) -> Paths {
        let home = tmp.path().join("home");
        Paths { data_home: home.clone(), data_dirs: vec![home], config_home: tmp.path().join("config"), maia_data_dirs: vec![], plugin_dirs: vec![] }
    }

    fn theme_dir(at: &Path, name: &str) -> PathBuf {
        let dir = at.join(name);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("metadata.desktop"), format!("[Desktop Entry]\nName={name}\n")).unwrap();
        std::fs::write(dir.join("decoration.svg"), "<svg/>").unwrap();
        std::fs::write(dir.join(format!("{name}rc")), "[General]\n").unwrap();
        dir
    }

    fn tar(tmp: &TempDir, args: &[&str]) -> PathBuf {
        let archive = tmp.path().join("theme.tar.gz");
        let status = std::process::Command::new("tar").current_dir(tmp.path().join("src")).arg("-czf").arg(&archive).args(args).status().unwrap();
        assert!(status.success());
        archive
    }

    #[test]
    fn names_and_entries() {
        assert!(valid_name("XBoomer") && valid_name("Sweet-dark 2"));
        assert!(!valid_name(".hidden") && !valid_name("a/b") && !valid_name(""));
        assert!(safe_entry("XBoomer/decoration.svg") && safe_entry("./XBoomer/"));
        assert!(!safe_entry("../x") && !safe_entry("/etc/passwd") && !safe_entry("a/../../b"));
        assert_eq!(archive_stem(Path::new("/d/Sweet-dark.tar.gz")), "Sweet-dark");
        assert_eq!(archive_kind(Path::new("a.TGZ")), Some(Archive::Tar));
        assert_eq!(archive_kind(Path::new("a.svg")), None);
    }

    #[tokio::test(flavor = "current_thread")]
    async fn an_archive_installs_into_the_users_themes_and_can_be_removed() {
        let tmp = TempDir::new("install-archive");
        theme_dir(&tmp.path().join("src"), "Glass");
        let archive = tar(&tmp, &["Glass"]);
        let paths = paths_in(&tmp);
        let id = install(&paths, &archive, &HashSet::new()).await.unwrap();
        assert_eq!(id.to_string(), "aurorae-svg:Glass");
        let installed = paths.data_home.join("aurorae/themes/Glass");
        assert!(installed.join("decoration.svg").is_file());
        // Nothing left behind
        let leftovers: Vec<_> = std::fs::read_dir(paths.data_home.join("aurorae")).unwrap().flatten().filter(|e| e.file_name().to_string_lossy().starts_with(".maia-")).collect();
        assert!(leftovers.is_empty());

        let taken: HashSet<String> = ["Glass".to_string()].into();
        let again = install(&paths, &archive, &taken).await.unwrap_err();
        assert_eq!(again.code, ErrorCode::AlreadyExists);

        let theme = Theme {
            id,
            name: "Glass".into(),
            description: String::new(),
            author: String::new(),
            origin: Origin::User,
            available: true,
            unavailable_reason: String::new(),
            path: installed.clone(),
        };
        remove(&paths, &theme).await.unwrap();
        assert!(!installed.exists());
    }

    #[tokio::test(flavor = "current_thread")]
    async fn links_and_escaping_paths_are_refused() {
        let tmp = TempDir::new("install-evil");
        let dir = theme_dir(&tmp.path().join("src"), "Evil");
        std::os::unix::fs::symlink("/etc/passwd", dir.join("passwd")).unwrap();
        let archive = tar(&tmp, &["Evil"]);
        let error = install(&paths_in(&tmp), &archive, &HashSet::new()).await.unwrap_err();
        assert_eq!(error.code, ErrorCode::InvalidArgument, "{error}");
        assert!(!tmp.path().join("home/aurorae/themes/Evil").exists());

        let escaping = tmp.path().join("escape.tar");
        let status = std::process::Command::new("tar")
            .current_dir(tmp.path().join("src"))
            .args(["-cf"])
            .arg(&escaping)
            .args(["--transform", "s,^Evil,../Evil,", "Evil/metadata.desktop"])
            .status()
            .unwrap();
        assert!(status.success());
        assert_eq!(install(&paths_in(&tmp), &escaping, &HashSet::new()).await.unwrap_err().code, ErrorCode::InvalidArgument);
    }

    #[tokio::test(flavor = "current_thread")]
    async fn directories_install_and_qml_themes_are_refused() {
        let tmp = TempDir::new("install-dir");
        let dir = theme_dir(&tmp.path().join("src"), "Plain");
        let paths = paths_in(&tmp);
        assert_eq!(install(&paths, &dir, &HashSet::new()).await.unwrap().name, "Plain");
        assert!(dir.exists(), "the source stays");

        let qml = tmp.path().join("src/kwin4_decoration_qml_x");
        std::fs::create_dir_all(qml.join("contents")).unwrap();
        std::fs::write(qml.join("metadata.json"), r#"{"KPackageStructure": "KWin/Decoration"}"#).unwrap();
        assert_eq!(install(&paths, &qml, &HashSet::new()).await.unwrap_err().code, ErrorCode::NotSupported);
    }
}

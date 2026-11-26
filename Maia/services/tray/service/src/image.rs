//! Icons of items as file:// URLs.
//!
//! An application gives an icon as a theme name, a name in its own icon directory
//! (IconThemePath), an absolute path, or as pixels (IconPixmap: ARGB32 in network byte order, often
//! several sizes; a menu entry's icon-data: PNG bytes). The shells get names and URLs only:
//!
//! - pixels are scaled down to at most `ICON_SIDE` and written as PNG into the service's directory
//!   in $XDG_RUNTIME_DIR, which lives in memory; the shell decodes a small file in its image loader
//!   thread, and the Cap'n Proto messages stay small;
//! - a file is named by a hash of its content: the same image (the frames of an animated icon, a
//!   menu opened again) is written once and keeps its URL, a changed image gets a new URL, so a
//!   shell never shows a stale cached image;
//! - files are shared and counted (`ImageRef`): one no longer used is removed some seconds later
//!   (an animation that comes back to a frame finds it still there);
//! - an image of one colour on transparency is a mask (`is_mask`): a "template" as macOS has them,
//!   made for a light panel or a dark one. The shells draw it in their own colour of text, so a
//!   black icon does not vanish in dark mode.
//!
//! Scaling and PNG run on tokio's blocking threads, never in the event loop.

use std::cell::RefCell;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::rc::{Rc, Weak};
use std::time::Duration;

// The clock of tokio: a test with a paused clock moves it
use tokio::time::Instant;

use crate::model::{Icon, Pixmap, RawIcon};

/// The longest side of a written icon, in pixels: a tray icon of 22–32 px at a scale of 2
pub const ICON_SIDE: u32 = 64;
/// A menu entry's PNG larger than this is refused
pub const MAX_PNG_BYTES: usize = 512 * 1024;
/// How long an image no longer used stays
pub const KEEP_UNUSED: Duration = Duration::from_secs(10);

/// A path or a file:// URL as a URL; "" when it is neither
pub fn url_from_path(path_or_url: &str) -> String {
    let s = path_or_url.trim();
    if s.starts_with("file://") {
        return s.to_string();
    }
    if !s.starts_with('/') {
        return String::new();
    }
    let mut url = String::from("file://");
    for c in s.chars() {
        match c {
            '%' => url.push_str("%25"),
            ' ' => url.push_str("%20"),
            '#' => url.push_str("%23"),
            '?' => url.push_str("%3F"),
            c => url.push(c),
        }
    }
    url
}

/// The pixmap to scale from: the smallest one at least `side` large, or else the largest
pub fn best_pixmap(pixmaps: &[Pixmap], side: u32) -> Option<&Pixmap> {
    let side = side as i32;
    let large_enough = pixmaps.iter().filter(|p| p.width.min(p.height) >= side).min_by_key(|p| p.width * p.height);
    large_enough.or_else(|| pixmaps.iter().max_by_key(|p| p.width * p.height))
}

/// The size an image gets: at most `max` on its longer side, never larger than it is
pub fn scaled_size(width: u32, height: u32, max: u32) -> (u32, u32) {
    if width <= max && height <= max {
        return (width, height);
    }
    if width >= height {
        (max, ((height as u64 * max as u64 + width as u64 / 2) / width as u64).max(1) as u32)
    } else {
        (((width as u64 * max as u64 + height as u64 / 2) / height as u64).max(1) as u32, max)
    }
}

/// A pixmap as RGBA, scaled down (area average weighted by alpha: no aliasing, no dark edges)
pub fn to_rgba(p: &Pixmap, max: u32) -> (u32, u32, Vec<u8>) {
    let (sw, sh) = (p.width as u32, p.height as u32);
    let (dw, dh) = scaled_size(sw, sh, max);
    // ARGB in network byte order: A, R, G, B
    let pixel = |x: u32, y: u32| -> [u32; 4] {
        let at = (y as usize * sw as usize + x as usize) * 4;
        [p.data[at + 1] as u32, p.data[at + 2] as u32, p.data[at + 3] as u32, p.data[at] as u32]
    };
    let mut out = Vec::with_capacity(dw as usize * dh as usize * 4);
    if (dw, dh) == (sw, sh) {
        for y in 0..sh {
            for x in 0..sw {
                out.extend(pixel(x, y).map(|c| c as u8));
            }
        }
        return (dw, dh, out);
    }
    for y in 0..dh {
        let y0 = (y as u64 * sh as u64 / dh as u64) as u32;
        let y1 = (((y + 1) as u64 * sh as u64).div_ceil(dh as u64) as u32).max(y0 + 1).min(sh);
        for x in 0..dw {
            let x0 = (x as u64 * sw as u64 / dw as u64) as u32;
            let x1 = (((x + 1) as u64 * sw as u64).div_ceil(dw as u64) as u32).max(x0 + 1).min(sw);
            let (mut r, mut g, mut b, mut a, mut n) = (0u64, 0u64, 0u64, 0u64, 0u64);
            for sy in y0..y1 {
                for sx in x0..x1 {
                    let [pr, pg, pb, pa] = pixel(sx, sy);
                    r += (pr * pa) as u64;
                    g += (pg * pa) as u64;
                    b += (pb * pa) as u64;
                    a += pa as u64;
                    n += 1;
                }
            }
            if a == 0 {
                out.extend([0, 0, 0, 0]);
            } else {
                out.extend([(r / a) as u8, (g / a) as u8, (b / a) as u8, (a / n) as u8]);
            }
        }
    }
    (dw, dh, out)
}

pub fn encode_png(width: u32, height: u32, rgba: &[u8]) -> Result<Vec<u8>, String> {
    let mut bytes = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut bytes, width, height);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        encoder.set_compression(png::Compression::Fast);
        let mut writer = encoder.write_header().map_err(|e| e.to_string())?;
        writer.write_image_data(rgba).map_err(|e| e.to_string())?;
    }
    Ok(bytes)
}

/// The alpha from which a pixel counts as part of the shape, and how far colours may differ and
/// still be one (anti-aliasing, rounding)
const MASK_VISIBLE_ALPHA: u8 = 64;
const MASK_TOLERANCE: i32 = 24;

/// Whether an RGBA image is a mask: every visible pixel of the same grey (black, white, or between),
/// only the transparency drawing the shape. A shape of one other colour (a red dot) keeps its colour.
pub fn is_mask(rgba: &[u8]) -> bool {
    let mut first: Option<[i32; 3]> = None;
    let mut visible = 0;
    for pixel in rgba.chunks_exact(4) {
        if pixel[3] < MASK_VISIBLE_ALPHA {
            continue;
        }
        let colour = [pixel[0] as i32, pixel[1] as i32, pixel[2] as i32];
        let (min, max) = (colour.iter().min().unwrap(), colour.iter().max().unwrap());
        if max - min > MASK_TOLERANCE {
            return false;
        }
        match first {
            None => first = Some(colour),
            Some(f) if f.iter().zip(colour).any(|(a, b)| (a - b).abs() > MASK_TOLERANCE) => return false,
            Some(_) => {}
        }
        visible += 1;
    }
    visible >= 4
}

/// A PNG as RGBA, 8 bits a channel (a menu entry's icon-data); None when it cannot be read
pub fn png_rgba(bytes: &[u8]) -> Option<Vec<u8>> {
    let mut decoder = png::Decoder::new(std::io::Cursor::new(bytes));
    decoder.set_transformations(png::Transformations::EXPAND | png::Transformations::STRIP_16);
    let mut reader = decoder.read_info().ok()?;
    let mut buffer = vec![0; reader.output_buffer_size()?];
    let info = reader.next_frame(&mut buffer).ok()?;
    let data = &buffer[..info.buffer_size()];
    let rgba = match info.color_type {
        png::ColorType::Rgba => data.to_vec(),
        png::ColorType::Rgb => data.chunks_exact(3).flat_map(|p| [p[0], p[1], p[2], 255]).collect(),
        png::ColorType::GrayscaleAlpha => data.chunks_exact(2).flat_map(|p| [p[0], p[0], p[0], p[1]]).collect(),
        png::ColorType::Grayscale => data.iter().flat_map(|&g| [g, g, g, 255]).collect(),
        png::ColorType::Indexed => return None,
    };
    Some(rgba)
}

/// Whether bytes are a PNG of a sensible size (a menu entry's icon-data)
pub fn is_png(bytes: &[u8]) -> bool {
    bytes.len() <= MAX_PNG_BYTES && bytes.starts_with(b"\x89PNG\r\n\x1a\n")
}

/// Writes `<dir>/<hash>.png`, complete or not at all (a temporary file is renamed). Blocking.
fn write_file(dir: &Path, hash: u64, bytes: &[u8]) -> Result<PathBuf, String> {
    let file = dir.join(file_name(hash));
    let temporary = dir.join(format!(".{hash:016x}.png.part"));
    let mut out = std::fs::File::create(&temporary).map_err(|e| format!("{}: {e}", temporary.display()))?;
    out.write_all(bytes).map_err(|e| e.to_string())?;
    drop(out);
    std::fs::rename(&temporary, &file).map_err(|e| e.to_string())?;
    Ok(file)
}

fn file_name(hash: u64) -> String {
    format!("{hash:016x}.png")
}

/// Removes the PNG files left by an earlier run (a crash), keeping the directory
pub fn clean_directory(dir: &Path) {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            if name.ends_with(".png") || name.ends_with(".png.part") {
                let _ = std::fs::remove_file(path);
            }
        }
    }
}

// --- Icon files in an application's own directory (IconThemePath) ---

/// The size an icon file is for, from a directory of its path ("48x48", "scalable" = u32::MAX)
fn size_of_path(path: &Path) -> u32 {
    for component in path.components().rev().skip(1) {
        let name = component.as_os_str().to_string_lossy();
        if name == "scalable" {
            return u32::MAX;
        }
        if let Some((w, h)) = name.split_once('x') {
            if let (Ok(w), Ok(h)) = (w.parse::<u32>(), h.split('@').next().unwrap_or("").parse::<u32>()) {
                return w.max(h);
            }
        }
    }
    0
}

/// The file of icon `name` in an application's icon directory: a scalable one first, then the
/// smallest image at least ICON_SIDE large, then the largest. Looks at most 4 directories deep (the
/// layout of an icon theme: hicolor/48x48/apps/name.png). Blocking.
pub fn find_in_theme_path(dir: &Path, name: &str) -> Option<PathBuf> {
    if name.is_empty() || name.contains('/') {
        return None;
    }
    let mut found: Vec<(u32, bool, PathBuf)> = Vec::new();
    let mut pending = vec![(dir.to_path_buf(), 0)];
    let mut visited = 0;
    while let Some((current, depth)) = pending.pop() {
        visited += 1;
        // A sender's directory may be large or a loop of links: a bounded walk
        if visited > 512 {
            break;
        }
        let Ok(entries) = std::fs::read_dir(&current) else { continue };
        for entry in entries.flatten() {
            let path = entry.path();
            let Ok(kind) = entry.file_type() else { continue };
            if kind.is_dir() && depth < 4 {
                pending.push((path, depth + 1));
                continue;
            }
            let (Some(stem), Some(extension)) = (path.file_stem(), path.extension()) else { continue };
            if stem.to_string_lossy() != name {
                continue;
            }
            let extension = extension.to_string_lossy().to_ascii_lowercase();
            let scalable = matches!(extension.as_str(), "svg" | "svgz");
            if scalable || matches!(extension.as_str(), "png" | "xpm") {
                let size = if scalable { u32::MAX } else { size_of_path(&path) };
                found.push((size, scalable, path));
            }
        }
    }
    let side = ICON_SIDE;
    found.sort_by_key(|(size, scalable, path)| {
        // Scalable first, then images at least `side` from the smallest, then smaller from the largest
        let rank = if *scalable { 0 } else if *size >= side { 1 } else { 2 };
        let order = if rank == 1 { *size as i64 } else { -(*size as i64) };
        (rank, order, path.clone())
    });
    found.into_iter().next().map(|(_, _, path)| path)
}

// --- The store of written images ---

struct Stored {
    url: String,
    mask: bool,
    file: PathBuf,
    refs: usize,
    unused_since: Option<Instant>,
}

pub struct ImageStore {
    dir: Option<PathBuf>,
    files: HashMap<u64, Stored>,
    sweep_scheduled: bool,
    /// Lookups in applications' icon directories: (directory, name) → URL ("" not found)
    theme_files: HashMap<(String, String), String>,
}

pub type ImageStoreRef = Rc<RefCell<ImageStore>>;

/// A use of a written image; the image is removed some time after its last use ends
pub struct ImageRef {
    store: Weak<RefCell<ImageStore>>,
    hash: u64,
}

impl std::fmt::Debug for ImageRef {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "ImageRef({:016x})", self.hash)
    }
}

impl Drop for ImageRef {
    fn drop(&mut self) {
        if let Some(store) = self.store.upgrade() {
            ImageStore::release(&store, self.hash);
        }
    }
}

/// A written image: its URL, a use of it, and whether it is a mask
#[derive(Debug)]
pub struct Written {
    pub url: String,
    pub image: ImageRef,
    pub mask: bool,
}

/// An icon for the shells, with the images it uses
#[derive(Debug, Default)]
pub struct ResolvedIcon {
    pub icon: Icon,
    pub image: Option<ImageRef>,
}

fn hash_of(kind: u8, width: i32, height: i32, data: &[u8]) -> u64 {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    (kind, width, height).hash(&mut hasher);
    data.hash(&mut hasher);
    hasher.finish()
}

impl ImageStore {
    /// dir: where images are written (None: icons given as pixels have no image)
    pub fn new(dir: Option<PathBuf>) -> ImageStoreRef {
        Rc::new(RefCell::new(ImageStore { dir, files: HashMap::new(), sweep_scheduled: false, theme_files: HashMap::new() }))
    }

    /// Images written and not yet removed (tests)
    pub fn file_count(&self) -> usize {
        self.files.len()
    }

    /// Takes a use of an image that is already written
    fn acquire_existing(store: &ImageStoreRef, hash: u64) -> Option<Written> {
        let mut this = store.borrow_mut();
        let stored = this.files.get_mut(&hash)?;
        stored.refs += 1;
        stored.unused_since = None;
        Some(Written { url: stored.url.clone(), image: ImageRef { store: Rc::downgrade(store), hash }, mask: stored.mask })
    }

    /// The image of `hash`, written by `encode` (on a blocking thread: the PNG and whether it is a
    /// mask) when it is new
    async fn acquire(
        store: &ImageStoreRef,
        hash: u64,
        encode: impl FnOnce() -> Result<(Vec<u8>, bool), String> + Send + 'static,
    ) -> Option<Written> {
        if let Some(found) = ImageStore::acquire_existing(store, hash) {
            return Some(found);
        }
        let dir = store.borrow().dir.clone()?;
        let written = tokio::task::spawn_blocking(move || {
            encode().and_then(|(png, mask)| write_file(&dir, hash, &png).map(|file| (file, mask)))
        })
            .await
            .unwrap_or_else(|error| Err(error.to_string()));
        // Written meanwhile by another use: the same content under the same name
        if let Some(found) = ImageStore::acquire_existing(store, hash) {
            return Some(found);
        }
        match written {
            Ok((file, mask)) => {
                let url = url_from_path(&file.to_string_lossy());
                store.borrow_mut().files.insert(hash, Stored { url: url.clone(), mask, file, refs: 1, unused_since: None });
                Some(Written { url, image: ImageRef { store: Rc::downgrade(store), hash }, mask })
            }
            Err(error) => {
                eprintln!("maia-tray-service: an icon image: {error}");
                None
            }
        }
    }

    /// The best of an icon's pixmaps as a PNG of at most ICON_SIDE
    pub async fn pixmap(store: &ImageStoreRef, pixmaps: &[Pixmap]) -> Option<Written> {
        let pixmap = best_pixmap(pixmaps, ICON_SIDE)?.clone();
        let hash = hash_of(0, pixmap.width, pixmap.height, &pixmap.data);
        ImageStore::acquire(store, hash, move || {
            let (width, height, rgba) = to_rgba(&pixmap, ICON_SIDE);
            Ok((encode_png(width, height, &rgba)?, is_mask(&rgba)))
        })
        .await
    }

    /// PNG bytes as they are (a menu entry's icon-data)
    pub async fn png(store: &ImageStoreRef, bytes: Vec<u8>) -> Option<Written> {
        if !is_png(&bytes) {
            return None;
        }
        let hash = hash_of(1, 0, 0, &bytes);
        ImageStore::acquire(store, hash, move || {
            let mask = png_rgba(&bytes).is_some_and(|rgba| is_mask(&rgba));
            Ok((bytes, mask))
        })
        .await
    }

    /// The URL of icon `name` in an application's icon directory, "" none (looked up once)
    pub async fn theme_file(store: &ImageStoreRef, dir: &str, name: &str) -> String {
        if dir.is_empty() || name.is_empty() {
            return String::new();
        }
        let key = (dir.to_string(), name.to_string());
        if let Some(url) = store.borrow().theme_files.get(&key) {
            return url.clone();
        }
        let (path, icon) = (PathBuf::from(dir), name.to_string());
        let url = tokio::task::spawn_blocking(move || find_in_theme_path(&path, &icon))
            .await
            .ok()
            .flatten()
            .map(|file| url_from_path(&file.to_string_lossy()))
            .unwrap_or_default();
        let mut this = store.borrow_mut();
        // Applications that write a new file for every change (Electron) would grow it forever
        if this.theme_files.len() > 256 {
            this.theme_files.clear();
        }
        this.theme_files.insert(key, url.clone());
        url
    }

    /// An icon for the shells:
    /// - an absolute path is a URL;
    /// - a name stays a name; found in the application's icon directory, its file is the URL;
    /// - pixmaps are the URL when there is no file (also next to a name: the shell takes the image
    ///   when its theme has no such icon).
    pub async fn resolve(store: &ImageStoreRef, raw: &RawIcon, theme_path: &str) -> ResolvedIcon {
        let mut resolved = ResolvedIcon::default();
        if raw.name.starts_with('/') || raw.name.starts_with("file://") {
            resolved.icon.url = url_from_path(&raw.name);
        } else {
            resolved.icon.name = raw.name.clone();
            resolved.icon.url = ImageStore::theme_file(store, theme_path, &raw.name).await;
        }
        if resolved.icon.url.is_empty() && !raw.pixmaps.is_empty() {
            if let Some(written) = ImageStore::pixmap(store, &raw.pixmaps).await {
                resolved.icon.url = written.url;
                resolved.icon.mask = written.mask;
                resolved.image = Some(written.image);
            }
        }
        resolved
    }

    fn release(store: &ImageStoreRef, hash: u64) {
        let mut this = store.borrow_mut();
        let Some(stored) = this.files.get_mut(&hash) else { return };
        stored.refs = stored.refs.saturating_sub(1);
        if stored.refs == 0 {
            stored.unused_since = Some(Instant::now());
            ImageStore::schedule_sweep(store, &mut this);
        }
    }

    /// A sweep when the image unused the longest is due
    fn schedule_sweep(store: &ImageStoreRef, this: &mut ImageStore) {
        if this.sweep_scheduled {
            return;
        }
        let Some(oldest) = this.files.values().filter_map(|s| s.unused_since).min() else { return };
        this.sweep_scheduled = true;
        let weak = Rc::downgrade(store);
        tokio::task::spawn_local(async move {
            tokio::time::sleep_until(oldest + KEEP_UNUSED).await;
            if let Some(store) = weak.upgrade() {
                ImageStore::sweep(&store);
            }
        });
    }

    /// Removes the images unused for KEEP_UNUSED. In this thread: one unlink in a directory in
    /// memory is quick, and a later write of the same image can never race with it.
    fn sweep(store: &ImageStoreRef) {
        let mut this = store.borrow_mut();
        this.sweep_scheduled = false;
        let now = Instant::now();
        let old: Vec<u64> = this
            .files
            .iter()
            .filter(|(_, s)| s.unused_since.is_some_and(|since| now.duration_since(since) >= KEEP_UNUSED))
            .map(|(hash, _)| *hash)
            .collect();
        for hash in old {
            if let Some(stored) = this.files.remove(&hash) {
                let _ = std::fs::remove_file(&stored.file);
            }
        }
        ImageStore::schedule_sweep(store, &mut this);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn argb(side: i32, color: [u8; 4]) -> Pixmap {
        Pixmap { width: side, height: side, data: color.repeat((side * side) as usize) }
    }

    fn temp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("maia-tray-image-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn local<F: std::future::Future>(future: F) -> F::Output {
        let runtime = tokio::runtime::Builder::new_current_thread().enable_all().start_paused(true).build().unwrap();
        tokio::task::LocalSet::new().block_on(&runtime, future)
    }

    #[test]
    fn templates_are_masks_and_colours_are_not() {
        let rgba = |pixels: &[[u8; 4]]| pixels.concat();
        // Black on transparency, with soft edges whose colour wanders a little
        assert!(is_mask(&rgba(&[[0, 0, 0, 255], [0, 0, 0, 255], [3, 3, 3, 120], [10, 10, 10, 70], [0, 0, 0, 0], [200, 0, 0, 10]])));
        // White, or a grey
        assert!(is_mask(&rgba(&[[255; 4], [255; 4], [250, 250, 250, 255], [255, 255, 255, 90]])));
        assert!(is_mask(&rgba(&[[128, 128, 128, 255]; 4])));
        // One colour that is no grey (a red dot), two greys, a picture
        assert!(!is_mask(&rgba(&[[220, 30, 30, 255]; 4])));
        assert!(!is_mask(&rgba(&[[0, 0, 0, 255], [0, 0, 0, 255], [255, 255, 255, 255], [255, 255, 255, 255]])));
        assert!(!is_mask(&rgba(&[[0, 0, 0, 255], [0, 0, 0, 255], [0, 0, 0, 255], [0, 120, 255, 255]])));
        // Nothing visible is no mask
        assert!(!is_mask(&rgba(&[[0, 0, 0, 0]; 8])));
    }

    #[test]
    fn png_bytes_are_read_back() {
        let png = encode_png(1, 2, &[1, 2, 3, 4, 5, 6, 7, 8]).unwrap();
        assert_eq!(png_rgba(&png).unwrap(), [1, 2, 3, 4, 5, 6, 7, 8]);
        assert!(png_rgba(b"nope").is_none());
    }

    #[test]
    fn paths_become_urls() {
        assert_eq!(url_from_path("/tmp/a b#1.png"), "file:///tmp/a%20b%231.png");
        assert_eq!(url_from_path("file:///x.png"), "file:///x.png");
        assert_eq!(url_from_path("mail-unread"), "");
    }

    #[test]
    fn the_best_pixmap_is_the_smallest_large_enough() {
        let list = [argb(16, [0; 4]), argb(128, [0; 4]), argb(64, [0; 4]), argb(256, [0; 4])];
        assert_eq!(best_pixmap(&list, 64).unwrap().width, 64);
        let small = [argb(16, [0; 4]), argb(32, [0; 4])];
        assert_eq!(best_pixmap(&small, 64).unwrap().width, 32);
        assert!(best_pixmap(&[], 64).is_none());
    }

    #[test]
    fn argb_in_network_order_becomes_rgba() {
        // Opaque red, then half transparent blue
        let p = Pixmap { width: 2, height: 1, data: vec![255, 255, 0, 0, 128, 0, 0, 255] };
        let (w, h, out) = to_rgba(&p, 64);
        assert_eq!((w, h), (2, 1));
        assert_eq!(out, [255, 0, 0, 255, 0, 0, 255, 128]);
    }

    #[test]
    fn scaling_keeps_colors_at_transparent_edges() {
        let mut p = argb(2, [255, 200, 100, 50]);
        p.data[4..8].copy_from_slice(&[0, 0, 0, 0]);
        let (w, h, out) = to_rgba(&Pixmap { width: 2, height: 1, data: p.data[..8].to_vec() }, 1);
        assert_eq!((w, h), (1, 1));
        assert_eq!(out, [200, 100, 50, 127]);
    }

    #[test]
    fn icon_files_of_an_application_directory() {
        let dir = temp_dir("theme");
        for (path, content) in [
            ("hicolor/16x16/apps/app.png", "x"),
            ("hicolor/48x48/apps/app.png", "x"),
            ("hicolor/128x128/apps/app.png", "x"),
            ("hicolor/256x256/apps/app.png", "x"),
            ("hicolor/48x48/apps/other.png", "x"),
            ("flat.png", "x"),
        ] {
            let file = dir.join(path);
            std::fs::create_dir_all(file.parent().unwrap()).unwrap();
            std::fs::write(file, content).unwrap();
        }
        assert_eq!(find_in_theme_path(&dir, "app").unwrap(), dir.join("hicolor/128x128/apps/app.png"));
        assert_eq!(find_in_theme_path(&dir, "other").unwrap(), dir.join("hicolor/48x48/apps/other.png"));
        assert_eq!(find_in_theme_path(&dir, "flat").unwrap(), dir.join("flat.png"));
        assert!(find_in_theme_path(&dir, "missing").is_none());
        assert!(find_in_theme_path(&dir, "../x").is_none());
        std::fs::create_dir_all(dir.join("hicolor/scalable/apps")).unwrap();
        std::fs::write(dir.join("hicolor/scalable/apps/app.svg"), "x").unwrap();
        assert_eq!(find_in_theme_path(&dir, "app").unwrap(), dir.join("hicolor/scalable/apps/app.svg"));
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn the_same_pixels_are_written_once_and_removed_after_their_last_use() {
        let dir = temp_dir("store");
        local(async {
            let store = ImageStore::new(Some(dir.clone()));
            let pixels = vec![argb(128, [255, 1, 2, 3])];
            let Written { url: url1, image: ref1, .. } = ImageStore::pixmap(&store, &pixels).await.unwrap();
            let Written { url: url2, image: ref2, .. } = ImageStore::pixmap(&store, &pixels).await.unwrap();
            assert_eq!(url1, url2);
            assert_eq!(store.borrow().file_count(), 1);
            let file = PathBuf::from(url1.strip_prefix("file://").unwrap());
            let decoder = png::Decoder::new(std::io::BufReader::new(std::fs::File::open(&file).unwrap()));
            let reader = decoder.read_info().unwrap();
            assert_eq!((reader.info().width, reader.info().height), (64, 64));

            let Written { url: other, image: _ref3, .. } = ImageStore::pixmap(&store, &[argb(8, [255, 9, 9, 9])]).await.unwrap();
            assert_ne!(other, url1);

            drop(ref1);
            tokio::time::sleep(KEEP_UNUSED * 2).await;
            assert!(file.exists(), "still used once");
            drop(ref2);
            tokio::time::sleep(KEEP_UNUSED / 2).await;
            // Used again before it was removed: the same file
            let Written { url: url3, image: ref4, .. } = ImageStore::pixmap(&store, &pixels).await.unwrap();
            assert_eq!(url3, url1);
            drop(ref4);
            tokio::time::sleep(KEEP_UNUSED + Duration::from_secs(1)).await;
            assert!(!file.exists());
            assert_eq!(store.borrow().file_count(), 1);
        });
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn icons_are_resolved_by_their_kind() {
        let dir = temp_dir("resolve");
        local(async {
            let store = ImageStore::new(Some(dir.clone()));
            let named = ImageStore::resolve(&store, &RawIcon { name: "kmail".into(), pixmaps: vec![] }, "").await;
            assert_eq!(named.icon, Icon { name: "kmail".into(), ..Icon::default() });
            let path = ImageStore::resolve(&store, &RawIcon { name: "/tmp/x.png".into(), pixmaps: vec![] }, "").await;
            assert_eq!(path.icon, Icon { url: "file:///tmp/x.png".into(), ..Icon::default() });
            let both = ImageStore::resolve(&store, &RawIcon { name: "app".into(), pixmaps: vec![argb(4, [255; 4])] }, "").await;
            assert_eq!(both.icon.name, "app");
            assert!(both.icon.url.starts_with("file://") && both.image.is_some());
            assert!(ImageStore::png(&store, b"not a png".to_vec()).await.is_none());

            // A black template: a mask, also when the same pixels come again; colour stays colour
            let black = ImageStore::resolve(&store, &RawIcon { name: String::new(), pixmaps: vec![argb(16, [255, 0, 0, 0])] }, "").await;
            assert!(black.icon.mask);
            let again = ImageStore::resolve(&store, &RawIcon { name: String::new(), pixmaps: vec![argb(16, [255, 0, 0, 0])] }, "").await;
            assert!(again.icon.mask);
            let orange = ImageStore::resolve(&store, &RawIcon { name: String::new(), pixmaps: vec![argb(16, [255, 255, 136, 0])] }, "").await;
            assert!(!orange.icon.mask);
            // A menu entry's PNG
            let png = encode_png(3, 2, &[[255, 255, 255, 255], [255, 255, 255, 0], [250, 250, 250, 200], [255; 4], [255; 4], [255; 4]].concat()).unwrap();
            assert!(ImageStore::png(&store, png).await.unwrap().mask);
        });
        std::fs::remove_dir_all(&dir).unwrap();
    }
}

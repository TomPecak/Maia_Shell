//! Images of notifications as file:// URLs.
//!
//! Applications give an image as a path, a URL, an icon name, or as raw pixels over D-Bus
//! ("image-data"). The shells get URLs only: pixels are scaled down to at most `MAX_SIDE` and written
//! as PNG into the service's directory in $XDG_RUNTIME_DIR, which lives in memory. The shell then
//! decodes a small file in its image loader thread (QML Image, asynchronous) and the Cap'n Proto
//! messages stay small, also when a shell reconnects and gets the whole list again.
//!
//! The work (scaling, PNG) runs on tokio's blocking threads (hub.rs), never in the event loop.

use std::io::Write;
use std::path::{Path, PathBuf};

use crate::model::Pixels;

/// The longest side of a written image, in pixels: enough for a popup and the list at 2x
pub const MAX_SIDE: u32 = 512;
/// Larger images are refused (a sender bug or abuse), before any work
pub const MAX_INPUT_SIDE: i32 = 8192;

/// A path or a file:// URL as a URL; "" when it is neither (an icon name, or nothing)
pub fn url_from_path(path_or_url: &str) -> String {
    let s = path_or_url.trim();
    if s.starts_with("file://") {
        return s.to_string();
    }
    if s.starts_with('/') {
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
        return url;
    }
    String::new()
}

/// An icon of a notification: a theme icon name stays, a path becomes a URL
pub fn icon(name_or_path: &str) -> String {
    let s = name_or_path.trim();
    if s.starts_with('/') || s.starts_with("file://") { url_from_path(s) } else { s.to_string() }
}

/// Checks the layout of the pixels before anything reads them
pub fn validate(p: &Pixels) -> Result<(), String> {
    if p.bits_per_sample != 8 {
        return Err(format!("{} bits per sample (only 8 are supported)", p.bits_per_sample));
    }
    let expected_channels = if p.has_alpha { 4 } else { 3 };
    if p.channels != expected_channels {
        return Err(format!("{} channels with has_alpha = {}", p.channels, p.has_alpha));
    }
    if p.width <= 0 || p.height <= 0 || p.width > MAX_INPUT_SIDE || p.height > MAX_INPUT_SIDE {
        return Err(format!("size {}x{}", p.width, p.height));
    }
    let row = p.width as usize * p.channels as usize;
    if (p.rowstride as usize) < row {
        return Err(format!("rowstride {} < {row}", p.rowstride));
    }
    let needed = p.rowstride as usize * (p.height as usize - 1) + row;
    if p.data.len() < needed {
        return Err(format!("{} bytes of pixels, {needed} needed", p.data.len()));
    }
    Ok(())
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

/// The pixels as RGBA, scaled down (area average: every source pixel counts, no aliasing)
pub fn to_rgba(p: &Pixels, max: u32) -> (u32, u32, Vec<u8>) {
    let (sw, sh) = (p.width as u32, p.height as u32);
    let (dw, dh) = scaled_size(sw, sh, max);
    let channels = p.channels as usize;
    let pixel = |x: u32, y: u32| -> [u32; 4] {
        let at = y as usize * p.rowstride as usize + x as usize * channels;
        let a = if channels == 4 { p.data[at + 3] as u32 } else { 255 };
        [p.data[at] as u32, p.data[at + 1] as u32, p.data[at + 2] as u32, a]
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
            // Colors weighted by alpha, so that transparent pixels do not darken the edges
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

/// Writes the pixels as `<dir>/<id>-<generation>.png` (complete or not at all: a temporary file is
/// renamed) and returns the file and its URL. Blocking: runs on a blocking thread.
pub fn write_png(dir: &Path, id: u32, generation: u64, pixels: &Pixels) -> Result<(PathBuf, String), String> {
    validate(pixels)?;
    let (width, height, rgba) = to_rgba(pixels, MAX_SIDE);
    let png = encode_png(width, height, &rgba)?;
    let file = dir.join(format!("{id}-{generation}.png"));
    let temporary = dir.join(format!(".{id}-{generation}.png.part"));
    let mut out = std::fs::File::create(&temporary).map_err(|e| format!("{}: {e}", temporary.display()))?;
    out.write_all(&png).map_err(|e| e.to_string())?;
    drop(out);
    std::fs::rename(&temporary, &file).map_err(|e| e.to_string())?;
    let url = url_from_path(&file.to_string_lossy());
    Ok((file, url))
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

#[cfg(test)]
mod tests {
    use super::*;

    fn rgba(width: i32, height: i32, color: [u8; 4]) -> Pixels {
        Pixels {
            width,
            height,
            rowstride: width * 4,
            has_alpha: true,
            bits_per_sample: 8,
            channels: 4,
            data: color.iter().copied().cycle().take((width * height * 4) as usize).collect(),
        }
    }

    #[test]
    fn paths_become_urls_and_names_stay() {
        assert_eq!(url_from_path("/tmp/a b#1.png"), "file:///tmp/a%20b%231.png");
        assert_eq!(url_from_path("file:///x.png"), "file:///x.png");
        assert_eq!(url_from_path("mail-unread"), "");
        assert_eq!(icon("mail-unread"), "mail-unread");
        assert_eq!(icon("/usr/share/icons/x.svg"), "file:///usr/share/icons/x.svg");
    }

    #[test]
    fn sizes_keep_the_aspect_and_never_grow() {
        assert_eq!(scaled_size(4000, 3000, 512), (512, 384));
        assert_eq!(scaled_size(300, 1200, 512), (128, 512));
        assert_eq!(scaled_size(64, 64, 512), (64, 64));
        assert_eq!(scaled_size(5000, 1, 512), (512, 1));
    }

    #[test]
    fn broken_pixel_data_is_refused() {
        let mut p = rgba(4, 4, [1, 2, 3, 4]);
        p.data.truncate(10);
        assert!(validate(&p).is_err());
        let mut p = rgba(4, 4, [1, 2, 3, 4]);
        p.channels = 3;
        assert!(validate(&p).is_err());
        let mut p = rgba(4, 4, [1, 2, 3, 4]);
        p.rowstride = 8;
        assert!(validate(&p).is_err());
        assert!(validate(&rgba(4, 4, [1, 2, 3, 4])).is_ok());
    }

    #[test]
    fn rgb_with_row_padding_is_read() {
        // 2x1 RGB, rows padded to 8 bytes
        let p = Pixels { width: 2, height: 2, rowstride: 8, has_alpha: false, bits_per_sample: 8, channels: 3,
                         data: vec![10, 20, 30, 40, 50, 60, 0, 0, 70, 80, 90, 100, 110, 120] };
        let (w, h, out) = to_rgba(&p, 512);
        assert_eq!((w, h), (2, 2));
        assert_eq!(&out[..8], &[10, 20, 30, 255, 40, 50, 60, 255]);
        assert_eq!(&out[8..], &[70, 80, 90, 255, 100, 110, 120, 255]);
    }

    #[test]
    fn scaling_averages_the_area() {
        // Left half red, right half blue: 1024x2 -> 512x1 keeps the halves
        let mut p = rgba(1024, 2, [255, 0, 0, 255]);
        for y in 0..2 {
            for x in 512..1024 {
                let at = (y * 1024 + x) * 4;
                p.data[at..at + 4].copy_from_slice(&[0, 0, 255, 255]);
            }
        }
        let (w, h, out) = to_rgba(&p, 512);
        assert_eq!((w, h), (512, 1));
        assert_eq!(&out[..4], &[255, 0, 0, 255]);
        assert_eq!(&out[511 * 4..], &[0, 0, 255, 255]);
    }

    #[test]
    fn transparent_pixels_do_not_darken_their_neighbours() {
        let mut p = rgba(2, 1, [200, 100, 50, 255]);
        p.data[4..8].copy_from_slice(&[0, 0, 0, 0]);
        let (_, _, out) = to_rgba(&p, 1);
        assert_eq!(out, [200, 100, 50, 127]);
    }

    #[test]
    fn written_files_are_png_of_the_scaled_size() {
        let dir = std::env::temp_dir().join(format!("maia-notifications-image-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let (file, url) = write_png(&dir, 7, 3, &rgba(2000, 1000, [1, 2, 3, 255])).unwrap();
        assert_eq!(file, dir.join("7-3.png"));
        assert!(url.starts_with("file://") && url.ends_with("/7-3.png"));
        let decoder = png::Decoder::new(std::io::BufReader::new(std::fs::File::open(&file).unwrap()));
        let reader = decoder.read_info().unwrap();
        assert_eq!((reader.info().width, reader.info().height), (512, 256));
        clean_directory(&dir);
        assert!(!file.exists());
        std::fs::remove_dir_all(&dir).unwrap();
    }
}

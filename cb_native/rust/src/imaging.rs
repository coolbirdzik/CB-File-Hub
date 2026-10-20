//! Image thumbnails, encoding and inpainting for the media screens.
//!
//! Replaces the pure-Dart `package:image` pipelines (decode -> resize ->
//! adjustColor -> sharpen -> encode). JPEG thumbnails decode at 1/2, 1/4 or
//! 1/8 scale straight from the DCT when that still covers the target, which
//! is most of the win for camera photos. EXIF orientation is applied like
//! `package:image` does, so thumbnails come out upright.

use std::io::Cursor;
use std::sync::Arc;

use fast_image_resize::images::Image as FrImage;
use fast_image_resize::{FilterType, PixelType, ResizeAlg, ResizeOptions, Resizer};
use image::codecs::bmp::BmpEncoder;
use image::codecs::gif::GifEncoder;
use image::codecs::jpeg::JpegEncoder;
use image::codecs::png::{CompressionType, FilterType as PngFilter, PngEncoder};
use image::codecs::tiff::TiffEncoder;
use image::metadata::Orientation;
use image::{
    DynamicImage, ExtendedColorType, Frame, ImageDecoder, ImageEncoder, ImageFormat, ImageReader,
    RgbImage, RgbaImage,
};

use crate::job::Job;
use crate::wire::{Reader, Writer};

const FIT_SHRINK_ONLY: u8 = 0;
const FIT_BOX: u8 = 1;
const FIT_STRETCH: u8 = 2;

const FILTER_BILINEAR: u8 = 0;
const FILTER_BOX: u8 = 1;
const FILTER_CUBIC: u8 = 2;

const FORMAT_JPEG: u8 = 0;
const FORMAT_PNG: u8 = 1;
const FORMAT_BMP: u8 = 2;
const FORMAT_GIF: u8 = 3;
const FORMAT_TIFF: u8 = 4;

struct ThumbnailRequest {
    source: Source,
    box_w: u32,
    box_h: u32,
    fit: u8,
    filter: u8,
    enhance: bool,
    format: u8,
    quality: u8,
    png_level: u8,
}

enum Source {
    Path(String),
    Bytes(Vec<u8>),
}

/// The output size for a `w` x `h` source, mirroring the Dart callers.
fn target_size(w: u32, h: u32, box_w: u32, box_h: u32, fit: u8) -> (u32, u32) {
    let (wf, hf) = (f64::from(w), f64::from(h));
    let (tw, th) = match fit {
        // PhotoThumbnailHelper: only shrink, keep the aspect ratio.
        FIT_SHRINK_ONLY => {
            if w <= box_w && h <= box_h {
                (w, h)
            } else if w >= h {
                (box_w, (hf * f64::from(box_w) / wf).round() as u32)
            } else {
                ((wf * f64::from(box_h) / hf).round() as u32, box_h)
            }
        }
        // The network thumbnailers: always fill the box's long side.
        FIT_BOX => {
            let aspect = wf / hf;
            if aspect > 1.0 {
                (box_w, (f64::from(box_w) / aspect).round() as u32)
            } else {
                ((f64::from(box_h) * aspect).round() as u32, box_h)
            }
        }
        _ => (box_w, box_h),
    };
    (tw.clamp(1, box_w.max(1)), th.clamp(1, box_h.max(1)))
}

fn decode_error(e: impl std::fmt::Display) -> String {
    format!("decode failed: {e}")
}

/// JPEG decoded at the smallest DCT scale that still covers the target.
fn decode_scaled_jpeg(bytes: &[u8], request: &ThumbnailRequest) -> Option<DynamicImage> {
    let mut decoder = jpeg_decoder::Decoder::new(Cursor::new(bytes));
    decoder.read_info().ok()?;
    let info = decoder.info()?;
    if !matches!(
        info.pixel_format,
        jpeg_decoder::PixelFormat::RGB24 | jpeg_decoder::PixelFormat::L8
    ) {
        return None;
    }
    let (raw_w, raw_h) = (u32::from(info.width), u32::from(info.height));
    // Orientation only swaps the axes, and every caller uses a square box, so
    // the sorted target sides do not depend on it.
    let (tw, th) = target_size(raw_w, raw_h, request.box_w, request.box_h, request.fit);
    let need = (tw.max(th), tw.min(th));
    let have = (raw_w.max(raw_h), raw_w.min(raw_h));
    let divisor = [8u32, 4, 2]
        .into_iter()
        .find(|d| have.0.div_ceil(*d) >= need.0 && have.1.div_ceil(*d) >= need.1)?;
    decoder
        .scale(
            raw_w.div_ceil(divisor) as u16,
            raw_h.div_ceil(divisor) as u16,
        )
        .ok()?;
    let pixels = decoder.decode().ok()?;
    let info = decoder.info()?;
    let (w, h) = (u32::from(info.width), u32::from(info.height));
    let mut image = match info.pixel_format {
        jpeg_decoder::PixelFormat::RGB24 => {
            DynamicImage::ImageRgb8(RgbImage::from_raw(w, h, pixels)?)
        }
        jpeg_decoder::PixelFormat::L8 => {
            DynamicImage::ImageLuma8(image::GrayImage::from_raw(w, h, pixels)?)
        }
        _ => return None,
    };
    if let Some(orientation) = decoder.exif_data().and_then(Orientation::from_exif_chunk) {
        image.apply_orientation(orientation);
    }
    Some(image)
}

fn decode(bytes: &[u8], request: Option<&ThumbnailRequest>) -> Result<DynamicImage, String> {
    let format = image::guess_format(bytes).map_err(decode_error)?;
    if let (ImageFormat::Jpeg, Some(request)) = (format, request) {
        if let Some(image) = decode_scaled_jpeg(bytes, request) {
            return Ok(image);
        }
    }
    let mut reader = ImageReader::new(Cursor::new(bytes));
    reader.set_format(format);
    let mut decoder = reader.into_decoder().map_err(decode_error)?;
    let orientation = decoder.orientation().unwrap_or(Orientation::NoTransforms);
    let mut image = DynamicImage::from_decoder(decoder).map_err(decode_error)?;
    image.apply_orientation(orientation);
    Ok(image)
}

/// RGB(A)8 pixels, keeping alpha only when the source has it.
struct Pixels {
    data: Vec<u8>,
    width: u32,
    height: u32,
    alpha: bool,
}

impl Pixels {
    fn of(image: DynamicImage) -> Pixels {
        let (width, height) = (image.width(), image.height());
        if image.color().has_alpha() {
            Pixels {
                data: image.into_rgba8().into_raw(),
                width,
                height,
                alpha: true,
            }
        } else {
            Pixels {
                data: image.into_rgb8().into_raw(),
                width,
                height,
                alpha: false,
            }
        }
    }

    fn channels(&self) -> usize {
        if self.alpha {
            4
        } else {
            3
        }
    }

    fn resize(self, width: u32, height: u32, filter: u8) -> Result<Pixels, String> {
        if width == self.width && height == self.height {
            return Ok(self);
        }
        let pixel_type = if self.alpha {
            PixelType::U8x4
        } else {
            PixelType::U8x3
        };
        let src = FrImage::from_vec_u8(self.width, self.height, self.data, pixel_type)
            .map_err(|e| e.to_string())?;
        let mut dst = FrImage::new(width, height, pixel_type);
        let filter = match filter {
            FILTER_BILINEAR => FilterType::Bilinear,
            FILTER_BOX => FilterType::Box,
            FILTER_CUBIC => FilterType::CatmullRom,
            _ => FilterType::Bilinear,
        };
        let options = ResizeOptions::new().resize_alg(ResizeAlg::Convolution(filter));
        Resizer::new()
            .resize(&src, &mut dst, &options)
            .map_err(|e| e.to_string())?;
        Ok(Pixels {
            data: dst.into_vec(),
            width,
            height,
            alpha: self.alpha,
        })
    }

    /// `adjustColor(contrast: 1.05, saturation: 1.1, brightness: 1.02)`.
    fn adjust_color(&mut self) {
        const BRIGHTNESS: f64 = 1.02;
        const SATURATION: f64 = 1.1;
        const CONTRAST: f64 = 1.05;
        let channels = self.channels();
        for pixel in self.data.chunks_exact_mut(channels) {
            let mut r = f64::from(pixel[0]) / 255.0 * BRIGHTNESS;
            let mut g = f64::from(pixel[1]) / 255.0 * BRIGHTNESS;
            let mut b = f64::from(pixel[2]) / 255.0 * BRIGHTNESS;
            let (h, s, v) = rgb_to_hsv(r, g, b);
            (r, g, b) = hsv_to_rgb(h, s * SATURATION, v);
            let invert = 1.0 - CONTRAST;
            r = 0.5 * invert + r * CONTRAST;
            g = 0.5 * invert + g * CONTRAST;
            b = 0.5 * invert + b * CONTRAST;
            pixel[0] = (r.clamp(0.0, 1.0) * 255.0) as u8;
            pixel[1] = (g.clamp(0.0, 1.0) * 255.0) as u8;
            pixel[2] = (b.clamp(0.0, 1.0) * 255.0) as u8;
        }
    }

    /// `convolution(filter: [0,-1,0,-1,5,-1,0,-1,0])` with clamped edges.
    fn sharpen(&mut self) {
        let channels = self.channels();
        let (w, h) = (self.width as usize, self.height as usize);
        let src = self.data.clone();
        let at = |x: usize, y: usize, c: usize| i32::from(src[(y * w + x) * channels + c]);
        for y in 0..h {
            let up = y.saturating_sub(1);
            let down = (y + 1).min(h - 1);
            for x in 0..w {
                let left = x.saturating_sub(1);
                let right = (x + 1).min(w - 1);
                for c in 0..3 {
                    let value = 5 * at(x, y, c)
                        - at(x, up, c)
                        - at(x, down, c)
                        - at(left, y, c)
                        - at(right, y, c);
                    self.data[(y * w + x) * channels + c] = value.clamp(0, 255) as u8;
                }
            }
        }
    }

    fn encode(&self, format: u8, quality: u8, png_level: u8) -> Result<Vec<u8>, String> {
        let color = if self.alpha {
            ExtendedColorType::Rgba8
        } else {
            ExtendedColorType::Rgb8
        };
        let mut out = Vec::new();
        match format {
            FORMAT_JPEG => {
                let rgb;
                let data = if self.alpha {
                    rgb = drop_alpha(&self.data);
                    &rgb
                } else {
                    &self.data
                };
                JpegEncoder::new_with_quality(&mut out, quality.clamp(1, 100)).write_image(
                    data,
                    self.width,
                    self.height,
                    ExtendedColorType::Rgb8,
                )
            }
            FORMAT_PNG => {
                let compression = match png_level {
                    0 => CompressionType::Fast,
                    2 => CompressionType::Best,
                    _ => CompressionType::Default,
                };
                PngEncoder::new_with_quality(&mut out, compression, PngFilter::Adaptive)
                    .write_image(&self.data, self.width, self.height, color)
            }
            FORMAT_BMP => {
                BmpEncoder::new(&mut out).write_image(&self.data, self.width, self.height, color)
            }
            FORMAT_TIFF => TiffEncoder::new(Cursor::new(&mut out)).write_image(
                &self.data,
                self.width,
                self.height,
                color,
            ),
            FORMAT_GIF => {
                let rgba = if self.alpha {
                    self.data.clone()
                } else {
                    add_alpha(&self.data)
                };
                let frame =
                    RgbaImage::from_raw(self.width, self.height, rgba).ok_or("bad pixel buffer")?;
                GifEncoder::new(&mut out).encode_frame(Frame::new(frame))
            }
            _ => return Err(format!("unknown format {format}")),
        }
        .map_err(|e| format!("encode failed: {e}"))?;
        Ok(out)
    }
}

fn drop_alpha(rgba: &[u8]) -> Vec<u8> {
    let mut rgb = Vec::with_capacity(rgba.len() / 4 * 3);
    for pixel in rgba.chunks_exact(4) {
        rgb.extend_from_slice(&pixel[..3]);
    }
    rgb
}

fn add_alpha(rgb: &[u8]) -> Vec<u8> {
    let mut rgba = Vec::with_capacity(rgb.len() / 3 * 4);
    for pixel in rgb.chunks_exact(3) {
        rgba.extend_from_slice(pixel);
        rgba.push(255);
    }
    rgba
}

/// package:image `rgbToHsv` (all channels in 0..1, hue in 0..1).
fn rgb_to_hsv(r: f64, g: f64, b: f64) -> (f64, f64, f64) {
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let delta = max - min;
    if max == 0.0 || delta == 0.0 {
        return (0.0, 0.0, max);
    }
    let s = delta / max;
    let mut h = if r == max {
        (g - b) / delta
    } else if g == max {
        2.0 + (b - r) / delta
    } else {
        4.0 + (r - g) / delta
    } / 6.0;
    if h < 0.0 {
        h += 1.0;
    }
    (h, s, max)
}

fn hsv_to_rgb(h: f64, s: f64, v: f64) -> (f64, f64, f64) {
    if s == 0.0 {
        return (v, v, v);
    }
    let h = (h - h.floor()) * 6.0;
    let i = h.floor();
    let f = h - i;
    let p = v * (1.0 - s);
    let q = v * (1.0 - s * f);
    let t = v * (1.0 - s * (1.0 - f));
    match i as i32 {
        0 => (v, t, p),
        1 => (q, v, p),
        2 => (p, v, t),
        3 => (p, q, v),
        4 => (t, p, v),
        _ => (v, p, q),
    }
}

fn thumbnail(job: &Job, request: ThumbnailRequest) -> Result<(), String> {
    let bytes = match &request.source {
        Source::Path(path) => std::fs::read(path).map_err(|e| e.to_string())?,
        Source::Bytes(bytes) => bytes.clone(),
    };
    if job.cancelled() {
        return Ok(());
    }
    let image = decode(&bytes, Some(&request))?;
    drop(bytes);
    let (tw, th) = target_size(
        image.width(),
        image.height(),
        request.box_w,
        request.box_h,
        request.fit,
    );
    let mut pixels = Pixels::of(image).resize(tw, th, request.filter)?;
    if request.enhance {
        pixels.adjust_color();
        if tw <= 256 && th <= 256 {
            pixels.sharpen();
        }
    }
    if job.cancelled() {
        return Ok(());
    }
    let encoded = pixels.encode(request.format, request.quality, request.png_level)?;
    let mut out = Writer::default();
    out.u32(tw);
    out.u32(th);
    out.raw(&encoded);
    job.append(&out.into_bytes());
    Ok(())
}

/// Config: source u8 (0 path, 1 bytes) + path or u32-length bytes, box width
/// and height u32, fit u8, filter u8, enhance u8, format u8, quality u8, png
/// level u8. Output: width u32, height u32, encoded image.
pub fn start_thumbnail(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let source = match r.u8()? {
        0 => Source::Path(r.str()?),
        _ => {
            let len = r.u32()? as usize;
            Source::Bytes(r.bytes(len)?.to_vec())
        }
    };
    let request = ThumbnailRequest {
        source,
        box_w: r.u32()?,
        box_h: r.u32()?,
        fit: r.u8()?,
        filter: r.u8()?,
        enhance: r.bool()?,
        format: r.u8()?,
        quality: r.u8()?,
        png_level: r.u8()?,
    };
    if !r.is_empty() || request.box_w == 0 || request.box_h == 0 || request.fit > FIT_STRETCH {
        return None;
    }
    Some(Job::spawn(port, "cb_native_thumbnail", move |job| {
        thumbnail(job, request)
    }))
}

/// Config: width u32, height u32, format u8, quality u8, then straight RGBA.
/// Output: the encoded image.
pub fn start_encode(port: i64, config: Vec<u8>) -> Option<Arc<Job>> {
    let mut r = Reader::new(&config);
    let width = r.u32()?;
    let height = r.u32()?;
    let format = r.u8()?;
    let quality = r.u8()?;
    let header = 10;
    let len = width as usize * height as usize * 4;
    if config.len() != header + len || width == 0 || height == 0 || format > FORMAT_TIFF {
        return None;
    }
    Some(Job::spawn(port, "cb_native_encode", move |job| {
        let mut data = config;
        data.drain(..header);
        let pixels = Pixels {
            data,
            width,
            height,
            alpha: true,
        };
        let encoded = pixels.encode(format, quality, 1)?;
        job.append(&encoded);
        Ok(())
    }))
}

// ---------------------------------------------------------------------------
// Inpainting: a line-for-line port of inpaint.dart, so results are identical.
// ---------------------------------------------------------------------------

fn has_known_neighbour(state: &[u8], index: usize, width: usize, height: usize) -> bool {
    let x = index % width;
    let y = index / width;
    (x > 0 && state[index - 1] != 0)
        || (x < width - 1 && state[index + 1] != 0)
        || (y > 0 && state[index - width] != 0)
        || (y < height - 1 && state[index + width] != 0)
}

/// Dart's `double.round()`: half away from zero, like `f64::round`.
fn round(value: f64) -> u8 {
    value.round() as i64 as u8
}

pub fn inpaint_rgba(rgba: &[u8], mask: &[u8], width: usize, height: usize) -> Vec<u8> {
    let pixel_count = width * height;
    let mut out = rgba.to_vec();
    // 0 = hole, 1 = filled, 2 = original.
    let mut state = vec![0u8; pixel_count];
    let mut hole_count = 0;
    for i in 0..pixel_count {
        if mask[i] == 0 {
            state[i] = 2;
        } else {
            hole_count += 1;
        }
    }
    if hole_count == 0 || hole_count == pixel_count {
        return out;
    }

    let mut queued = vec![0u8; pixel_count];
    let mut frontier = Vec::new();
    for i in 0..pixel_count {
        if state[i] == 0 && has_known_neighbour(&state, i, width, height) {
            frontier.push(i);
            queued[i] = 1;
        }
    }

    const RADIUS: i64 = 2;
    let (w, h) = (width as i64, height as i64);
    let mut fills: Vec<(usize, [u8; 4])> = Vec::new();
    while !frontier.is_empty() {
        fills.clear();
        for &index in &frontier {
            let x = (index % width) as i64;
            let y = (index / width) as i64;
            let (mut r, mut g, mut b, mut a, mut total) = (0.0, 0.0, 0.0, 0.0, 0.0);
            for dy in -RADIUS..=RADIUS {
                let ny = y + dy;
                if ny < 0 || ny >= h {
                    continue;
                }
                for dx in -RADIUS..=RADIUS {
                    if dx == 0 && dy == 0 {
                        continue;
                    }
                    let nx = x + dx;
                    if nx < 0 || nx >= w {
                        continue;
                    }
                    let n = (ny * w + nx) as usize;
                    let known = state[n];
                    if known == 0 {
                        continue;
                    }
                    let weight =
                        (if known == 2 { 2.0 } else { 1.0 }) / ((dx * dx + dy * dy) as f64);
                    let p = n * 4;
                    r += f64::from(out[p]) * weight;
                    g += f64::from(out[p + 1]) * weight;
                    b += f64::from(out[p + 2]) * weight;
                    a += f64::from(out[p + 3]) * weight;
                    total += weight;
                }
            }
            if total == 0.0 {
                continue;
            }
            fills.push((
                index,
                [
                    round(r / total),
                    round(g / total),
                    round(b / total),
                    round(a / total),
                ],
            ));
        }

        // Commit the whole ring at once so it does not feed on itself.
        let mut next = Vec::new();
        for (index, value) in &fills {
            out[index * 4..index * 4 + 4].copy_from_slice(value);
            state[*index] = 1;
        }
        for (index, _) in &fills {
            let x = (index % width) as i64;
            let y = (index / width) as i64;
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                if nx < 0 || ny < 0 || nx >= w || ny >= h {
                    continue;
                }
                let n = (ny * w + nx) as usize;
                if state[n] == 0 && queued[n] == 0 {
                    queued[n] = 1;
                    next.push(n);
                }
            }
        }
        // Pixels that found no known neighbour this time wait for the next ring.
        for &index in &frontier {
            if state[index] == 0 {
                next.push(index);
            }
        }
        if next.len() == frontier.len() && fills.is_empty() {
            break;
        }
        frontier = next;
    }

    smooth_hole(&mut out, mask, width, height, 4);
    out
}

fn smooth_hole(pixels: &mut [u8], mask: &[u8], width: usize, height: usize, passes: usize) {
    let holes: Vec<usize> = (0..mask.len()).filter(|&i| mask[i] != 0).collect();
    let mut values = vec![0u8; holes.len() * 4];
    for _ in 0..passes {
        for (h, &index) in holes.iter().enumerate() {
            let x = index % width;
            let y = index / width;
            let (mut r, mut g, mut b, mut a, mut count) = (0u32, 0u32, 0u32, 0u32, 0u32);
            for ny in y.saturating_sub(1)..=(y + 1).min(height - 1) {
                for nx in x.saturating_sub(1)..=(x + 1).min(width - 1) {
                    let p = (ny * width + nx) * 4;
                    r += u32::from(pixels[p]);
                    g += u32::from(pixels[p + 1]);
                    b += u32::from(pixels[p + 2]);
                    a += u32::from(pixels[p + 3]);
                    count += 1;
                }
            }
            values[h * 4] = (r / count) as u8;
            values[h * 4 + 1] = (g / count) as u8;
            values[h * 4 + 2] = (b / count) as u8;
            values[h * 4 + 3] = (a / count) as u8;
        }
        for (h, &index) in holes.iter().enumerate() {
            pixels[index * 4..index * 4 + 4].copy_from_slice(&values[h * 4..h * 4 + 4]);
        }
    }
}

/// Config: width u32, height u32, RGBA bytes, then one mask byte per pixel.
/// Output: the filled RGBA.
pub fn start_inpaint(port: i64, config: Vec<u8>) -> Option<Arc<Job>> {
    let mut r = Reader::new(&config);
    let width = r.u32()? as usize;
    let height = r.u32()? as usize;
    let pixels = width * height;
    if width == 0 || height == 0 || config.len() != 8 + pixels * 5 {
        return None;
    }
    Some(Job::spawn(port, "cb_native_inpaint", move |job| {
        let rgba = &config[8..8 + pixels * 4];
        let mask = &config[8 + pixels * 4..];
        job.append(&inpaint_rgba(rgba, mask, width, height));
        Ok(())
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::job::testing::wait;
    use crate::job::JOB_DONE;

    #[test]
    fn target_sizes_follow_the_dart_callers() {
        assert_eq!(
            target_size(4000, 3000, 512, 512, FIT_SHRINK_ONLY),
            (512, 384)
        );
        assert_eq!(target_size(300, 200, 512, 512, FIT_SHRINK_ONLY), (300, 200));
        assert_eq!(target_size(300, 200, 512, 512, FIT_BOX), (512, 341));
        assert_eq!(target_size(200, 300, 128, 128, FIT_BOX), (85, 128));
        assert_eq!(target_size(10, 3000, 128, 128, FIT_STRETCH), (128, 128));
    }

    fn sample_jpeg(width: u32, height: u32) -> Vec<u8> {
        let mut rgb = Vec::new();
        for y in 0..height {
            for x in 0..width {
                rgb.extend_from_slice(&[(x % 256) as u8, (y % 256) as u8, 128]);
            }
        }
        let mut out = Vec::new();
        JpegEncoder::new_with_quality(&mut out, 90)
            .write_image(&rgb, width, height, ExtendedColorType::Rgb8)
            .unwrap();
        out
    }

    fn thumbnail_config(bytes: &[u8], fit: u8, format: u8, enhance: bool) -> Vec<u8> {
        let mut w = Writer::default();
        w.u8(1);
        w.u32(bytes.len() as u32);
        w.raw(bytes);
        w.u32(128);
        w.u32(128);
        w.u8(fit);
        w.u8(FILTER_BOX);
        w.u8(u8::from(enhance));
        w.u8(format);
        w.u8(85);
        w.u8(1);
        w.into_bytes()
    }

    #[test]
    fn makes_jpeg_and_png_thumbnails() {
        let jpeg = sample_jpeg(1600, 1200);
        for (format, enhance) in [(FORMAT_JPEG, false), (FORMAT_PNG, true)] {
            let job =
                start_thumbnail(0, &thumbnail_config(&jpeg, FIT_BOX, format, enhance)).unwrap();
            let (state, out) = wait(&job);
            assert_eq!(state, JOB_DONE, "{}", job.error());
            let mut r = Reader::new(&out);
            assert_eq!((r.u32().unwrap(), r.u32().unwrap()), (128, 96));
            let decoded = image::load_from_memory(&out[8..]).unwrap();
            assert_eq!((decoded.width(), decoded.height()), (128, 96));
        }
        let bad = start_thumbnail(
            0,
            &thumbnail_config(b"not an image", FIT_BOX, FORMAT_PNG, false),
        )
        .unwrap();
        assert_eq!(wait(&bad).0, crate::job::JOB_FAILED);
    }

    #[test]
    fn encodes_every_editor_format() {
        let (width, height) = (8u32, 6u32);
        for format in [FORMAT_JPEG, FORMAT_PNG, FORMAT_BMP, FORMAT_GIF, FORMAT_TIFF] {
            let mut config = Writer::default();
            config.u32(width);
            config.u32(height);
            config.u8(format);
            config.u8(95);
            config.raw(&vec![200u8; (width * height * 4) as usize]);
            let job = start_encode(0, config.into_bytes()).unwrap();
            let (state, out) = wait(&job);
            assert_eq!(state, JOB_DONE, "format {format}: {}", job.error());
            let decoded = image::load_from_memory(&out).unwrap();
            assert_eq!((decoded.width(), decoded.height()), (width, height));
        }
    }

    #[test]
    fn inpaint_fills_holes_from_surroundings() {
        let (w, h) = (9, 7);
        let mut rgba = vec![0u8; w * h * 4];
        for (i, pixel) in rgba.chunks_exact_mut(4).enumerate() {
            pixel.copy_from_slice(&[(i * 3) as u8, 90, 200, 255]);
        }
        let mut mask = vec![0u8; w * h];
        for y in 2..5 {
            for x in 3..6 {
                mask[y * w + x] = 1;
                rgba[(y * w + x) * 4] = 0;
            }
        }
        let out = inpaint_rgba(&rgba, &mask, w, h);
        let centre = (3 * w + 4) * 4;
        assert!(out[centre] > 0);
        assert_eq!(out[centre + 1], 90);
        assert_eq!(out[centre + 3], 255);
        // Unmasked pixels keep their colour exactly.
        assert_eq!(out[..4], rgba[..4]);
    }
}

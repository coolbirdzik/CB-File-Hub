//! Listing and extracting zip, tar (plain, gz, bz2, xz), gz, bz2 and 7z.
//!
//! Replaces the synchronous `package:archive` decoders, which ran on the UI
//! isolate, and the 7-Zip executable for `.7z`. Extraction streams every
//! entry to disk, reports bytes as it goes and can be cancelled between
//! chunks. Entry names that would escape the destination (absolute paths,
//! `..`, drive letters) and links are skipped.

use std::fs::{self, File};
use std::io::{self, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, UNIX_EPOCH};

use crate::fsx::filetime_to_ms;
use crate::job::Job;
use crate::wire::{Reader, Writer};

const ZIP: u8 = 0;
const TAR: u8 = 1;
const TAR_GZ: u8 = 2;
const TAR_BZ2: u8 = 3;
const TAR_XZ: u8 = 4;
const GZIP: u8 = 5;
const BZIP2: u8 = 6;
const SEVEN_ZIP: u8 = 7;

const TIME_NONE: u8 = 0;
/// Milliseconds since the epoch, UTC.
const TIME_UTC: u8 = 1;
/// A wall-clock time without zone (zip's DOS time), encoded as if UTC.
const TIME_LOCAL: u8 = 2;

const CHUNK: usize = 256 * 1024;

/// Counters while extracting.
const DONE: usize = 0;
const TOTAL: usize = 1;
const ENTRIES: usize = 2;

/// Stream a set of named files to ZIP. Only explicitly supplied files enter it.
pub fn start_create_zip(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let target = r.str()?;
    let count = r.u32()?;
    let mut files = Vec::new();
    for _ in 0..count {
        let path = r.str()?;
        let name = r.str()?;
        safe_relative(&name)?;
        files.push((path, name));
    }
    if !r.is_empty() {
        return None;
    }
    Some(Job::spawn(port, "cb_create_zip", move |job| {
        let result = (|| {
            let mut zip = zip::ZipWriter::new(File::create(&target).map_err(err)?);
            let options = zip::write::SimpleFileOptions::default()
                .compression_method(zip::CompressionMethod::Deflated);
            let mut buffer = vec![0u8; CHUNK];
            for (path, name) in files {
                if job.cancelled() {
                    return Ok(());
                }
                job.set_current(&path);
                let mut file = open(&path)?;
                zip.start_file(name, options).map_err(err)?;
                loop {
                    if job.cancelled() {
                        return Ok(());
                    }
                    let n = file.read(&mut buffer).map_err(err)?;
                    if n == 0 {
                        break;
                    }
                    zip.write_all(&buffer[..n]).map_err(err)?;
                    job.add_counter(DONE, n as u64);
                }
            }
            zip.finish().map_err(err)?;
            Ok(())
        })();
        if result.is_err() || job.cancelled() {
            let _ = fs::remove_file(&target);
        }
        result
    }))
}

/// Read one member by name, leaving the rest of a ZIP compressed/on disk.
/// A missing member is a successful empty response; failures use job errors.
pub fn start_read_zip_entry(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let path = r.str()?;
    let name = r.str()?;
    if !r.is_empty() {
        return None;
    }
    Some(Job::spawn(port, "cb_read_zip_entry", move |job| {
        let mut zip = zip::ZipArchive::new(open(&path)?).map_err(err)?;
        let mut entry = match zip.by_name(&name) {
            Ok(entry) => entry,
            Err(zip::result::ZipError::FileNotFound) => {
                job.append(&[0]);
                return Ok(());
            }
            Err(e) => return Err(err(e)),
        };
        job.append(&[1]);
        let mut buffer = vec![0u8; CHUNK];
        loop {
            if job.cancelled() {
                return Ok(());
            }
            let n = entry.read(&mut buffer).map_err(err)?;
            if n == 0 {
                break;
            }
            job.append(&buffer[..n]);
        }
        Ok(())
    }))
}

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

/// Archive names use `/`; some Windows tools write `\`.
fn normalize(name: &str) -> String {
    name.replace('\\', "/")
}

/// A relative path that stays inside the destination, or None.
fn safe_relative(name: &str) -> Option<PathBuf> {
    let mut out = PathBuf::new();
    let mut depth = 0usize;
    for part in normalize(name).split('/') {
        match part {
            "" | "." => {}
            ".." => {
                if depth == 0 {
                    return None;
                }
                out.pop();
                depth -= 1;
            }
            part => {
                if part.contains(':') || part.contains('\0') {
                    return None;
                }
                out.push(part);
                depth += 1;
            }
        }
    }
    (depth > 0).then_some(out)
}

/// package:path `basename` of an entry name.
fn entry_basename(name: &str) -> String {
    normalize(name)
        .trim_end_matches('/')
        .rsplit('/')
        .next()
        .unwrap_or("")
        .to_string()
}

/// Counts bytes read from the archive file for tar progress.
struct Counting<'a, R> {
    inner: R,
    job: &'a Job,
}

impl<R: Read> Read for Counting<'_, R> {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let read = self.inner.read(buf)?;
        self.job.add_counter(DONE, read as u64);
        Ok(read)
    }
}

fn open(path: &str) -> Result<File, String> {
    File::open(path).map_err(err)
}

fn decompressed<'a>(format: u8, file: impl Read + 'a) -> Result<Box<dyn Read + 'a>, String> {
    let file = BufReader::with_capacity(CHUNK, file);
    Ok(match format {
        TAR => Box::new(file),
        TAR_GZ | GZIP => Box::new(flate2::read::MultiGzDecoder::new(file)),
        TAR_BZ2 | BZIP2 => Box::new(bzip2::read::MultiBzDecoder::new(file)),
        TAR_XZ => Box::new(lzma_rust2::XzReader::new(file, true)),
        _ => return Err(format!("not a stream format: {format}")),
    })
}

/// Copies `reader` to a new file at `target`. Returns false when cancelled.
fn write_file(
    job: &Job,
    reader: &mut dyn Read,
    target: &Path,
    count_output: bool,
) -> Result<bool, String> {
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent).map_err(err)?;
    }
    let mut out = File::create(target).map_err(|e| format!("{}: {e}", target.display()))?;
    let mut buffer = vec![0u8; CHUNK];
    loop {
        if job.cancelled() {
            drop(out);
            let _ = fs::remove_file(target);
            return Ok(false);
        }
        let read = match reader.read(&mut buffer) {
            Ok(0) => break,
            Ok(read) => read,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(err(e)),
        };
        io::Write::write_all(&mut out, &buffer[..read]).map_err(err)?;
        if count_output {
            job.add_counter(DONE, read as u64);
        }
    }
    Ok(true)
}

fn set_modified(path: &Path, epoch_ms: Option<i64>) {
    let Some(ms) = epoch_ms.filter(|ms| *ms > 0) else {
        return;
    };
    if let Ok(file) = File::options().write(true).open(path) {
        let _ = file.set_modified(UNIX_EPOCH + Duration::from_millis(ms as u64));
    }
}

struct EntryInfo {
    name: String,
    size: u64,
    compressed: u64,
    is_dir: bool,
    time_kind: u8,
    time: i64,
}

fn dos_time_ms(time: zip::DateTime) -> i64 {
    // Days from the civil date (proleptic Gregorian), then wall-clock time.
    let (y, m, d) = (
        i64::from(time.year()),
        i64::from(time.month()),
        i64::from(time.day()),
    );
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    let seconds =
        i64::from(time.hour()) * 3600 + i64::from(time.minute()) * 60 + i64::from(time.second());
    (days * 86_400 + seconds) * 1000
}

fn list_zip(path: &str) -> Result<Vec<EntryInfo>, String> {
    let mut archive = zip::ZipArchive::new(BufReader::new(open(path)?)).map_err(err)?;
    let mut entries = Vec::with_capacity(archive.len());
    for index in 0..archive.len() {
        let file = archive.by_index_raw(index).map_err(err)?;
        let name = normalize(&file.name().map_err(err)?);
        let time = file.last_modified();
        entries.push(EntryInfo {
            name,
            size: file.size(),
            compressed: file.compressed_size(),
            is_dir: file.is_dir(),
            time_kind: if time.is_some() {
                TIME_LOCAL
            } else {
                TIME_NONE
            },
            time: time.map_or(0, dos_time_ms),
        });
    }
    Ok(entries)
}

fn list_tar(job: &Job, path: &str, format: u8) -> Result<Vec<EntryInfo>, String> {
    let file = open(path)?;
    let mut archive = tar::Archive::new(decompressed(format, file)?);
    let mut entries = Vec::new();
    for entry in archive.entries().map_err(err)? {
        if job.cancelled() {
            break;
        }
        let entry = entry.map_err(err)?;
        let name = normalize(&String::from_utf8_lossy(&entry.path_bytes()));
        let header = entry.header();
        entries.push(EntryInfo {
            is_dir: header.entry_type().is_dir() || name.ends_with('/'),
            size: entry.size(),
            compressed: 0,
            time_kind: TIME_UTC,
            time: header.mtime().map_or(0, |s| s as i64 * 1000),
            name,
        });
    }
    Ok(entries)
}

fn seven_zip_time(entry: &sevenz_rust2::ArchiveEntry) -> (u8, i64) {
    if entry.has_last_modified_date {
        (
            TIME_UTC,
            filetime_to_ms(u64::from(entry.last_modified_date)),
        )
    } else {
        (TIME_NONE, 0)
    }
}

fn list_seven_zip(path: &str) -> Result<Vec<EntryInfo>, String> {
    let archive = sevenz_rust2::Archive::open(path).map_err(err)?;
    Ok(archive
        .files
        .iter()
        .map(|entry| {
            let (time_kind, time) = seven_zip_time(entry);
            EntryInfo {
                name: normalize(&entry.name),
                size: entry.size,
                compressed: entry.compressed_size,
                is_dir: entry.is_directory,
                time_kind,
                time,
            }
        })
        .collect())
}

fn read_entries(job: &Job, path: &str, format: u8) -> Result<Vec<EntryInfo>, String> {
    Ok(match format {
        ZIP => list_zip(path)?,
        TAR | TAR_GZ | TAR_BZ2 | TAR_XZ => list_tar(job, path, format)?,
        SEVEN_ZIP => list_seven_zip(path)?,
        _ => return Err(format!("cannot list format {format}")),
    })
}

fn list(job: &Job, path: &str, format: u8) -> Result<(), String> {
    let entries = read_entries(job, path, format)?;
    let mut out = Writer::default();
    for entry in entries.iter().filter(|entry| !entry.name.is_empty()) {
        out.str(&entry.name);
        out.u64(entry.size);
        out.u64(entry.compressed);
        out.u8(u8::from(entry.is_dir));
        out.u8(entry.time_kind);
        out.i64(entry.time);
    }
    job.append(&out.into_bytes());
    Ok(())
}

type ChildNames = (Vec<String>, Vec<String>);
struct DirectoryIndex {
    path: String,
    format: u8,
    fingerprint: (
        u64,
        Option<std::time::SystemTime>,
        Option<std::time::SystemTime>,
    ),
    directories: std::collections::HashMap<String, ChildNames>,
}
static DIRECTORY_CACHE: std::sync::OnceLock<
    std::sync::Mutex<std::collections::VecDeque<Arc<DirectoryIndex>>>,
> = std::sync::OnceLock::new();

fn fingerprint(
    path: &str,
) -> Result<
    (
        u64,
        Option<std::time::SystemTime>,
        Option<std::time::SystemTime>,
    ),
    String,
> {
    let m = fs::metadata(path).map_err(err)?;
    Ok((m.len(), m.modified().ok(), m.created().ok()))
}

/// Cached archive directory index: only names in the requested folder cross FFI.
pub fn start_children(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let path = r.str()?;
    let format = r.u8()?;
    let inner = r.str()?;
    if !r.is_empty() || matches!(format, GZIP | BZIP2) {
        return None;
    }
    Some(Job::spawn(port, "cb_archive_children", move |job| {
        use crate::{
            job::lock,
            normalize::{dart_compare, dart_lower},
        };
        use std::collections::{BTreeSet, HashMap};
        let key = fs::canonicalize(&path)
            .map_err(err)?
            .to_string_lossy()
            .into_owned();
        let before = fingerprint(&path)?;
        let cache = DIRECTORY_CACHE.get_or_init(Default::default);
        let cached = {
            let mut entries = lock(cache);
            let pos = entries
                .iter()
                .position(|e| e.path == key && e.format == format && e.fingerprint == before);
            pos.and_then(|i| entries.remove(i))
                .inspect(|e| entries.push_front(Arc::clone(e)))
        };
        let index = if let Some(index) = cached {
            index
        } else {
            let entries = read_entries(job, &path, format)?;
            let entry_count = entries.len();
            let mut dirs: HashMap<String, (BTreeSet<String>, BTreeSet<String>)> = HashMap::new();
            let mut cost = 0usize;
            for entry in entries {
                if job.cancelled() {
                    return Ok(());
                }
                let parts: Vec<&str> = entry.name.split('/').filter(|s| !s.is_empty()).collect();
                let mut parent = String::new();
                for (i, part) in parts.iter().enumerate() {
                    cost += parent.len() + part.len();
                    let children = dirs.entry(parent.clone()).or_default();
                    if i + 1 < parts.len() || entry.is_dir {
                        children.0.insert((*part).to_string());
                    } else {
                        children.1.insert((*part).to_string());
                    }
                    if !parent.is_empty() {
                        parent.push('/');
                    }
                    parent.push_str(part);
                }
            }
            let mut directories = HashMap::new();
            for (path, (folders, files)) in dirs {
                let sorted = |set: BTreeSet<String>| {
                    let mut names: Vec<_> = set.into_iter().map(|s| (dart_lower(&s), s)).collect();
                    names.sort_by(|a, b| dart_compare(&a.0, &b.0));
                    names.into_iter().map(|(_, s)| s).collect()
                };
                directories.insert(path, (sorted(folders), sorted(files)));
            }
            if fingerprint(&path)? != before {
                return Err("archive changed while being indexed".into());
            }
            let index = Arc::new(DirectoryIndex {
                path: key.clone(),
                format,
                fingerprint: before,
                directories,
            });
            if entry_count <= 200_000 && cost <= 32 * 1024 * 1024 {
                let mut entries = lock(cache);
                entries.retain(|e| e.path != key || e.format != format);
                entries.push_front(Arc::clone(&index));
                entries.truncate(2);
            }
            index
        };
        let inner = normalize(&inner)
            .split('/')
            .filter(|s| !s.is_empty())
            .collect::<Vec<_>>()
            .join("/");
        let mut out = Writer::default();
        if let Some((folders, files)) = index.directories.get(&inner) {
            out.u32(folders.len() as u32);
            for name in folders {
                out.str(name);
            }
            out.u32(files.len() as u32);
            for name in files {
                out.str(name);
            }
        } else {
            out.u32(0);
            out.u32(0);
        }
        job.append(&out.into_bytes());
        Ok(())
    }))
}

/// Where an entry goes: under its own path for a full extraction, or flat
/// under its base name for a single one (`7z e` / `extractEntry`).
fn target_for(dest: &Path, name: &str, single: bool) -> Option<PathBuf> {
    if single {
        let base = entry_basename(name);
        safe_relative(&base).map(|relative| dest.join(relative))
    } else {
        safe_relative(name).map(|relative| dest.join(relative))
    }
}

fn extract_zip(job: &Job, path: &str, dest: &Path, entry: Option<&str>) -> Result<(), String> {
    let mut archive = zip::ZipArchive::new(BufReader::new(open(path)?)).map_err(err)?;
    let mut indices = Vec::new();
    let mut total = 0;
    for index in 0..archive.len() {
        let file = archive.by_index_raw(index).map_err(err)?;
        let name = normalize(&file.name().map_err(err)?);
        if entry.is_some_and(|wanted| wanted != name) {
            continue;
        }
        total += file.size();
        indices.push(index);
        if entry.is_some() {
            break;
        }
    }
    if entry.is_some() && indices.is_empty() {
        return Err(format!("Entry not found: {}", entry.unwrap_or_default()));
    }
    job.set_counter(TOTAL, total);
    job.set_counter(3, indices.len() as u64);
    for index in indices {
        let mut file = archive.by_index(index).map_err(err)?;
        let name = normalize(&file.name().map_err(err)?);
        let is_dir = file.is_dir();
        let symlink = file.is_symlink();
        job.set_current(&name);
        if let Some(target) = target_for(dest, &name, entry.is_some()) {
            if is_dir {
                fs::create_dir_all(&target).map_err(err)?;
            } else if !symlink && !write_file(job, &mut file, &target, true)? {
                return Ok(());
            }
        }
        job.add_counter(ENTRIES, 1);
    }
    Ok(())
}

fn extract_tar(
    job: &Job,
    path: &str,
    format: u8,
    dest: &Path,
    entry: Option<&str>,
) -> Result<(), String> {
    let file = open(path)?;
    job.set_counter(TOTAL, file.metadata().map_or(0, |m| m.len()));
    let counting = Counting { inner: file, job };
    let mut archive = tar::Archive::new(decompressed(format, counting)?);
    let mut found = false;
    for item in archive.entries().map_err(err)? {
        if job.cancelled() {
            return Ok(());
        }
        let mut item = item.map_err(err)?;
        let name = normalize(&String::from_utf8_lossy(&item.path_bytes()));
        if entry.is_some_and(|wanted| wanted != name) {
            continue;
        }
        found = true;
        job.set_current(&name);
        let kind = item.header().entry_type();
        let modified = item.header().mtime().ok().map(|s| s as i64 * 1000);
        if let Some(target) = target_for(dest, &name, entry.is_some()) {
            if kind.is_dir() || name.ends_with('/') {
                fs::create_dir_all(&target).map_err(err)?;
            } else if kind.is_file() || kind.is_contiguous() || kind.is_gnu_sparse() {
                if !write_file(job, &mut item, &target, false)? {
                    return Ok(());
                }
                set_modified(&target, modified);
            }
        }
        job.add_counter(ENTRIES, 1);
        if entry.is_some() {
            break;
        }
    }
    if entry.is_some() && !found {
        return Err(format!("Entry not found: {}", entry.unwrap_or_default()));
    }
    Ok(())
}

/// A lone `.gz` / `.bz2`: one member named after the archive.
fn extract_stream(
    job: &Job,
    path: &str,
    format: u8,
    dest: &Path,
    entry: Option<&str>,
) -> Result<(), String> {
    let file = open(path)?;
    job.set_counter(TOTAL, file.metadata().map_or(0, |m| m.len()));
    let name = match entry {
        Some(entry) => entry_basename(entry),
        None => {
            let base = Path::new(path)
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default();
            let ext = crate::fsx::path_extension(&base).len();
            let stem = base[..base.len() - ext].to_string();
            if stem.is_empty() {
                "extracted".to_string()
            } else {
                stem
            }
        }
    };
    let target = safe_relative(&name)
        .map(|relative| dest.join(relative))
        .ok_or_else(|| format!("unsafe name: {name}"))?;
    let counting = Counting { inner: file, job };
    let mut reader = decompressed(format, counting)?;
    write_file(job, &mut reader, &target, false)?;
    job.add_counter(ENTRIES, 1);
    Ok(())
}

fn extract_seven_zip(
    job: &Job,
    path: &str,
    dest: &Path,
    entry: Option<&str>,
) -> Result<(), String> {
    let mut reader =
        sevenz_rust2::ArchiveReader::open(path, sevenz_rust2::Password::empty()).map_err(err)?;
    let total = reader
        .archive()
        .files
        .iter()
        .filter(|file| entry.is_none_or(|wanted| normalize(&file.name) == wanted))
        .map(|file| file.size)
        .sum();
    job.set_counter(TOTAL, total);
    if let Some(wanted) = entry {
        if !reader
            .archive()
            .files
            .iter()
            .any(|file| normalize(&file.name) == wanted)
        {
            return Err(format!("Entry not found: {wanted}"));
        }
    }
    let mut failure: Option<String> = None;
    let mut done_single = false;
    reader
        .for_each_entries(|file, data| {
            if job.cancelled() {
                return Ok(false);
            }
            let name = normalize(&file.name);
            let wanted = entry.is_none_or(|wanted| wanted == name);
            let target = if wanted {
                target_for(dest, &name, entry.is_some())
            } else {
                None
            };
            let result = match target {
                Some(target) if file.is_directory => fs::create_dir_all(&target).map_err(err),
                Some(target) if !file.is_anti_item => {
                    let written = write_file(job, data, &target, true);
                    if let Ok(true) = written {
                        let (kind, time) = seven_zip_time(file);
                        set_modified(&target, (kind == TIME_UTC).then_some(time));
                    }
                    written.map(|_| ())
                }
                // Solid blocks decode front to back: skipped data still has
                // to be read through.
                _ => io::copy(data, &mut io::sink()).map(|_| ()).map_err(err),
            };
            if let Err(message) = result {
                failure = Some(message);
                return Ok(false);
            }
            if wanted {
                job.add_counter(ENTRIES, 1);
                if entry.is_some() {
                    done_single = true;
                    return Ok(false);
                }
            }
            Ok(!job.cancelled())
        })
        .map_err(err)?;
    if let Some(message) = failure {
        return Err(message);
    }
    if entry.is_some() && !done_single && !job.cancelled() {
        return Err(format!("Entry not found: {}", entry.unwrap_or_default()));
    }
    Ok(())
}

fn extract(
    job: &Job,
    path: &str,
    format: u8,
    dest: &str,
    entry: Option<&str>,
) -> Result<(), String> {
    let dest = Path::new(dest);
    fs::create_dir_all(dest).map_err(err)?;
    match format {
        ZIP => extract_zip(job, path, dest, entry),
        TAR | TAR_GZ | TAR_BZ2 | TAR_XZ => extract_tar(job, path, format, dest, entry),
        GZIP | BZIP2 => extract_stream(job, path, format, dest, entry),
        SEVEN_ZIP => extract_seven_zip(job, path, dest, entry),
        _ => Err(format!("cannot extract format {format}")),
    }
}

/// Config: path, format u8. Output per entry: name, size u64, compressed
/// size u64, is directory u8, time kind u8, time i64.
pub fn start_list(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let path = r.str()?;
    let format = r.u8()?;
    if !r.is_empty()
        || path.is_empty()
        || !matches!(format, ZIP | TAR | TAR_GZ | TAR_BZ2 | TAR_XZ | SEVEN_ZIP)
    {
        return None;
    }
    Some(Job::spawn(port, "cb_native_archive", move |job| {
        list(job, &path, format)
    }))
}

/// Config: path, format u8, destination, single u8, entry name. Counters:
/// bytes done, bytes total, entries done, entries total (0 when unknown).
pub fn start_extract(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let path = r.str()?;
    let format = r.u8()?;
    let dest = r.str()?;
    let single = r.bool()?;
    let entry = normalize(&r.str()?);
    if !r.is_empty()
        || path.is_empty()
        || dest.is_empty()
        || format > SEVEN_ZIP
        || (single && entry.is_empty())
    {
        return None;
    }
    Some(Job::spawn(port, "cb_native_archive", move |job| {
        extract(job, &path, format, &dest, single.then_some(entry.as_str()))
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::job::testing::wait;
    use crate::job::{JOB_DONE, JOB_FAILED};
    use std::io::Write;

    fn temp(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("cb_native_archive_{name}_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn list_names(path: &Path, format: u8) -> Vec<(String, bool)> {
        let mut config = Writer::default();
        config.str(&path.to_string_lossy());
        config.u8(format);
        let job = start_list(0, &config.into_bytes()).unwrap();
        let (state, out) = wait(&job);
        assert_eq!(state, JOB_DONE, "{}", job.error());
        let mut r = Reader::new(&out);
        let mut names = Vec::new();
        while !r.is_empty() {
            let name = r.str().unwrap();
            r.u64().unwrap();
            r.u64().unwrap();
            let is_dir = r.u8().unwrap() != 0;
            r.u8().unwrap();
            r.i64().unwrap();
            names.push((name, is_dir));
        }
        names
    }

    fn run_extract(path: &Path, format: u8, dest: &Path, entry: Option<&str>) -> i32 {
        let mut config = Writer::default();
        config.str(&path.to_string_lossy());
        config.u8(format);
        config.str(&dest.to_string_lossy());
        config.u8(u8::from(entry.is_some()));
        config.str(entry.unwrap_or(""));
        let job = start_extract(0, &config.into_bytes()).unwrap();
        wait(&job).0
    }

    #[test]
    fn rejects_escaping_names() {
        assert_eq!(
            safe_relative("a/b.txt"),
            Some(PathBuf::from("a").join("b.txt"))
        );
        assert_eq!(
            safe_relative("/etc/passwd"),
            Some(PathBuf::from("etc").join("passwd"))
        );
        assert_eq!(safe_relative("a/../../x"), None);
        assert_eq!(safe_relative("C:/x"), None);
        assert_eq!(safe_relative("./"), None);
        assert_eq!(entry_basename("docs/sub/"), "sub");
    }

    #[test]
    fn zip_round_trip() {
        let dir = temp("zip");
        let path = dir.join("sample.zip");
        {
            let mut writer = zip::ZipWriter::new(File::create(&path).unwrap());
            let options = zip::write::SimpleFileOptions::default()
                .compression_method(zip::CompressionMethod::Deflated);
            writer.add_directory("docs/", options).unwrap();
            writer.start_file("docs/a.txt", options).unwrap();
            writer.write_all(b"hello archive").unwrap();
            writer.start_file("../evil.txt", options).unwrap();
            writer.write_all(b"x").unwrap();
            writer.finish().unwrap();
        }
        let names = list_names(&path, ZIP);
        assert!(names.contains(&("docs/".to_string(), true)));
        assert!(names.contains(&("docs/a.txt".to_string(), false)));

        let out = dir.join("out");
        assert_eq!(run_extract(&path, ZIP, &out, None), JOB_DONE);
        assert_eq!(
            fs::read(out.join("docs").join("a.txt")).unwrap(),
            b"hello archive"
        );
        assert!(!dir.join("evil.txt").exists());

        let single = dir.join("single");
        assert_eq!(
            run_extract(&path, ZIP, &single, Some("docs/a.txt")),
            JOB_DONE
        );
        assert_eq!(fs::read(single.join("a.txt")).unwrap(), b"hello archive");
        assert_eq!(run_extract(&path, ZIP, &single, Some("nope")), JOB_FAILED);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn tar_gz_and_gz_round_trip() {
        let dir = temp("tgz");
        let path = dir.join("sample.tar.gz");
        {
            let gz = flate2::write::GzEncoder::new(
                File::create(&path).unwrap(),
                flate2::Compression::fast(),
            );
            let mut builder = tar::Builder::new(gz);
            let mut header = tar::Header::new_gnu();
            header.set_size(5);
            header.set_mode(0o644);
            header.set_mtime(1_700_000_000);
            header.set_cksum();
            builder
                .append_data(&mut header, "dir/five.bin", &b"12345"[..])
                .unwrap();
            builder.into_inner().unwrap().finish().unwrap();
        }
        assert_eq!(
            list_names(&path, TAR_GZ),
            vec![("dir/five.bin".to_string(), false)]
        );
        let out = dir.join("out");
        assert_eq!(run_extract(&path, TAR_GZ, &out, None), JOB_DONE);
        let target = out.join("dir").join("five.bin");
        assert_eq!(fs::read(&target).unwrap(), b"12345");
        let modified = fs::metadata(&target).unwrap().modified().unwrap();
        assert_eq!(
            modified.duration_since(UNIX_EPOCH).unwrap().as_secs(),
            1_700_000_000
        );

        let gz_path = dir.join("note.txt.gz");
        {
            let mut gz = flate2::write::GzEncoder::new(
                File::create(&gz_path).unwrap(),
                flate2::Compression::fast(),
            );
            gz.write_all(b"plain").unwrap();
            gz.finish().unwrap();
        }
        assert_eq!(run_extract(&gz_path, GZIP, &out, None), JOB_DONE);
        assert_eq!(fs::read(out.join("note.txt")).unwrap(), b"plain");
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn seven_zip_lists_and_extracts_without_7zip() {
        // Made by 7-Zip: solid LZMA2 with docs/a.txt and docs/sub/b.txt.
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("testdata")
            .join("sample.7z");
        let mut names = list_names(&path, SEVEN_ZIP);
        names.sort();
        assert_eq!(
            names,
            vec![
                ("docs".to_string(), true),
                ("docs/a.txt".to_string(), false),
                ("docs/sub".to_string(), true),
                ("docs/sub/b.txt".to_string(), false),
            ]
        );
        let dir = temp("7z");
        let out = dir.join("out");
        assert_eq!(run_extract(&path, SEVEN_ZIP, &out, None), JOB_DONE);
        assert_eq!(
            fs::read(out.join("docs").join("a.txt")).unwrap(),
            b"hello seven"
        );
        assert_eq!(
            fs::read(out.join("docs").join("sub").join("b.txt")).unwrap(),
            b"second file contents"
        );
        let single = dir.join("single");
        assert_eq!(
            run_extract(&path, SEVEN_ZIP, &single, Some("docs/sub/b.txt")),
            JOB_DONE
        );
        assert_eq!(
            fs::read(single.join("b.txt")).unwrap(),
            b"second file contents"
        );
        assert_eq!(
            run_extract(&path, SEVEN_ZIP, &single, Some("nope")),
            JOB_FAILED
        );
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn dos_times_convert_to_wall_clock_ms() {
        let time = zip::DateTime::from_date_and_time(2024, 1, 2, 3, 4, 6).unwrap();
        assert_eq!(dos_time_ms(time), 1_704_164_646_000);
    }
}

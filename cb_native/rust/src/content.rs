//! The agent's content search: finds files by the words they contain.
//!
//! Directories and files are separate tasks on the shared walk pool, so
//! reading, text extraction (including PDF) and matching run on every worker
//! at once. Matching mirrors `ContentSearch._match` in
//! cb_file_manager/lib/services/ai/content_search.dart: the same folding,
//! hit counts, snippets and line numbers.

use std::collections::HashMap;
use std::fs;
use std::io::{self, Read};
use std::sync::atomic::{AtomicU64, AtomicU8, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use crate::doctext::{self, Format};
use crate::fsx;
use crate::job::{lock, Job};
#[cfg(test)]
use crate::normalize::search_key;
use crate::normalize::{dart_lower, search_key_into};
use crate::walk::{self, Kind, Task, Walk};
use crate::wire::{Reader, Writer};

pub const RECORD_MATCH: u8 = 1;
pub const RECORD_WARNING: u8 = 2;
pub const RECORD_SUMMARY: u8 = 3;

pub const STOP_NONE: u8 = 0;
pub const STOP_ENTRIES: u8 = 1;
pub const STOP_TIME: u8 = 2;
pub const STOP_READ_BUDGET: u8 = 3;
pub const STOP_RESULTS: u8 = 4;

const SNIPPETS_PER_FILE: usize = 3;
const SNIPPET_UNITS: usize = 200;

/// Tool and VCS folders that drown real documents in noise.
const SKIPPED_DIRECTORIES: &[&str] = &[
    ".git",
    ".svn",
    ".hg",
    "node_modules",
    ".dart_tool",
    "__pycache__",
    "$recycle.bin",
    "system volume information",
];

/// Windows and installed programs, skipped right below a drive root; a search
/// rooted inside one still reads it.
const SYSTEM_DIRECTORIES: &[&str] = &[
    "windows",
    "program files",
    "program files (x86)",
    "programdata",
    "$winreagent",
    "recovery",
    "msocache",
    // Unix roots.
    "proc",
    "sys",
    "dev",
    "usr",
    "bin",
    "sbin",
    "lib",
    "lib64",
    "boot",
    "snap",
    "system",
    "library",
    "private",
];

/// Application caches and settings, wherever they are below the root: large,
/// noisy and never what "find my file" means.
const APP_DATA_DIRECTORIES: &[&str] = &["appdata"];

/// Counters: files searched, matches, entries visited, bytes read.
struct ContentSearch {
    recursive: bool,
    case_sensitive: bool,
    match_all: bool,
    terms: Vec<String>,
    extension: String,
    max_entries: u64,
    max_results: u64,
    max_read_bytes: u64,
    /// The root is `C:\` or `/`, so system folders below it are skipped.
    root_is_drive: bool,
    time_limit: Duration,
    started: Instant,
    read_bytes: AtomicU64,
    too_large: AtomicU64,
    /// Documents without extractable text, such as scanned PDFs.
    no_text: AtomicU64,
    /// Placeholders of cloud files, never read so they are not downloaded.
    cloud_only: AtomicU64,
    stop_reason: AtomicU8,
    unsupported: Mutex<HashMap<String, u64>>,
    /// System and app-data folders not entered, for the summary.
    skipped_system: Mutex<Vec<String>>,
}

impl ContentSearch {
    fn stop(&self, walk: &Walk, reason: u8) {
        let _ = self.stop_reason.compare_exchange(
            STOP_NONE,
            reason,
            Ordering::AcqRel,
            Ordering::Acquire,
        );
        walk.stop.store(true, Ordering::Relaxed);
    }

    fn warn(job: &Job, message: String) {
        let mut out = Writer::default();
        out.u8(RECORD_WARNING);
        out.str(&message);
        job.append(&out.into_bytes());
    }

    fn scan_directory(&self, walk: &Walk, task: &Task) -> Vec<Task> {
        let job = &walk.job;
        let entries = match fs::read_dir(&task.path) {
            Ok(entries) => entries,
            Err(error) => {
                Self::warn(job, format!("Could not list {}: {}", task.path, error));
                return Vec::new();
            }
        };
        job.set_current(&task.path);
        let mut children = Vec::new();
        for entry in entries {
            if walk.halted() {
                break;
            }
            if job.add_counter(2, 1) > self.max_entries {
                self.stop(walk, STOP_ENTRIES);
                break;
            }
            if self.started.elapsed() > self.time_limit {
                self.stop(walk, STOP_TIME);
                break;
            }
            let Ok(entry) = entry else { continue };
            let Ok(file_type) = entry.file_type() else {
                continue;
            };
            // Directory.listSync(followLinks: false) reports links as Link.
            if file_type.is_symlink() {
                continue;
            }
            if cloud_only(&entry) {
                self.cloud_only.fetch_add(1, Ordering::Relaxed);
                continue;
            }
            let name = entry.file_name().to_string_lossy().into_owned();
            let path = fsx::join(&task.path, &name);
            if file_type.is_dir() {
                let lower = dart_lower(&name);
                if !self.recursive || SKIPPED_DIRECTORIES.contains(&lower.as_str()) {
                    continue;
                }
                if APP_DATA_DIRECTORIES.contains(&lower.as_str())
                    || is_tool_cache(&lower, &task.path)
                    || (task.depth == 0
                        && self.root_is_drive
                        && SYSTEM_DIRECTORIES.contains(&lower.as_str()))
                {
                    let mut skipped = lock(&self.skipped_system);
                    if skipped.len() < 50 {
                        skipped.push(path);
                    }
                    continue;
                }
                children.push(Task::dir(path, task.depth + 1));
                continue;
            }
            let extension = dart_lower(fsx::path_extension(&name));
            if !self.extension.is_empty() && extension != self.extension {
                continue;
            }
            match Format::of(&extension) {
                Format::Binary => {}
                Format::Unsupported => {
                    *lock(&self.unsupported).entry(extension).or_insert(0) += 1;
                }
                _ => children.push(Task {
                    path,
                    depth: task.depth,
                    file: true,
                }),
            }
        }
        children
    }

    fn search_file(&self, walk: &Walk, path: &str) {
        let job = &walk.job;
        let format = Format::of(&dart_lower(fsx::path_extension(path)));
        let metadata = match fs::metadata(path) {
            Ok(metadata) => metadata,
            Err(error) => {
                Self::warn(job, format!("Could not read {path}: {error}"));
                return;
            }
        };
        let size = metadata.len();
        if size > format.max_bytes() {
            self.too_large.fetch_add(1, Ordering::Relaxed);
            return;
        }
        if self.read_bytes.load(Ordering::Relaxed) + size > self.max_read_bytes {
            self.stop(walk, STOP_READ_BUDGET);
            return;
        }
        let (bytes, read) = match read_candidate(path, format, size) {
            Ok(read) => read,
            Err(error) => {
                Self::warn(job, format!("Could not read {path}: {error}"));
                return;
            }
        };
        self.read_bytes.fetch_add(read, Ordering::Relaxed);
        job.add_counter(3, read);
        let Some(bytes) = bytes else {
            return;
        };
        let Some(text) = doctext::extract(format, &bytes) else {
            if format != Format::Text {
                self.no_text.fetch_add(1, Ordering::Relaxed);
            }
            return;
        };
        drop(bytes);
        job.add_counter(0, 1);
        let Some(found) = find(&text, &self.terms, self.case_sensitive, self.match_all) else {
            return;
        };
        let mut out = Writer::default();
        out.u8(RECORD_MATCH);
        out.str(path);
        out.str(format.name());
        out.u64(size);
        out.i64(fsx::modified_ms(&metadata));
        out.u64(found.hits);
        out.u32(found.matched.len() as u32);
        for index in &found.matched {
            out.u32(*index as u32);
        }
        out.u32(found.snippets.len() as u32);
        for (line, text) in &found.snippets {
            out.u32(*line);
            out.str(text);
        }
        job.append(&out.into_bytes());
        if job.add_counter(1, 1) >= self.max_results {
            self.stop(walk, STOP_RESULTS);
        }
    }
}

impl Kind for ContentSearch {
    fn scan(&self, walk: &Walk, task: &Task) -> Vec<Task> {
        if task.file {
            self.search_file(walk, &task.path);
            Vec::new()
        } else {
            self.scan_directory(walk, task)
        }
    }

    fn finish(&self, walk: &Walk) -> Result<(), String> {
        let mut out = Writer::default();
        out.u8(RECORD_SUMMARY);
        out.u64(self.too_large.load(Ordering::Relaxed));
        out.u8(self.stop_reason.load(Ordering::Acquire));
        out.u64(walk.job.counter(0));
        out.u64(self.no_text.load(Ordering::Relaxed));
        out.u64(self.cloud_only.load(Ordering::Relaxed));
        let mut skipped = lock(&self.skipped_system).clone();
        skipped.sort();
        out.u32(skipped.len() as u32);
        for path in &skipped {
            out.str(path);
        }
        let unsupported = lock(&self.unsupported);
        let mut kinds: Vec<_> = unsupported.iter().collect();
        kinds.sort();
        out.u32(kinds.len() as u32);
        for (extension, count) in kinds {
            out.str(extension);
            out.u64(*count);
        }
        walk.job.append(&out.into_bytes());
        Ok(())
    }
}

/// The file's bytes and how many were read. A plain-text candidate whose
/// first 8 KiB hold a NUL (the same probe `doctext` applies) is binary: only
/// that much is read and the bytes are None, so extension-less caches do not
/// drain the read budget.
fn read_candidate(path: &str, format: Format, size: u64) -> io::Result<(Option<Vec<u8>>, u64)> {
    let mut file = fs::File::open(path)?;
    let mut bytes = Vec::with_capacity(size.min(format.max_bytes()) as usize);
    if format == Format::Text {
        (&mut file).take(8192).read_to_end(&mut bytes)?;
        let utf16 = bytes.starts_with(&[0xFF, 0xFE]) || bytes.starts_with(&[0xFE, 0xFF]);
        if !utf16 && bytes.contains(&0) {
            let read = bytes.len() as u64;
            return Ok((None, read));
        }
    }
    file.read_to_end(&mut bytes)?;
    let read = bytes.len() as u64;
    Ok((Some(bytes), read))
}

/// An entry whose data lives in the cloud (OneDrive, iCloud, Dropbox...):
/// reading it would download it. OFFLINE, RECALL_ON_OPEN and
/// RECALL_ON_DATA_ACCESS; the attributes come with the listing, so checking
/// opens nothing.
#[cfg(windows)]
fn cloud_only(entry: &fs::DirEntry) -> bool {
    use std::os::windows::fs::MetadataExt;
    const CLOUD: u32 = 0x1000 | 0x40000 | 0x400000;
    entry
        .metadata()
        .is_ok_and(|metadata| metadata.file_attributes() & CLOUD != 0)
}

#[cfg(not(windows))]
fn cloud_only(_entry: &fs::DirEntry) -> bool {
    false
}

pub struct Found {
    pub hits: u64,
    pub matched: Vec<usize>,
    pub snippets: Vec<(u32, String)>,
}

/// Hits per term over the whole text, plus the first lines that show them.
pub fn find(text: &str, terms: &[String], case_sensitive: bool, match_all: bool) -> Option<Found> {
    let mut hits = vec![0u64; terms.len()];
    let mut snippets = Vec::new();
    let mut folded = String::new();
    for (index, line) in text.split('\n').enumerate() {
        if line.is_empty() {
            continue;
        }
        let haystack = if case_sensitive {
            line
        } else {
            search_key_into(line, &mut folded);
            folded.as_str()
        };
        let mut first_at = None;
        for (term_index, term) in terms.iter().enumerate() {
            let mut starts = haystack
                .match_indices(term.as_str())
                .filter(|&(at, _)| starts_word(haystack, at, term));
            let Some((at, _)) = starts.next() else {
                continue;
            };
            first_at.get_or_insert(at);
            hits[term_index] += 1 + starts.count() as u64;
        }
        if let Some(at) = first_at {
            if snippets.len() < SNIPPETS_PER_FILE {
                let offset = haystack[..at].encode_utf16().count();
                let length = haystack.encode_utf16().count();
                snippets.push(((index + 1) as u32, snippet(line, offset, length)));
            }
        }
    }
    let matched: Vec<usize> = (0..terms.len()).filter(|&i| hits[i] > 0).collect();
    if matched.is_empty() || (match_all && matched.len() < terms.len()) {
        return None;
    }
    Some(Found {
        hits: hits.iter().sum(),
        matched,
        snippets,
    })
}

/// A term matches where a word starts, like Windows Search: "f95" finds
/// "F95" and "f95zone" but not the hex in "0x1f95f", which buried real
/// documents under thousands of code hits. A number may follow letters
/// ("2048" in "INV2048"), and text without spaces (CJK) matches anywhere.
/// `ContentSearch._startsWord` in Dart is the same rule.
fn starts_word(haystack: &str, at: usize, term: &str) -> bool {
    let Some(first) = term.chars().next() else {
        return true;
    };
    if !first.is_ascii_alphanumeric() {
        return true;
    }
    match haystack[..at].chars().next_back() {
        None => true,
        Some(previous) if !previous.is_ascii_alphanumeric() => true,
        Some(previous) => previous.is_ascii_alphabetic() && first.is_ascii_digit(),
    }
}

/// Hidden tool folders (`.cargo`, `.gradle`, `.vscode`...) and Go's module
/// cache (`pkg/mod`): dependency sources, never the user's documents.
fn is_tool_cache(lower_name: &str, parent: &str) -> bool {
    lower_name.starts_with('.')
        || (lower_name == "mod"
            && std::path::Path::new(parent)
                .file_name()
                .is_some_and(|name| dart_lower(&name.to_string_lossy()) == "pkg"))
}

/// Dart's RegExp `\s`.
fn is_regexp_space(c: char) -> bool {
    matches!(
        c as u32,
        0x09..=0x0D
            | 0x20
            | 0xA0
            | 0x1680
            | 0x2000..=0x200A
            | 0x2028
            | 0x2029
            | 0x202F
            | 0x205F
            | 0x3000
            | 0xFEFF
    )
}

/// `ContentSearch._snippet`, in UTF-16 units like the Dart string it mirrors.
fn snippet(line: &str, key_offset: usize, key_length: usize) -> String {
    let bom = char::from_u32(0xFEFF).unwrap_or(' ');
    let trimmed = line.trim_matches(|c: char| c.is_whitespace() || c == bom);
    let mut clean = String::with_capacity(trimmed.len());
    let mut gap = false;
    for c in trimmed.chars() {
        if is_regexp_space(c) {
            gap = true;
            continue;
        }
        if gap {
            clean.push(' ');
            gap = false;
        }
        clean.push(c);
    }
    let units: Vec<u16> = clean.encode_utf16().collect();
    if units.len() <= SNIPPET_UNITS {
        return clean;
    }
    let center = if key_length == 0 {
        0
    } else {
        (key_offset as f64 * units.len() as f64 / key_length as f64).round() as usize
    };
    let mut start = center.saturating_sub(SNIPPET_UNITS / 3);
    let mut end = start + SNIPPET_UNITS;
    if end > units.len() {
        end = units.len();
        start = end - SNIPPET_UNITS;
    }
    let mut out = String::new();
    if start > 0 {
        out.push('…');
    }
    out.push_str(&String::from_utf16_lossy(&units[start..end]));
    if end < units.len() {
        out.push('…');
    }
    out
}

/// Config: root, recursive u8, case-sensitive u8, match-all u8, terms
/// (already search keys unless case-sensitive), lower-cased extension with
/// its dot or empty, max entries u64, max results u64, max read bytes u64,
/// time limit ms u64. Output: `RECORD_MATCH` (path, format, size u64,
/// modified ms i64, hits u64, matched term indices, snippets as line u32 +
/// text), `RECORD_WARNING` (message), then one `RECORD_SUMMARY` (too-large
/// files u64, stop reason u8, files searched u64, documents without text
/// u64, cloud-only entries skipped u64, skipped system/app-data folders,
/// unsupported extensions with counts).
pub fn start_content_search(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let root = r.str()?;
    let recursive = r.bool()?;
    let case_sensitive = r.bool()?;
    let match_all = r.bool()?;
    let terms = r.strs()?;
    let extension = r.str()?;
    let max_entries = r.u64()?;
    let max_results = r.u64()?;
    let max_read_bytes = r.u64()?;
    let time_limit_ms = r.u64()?;
    if !r.is_empty() || root.is_empty() || terms.iter().all(String::is_empty) {
        return None;
    }
    let kind = ContentSearch {
        recursive,
        case_sensitive,
        match_all,
        terms: terms.into_iter().filter(|term| !term.is_empty()).collect(),
        extension,
        max_entries,
        max_results: max_results.max(1),
        max_read_bytes,
        root_is_drive: is_drive_root(&root),
        time_limit: Duration::from_millis(time_limit_ms),
        started: Instant::now(),
        read_bytes: AtomicU64::new(0),
        too_large: AtomicU64::new(0),
        no_text: AtomicU64::new(0),
        cloud_only: AtomicU64::new(0),
        stop_reason: AtomicU8::new(STOP_NONE),
        unsupported: Mutex::new(HashMap::new()),
        skipped_system: Mutex::new(Vec::new()),
    };
    let job = walk::start(port, vec![Task::dir(root, 0)], Box::new(kind));
    // Reading and extracting files is CPU work: use every pool thread.
    walk::widen_pool();
    Some(job)
}

/// `C:`, `C:\`, `C:/` or `/`.
fn is_drive_root(path: &str) -> bool {
    let bytes = path.as_bytes();
    path == "/"
        || (bytes.len() >= 2
            && bytes.len() <= 3
            && bytes[0].is_ascii_alphabetic()
            && bytes[1] == b':'
            && (bytes.len() == 2 || bytes[2] == b'\\' || bytes[2] == b'/'))
}

/// Config: path, format name. Output: the document's text (UTF-8), or
/// nothing when the format has no text in this file. Fails when unreadable.
pub fn start_document_text(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let path = r.str()?;
    let format = Format::from_name(&r.str()?)?;
    if !r.is_empty() {
        return None;
    }
    Some(Job::spawn(port, "cb_native_doctext", move |job| {
        let size = fs::metadata(&path).map_err(|e| e.to_string())?.len();
        if size > format.max_bytes() {
            return Err("Document is too large to read.".into());
        }
        let bytes = fs::read(&path).map_err(|e| e.to_string())?;
        if job.cancelled() {
            return Ok(());
        }
        let mut out = Writer::default();
        match doctext::extract(format, &bytes) {
            Some(text) => {
                out.u8(1);
                out.str(&text);
            }
            None => out.u8(0),
        }
        job.append(&out.into_bytes());
        Ok(())
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::job::{testing, JOB_DONE};

    fn terms(words: &[&str]) -> Vec<String> {
        words.iter().map(|word| search_key(word)).collect()
    }

    #[test]
    fn matches_words_across_lines_and_ranks_snippets() {
        let text = "HỢP ĐỒNG thuê nhà\n\nBên B: Công ty ABC\nGiá";
        let found = find(text, &terms(&["hop", "dong", "abc"]), false, true).unwrap();
        assert_eq!(found.matched, vec![0, 1, 2]);
        assert_eq!(found.hits, 3);
        assert_eq!(
            found.snippets,
            vec![
                (1, "HỢP ĐỒNG thuê nhà".to_string()),
                (3, "Bên B: Công ty ABC".to_string())
            ]
        );
        assert!(find(text, &terms(&["abc", "xyz"]), false, true).is_none());
        let any = find(text, &terms(&["abc", "xyz"]), false, false).unwrap();
        assert_eq!(any.matched, vec![0]);
    }

    #[test]
    fn recognises_drive_roots() {
        for root in ["C:", "C:\\", "d:/", "/"] {
            assert!(is_drive_root(root), "{root}");
        }
        for path in ["C:\\Users", "/home", "", "CC:"] {
            assert!(!is_drive_root(path), "{path}");
        }
    }

    #[test]
    fn terms_match_where_words_start() {
        let text = "F95
https://f95zone.to
const x = 0x1f95f, 0xf950
INV2048 hóa đơn";
        let found = find(text, &terms(&["f95"]), false, true).unwrap();
        assert_eq!(found.hits, 2);
        assert_eq!(found.snippets.len(), 2);
        assert!(find(text, &terms(&["2048"]), false, true).is_some());
        assert!(find(text, &terms(&["oa"]), false, true).is_none());
        assert!(find("中文搜索测试", &terms(&["搜索"]), false, true).is_some());
        assert!(is_tool_cache(".cargo", "home"));
        assert!(is_tool_cache(
            "mod",
            &format!("go{}pkg", std::path::MAIN_SEPARATOR)
        ));
        assert!(!is_tool_cache("mod", "src"));
    }

    #[test]
    fn long_lines_are_cut_around_the_match() {
        let line = format!("{}needle{}", "a ".repeat(300), " b".repeat(300));
        let found = find(&line, &terms(&["needle"]), false, true).unwrap();
        let text = &found.snippets[0].1;
        assert!(text.starts_with('…') && text.ends_with('…'));
        assert!(text.contains("needle"));
        assert_eq!(text.encode_utf16().count(), SNIPPET_UNITS + 2);
    }

    #[test]
    fn job_walks_files_in_parallel_and_reports_a_summary() {
        let root = std::env::temp_dir().join(format!("cb_content_{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("a/node_modules")).unwrap();
        fs::create_dir_all(root.join("AppData")).unwrap();
        fs::write(root.join("AppData/cache.txt"), "tien dien").unwrap();
        fs::write(root.join("blob"), [0u8; 20_000]).unwrap();
        fs::write(root.join("a/bill.txt"), "Tiền điện tháng 9").unwrap();
        fs::write(root.join("a/node_modules/x.txt"), "tien dien").unwrap();
        fs::write(root.join("old.doc"), "tien dien").unwrap();
        fs::write(root.join("photo.jpg"), "tien dien").unwrap();
        for i in 0..50 {
            fs::write(root.join(format!("n{i}.txt")), "other").unwrap();
        }

        let mut config = Writer::default();
        config.str(&root.to_string_lossy());
        config.u8(1);
        config.u8(0);
        config.u8(1);
        config.u32(2);
        config.str("tien");
        config.str("dien");
        config.str("");
        for limit in [100_000u64, 100, 1 << 30, 30_000] {
            config.u64(limit);
        }
        let job = start_content_search(0, &config.into_bytes()).unwrap();
        let (state, out) = testing::wait(&job);
        assert_eq!(state, JOB_DONE);
        let mut r = Reader::new(&out);
        let mut matches = Vec::new();
        let mut summary = None;
        while !r.is_empty() {
            match r.u8().unwrap() {
                RECORD_MATCH => {
                    let path = r.str().unwrap();
                    assert_eq!(r.str().unwrap(), "text");
                    r.u64().unwrap();
                    r.i64().unwrap();
                    assert_eq!(r.u64().unwrap(), 2);
                    for _ in 0..r.u32().unwrap() {
                        r.u32().unwrap();
                    }
                    for _ in 0..r.u32().unwrap() {
                        r.u32().unwrap();
                        r.str().unwrap();
                    }
                    matches.push(path);
                }
                RECORD_WARNING => panic!("{}", r.str().unwrap()),
                RECORD_SUMMARY => {
                    let too_large = r.u64().unwrap();
                    let stop = r.u8().unwrap();
                    assert_eq!(r.u64().unwrap(), 51);
                    assert_eq!(r.u64().unwrap(), 0);
                    assert_eq!(r.u64().unwrap(), 0);
                    assert_eq!(r.u32().unwrap(), 1);
                    assert!(r.str().unwrap().ends_with("AppData"));
                    let kinds = r.u32().unwrap();
                    let ext = r.str().unwrap();
                    let count = r.u64().unwrap();
                    summary = Some((too_large, stop, kinds, ext, count));
                }
                other => panic!("record {other}"),
            }
        }
        assert_eq!(matches.len(), 1);
        assert!(matches[0].ends_with("bill.txt"));
        assert_eq!(summary, Some((0, STOP_NONE, 1, ".doc".to_string(), 1)));
        assert_eq!(job.counter(0), 51);
        // The binary blob cost one 8 KiB probe, not 20 KB.
        assert!(job.counter(3) < 20_000);
        fs::remove_dir_all(&root).unwrap();
    }
}

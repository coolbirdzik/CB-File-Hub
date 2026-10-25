//! Parallel directory-tree scan for the Disk Cleaner.
//!
//! Port of the per-directory work in `_fullDiskScanWorker.scanInto`
//! (cb_file_manager/lib/services/disk_cleaner/full_disk_scan_isolate.dart):
//! enumerate, skip reparse points and system folders, classify junk, keep the
//! largest file rows, fold the rest, and report old large files. Worker threads
//! share a stack of directories. Each finished directory becomes one record
//! that Dart turns into `DiskTreeNode`s; a parent's record is always queued
//! before any of its children's records, so Dart can attach nodes as they come.
//!
//! Windows uses cached directory metadata; POSIX uses symlink metadata and
//! converts timestamps to the same wire format, with case-sensitive paths.

use std::fs;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread;
use std::time::Instant;

use crate::glob::glob_matches;
use crate::normalize::dart_upper;
use crate::wire::{Reader, Writer};

fn path_key(path: &str) -> String {
    if path.starts_with('/') {
        if path == "/System/Volumes/Data" || path == "/" {
            return "/".to_owned();
        }
        let path = path
            .strip_prefix("/System/Volumes/Data/")
            .map(|suffix| format!("/{suffix}"))
            .unwrap_or_else(|| path.to_owned());
        path.trim_end_matches('/').to_owned()
    } else {
        dart_upper(path)
    }
}

const FILE_ATTRIBUTE_DIRECTORY: u32 = 0x10;
const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;

pub const STATUS_SCANNED: u8 = 0;
pub const STATUS_INACCESSIBLE: u8 = 1;
pub const STATUS_MAX_DEPTH: u8 = 2;

/// A scan nobody has polled for this long is abandoned: the Dart isolate that
/// owned it was killed (the Cleaner's cancel does that), so it can never call
/// `cb_disk_scan_free`. Workers then stop instead of walking the whole disk.
const ABANDON_AFTER_MS: u64 = if cfg!(test) { 50 } else { 15_000 };

/// Directory names the Dart scanner never enters or counts.
const SKIPPED_DIRECTORIES: [&str; 3] = ["$RECYCLE.BIN", "System Volume Information", "$WinREAgent"];

struct WholeDirRule {
    path: String,
    prefix: String,
    category: i32,
}

struct GlobRule {
    base_path: String,
    category: i32,
    globs: Vec<Vec<char>>,
}

pub struct Config {
    root: String,
    start_depth: u32,
    max_depth: u32,
    max_children: i64,
    min_display_entry_bytes: i64,
    old_large_file_bytes: i64,
    inherited_category: i32,
    threads: u32,
    whole_dir_rules: Vec<WholeDirRule>,
    glob_rules: Vec<GlobRule>,
    /// Report each subdirectory's NTFS file ID (Windows only, free there).
    collect_file_ids: bool,
}

impl Config {
    /// Layout written by `NativeDiskScan.start` in package:cb_native.
    pub fn decode(bytes: &[u8]) -> Option<Config> {
        let mut r = Reader::new(bytes);
        let root = r.str()?;
        let start_depth = r.u32()?;
        let max_depth = r.u32()?;
        let max_children = r.i64()?;
        let min_display_entry_bytes = r.i64()?;
        let old_large_file_bytes = r.i64()?;
        let inherited_category = r.i32()?;
        let threads = r.u32()?;
        let mut whole_dir_rules = Vec::new();
        for _ in 0..r.u32()? {
            whole_dir_rules.push(WholeDirRule {
                path: r.str()?,
                prefix: r.str()?,
                category: r.i32()?,
            });
        }
        let mut glob_rules = Vec::new();
        for _ in 0..r.u32()? {
            let base_path = r.str()?;
            let category = r.i32()?;
            let mut globs = Vec::new();
            for _ in 0..r.u32()? {
                globs.push(r.str()?.chars().collect());
            }
            glob_rules.push(GlobRule {
                base_path,
                category,
                globs,
            });
        }
        let collect_file_ids = r.bool()?;
        if root.is_empty() || !r.is_empty() {
            return None;
        }
        Some(Config {
            root,
            start_depth,
            max_depth,
            max_children,
            min_display_entry_bytes,
            old_large_file_bytes,
            inherited_category,
            threads,
            whole_dir_rules,
            glob_rules,
            collect_file_ids,
        })
    }

    /// `wholeDirCategory`: rule paths and prefixes arrive upper-cased.
    fn whole_dir_category(&self, full_path: &str) -> i32 {
        if self.whole_dir_rules.is_empty() {
            return -1;
        }
        let upper = path_key(full_path);
        self.whole_dir_rules
            .iter()
            .find(|rule| upper == rule.path || upper.starts_with(&rule.prefix))
            .map_or(-1, |rule| rule.category)
    }

    /// `globRulesForDirectory`.
    fn glob_rules_for(&self, dir_path: &str) -> Vec<&GlobRule> {
        if self.glob_rules.is_empty() {
            return Vec::new();
        }
        let upper = path_key(dir_path);
        self.glob_rules
            .iter()
            .filter(|rule| {
                upper == rule.base_path
                    || (upper.len() > rule.base_path.len()
                        && upper.starts_with(&rule.base_path)
                        && (upper[rule.base_path.len()..].starts_with('\\')
                            || upper[rule.base_path.len()..].starts_with('/')))
            })
            .collect()
    }
}

/// `globCategory`: globs arrive upper-cased, the name is upper-cased the same
/// way, so this is the Dart case-insensitive `^glob$` RegExp.
fn glob_category(name: &str, rules: &[&GlobRule]) -> i32 {
    if rules.is_empty() {
        return -1;
    }
    let upper: Vec<char> = dart_upper(name).chars().collect();
    rules
        .iter()
        .find(|rule| rule.globs.iter().any(|glob| glob_matches(glob, &upper)))
        .map_or(-1, |rule| rule.category)
}

struct Task {
    id: u32,
    path: String,
    depth: u32,
    category: i32,
}

struct Queue {
    tasks: Vec<Task>,
    active: usize,
}

pub struct Progress {
    pub dirs: u64,
    pub files: u64,
    pub bytes: u64,
    pub current_path: String,
}

pub struct DiskScan {
    config: Config,
    queue: Mutex<Queue>,
    wake: Condvar,
    records: Mutex<Vec<u8>>,
    next_id: AtomicU32,
    dirs: AtomicU64,
    files: AtomicU64,
    bytes: AtomicU64,
    current_path: Mutex<String>,
    cancelled: AtomicBool,
    finished: AtomicBool,
    started: Instant,
    last_poll_ms: AtomicU64,
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(|e| e.into_inner())
}

impl DiskScan {
    pub fn start(config: Config) -> Arc<DiskScan> {
        let threads = match config.threads {
            0 => thread::available_parallelism()
                .map(|n| n.get())
                .unwrap_or(4)
                .clamp(2, 8),
            n => n as usize,
        };
        let root = Task {
            id: 0,
            path: config.root.clone(),
            depth: config.start_depth,
            category: config.inherited_category,
        };
        let scan = Arc::new(DiskScan {
            config,
            queue: Mutex::new(Queue {
                tasks: vec![root],
                active: 0,
            }),
            wake: Condvar::new(),
            records: Mutex::new(Vec::new()),
            next_id: AtomicU32::new(1),
            dirs: AtomicU64::new(0),
            files: AtomicU64::new(0),
            bytes: AtomicU64::new(0),
            current_path: Mutex::new(String::new()),
            cancelled: AtomicBool::new(false),
            finished: AtomicBool::new(false),
            started: Instant::now(),
            last_poll_ms: AtomicU64::new(0),
        });
        for _ in 0..threads {
            let worker = Arc::clone(&scan);
            let spawned = thread::Builder::new()
                .name("cb_native_disk_scan".into())
                .spawn(move || worker.run_worker());
            if spawned.is_err() {
                break;
            }
        }
        scan
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
        self.wake.notify_all();
    }

    fn elapsed_ms(&self) -> u64 {
        self.started.elapsed().as_millis() as u64
    }

    fn touch(&self) {
        self.last_poll_ms
            .store(self.elapsed_ms(), Ordering::Relaxed);
    }

    /// Cancels and drops buffered records once the owner stopped polling.
    fn check_abandoned(&self) {
        self.check_abandoned_at(self.elapsed_ms());
    }

    fn check_abandoned_at(&self, now_ms: u64) {
        // A concurrent poll may update last_poll_ms after now_ms was captured.
        // Clamping to a second elapsed_ms() reading still allows underflow.
        let idle = now_ms.saturating_sub(self.last_poll_ms.load(Ordering::Relaxed));
        if idle > ABANDON_AFTER_MS && !self.cancelled.load(Ordering::Relaxed) {
            self.cancel();
            *lock(&self.records) = Vec::new();
        }
    }

    pub fn take_records(&self) -> (Vec<u8>, bool) {
        self.touch();
        let finished = self.finished.load(Ordering::Acquire);
        let batch = std::mem::take(&mut *lock(&self.records));
        (batch, finished)
    }

    pub fn progress(&self) -> Progress {
        self.touch();
        Progress {
            dirs: self.dirs.load(Ordering::Relaxed),
            files: self.files.load(Ordering::Relaxed),
            bytes: self.bytes.load(Ordering::Relaxed),
            current_path: lock(&self.current_path).clone(),
        }
    }

    fn run_worker(&self) {
        loop {
            let task = {
                let mut queue = lock(&self.queue);
                loop {
                    if self.cancelled.load(Ordering::Acquire) {
                        self.finished.store(true, Ordering::Release);
                        return;
                    }
                    if let Some(task) = queue.tasks.pop() {
                        queue.active += 1;
                        break task;
                    }
                    if queue.active == 0 {
                        self.finished.store(true, Ordering::Release);
                        self.wake.notify_all();
                        return;
                    }
                    queue = self.wake.wait(queue).unwrap_or_else(|e| e.into_inner());
                }
            };

            let _active = ActiveGuard(self);
            self.check_abandoned();
            if self.cancelled.load(Ordering::Acquire) {
                continue;
            }
            let (record, children) = self.scan_directory(task);
            // The record goes out before the children are queued, so Dart
            // always sees a parent before any of its subdirectories.
            if !self.publish_record(&record) {
                continue;
            }
            if !children.is_empty() {
                lock(&self.queue).tasks.extend(children);
            }
        }
    }

    fn publish_record(&self, record: &[u8]) -> bool {
        let mut records = lock(&self.records);
        // Abandonment discards the buffered parents. A worker returning from
        // filesystem IO must not publish their children after that discard.
        if self.cancelled.load(Ordering::Acquire) {
            return false;
        }
        records.extend_from_slice(record);
        true
    }

    fn scan_directory(&self, task: Task) -> (Vec<u8>, Vec<Task>) {
        let config = &self.config;
        self.dirs.fetch_add(1, Ordering::Relaxed);
        if let Ok(mut current) = self.current_path.try_lock() {
            current.clone_from(&task.path);
        }

        let mut out = Writer::default();
        out.u32(task.id);
        if task.depth >= config.max_depth {
            out.u8(STATUS_MAX_DEPTH);
            DirectoryRecord::default().write(&mut out);
            return (out.into_bytes(), Vec::new());
        }

        let entries = match read_entries(&task.path, config.collect_file_ids) {
            Some(entries) => entries,
            None => {
                out.u8(STATUS_INACCESSIBLE);
                DirectoryRecord::default().write(&mut out);
                return (out.into_bytes(), Vec::new());
            }
        };

        let glob_rules = if task.category < 0 {
            config.glob_rules_for(&task.path)
        } else {
            Vec::new()
        };
        let separator = if task.path.starts_with('/') {
            if task.path.ends_with('/') {
                ""
            } else {
                "/"
            }
        } else if task.path.ends_with('\\') {
            ""
        } else {
            "\\"
        };
        let mut record = DirectoryRecord::default();
        let mut children = Vec::new();

        for (name, info, file_id) in entries {
            if self.cancelled.load(Ordering::Relaxed) {
                break;
            }

            if info.attributes & FILE_ATTRIBUTE_REPARSE_POINT != 0 {
                record.reparse_names.push(name);
                continue;
            }

            if info.attributes & FILE_ATTRIBUTE_DIRECTORY != 0 {
                if SKIPPED_DIRECTORIES.contains(&name.as_str()) {
                    continue;
                }
                let full_path = format!("{}{}{}", task.path, separator, name);
                let key = path_key(&full_path);
                if key == "/Volumes" || key == "/System/Volumes" {
                    record.reparse_names.push(name);
                    continue;
                }
                let category = if task.category >= 0 {
                    task.category
                } else {
                    config.whole_dir_category(&full_path)
                };
                let id = self.next_id.fetch_add(1, Ordering::Relaxed);
                record.note_activity(info.last_write);
                record.subdirs.push(SubdirEntry {
                    id,
                    last_write: info.last_write,
                    last_access: info.last_access,
                    category,
                    file_id,
                    name,
                });
                children.push(Task {
                    id,
                    path: full_path,
                    depth: task.depth + 1,
                    category,
                });
                continue;
            }

            record.note_activity(info.last_write.max(info.last_access));
            let size = info.size;
            if size as i64 >= config.old_large_file_bytes {
                record.old_large_files.push(FileEntry {
                    size,
                    last_write: info.last_write,
                    last_access: info.last_access,
                    category: -1,
                    name: name.clone(),
                });
            }
            let category = if task.category >= 0 {
                task.category
            } else {
                glob_category(&name, &glob_rules)
            };
            if (size as i64) < config.min_display_entry_bytes || config.max_children <= 0 {
                record.fold_entry(size, 1, category >= 0);
            } else {
                record.retain(
                    FileEntry {
                        size,
                        last_write: info.last_write,
                        last_access: info.last_access,
                        category,
                        name,
                    },
                    config.max_children as usize,
                );
            }
            record.own_bytes += size;
            record.own_files += 1;
            self.files.fetch_add(1, Ordering::Relaxed);
            self.bytes.fetch_add(size, Ordering::Relaxed);
        }

        out.u8(STATUS_SCANNED);
        record.write(&mut out);
        (out.into_bytes(), children)
    }
}

/// A directory's entries with their info and (when asked for) file IDs, or
/// None when it cannot be read. Entries whose metadata fails are skipped and
/// a failing iterator ends the listing, as the Dart walker does.
fn read_entries(path: &str, with_ids: bool) -> Option<Vec<(String, EntryInfo, u64)>> {
    #[cfg(windows)]
    if with_ids {
        if let Ok(entries) = crate::win_dir::read_dir_with_ids(path) {
            return Some(
                entries
                    .into_iter()
                    .map(|entry| {
                        let info = EntryInfo {
                            attributes: entry.attributes,
                            size: entry.size,
                            last_write: entry.last_write,
                            last_access: entry.last_access,
                        };
                        (entry.name, info, entry.file_id)
                    })
                    .collect(),
            );
        }
    }
    let _ = with_ids;
    let mut out = Vec::new();
    for entry in fs::read_dir(path).ok()? {
        let Ok(entry) = entry else { break };
        // DirEntry metadata never follows symlinks and retains Windows' cached
        // FindFirstFile metadata, avoiding an extra stat for every entry.
        let Ok(metadata) = entry.metadata() else {
            continue;
        };
        let name = entry.file_name().to_string_lossy().into_owned();
        out.push((name, EntryInfo::of(&metadata), 0));
    }
    Some(out)
}

struct ActiveGuard<'a>(&'a DiskScan);

impl Drop for ActiveGuard<'_> {
    fn drop(&mut self) {
        lock(&self.0.queue).active -= 1;
        self.0.wake.notify_all();
    }
}

struct EntryInfo {
    attributes: u32,
    size: u64,
    last_write: u64,
    last_access: u64,
}

impl EntryInfo {
    #[cfg(windows)]
    fn of(metadata: &fs::Metadata) -> EntryInfo {
        use std::os::windows::fs::MetadataExt;
        EntryInfo {
            attributes: metadata.file_attributes(),
            size: metadata.file_size(),
            last_write: metadata.last_write_time(),
            last_access: metadata.last_access_time(),
        }
    }

    /// Keep the existing FILETIME wire format on POSIX too.
    #[cfg(not(windows))]
    fn of(metadata: &fs::Metadata) -> EntryInfo {
        EntryInfo {
            attributes: if metadata.is_dir() {
                FILE_ATTRIBUTE_DIRECTORY
            } else {
                0
            } | if metadata.file_type().is_symlink() {
                FILE_ATTRIBUTE_REPARSE_POINT
            } else {
                0
            },
            size: metadata.len(),
            last_write: filetime(metadata.modified()),
            last_access: filetime(metadata.accessed()),
        }
    }
}

#[cfg(not(windows))]
fn filetime(time: std::io::Result<std::time::SystemTime>) -> u64 {
    time.ok()
        .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
        .map_or(0, |age| {
            age.as_secs()
                .saturating_mul(10_000_000)
                .saturating_add(u64::from(age.subsec_nanos()) / 100)
                .saturating_add(116_444_736_000_000_000)
        })
}

struct SubdirEntry {
    id: u32,
    last_write: u64,
    last_access: u64,
    category: i32,
    /// 0 when not collected.
    file_id: u64,
    name: String,
}

struct FileEntry {
    size: u64,
    last_write: u64,
    last_access: u64,
    category: i32,
    name: String,
}

#[derive(Default)]
struct DirectoryRecord {
    subdirs: Vec<SubdirEntry>,
    /// Ascending by size, like `retainedFiles` in Dart.
    retained: Vec<FileEntry>,
    folded_bytes: u64,
    folded_files: u64,
    folded_junk_bytes: u64,
    folded_entries: u64,
    own_bytes: u64,
    own_files: u64,
    /// Newest FILETIME among the direct entries: files' write or access, and
    /// subfolders' own write. Dart folds it up the tree to tell when anything
    /// inside a folder was last used.
    newest_activity: u64,
    reparse_names: Vec<String>,
    old_large_files: Vec<FileEntry>,
}

impl DirectoryRecord {
    fn note_activity(&mut self, filetime: u64) {
        self.newest_activity = self.newest_activity.max(filetime);
    }

    fn fold_entry(&mut self, size: u64, files: u64, junk: bool) {
        self.folded_bytes += size;
        self.folded_files += files;
        if junk {
            self.folded_junk_bytes += size;
        }
        self.folded_entries += 1;
    }

    /// `retainFile`: keep the `max` largest rows, folding the smallest.
    fn retain(&mut self, file: FileEntry, max: usize) {
        if self.retained.len() >= max && file.size <= self.retained[0].size {
            self.fold_entry(file.size, 1, file.category >= 0);
            return;
        }
        if self.retained.len() >= max {
            let smallest = self.retained.remove(0);
            self.fold_entry(smallest.size, 1, smallest.category >= 0);
        }
        let index = self.retained.partition_point(|kept| kept.size <= file.size);
        self.retained.insert(index, file);
    }

    fn write(&self, out: &mut Writer) {
        out.u32(self.subdirs.len() as u32);
        for subdir in &self.subdirs {
            out.u32(subdir.id);
            out.u64(subdir.last_write);
            out.u64(subdir.last_access);
            out.i32(subdir.category);
            out.u64(subdir.file_id);
            out.str(&subdir.name);
        }
        for list in [&self.retained, &self.old_large_files] {
            out.u32(list.len() as u32);
            for file in list {
                out.u64(file.size);
                out.u64(file.last_write);
                out.u64(file.last_access);
                out.i32(file.category);
                out.str(&file.name);
            }
        }
        out.u64(self.folded_bytes);
        out.u64(self.folded_files);
        out.u64(self.folded_junk_bytes);
        out.u64(self.folded_entries);
        out.u64(self.own_bytes);
        out.u64(self.own_files);
        out.u64(self.newest_activity);
        out.u32(self.reparse_names.len() as u32);
        for name in &self.reparse_names {
            out.str(name);
        }
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn posix_paths_keep_case_and_data_mount_aliases() {
        assert_eq!(
            super::path_key("/System/Volumes/Data/Users/me/Cache"),
            "/Users/me/Cache"
        );
        assert_ne!(
            super::path_key("/Users/me/Cache"),
            super::path_key("/Users/me/cache")
        );
        assert_eq!(super::path_key("/System/Volumes/Data"), "/");
        assert_eq!(super::path_key("c:\\Users\\Me"), "C:\\USERS\\ME");
    }
    use super::*;

    #[test]
    fn unpolled_scan_is_abandoned() {
        let root = std::env::temp_dir().join(format!("cb_native_abandon_{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let mut config_bytes = Writer::default();
        config_bytes.str(&root.to_string_lossy());
        for value in [0u32, 20] {
            config_bytes.u32(value);
        }
        for value in [200u64, 0, u64::MAX >> 1] {
            config_bytes.u64(value);
        }
        config_bytes.i32(-1);
        config_bytes.u32(1);
        config_bytes.u32(0);
        config_bytes.u32(0);
        config_bytes.u8(0);
        let config = Config::decode(&config_bytes.into_bytes()).unwrap();

        let scan = DiskScan::start(config);
        // Model a poll that lands after a worker captures its clock reading.
        // It must not wrap the idle time and cancel an actively polled scan.
        scan.last_poll_ms.store(101, Ordering::Relaxed);
        scan.check_abandoned_at(100);
        assert!(!scan.cancelled.load(Ordering::Relaxed));
        lock(&scan.records).extend_from_slice(&[1, 2, 3]);
        scan.last_poll_ms.store(0, Ordering::Relaxed);
        thread::sleep(std::time::Duration::from_millis(ABANDON_AFTER_MS + 50));
        scan.check_abandoned();
        assert!(scan.cancelled.load(Ordering::Relaxed));
        assert!(lock(&scan.records).is_empty());
        assert!(!scan.publish_record(&[4, 5, 6]));
        assert!(lock(&scan.records).is_empty());
        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn retain_keeps_the_largest_rows() {
        let mut record = DirectoryRecord::default();
        for size in [5u64, 1, 9, 3, 7] {
            record.retain(
                FileEntry {
                    size,
                    last_write: 0,
                    last_access: 0,
                    category: if size == 1 { 0 } else { -1 },
                    name: size.to_string(),
                },
                3,
            );
        }
        let kept: Vec<u64> = record.retained.iter().map(|f| f.size).collect();
        assert_eq!(kept, vec![5, 7, 9]);
        assert_eq!(record.folded_bytes, 4);
        assert_eq!(record.folded_entries, 2);
        assert_eq!(record.folded_junk_bytes, 1);
    }
}

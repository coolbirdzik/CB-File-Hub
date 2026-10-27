//! Parallel directory walks: folder sizes, filtered file lists and the Disk
//! Cleaner's junk rules.
//!
//! All walks share one pool of worker threads. Each walk keeps its own stack
//! of directories and the pool serves walks round-robin, so the many small
//! size jobs a folder grid starts finish alongside one big walk instead of
//! queueing behind it, and none of them spawns threads of its own. A thread
//! stuck on an unresponsive share only costs the pool one worker: when no
//! directory has finished for a while, a new walk adds a thread.

use std::collections::{HashSet, VecDeque};
use std::fs;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock};
use std::thread;
use std::time::Instant;

use regex::{Regex, RegexBuilder};

use crate::fsx::{self, KIND_DIRECTORY, KIND_FILE};
use crate::glob::glob_matches;
use crate::job::{lock, Job};
use crate::normalize::{dart_lower, dart_upper};
use crate::wire::{Reader, Writer};

/// Above the base size, the pool only grows while it looks stuck.
const MAX_THREADS: usize = 32;
const STUCK_AFTER_MS: u64 = 1_000;

pub struct Task {
    pub(crate) path: String,
    pub(crate) depth: u32,
    /// A path given as a file rather than a directory to read.
    pub(crate) file: bool,
}

impl Task {
    pub(crate) fn dir(path: String, depth: u32) -> Task {
        Task {
            path,
            depth,
            file: false,
        }
    }
}

pub(crate) trait Kind: Send + Sync {
    /// Reads one directory (or stats one file task) and returns the
    /// subdirectories to visit.
    fn scan(&self, walk: &Walk, task: &Task) -> Vec<Task>;
    /// Runs once after the last directory, before the job completes.
    fn finish(&self, _walk: &Walk) -> Result<(), String> {
        Ok(())
    }
}

pub struct Walk {
    pub(crate) job: Arc<Job>,
    kind: Box<dyn Kind>,
    stack: Mutex<Vec<Task>>,
    /// Queued plus running directories; the walk ends when it reaches zero.
    pending: AtomicUsize,
    /// In the pool's queue. Only changed under the pool lock.
    queued: AtomicBool,
    /// A result limit was reached: stop, but complete normally.
    pub(crate) stop: AtomicBool,
}

impl Walk {
    pub(crate) fn halted(&self) -> bool {
        self.stop.load(Ordering::Relaxed) || self.job.cancelled()
    }

    fn done(self: &Arc<Self>, count: usize) {
        if count > 0 && self.pending.fetch_sub(count, Ordering::AcqRel) == count {
            let walk = Arc::clone(self);
            self.job.run(move |_| walk.kind.finish(&walk));
        }
    }
}

pub(crate) fn start(port: i64, roots: Vec<Task>, kind: Box<dyn Kind>) -> Arc<Job> {
    let job = Job::new(port);
    let walk = Arc::new(Walk {
        job: Arc::clone(&job),
        kind,
        pending: AtomicUsize::new(roots.len()),
        stack: Mutex::new(roots),
        queued: AtomicBool::new(false),
        stop: AtomicBool::new(false),
    });
    if walk.pending.load(Ordering::Relaxed) == 0 {
        let finished = Arc::clone(&walk);
        job.run(move |_| finished.kind.finish(&finished));
    } else {
        pool().submit(walk);
    }
    job
}

struct PoolState {
    queue: VecDeque<Arc<Walk>>,
    threads: usize,
    idle: usize,
}

struct Pool {
    state: Mutex<PoolState>,
    wake: Condvar,
    base_threads: usize,
    started: Instant,
    last_progress_ms: AtomicU64,
}

fn pool() -> &'static Pool {
    static POOL: OnceLock<Pool> = OnceLock::new();
    POOL.get_or_init(|| Pool {
        state: Mutex::new(PoolState {
            queue: VecDeque::new(),
            threads: 0,
            idle: 0,
        }),
        wake: Condvar::new(),
        base_threads: thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(4)
            .clamp(2, 8),
        started: Instant::now(),
        last_progress_ms: AtomicU64::new(0),
    })
}

enum Next {
    Run(Arc<Walk>, Task),
    Drained(Arc<Walk>, usize),
}

impl Pool {
    fn now_ms(&self) -> u64 {
        self.started.elapsed().as_millis() as u64
    }

    fn submit(&'static self, walk: Arc<Walk>) {
        let mut state = lock(&self.state);
        walk.queued.store(true, Ordering::Relaxed);
        state.queue.push_back(walk);
        let stuck = self
            .now_ms()
            .saturating_sub(self.last_progress_ms.load(Ordering::Relaxed))
            > STUCK_AFTER_MS;
        if state.idle == 0
            && (state.threads < self.base_threads || (stuck && state.threads < MAX_THREADS))
        {
            self.spawn_thread(&mut state);
        }
        drop(state);
        self.wake.notify_one();
    }

    fn spawn_thread(&'static self, state: &mut PoolState) -> bool {
        let spawned = thread::Builder::new()
            .name("cb_native_walk".into())
            .spawn(move || self.work());
        if spawned.is_ok() {
            state.threads += 1;
        }
        spawned.is_ok()
    }

    /// Grows to the base size at once instead of one thread per submitted
    /// walk.
    fn widen(&'static self) {
        let mut state = lock(&self.state);
        while state.threads < self.base_threads {
            if !self.spawn_thread(&mut state) {
                break;
            }
        }
        drop(state);
        self.wake.notify_all();
    }

    fn next(&self) -> Next {
        let mut state = lock(&self.state);
        loop {
            if let Some(walk) = state.queue.pop_front() {
                let mut stack = lock(&walk.stack);
                if walk.halted() {
                    let dropped = stack.len();
                    stack.clear();
                    drop(stack);
                    walk.queued.store(false, Ordering::Relaxed);
                    return Next::Drained(walk, dropped);
                }
                match stack.pop() {
                    Some(task) => {
                        let more = !stack.is_empty();
                        drop(stack);
                        if more {
                            state.queue.push_back(Arc::clone(&walk));
                        } else {
                            walk.queued.store(false, Ordering::Relaxed);
                        }
                        return Next::Run(walk, task);
                    }
                    None => {
                        drop(stack);
                        walk.queued.store(false, Ordering::Relaxed);
                        continue;
                    }
                }
            }
            state.idle += 1;
            state = self.wake.wait(state).unwrap_or_else(|e| e.into_inner());
            state.idle -= 1;
        }
    }

    fn work(&self) {
        loop {
            match self.next() {
                Next::Drained(walk, dropped) => walk.done(dropped),
                Next::Run(walk, task) => {
                    let children = catch_unwind(AssertUnwindSafe(|| walk.kind.scan(&walk, &task)))
                        .unwrap_or_default();
                    if !children.is_empty() && !walk.halted() {
                        walk.pending.fetch_add(children.len(), Ordering::AcqRel);
                        let mut state = lock(&self.state);
                        lock(&walk.stack).extend(children);
                        if !walk.queued.swap(true, Ordering::Relaxed) {
                            state.queue.push_back(Arc::clone(&walk));
                        }
                        drop(state);
                        self.wake.notify_all();
                    }
                    self.last_progress_ms
                        .store(self.now_ms(), Ordering::Relaxed);
                    walk.done(1);
                }
            }
        }
    }
}

/// Lets one walk whose tasks are CPU-bound (the content search) or that is
/// the only walk running (a junk scan) run on every base pool thread. Other walks keep growing the pool one thread per
/// submitted walk.
pub(crate) fn widen_pool() {
    pool().widen();
}

pub(crate) fn read_dir(walk: &Walk, task: &Task) -> Option<fs::ReadDir> {
    walk.job.set_current(&task.path);
    fs::read_dir(&task.path).ok()
}

// ---------------------------------------------------------------------------
// Folder sizes
// ---------------------------------------------------------------------------

/// Total size of files and folders, like `LazyPathSizeCalculator`.
/// Counters: bytes, files, directories, unreadable paths.
struct DirSize;

impl Kind for DirSize {
    fn scan(&self, walk: &Walk, task: &Task) -> Vec<Task> {
        let job = &walk.job;
        if task.file {
            // `File(path).stat()` follows links for an explicitly given path.
            match fs::metadata(&task.path) {
                Ok(metadata) if metadata.is_file() => {
                    job.add_counter(0, metadata.len());
                    job.add_counter(1, 1);
                }
                Ok(_) => {}
                Err(_) => {
                    job.add_counter(3, 1);
                }
            }
            return Vec::new();
        }
        let Some(entries) = read_dir(walk, task) else {
            job.add_counter(3, 1);
            return Vec::new();
        };
        job.add_counter(2, 1);
        let mut children = Vec::new();
        let (mut bytes, mut files) = (0, 0);
        for entry in entries {
            if walk.halted() {
                break;
            }
            let Ok(entry) = entry else { continue };
            let Ok(file_type) = entry.file_type() else {
                continue;
            };
            // `list(followLinks: false)` reports links as Link: never counted.
            if file_type.is_symlink() {
                continue;
            }
            if file_type.is_dir() {
                let name = entry.file_name();
                children.push(Task::dir(
                    fsx::join(&task.path, &name.to_string_lossy()),
                    task.depth + 1,
                ));
            } else if let Ok(metadata) = entry.metadata() {
                bytes += metadata.len();
                files += 1;
            }
        }
        job.add_counter(0, bytes);
        job.add_counter(1, files);
        children
    }

    fn finish(&self, walk: &Walk) -> Result<(), String> {
        let job = &walk.job;
        let mut out = Writer::default();
        for index in 0..4 {
            out.u64(job.counter(index));
        }
        job.append(&out.into_bytes());
        Ok(())
    }
}

/// Config: file paths, then directory paths (each a string list).
pub fn start_dir_size(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let files = r.strs()?;
    let dirs = r.strs()?;
    if !r.is_empty() {
        return None;
    }
    let roots = files
        .into_iter()
        .map(|path| Task {
            path,
            depth: 0,
            file: true,
        })
        .chain(dirs.into_iter().map(|path| Task::dir(path, 0)))
        .collect();
    Some(start(port, roots, Box::new(DirSize)))
}

// ---------------------------------------------------------------------------
// Filtered file lists
// ---------------------------------------------------------------------------

const EXT_NONE: u8 = 0;
const EXT_LAST_DOT: u8 = 1;
const EXT_PATH: u8 = 2;

const WALK_FILES: u8 = 1;
const WALK_DIRS: u8 = 2;
const WALK_SKIP_DOT_NAMES: u8 = 4;
const WALK_STATS: u8 = 8;
const WALK_FOLLOW_LINKS: u8 = 16;
/// Only count the hits; the output is then one u64.
const WALK_COUNT_ONLY: u8 = 32;

/// Lists entries below roots, filtered in Rust so Dart only sees the hits.
/// Output records: kind u8, size u64, modified ms i64, path (or just the hit
/// count with `WALK_COUNT_ONLY`). Counters: matches, directories read,
/// unreadable directories, matched bytes.
struct FileWalk {
    recursive: bool,
    /// 0 = unlimited; otherwise directories deeper than this are not read.
    max_depth: u32,
    flags: u8,
    ext_mode: u8,
    extensions: HashSet<String>,
    excludes: Vec<Regex>,
    max_results: u64,
    min_size: u64,
    max_modified_ms: i64,
    visited_links: Mutex<HashSet<PathBuf>>,
}

impl FileWalk {
    fn wants_extension(&self, name: &str) -> bool {
        let extension = match self.ext_mode {
            EXT_NONE => return true,
            EXT_LAST_DOT => fsx::last_dot_extension(name),
            EXT_PATH => fsx::path_extension(name),
            _ => return true,
        };
        self.extensions.contains(&dart_lower(extension))
    }

    fn needs_metadata(&self) -> bool {
        self.flags & WALK_STATS != 0 || self.min_size > 0 || self.max_modified_ms != i64::MAX
    }

    /// Follows a directory link once per target, so link cycles end.
    fn first_visit(&self, path: &str) -> bool {
        match fs::canonicalize(path) {
            Ok(target) => lock(&self.visited_links).insert(target),
            Err(_) => false,
        }
    }
}

impl Kind for FileWalk {
    fn scan(&self, walk: &Walk, task: &Task) -> Vec<Task> {
        let job = &walk.job;
        let Some(entries) = read_dir(walk, task) else {
            job.add_counter(2, 1);
            return Vec::new();
        };
        job.add_counter(1, 1);
        let descend = self.recursive && (self.max_depth == 0 || task.depth < self.max_depth);
        let mut children = Vec::new();
        let mut out = Writer::default();
        let mut bytes = 0;
        for entry in entries {
            if walk.halted() {
                break;
            }
            let Ok(entry) = entry else { continue };
            let Ok(file_type) = entry.file_type() else {
                continue;
            };
            let name = entry.file_name().to_string_lossy().into_owned();
            let path = fsx::join(&task.path, &name);

            let mut followed = None;
            let is_dir = if file_type.is_symlink() {
                if self.flags & WALK_FOLLOW_LINKS == 0 {
                    continue;
                }
                let Ok(metadata) = fs::metadata(&path) else {
                    continue;
                };
                let is_dir = metadata.is_dir();
                followed = Some(metadata);
                is_dir
            } else {
                file_type.is_dir()
            };

            if is_dir && descend && (followed.is_none() || self.first_visit(&path)) {
                children.push(Task::dir(path.clone(), task.depth + 1));
            }

            let wanted = if is_dir { WALK_DIRS } else { WALK_FILES };
            if self.flags & wanted == 0 {
                continue;
            }
            // getFoldersAndFiles drops dot entries but still lists inside them.
            if self.flags & WALK_SKIP_DOT_NAMES != 0 && name.starts_with('.') {
                continue;
            }
            if !self.wants_extension(&name) {
                continue;
            }
            if self.excludes.iter().any(|regex| regex.is_match(&name)) {
                continue;
            }

            let (mut size, mut modified) = (0, 0);
            if self.needs_metadata() {
                let metadata = match followed {
                    Some(metadata) => metadata,
                    None => match entry.metadata() {
                        Ok(metadata) => metadata,
                        Err(_) => continue,
                    },
                };
                if !is_dir {
                    size = metadata.len();
                }
                modified = fsx::modified_ms(&metadata);
                if size < self.min_size || modified > self.max_modified_ms {
                    continue;
                }
            }

            if self.flags & WALK_COUNT_ONLY == 0 {
                out.u8(if is_dir { KIND_DIRECTORY } else { KIND_FILE });
                out.u64(size);
                out.i64(modified);
                out.str(&path);
            }
            bytes += size;
            let found = job.add_counter(0, 1);
            if self.max_results > 0 && found >= self.max_results {
                walk.stop.store(true, Ordering::Relaxed);
                break;
            }
        }
        job.add_counter(3, bytes);
        job.append_vec(&mut out.into_bytes());
        children
    }

    fn finish(&self, walk: &Walk) -> Result<(), String> {
        if self.flags & WALK_COUNT_ONLY != 0 {
            let mut out = Writer::default();
            out.u64(walk.job.counter(0));
            walk.job.append(&out.into_bytes());
        }
        Ok(())
    }
}

fn case_insensitive(pattern: &str) -> Option<Regex> {
    RegexBuilder::new(pattern)
        .case_insensitive(true)
        .build()
        .ok()
}

pub enum WalkStart {
    Started(Arc<Job>),
    InvalidConfig,
    InvalidRegex,
}

/// Config: roots, recursive u8, max depth u32, flags u8, extension mode u8,
/// lower-cased extensions (with dot), exclude regexes, max results u64,
/// min size u64, max modified ms i64.
pub fn start_walk(port: i64, config: &[u8]) -> WalkStart {
    let mut r = Reader::new(config);
    let decoded = (|| {
        Some((
            r.strs()?,
            r.bool()?,
            r.u32()?,
            r.u8()?,
            r.u8()?,
            r.strs()?,
            r.strs()?,
            r.u64()?,
            r.u64()?,
            r.i64()?,
        ))
    })();
    let Some((
        roots,
        recursive,
        max_depth,
        flags,
        ext_mode,
        extensions,
        excludes,
        max_results,
        min_size,
        max_modified_ms,
    )) = decoded
    else {
        return WalkStart::InvalidConfig;
    };
    if !r.is_empty() {
        return WalkStart::InvalidConfig;
    }
    let mut compiled = Vec::with_capacity(excludes.len());
    for pattern in &excludes {
        match case_insensitive(pattern) {
            Some(regex) => compiled.push(regex),
            None => return WalkStart::InvalidRegex,
        }
    }
    let kind = FileWalk {
        recursive,
        max_depth,
        flags,
        ext_mode,
        extensions: extensions.into_iter().collect(),
        excludes: compiled,
        max_results,
        min_size,
        max_modified_ms,
        visited_links: Mutex::new(HashSet::new()),
    };
    let roots = roots.into_iter().map(|path| Task::dir(path, 0)).collect();
    WalkStart::Started(start(port, roots, Box::new(kind)))
}

// ---------------------------------------------------------------------------
// Disk Cleaner junk rules
// ---------------------------------------------------------------------------

pub const JUNK_ITEM: u8 = 1;
pub const JUNK_ERROR: u8 = 2;

/// `_CompiledRule` in disk_cleaner_isolate.dart.
struct JunkRule {
    index: i32,
    base_key: String,
    recursive: bool,
    include: Option<Vec<Vec<char>>>,
    exclude: Option<Vec<Vec<char>>>,
    /// Files modified after this are too new.
    cutoff_ms: Option<i64>,
}

/// One `_ScanGroup` of `_scanWorker`: walks the group root and reports every
/// file with the rules it satisfies. Output: `JUNK_ITEM`, size u64, modified
/// ms i64, path, rule indices (u32 count + i32s); or `JUNK_ERROR` and a
/// message, once. Counters: files reported, their bytes, directories read,
/// last matching rule index + 1.
struct JunkScan {
    recursive: bool,
    lower_keys: bool,
    rules: Vec<JunkRule>,
    reported_error: AtomicBool,
}

/// `_pathKey`.
fn path_key(path: &str, lower: bool) -> String {
    let mut key = path.replace('/', "\\");
    while key.len() > 1 && key.ends_with('\\') {
        if key.len() == 3 && key.as_bytes()[1] == b':' {
            break;
        }
        key.pop();
    }
    if lower {
        dart_lower(&key)
    } else {
        key
    }
}

/// `_isSameOrDescendantPath`.
fn is_same_or_descendant(path: &str, base: &str) -> bool {
    if path == base {
        return true;
    }
    if base.ends_with('\\') {
        return path.starts_with(base);
    }
    path.len() > base.len() && path.starts_with(base) && path[base.len()..].starts_with('\\')
}

impl JunkRule {
    /// `_matchesRule`, with the name already upper-cased.
    fn matches(&self, key: &str, upper_name: &[char]) -> bool {
        if !is_same_or_descendant(key, &self.base_key) {
            return false;
        }
        if !self.recursive {
            let parent = key.rfind('\\').map_or(key, |i| &key[..i]);
            if parent != self.base_key {
                return false;
            }
        }
        if let Some(include) = &self.include {
            if !include.iter().any(|glob| glob_matches(glob, upper_name)) {
                return false;
            }
        }
        if let Some(exclude) = &self.exclude {
            if exclude.iter().any(|glob| glob_matches(glob, upper_name)) {
                return false;
            }
        }
        true
    }
}

impl Kind for JunkScan {
    fn scan(&self, walk: &Walk, task: &Task) -> Vec<Task> {
        let job = &walk.job;
        let Some(entries) = read_dir(walk, task) else {
            if !self.reported_error.swap(true, Ordering::Relaxed) {
                let mut out = Writer::default();
                out.u8(JUNK_ERROR);
                // FileSystemException.message for a failed Directory.list.
                out.str("Directory listing failed");
                job.append(&out.into_bytes());
            }
            return Vec::new();
        };
        job.add_counter(2, 1);
        let mut children = Vec::new();
        let mut out = Writer::default();
        let mut matched = Vec::new();
        for entry in entries {
            if walk.halted() {
                break;
            }
            let Ok(entry) = entry else { continue };
            let Ok(file_type) = entry.file_type() else {
                continue;
            };
            if file_type.is_symlink() {
                continue;
            }
            let name = entry.file_name().to_string_lossy().into_owned();
            let path = fsx::join(&task.path, &name);
            if file_type.is_dir() {
                if self.recursive {
                    children.push(Task::dir(path, task.depth + 1));
                }
                continue;
            }

            let key = path_key(&path, self.lower_keys);
            let upper: Vec<char> = dart_upper(&name).chars().collect();
            matched.clear();
            matched.extend(self.rules.iter().filter(|rule| rule.matches(&key, &upper)));
            if matched.is_empty() {
                continue;
            }
            let Ok(metadata) = entry.metadata() else {
                continue;
            };
            let modified = fsx::modified_ms(&metadata);
            let passing: Vec<i32> = matched
                .iter()
                .filter(|rule| rule.cutoff_ms.is_none_or(|cutoff| modified <= cutoff))
                .map(|rule| rule.index)
                .collect();
            if passing.is_empty() {
                continue;
            }
            out.u8(JUNK_ITEM);
            out.u64(metadata.len());
            out.i64(modified);
            out.str(&path);
            out.u32(passing.len() as u32);
            for index in &passing {
                out.i32(*index);
            }
            job.add_counter(0, 1);
            job.add_counter(1, metadata.len());
            job.set_counter(3, (*passing.last().unwrap_or(&-1) + 1) as u64);
        }
        job.append_vec(&mut out.into_bytes());
        children
    }
}

/// Config: scan path, group recursive u8, lower-case keys u8, then rules:
/// index i32, base key, recursive u8, include globs (u8 present + list),
/// exclude globs (same), cutoff present u8 + ms i64.
pub fn start_junk_scan(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let scan_path = r.str()?;
    let recursive = r.bool()?;
    let lower_keys = r.bool()?;
    let mut rules = Vec::new();
    let globs = |r: &mut Reader| -> Option<Option<Vec<Vec<char>>>> {
        if !r.bool()? {
            return Some(None);
        }
        Some(Some(
            r.strs()?
                .iter()
                .map(|glob| dart_upper(glob).chars().collect())
                .collect(),
        ))
    };
    for _ in 0..r.u32()? {
        let index = r.i32()?;
        let base_key = r.str()?;
        let rule_recursive = r.bool()?;
        let include = globs(&mut r)?;
        let exclude = globs(&mut r)?;
        let has_cutoff = r.bool()?;
        let cutoff = r.i64()?;
        rules.push(JunkRule {
            index,
            base_key,
            recursive: rule_recursive,
            include,
            exclude,
            cutoff_ms: has_cutoff.then_some(cutoff),
        });
    }
    if !r.is_empty() || scan_path.is_empty() {
        return None;
    }
    let kind = JunkScan {
        recursive,
        lower_keys,
        rules,
        reported_error: AtomicBool::new(false),
    };
    let job = start(port, vec![Task::dir(scan_path, 0)], Box::new(kind));
    // One walk per rule group, often a %TEMP% with thousands of folders. On
    // the single thread a lone walk gets, a ~9k-folder %TEMP% took 3.4-7.8 s
    // instead of 0.8-1.8 s.
    widen_pool();
    Some(job)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::job::testing::wait;
    use crate::job::JOB_DONE;

    fn temp_tree(name: &str) -> PathBuf {
        let root =
            std::env::temp_dir().join(format!("cb_native_walk_{name}_{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("a").join("b")).unwrap();
        fs::create_dir_all(root.join(".hidden")).unwrap();
        fs::write(root.join("one.jpg"), [0u8; 3]).unwrap();
        fs::write(root.join("a").join("two.JPG"), [0u8; 5]).unwrap();
        fs::write(root.join("a").join("b").join("three.png"), [0u8; 7]).unwrap();
        fs::write(root.join("a").join("b").join("note.txt"), [0u8; 11]).unwrap();
        fs::write(root.join(".hidden").join("four.jpg"), [0u8; 13]).unwrap();
        fs::write(root.join(".dot.jpg"), [0u8; 17]).unwrap();
        root
    }

    fn u64_at(bytes: &[u8], index: usize) -> u64 {
        u64::from_le_bytes(bytes[index * 8..index * 8 + 8].try_into().unwrap())
    }

    #[test]
    fn sums_files_and_folders() {
        let root = temp_tree("size");
        let mut config = Writer::default();
        config.u32(1);
        config.str(&root.join("one.jpg").to_string_lossy());
        config.u32(2);
        config.str(&root.join("a").to_string_lossy());
        config.str(&root.join("missing").to_string_lossy());
        let job = start_dir_size(0, &config.into_bytes()).unwrap();
        let (state, out) = wait(&job);
        assert_eq!(state, JOB_DONE);
        assert_eq!(u64_at(&out, 0), 3 + 5 + 7 + 11);
        assert_eq!(u64_at(&out, 1), 4);
        assert_eq!(u64_at(&out, 2), 2);
        assert_eq!(u64_at(&out, 3), 1);
        fs::remove_dir_all(&root).unwrap();
    }

    fn walk_names(config: Vec<u8>) -> Vec<String> {
        let WalkStart::Started(job) = start_walk(0, &config) else {
            panic!("walk did not start");
        };
        let (state, out) = wait(&job);
        assert_eq!(state, JOB_DONE);
        let mut r = Reader::new(&out);
        let mut names = Vec::new();
        while !r.is_empty() {
            r.u8().unwrap();
            r.u64().unwrap();
            r.i64().unwrap();
            let path = r.str().unwrap();
            names.push(
                PathBuf::from(path)
                    .file_name()
                    .unwrap()
                    .to_string_lossy()
                    .into_owned(),
            );
        }
        names.sort();
        names
    }

    fn walk_config(root: &std::path::Path, max_depth: u32, excludes: &[&str]) -> Vec<u8> {
        let mut config = Writer::default();
        config.u32(1);
        config.str(&root.to_string_lossy());
        config.u8(1);
        config.u32(max_depth);
        config.u8(WALK_FILES | WALK_SKIP_DOT_NAMES | WALK_STATS);
        config.u8(EXT_LAST_DOT);
        config.u32(2);
        config.str(".jpg");
        config.str(".png");
        config.u32(excludes.len() as u32);
        for pattern in excludes {
            config.str(pattern);
        }
        config.u64(0);
        config.u64(0);
        config.i64(i64::MAX);
        config.into_bytes()
    }

    #[test]
    fn walks_with_filters_like_get_all_images() {
        let root = temp_tree("files");
        assert_eq!(
            walk_names(walk_config(&root, 0, &[])),
            ["four.jpg", "one.jpg", "three.png", "two.JPG"]
        );
        assert_eq!(
            walk_names(walk_config(&root, 1, &["^T"])),
            ["four.jpg", "one.jpg"]
        );
        assert!(matches!(
            start_walk(0, &walk_config(&root, 0, &["("])),
            WalkStart::InvalidRegex
        ));

        let mut counting = walk_config(&root, 0, &[]);
        // The flags byte follows roots (u32 + str), recursive and max depth.
        let flags_at = 4 + 4 + root.to_string_lossy().len() + 1 + 4;
        counting[flags_at] |= WALK_COUNT_ONLY;
        let WalkStart::Started(job) = start_walk(0, &counting) else {
            panic!("walk did not start");
        };
        let (state, out) = wait(&job);
        assert_eq!(state, JOB_DONE);
        assert_eq!(out, 4u64.to_le_bytes());
        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn junk_rules_match_like_the_dart_worker() {
        let root = temp_tree("junk");
        let lower = cfg!(windows);
        let base = path_key(&root.to_string_lossy(), lower);
        let mut config = Writer::default();
        config.str(&root.to_string_lossy());
        config.u8(1);
        config.u8(u8::from(lower));
        config.u32(2);
        // Rule 0: *.JPG anywhere below root.
        config.i32(0);
        config.str(&base);
        config.u8(1);
        config.u8(1);
        config.u32(1);
        config.str("*.jpg");
        config.u8(0);
        config.u8(0);
        config.i64(0);
        // Rule 1: everything directly in root, but nothing new enough.
        config.i32(1);
        config.str(&base);
        config.u8(0);
        config.u8(0);
        config.u8(0);
        config.u8(1);
        config.i64(-1);
        let job = start_junk_scan(0, &config.into_bytes()).unwrap();
        let (state, out) = wait(&job);
        assert_eq!(state, JOB_DONE);
        let mut r = Reader::new(&out);
        let mut hits = Vec::new();
        while !r.is_empty() {
            assert_eq!(r.u8().unwrap(), JUNK_ITEM);
            r.u64().unwrap();
            r.i64().unwrap();
            let path = r.str().unwrap();
            let rules: Vec<i32> = (0..r.u32().unwrap()).map(|_| r.i32().unwrap()).collect();
            let name = PathBuf::from(path)
                .file_name()
                .unwrap()
                .to_string_lossy()
                .into_owned();
            hits.push((name, rules));
        }
        hits.sort();
        assert_eq!(
            hits,
            vec![
                (".dot.jpg".to_string(), vec![0]),
                ("four.jpg".to_string(), vec![0]),
                ("one.jpg".to_string(), vec![0]),
                ("two.JPG".to_string(), vec![0]),
            ]
        );
        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn many_concurrent_walks_all_finish() {
        let root = temp_tree("many");
        let jobs: Vec<_> = (0..40)
            .map(|_| {
                let mut config = Writer::default();
                config.u32(0);
                config.u32(1);
                config.str(&root.to_string_lossy());
                start_dir_size(0, &config.into_bytes()).unwrap()
            })
            .collect();
        for job in &jobs {
            let (state, out) = wait(job);
            assert_eq!(state, JOB_DONE);
            assert_eq!(u64_at(&out, 0), 3 + 5 + 7 + 11 + 13 + 17);
        }
        fs::remove_dir_all(&root).unwrap();
    }
}

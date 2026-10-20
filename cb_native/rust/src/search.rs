//! Parallel recursive name search.
//!
//! A fixed pool of worker threads shares one stack of directories still to
//! read. Each worker reads a directory, matches every entry name, queues the
//! subdirectories and appends matches to a shared buffer that Dart drains by
//! polling. Nothing here blocks the caller: `start` only spawns threads.

use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;

use regex::{Regex, RegexBuilder};

use crate::normalize::search_key;

// Non-zero: records are NUL-terminated, so a kind byte must never be 0.
pub const KIND_DIRECTORY: u8 = 1;
pub const KIND_FILE: u8 = 2;
pub const KIND_LINK: u8 = 3;

/// Matches drained from workers before they are pushed to the shared buffer.
const LOCAL_FLUSH_BYTES: usize = 16 * 1024;

pub enum Matcher {
    /// `TextUtils.matchesSearch`: every word occurs in the name's search key.
    Words(Vec<String>),
    /// Dart's `RegExp(pattern, caseSensitive: false, unicode: true).hasMatch`.
    Regex(Regex),
}

impl Matcher {
    pub fn regex(pattern: &str) -> Option<Matcher> {
        RegexBuilder::new(pattern)
            .case_insensitive(true)
            .build()
            .ok()
            .map(Matcher::Regex)
    }

    fn matches(&self, name: &str) -> bool {
        match self {
            Matcher::Words(words) => {
                if words.is_empty() {
                    return true;
                }
                let key = search_key(name);
                words.iter().all(|word| key.contains(word.as_str()))
            }
            Matcher::Regex(regex) => regex.is_match(name),
        }
    }
}

struct Queue {
    dirs: Vec<PathBuf>,
    /// Workers currently reading a directory. The walk is over once the
    /// stack is empty and no worker can push more.
    active: usize,
}

pub struct Search {
    queue: Mutex<Queue>,
    wake: Condvar,
    /// Records of `[kind][utf-8 path][0]`, drained by `take_results`.
    results: Mutex<Vec<u8>>,
    cancelled: AtomicBool,
    finished: AtomicBool,
    matcher: Matcher,
}

impl Search {
    pub fn start(root: PathBuf, matcher: Matcher) -> Arc<Search> {
        let search = Arc::new(Search {
            queue: Mutex::new(Queue {
                dirs: vec![root],
                active: 0,
            }),
            wake: Condvar::new(),
            results: Mutex::new(Vec::new()),
            cancelled: AtomicBool::new(false),
            finished: AtomicBool::new(false),
            matcher,
        });

        let workers = thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(4)
            .clamp(2, 8);
        for _ in 0..workers {
            let worker = Arc::clone(&search);
            let spawned = thread::Builder::new()
                .name("cb_native_search".into())
                .spawn(move || worker.run_worker());
            if spawned.is_err() {
                // Fewer workers only slows the walk; one is enough to finish it.
                break;
            }
        }
        search
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
        self.wake.notify_all();
    }

    /// Returns the matches found since the last call, and whether the walk
    /// is over. `finished` is read before draining so the final batch is
    /// never left behind.
    pub fn take_results(&self) -> (Vec<u8>, bool) {
        let finished = self.finished.load(Ordering::Acquire);
        let batch = std::mem::take(&mut *self.lock_results());
        (batch, finished)
    }

    fn lock_results(&self) -> std::sync::MutexGuard<'_, Vec<u8>> {
        self.results.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn lock_queue(&self) -> std::sync::MutexGuard<'_, Queue> {
        self.queue.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn run_worker(&self) {
        loop {
            let dir = {
                let mut queue = self.lock_queue();
                loop {
                    if self.cancelled.load(Ordering::Acquire) {
                        self.finished.store(true, Ordering::Release);
                        return;
                    }
                    if let Some(dir) = queue.dirs.pop() {
                        queue.active += 1;
                        break dir;
                    }
                    if queue.active == 0 {
                        self.finished.store(true, Ordering::Release);
                        self.wake.notify_all();
                        return;
                    }
                    queue = self.wake.wait(queue).unwrap_or_else(|e| e.into_inner());
                }
            };

            // Decrements `active` even if reading the directory panics, so the
            // walk can still finish and Dart's poll loop can still end.
            let _active = ActiveGuard(self);
            let subdirs = self.read_directory(dir);
            if !subdirs.is_empty() {
                let mut queue = self.lock_queue();
                queue.dirs.extend(subdirs);
            }
        }
    }

    fn read_directory(&self, dir: PathBuf) -> Vec<PathBuf> {
        let mut subdirs = Vec::new();
        let entries = match fs::read_dir(&dir) {
            Ok(entries) => entries,
            // Inaccessible directories are skipped, like the Dart walker.
            Err(_) => return subdirs,
        };

        let mut local = Vec::new();
        for entry in entries {
            if self.cancelled.load(Ordering::Relaxed) {
                break;
            }
            let Ok(entry) = entry else { continue };
            let Ok(file_type) = entry.file_type() else {
                continue;
            };

            // `Directory.list(followLinks: false)` reports symlinks and
            // junctions as Link and the Dart walker never descends into them.
            let kind = if file_type.is_symlink() {
                KIND_LINK
            } else if file_type.is_dir() {
                KIND_DIRECTORY
            } else {
                KIND_FILE
            };

            let path = entry.path();
            let name = entry.file_name();
            if self.matcher.matches(&name.to_string_lossy()) {
                local.push(kind);
                local.extend_from_slice(path.to_string_lossy().as_bytes());
                local.push(0);
                if local.len() >= LOCAL_FLUSH_BYTES {
                    self.lock_results().append(&mut local);
                }
            }
            if kind == KIND_DIRECTORY {
                subdirs.push(path);
            }
        }
        if !local.is_empty() {
            self.lock_results().append(&mut local);
        }
        subdirs
    }
}

struct ActiveGuard<'a>(&'a Search);

impl Drop for ActiveGuard<'_> {
    fn drop(&mut self) {
        let mut queue = self.0.lock_queue();
        queue.active -= 1;
        drop(queue);
        self.0.wake.notify_all();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Duration, Instant};

    fn collect(search: &Search) -> Vec<(u8, String)> {
        let deadline = Instant::now() + Duration::from_secs(10);
        let mut bytes = Vec::new();
        loop {
            let (batch, finished) = search.take_results();
            bytes.extend(batch);
            if finished {
                break;
            }
            assert!(Instant::now() < deadline, "search did not finish");
            thread::sleep(Duration::from_millis(5));
        }
        let mut hits: Vec<(u8, String)> = bytes
            .split(|&b| b == 0)
            .filter(|record| !record.is_empty())
            .map(|record| {
                (
                    record[0],
                    String::from_utf8_lossy(&record[1..]).into_owned(),
                )
            })
            .collect();
        hits.sort();
        hits
    }

    #[test]
    fn finds_matches_in_nested_directories() {
        let root = std::env::temp_dir().join(format!("cb_native_search_{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("Bổ Não").join("deep")).unwrap();
        fs::write(root.join("Bổ Não").join("deep").join("bo_nao.txt"), b"").unwrap();
        fs::write(root.join("other.txt"), b"").unwrap();

        let search = Search::start(
            root.clone(),
            Matcher::Words(vec!["bo".into(), "nao".into()]),
        );
        let hits = collect(&search);
        let names: Vec<_> = hits
            .iter()
            .map(|(kind, path)| {
                (
                    *kind,
                    PathBuf::from(path)
                        .file_name()
                        .unwrap()
                        .to_string_lossy()
                        .into_owned(),
                )
            })
            .collect();
        assert_eq!(
            names,
            vec![
                (KIND_DIRECTORY, "Bổ Não".to_string()),
                (KIND_FILE, "bo_nao.txt".to_string())
            ]
        );

        let regex = Search::start(root.clone(), Matcher::regex(r"^other\.TXT$").unwrap());
        assert_eq!(collect(&regex).len(), 1);

        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn missing_root_finishes_empty() {
        let search = Search::start(
            PathBuf::from("Z:/cb_native/definitely/missing"),
            Matcher::Words(vec![]),
        );
        assert!(collect(&search).is_empty());
    }
}

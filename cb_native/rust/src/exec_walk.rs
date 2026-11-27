//! Runnable-file walk for the Cleaner's leftover Deep Scan.
//!
//! Port of `_scanExecutables` in
//! cb_file_manager/lib/services/app_insights/windows_leftover_presence.dart:
//! lists every file below one root whose extension is in a set (`.exe`,
//! `.cmd`, ...) so Dart can rule out leftover folders that belong to an
//! unregistered (portable) app. Dart keeps the name rules and decides when it
//! has seen enough; this only replaces the walk, on the shared pool's threads.
//!
//! It must never see fewer files than the Dart walk, or a live app's data
//! could be offered for deletion. So it classifies entries like Dart's
//! `Directory.listSync(followLinks: false)` on Windows: any reparse point
//! (symlink, junction, cloud placeholder, app execution alias) is a `Link`,
//! skipped and counted as incomplete; everything else that is not a
//! directory is a `File`. Every listed entry counts toward the budget.
//!
//! Output: one string per matching file path. Counters: entries listed,
//! directories read, incomplete events (unreadable folder, link or reparse
//! point, failed entry, budget reached), matches.

use std::collections::HashSet;
use std::fs;
use std::sync::atomic::Ordering;
use std::sync::Arc;

use crate::fsx;
use crate::job::Job;
use crate::normalize::{dart_lower, dart_upper};
use crate::walk::{read_dir, start, widen_pool, Kind, Task, Walk};
use crate::wire::{Reader, Writer};

const VISITED: usize = 0;
const DIRECTORIES: usize = 1;
const INCOMPLETE: usize = 2;
const MATCHES: usize = 3;

struct ExecutableWalk {
    recursive: bool,
    /// 0 = unlimited; otherwise listing more entries than this stops the
    /// walk as incomplete, like the Dart `maxEntries`.
    max_entries: u64,
    /// Lower-cased, with the dot, compared with package:path `extension`.
    extensions: HashSet<String>,
    /// Upper-cased folder names that are never entered.
    skip_names: HashSet<String>,
    /// Upper-cased full folder paths that are never entered.
    skip_paths: HashSet<String>,
}

/// What `Directory.listSync(followLinks: false)` reports as a `Link`.
fn is_link(file_type: &fs::FileType, metadata: Option<&fs::Metadata>) -> bool {
    if file_type.is_symlink() {
        return true;
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
        if let Some(metadata) = metadata {
            return metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0;
        }
    }
    #[cfg(not(windows))]
    let _ = metadata;
    false
}

impl ExecutableWalk {
    fn skipped(&self, name: &str, path: &str) -> bool {
        (!self.skip_names.is_empty() && self.skip_names.contains(&dart_upper(name)))
            || (!self.skip_paths.is_empty() && self.skip_paths.contains(&dart_upper(path)))
    }
}

impl Kind for ExecutableWalk {
    fn scan(&self, walk: &Walk, task: &Task) -> Vec<Task> {
        let job = &walk.job;
        // Dart checks the reparse attribute of every folder it is about to
        // list; children that are reparse points never get here (they are
        // links below), so only the root needs it.
        if task.depth == 0 {
            if let Ok(metadata) = fs::symlink_metadata(&task.path) {
                if is_link(&metadata.file_type(), Some(&metadata)) {
                    job.add_counter(INCOMPLETE, 1);
                    return Vec::new();
                }
            }
        }
        let Some(entries) = read_dir(walk, task) else {
            job.add_counter(INCOMPLETE, 1);
            return Vec::new();
        };
        job.add_counter(DIRECTORIES, 1);
        let mut children = Vec::new();
        let mut out = Writer::default();
        for entry in entries {
            if walk.halted() {
                break;
            }
            let visited = job.add_counter(VISITED, 1);
            if self.max_entries > 0 && visited > self.max_entries {
                job.add_counter(INCOMPLETE, 1);
                walk.stop.store(true, Ordering::Relaxed);
                break;
            }
            // Dart's listSync throws for the whole folder on such an error.
            let Ok(entry) = entry else {
                job.add_counter(INCOMPLETE, 1);
                continue;
            };
            let Ok(file_type) = entry.file_type() else {
                job.add_counter(INCOMPLETE, 1);
                continue;
            };
            // Free on Windows: read from the directory listing itself.
            let metadata = if cfg!(windows) {
                entry.metadata().ok()
            } else {
                None
            };
            if is_link(&file_type, metadata.as_ref()) {
                job.add_counter(INCOMPLETE, 1);
                continue;
            }
            let name = entry.file_name().to_string_lossy().into_owned();
            if file_type.is_dir() {
                if !self.recursive {
                    continue;
                }
                let path = fsx::join(&task.path, &name);
                if !self.skipped(&name, &path) {
                    children.push(Task::dir(path, task.depth + 1));
                }
                continue;
            }
            if !self
                .extensions
                .contains(&dart_lower(fsx::path_extension(&name)))
            {
                continue;
            }
            out.str(&fsx::join(&task.path, &name));
            job.add_counter(MATCHES, 1);
        }
        job.append_vec(&mut out.into_bytes());
        children
    }
}

/// Config: root, recursive u8, max entries u64, extensions (lower-case, with
/// the dot), folder names to skip, full folder paths to skip.
pub fn start_executable_walk(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let root = r.str()?;
    let recursive = r.bool()?;
    let max_entries = r.u64()?;
    let extensions = r.strs()?;
    let skip_names = r.strs()?;
    let skip_paths = r.strs()?;
    if !r.is_empty() || root.is_empty() {
        return None;
    }
    let kind = ExecutableWalk {
        recursive,
        max_entries,
        extensions: extensions.iter().map(|e| dart_lower(e)).collect(),
        skip_names: skip_names.iter().map(|n| dart_upper(n)).collect(),
        skip_paths: skip_paths.iter().map(|p| dart_upper(p)).collect(),
    };
    let job = start(port, vec![Task::dir(root, 0)], Box::new(kind));
    // A whole drive is the common case: let it use every idle pool thread.
    widen_pool();
    Some(job)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::job::testing::wait;
    use crate::job::JOB_DONE;
    use std::path::PathBuf;

    fn tree(name: &str) -> PathBuf {
        let root =
            std::env::temp_dir().join(format!("cb_native_exec_{name}_{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        for dir in ["app/bin", "Skipme/deep", "sys/inner", "data"] {
            fs::create_dir_all(root.join(dir)).unwrap();
        }
        for file in [
            "top.exe",
            "app/bin/tool.EXE",
            "app/bin/run.cmd",
            "app/readme.txt",
            "Skipme/deep/hidden.exe",
            "sys/inner/sys.exe",
            "data/.exe",
            "data/notes.bat.txt",
        ] {
            fs::write(root.join(file), b"x").unwrap();
        }
        root
    }

    fn config(root: &std::path::Path, recursive: bool, max_entries: u64) -> Vec<u8> {
        let mut c = Writer::default();
        c.str(&root.to_string_lossy());
        c.u8(u8::from(recursive));
        c.u64(max_entries);
        c.u32(4);
        for ext in [".exe", ".com", ".CMD", ".bat"] {
            c.str(ext);
        }
        c.u32(1);
        c.str("skipme");
        c.u32(1);
        c.str(&root.join("sys").to_string_lossy());
        c.into_bytes()
    }

    fn names(out: &[u8]) -> Vec<String> {
        let mut r = Reader::new(out);
        let mut names = Vec::new();
        while !r.is_empty() {
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

    #[test]
    fn lists_runnable_files_and_skips_folders() {
        let root = tree("list");
        let job = start_executable_walk(0, &config(&root, true, 0)).unwrap();
        let (state, out) = wait(&job);
        assert_eq!(state, JOB_DONE);
        // `.exe` alone is a dot name without an extension, like package:path.
        assert_eq!(names(&out), ["run.cmd", "tool.EXE", "top.exe"]);
        let (counters, _) = job.progress();
        assert_eq!(counters[INCOMPLETE], 0);
        assert_eq!(counters[MATCHES], 3);
        // root: top.exe app Skipme sys data (5); app: bin readme (2);
        // app/bin: 2; data: 2. Skipped folders are listed but not entered.
        assert_eq!(counters[VISITED], 11);
        assert_eq!(counters[DIRECTORIES], 4);
        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn non_recursive_reads_only_the_root() {
        let root = tree("flat");
        let job = start_executable_walk(0, &config(&root, false, 0)).unwrap();
        let (state, out) = wait(&job);
        assert_eq!(state, JOB_DONE);
        assert_eq!(names(&out), ["top.exe"]);
        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn budget_and_missing_root_are_incomplete() {
        let root = tree("budget");
        let job = start_executable_walk(0, &config(&root, true, 3)).unwrap();
        let (state, _) = wait(&job);
        assert_eq!(state, JOB_DONE);
        assert!(job.progress().0[INCOMPLETE] > 0);

        let missing = start_executable_walk(0, &config(&root.join("nope"), true, 0)).unwrap();
        let (state, out) = wait(&missing);
        assert_eq!(state, JOB_DONE);
        assert!(out.is_empty());
        assert_eq!(missing.progress().0[INCOMPLETE], 1);
        fs::remove_dir_all(&root).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn links_are_skipped_as_incomplete() {
        let root = tree("links");
        std::os::unix::fs::symlink(root.join("app"), root.join("linked")).unwrap();
        let job = start_executable_walk(0, &config(&root, true, 0)).unwrap();
        let (_, out) = wait(&job);
        assert_eq!(names(&out), ["run.cmd", "tool.EXE", "top.exe"]);
        assert_eq!(job.progress().0[INCOMPLETE], 1);
        fs::remove_dir_all(&root).unwrap();
    }

    /// Junctions need no privilege, unlike symlinks, and are what Windows
    /// profiles are full of (`Application Data`, `My Documents`).
    #[cfg(windows)]
    #[test]
    fn junctions_are_skipped_as_incomplete() {
        let root = tree("junction");
        let status = std::process::Command::new("cmd")
            .args(["/C", "mklink", "/J"])
            .arg(root.join("linked"))
            .arg(root.join("app"))
            .output()
            .unwrap()
            .status;
        assert!(status.success());
        let job = start_executable_walk(0, &config(&root, true, 0)).unwrap();
        let (_, out) = wait(&job);
        assert_eq!(names(&out), ["run.cmd", "tool.EXE", "top.exe"]);
        assert_eq!(job.progress().0[INCOMPLETE], 1);

        // A junction given as the root is not entered either.
        let linked = start_executable_walk(0, &config(&root.join("linked"), true, 0)).unwrap();
        let (_, out) = wait(&linked);
        assert!(out.is_empty());
        assert_eq!(linked.progress().0[INCOMPLETE], 1);
        fs::remove_dir(root.join("linked")).unwrap();
        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn rejects_bad_config() {
        assert!(start_executable_walk(0, &[1, 2]).is_none());
    }
}

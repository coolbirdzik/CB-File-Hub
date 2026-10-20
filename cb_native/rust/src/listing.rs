//! One directory's listing, sorted the way the folder browser shows it.
//!
//! Port of `_scanDirectoryInIsolate` in file_navigation_bloc.dart. On Windows
//! the size and times come with the directory entries, so sorting by date or
//! size costs no extra syscall per file (the Dart code stats every entry).

use std::cmp::Ordering;
use std::fs;
use std::sync::Arc;

use crate::fsx::{self, KIND_DIRECTORY, KIND_FILE};
use crate::job::Job;
use crate::normalize::{dart_compare, dart_lower};
use crate::wire::{Reader, Writer};

/// `SortOption` names, in the order Dart encodes them.
#[derive(Clone, Copy, PartialEq)]
enum Sort {
    NameAsc,
    NameDesc,
    DateAsc,
    DateDesc,
    CreatedAsc,
    CreatedDesc,
    SizeAsc,
    SizeDesc,
    ExtensionAsc,
    ExtensionDesc,
}

impl Sort {
    fn from_index(index: u8) -> Sort {
        match index {
            1 => Sort::NameDesc,
            2 => Sort::DateAsc,
            3 => Sort::DateDesc,
            4 => Sort::CreatedAsc,
            5 => Sort::CreatedDesc,
            6 => Sort::SizeAsc,
            7 => Sort::SizeDesc,
            8 => Sort::ExtensionAsc,
            9 => Sort::ExtensionDesc,
            _ => Sort::NameAsc,
        }
    }

    fn needs_stats(self) -> bool {
        !matches!(
            self,
            Sort::NameAsc | Sort::NameDesc | Sort::ExtensionAsc | Sort::ExtensionDesc
        )
    }
}

struct Entry {
    kind: u8,
    path: String,
    /// Dart-lower-cased name (or extension) for the comparator.
    key: String,
    size: u64,
    modified: i64,
    changed: i64,
}

fn compare(sort: Sort, a: &Entry, b: &Entry) -> Ordering {
    match sort {
        Sort::NameAsc | Sort::ExtensionAsc => dart_compare(&a.key, &b.key),
        Sort::NameDesc | Sort::ExtensionDesc => dart_compare(&b.key, &a.key),
        Sort::DateAsc => a.modified.cmp(&b.modified),
        Sort::DateDesc => b.modified.cmp(&a.modified),
        Sort::CreatedAsc => a.changed.cmp(&b.changed),
        Sort::CreatedDesc => b.changed.cmp(&a.changed),
        Sort::SizeAsc => a.size.cmp(&b.size),
        Sort::SizeDesc => b.size.cmp(&a.size),
    }
}

/// `cmpExt` takes the last dot of the whole path, not of the name.
fn extension_key(path: &str) -> String {
    path.rfind('.')
        .map_or_else(String::new, |dot| dart_lower(&path[dot..]))
}

fn list(
    job: &Job,
    path: &str,
    sort: Sort,
    stats: bool,
    skip_suffixes: &[String],
    skip_names: &[String],
) -> Result<(), String> {
    let entries = fs::read_dir(path).map_err(|e| e.to_string())?;
    let with_stats = stats || sort.needs_stats();
    let mut folders = Vec::new();
    let mut files = Vec::new();
    for entry in entries {
        if job.cancelled() {
            return Ok(());
        }
        let Ok(entry) = entry else { continue };
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        // `list(followLinks: false)` yields links as Link, which the Dart
        // listing drops.
        if file_type.is_symlink() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().into_owned();
        let full = fsx::join(path, &name);
        let is_dir = file_type.is_dir();
        if !is_dir
            && (skip_suffixes
                .iter()
                .any(|suffix| full.ends_with(suffix.as_str()))
                || skip_names.contains(&name))
        {
            continue;
        }
        let (mut size, mut modified, mut changed) = (0, 0, 0);
        if with_stats {
            if let Ok(metadata) = entry.metadata() {
                size = if is_dir { 0 } else { metadata.len() };
                modified = fsx::modified_ms(&metadata);
                changed = fsx::changed_ms(&metadata);
            }
        }
        let key = match sort {
            Sort::ExtensionAsc | Sort::ExtensionDesc => extension_key(&full),
            Sort::NameAsc | Sort::NameDesc => dart_lower(&name),
            _ => String::new(),
        };
        let item = Entry {
            kind: if is_dir { KIND_DIRECTORY } else { KIND_FILE },
            path: full,
            key,
            size,
            modified,
            changed,
        };
        if is_dir {
            folders.push(item);
        } else {
            files.push(item);
        }
    }
    folders.sort_by(|a, b| compare(sort, a, b));
    files.sort_by(|a, b| compare(sort, a, b));

    let mut out = Writer::default();
    out.u32(folders.len() as u32);
    out.u32(files.len() as u32);
    for item in folders.iter().chain(files.iter()) {
        out.u8(item.kind);
        out.u64(item.size);
        out.i64(item.modified);
        out.i64(item.changed);
        out.str(&item.path);
    }
    job.set_counter(0, (folders.len() + files.len()) as u64);
    job.append(&out.into_bytes());
    Ok(())
}

/// Config: path, sort index u8, always stat u8, file suffixes to skip, file
/// names to skip. Output: folder count u32, file count u32, then folders and
/// files in display order as kind u8, size u64, modified ms i64, changed ms
/// i64, path.
pub fn start_list_dir(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let path = r.str()?;
    let sort = Sort::from_index(r.u8()?);
    let stats = r.bool()?;
    let skip_suffixes = r.strs()?;
    let skip_names = r.strs()?;
    if !r.is_empty() || path.is_empty() {
        return None;
    }
    Some(Job::spawn(port, "cb_native_list", move |job| {
        list(job, &path, sort, stats, &skip_suffixes, &skip_names)
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::job::testing::wait;
    use crate::job::JOB_DONE;

    fn names(config: &[u8]) -> (u32, Vec<String>) {
        let job = start_list_dir(0, config).unwrap();
        let (state, out) = wait(&job);
        assert_eq!(state, JOB_DONE);
        let mut r = Reader::new(&out);
        let folders = r.u32().unwrap();
        let files = r.u32().unwrap();
        let mut names = Vec::new();
        for _ in 0..folders + files {
            r.u8().unwrap();
            r.u64().unwrap();
            r.i64().unwrap();
            r.i64().unwrap();
            let path = r.str().unwrap();
            names.push(path.rsplit(['/', '\\']).next().unwrap().to_string());
        }
        (folders, names)
    }

    fn config(path: &str, sort: u8) -> Vec<u8> {
        let mut w = Writer::default();
        w.str(path);
        w.u8(sort);
        w.u8(0);
        w.u32(1);
        w.str(".tags");
        w.u32(1);
        w.str(".cbfile_config.json");
        w.into_bytes()
    }

    #[test]
    fn sorts_folders_then_files_like_dart() {
        let root = std::env::temp_dir().join(format!("cb_native_list_{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("Zeta")).unwrap();
        fs::create_dir_all(root.join("alpha")).unwrap();
        fs::write(root.join("b.txt"), [0u8; 9]).unwrap();
        fs::write(root.join("A.mp4"), [0u8; 1]).unwrap();
        fs::write(root.join("c.tags"), b"").unwrap();
        fs::write(root.join(".cbfile_config.json"), b"").unwrap();
        let path = root.to_string_lossy().into_owned();

        assert_eq!(
            names(&config(&path, 0)),
            (
                2,
                vec![
                    "alpha".into(),
                    "Zeta".into(),
                    "A.mp4".into(),
                    "b.txt".into()
                ]
            )
        );
        assert_eq!(
            names(&config(&path, 7)).1[2..],
            ["b.txt".to_string(), "A.mp4".to_string()]
        );
        assert_eq!(
            names(&config(&path, 9)).1[2..],
            ["b.txt".to_string(), "A.mp4".to_string()]
        );

        let missing = start_list_dir(0, &config(&root.join("nope").to_string_lossy(), 0)).unwrap();
        assert_eq!(wait(&missing).0, crate::job::JOB_FAILED);
        fs::remove_dir_all(&root).unwrap();
    }
}

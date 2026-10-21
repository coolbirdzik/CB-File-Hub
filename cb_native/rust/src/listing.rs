//! One directory's listing, sorted the way the folder browser shows it.
//!
//! Port of `_scanDirectoryInIsolate` in file_navigation_bloc.dart. On Windows
//! the size and times come with the directory entries, so sorting by date or
//! size costs no extra syscall per file (the Dart code stats every entry).

use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::Path;
use std::sync::atomic::{AtomicUsize, Ordering as AtomicOrdering};
use std::sync::{Arc, Mutex};
use std::thread;

use crate::fsx::{self, KIND_DIRECTORY, KIND_FILE};
use crate::job::{lock, Job};
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
    TypeAsc,
    TypeDesc,
    AccessedAsc,
    AccessedDesc,
    PathAsc,
    PathDesc,
    AttributesAsc,
    AttributesDesc,
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
            10 => Sort::TypeAsc,
            11 => Sort::TypeDesc,
            12 => Sort::AccessedAsc,
            13 => Sort::AccessedDesc,
            14 => Sort::PathAsc,
            15 => Sort::PathDesc,
            16 => Sort::AttributesAsc,
            17 => Sort::AttributesDesc,
            _ => Sort::NameAsc,
        }
    }

    fn needs_stats(self) -> bool {
        !matches!(
            self,
            Sort::NameAsc
                | Sort::NameDesc
                | Sort::ExtensionAsc
                | Sort::ExtensionDesc
                | Sort::TypeAsc
                | Sort::TypeDesc
                | Sort::PathAsc
                | Sort::PathDesc
        )
    }
}

struct Entry {
    kind: u8,
    path: String,
    /// What a text order compares: the Dart-lower-cased name, extension,
    /// type or path, or the attribute letters.
    key: String,
    size: u64,
    modified: i64,
    changed: i64,
    accessed: i64,
}

fn compare(sort: Sort, a: &Entry, b: &Entry) -> Ordering {
    match sort {
        Sort::NameAsc
        | Sort::ExtensionAsc
        | Sort::TypeAsc
        | Sort::PathAsc
        | Sort::AttributesAsc => dart_compare(&a.key, &b.key),
        Sort::NameDesc
        | Sort::ExtensionDesc
        | Sort::TypeDesc
        | Sort::PathDesc
        | Sort::AttributesDesc => dart_compare(&b.key, &a.key),
        Sort::AccessedAsc => a.accessed.cmp(&b.accessed),
        Sort::AccessedDesc => b.accessed.cmp(&a.accessed),
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

/// package:path `extension` of the name (the Type order): from the last
/// dot, which must not be the first character.
fn type_key(name: &str) -> String {
    match name.rfind('.') {
        Some(dot) if dot > 0 => dart_lower(&name[dot..]),
        _ => String::new(),
    }
}

/// The letters `FileAttributes.describe` shows in the Attributes column:
/// the Windows attribute bits, or read-only and dot-hidden elsewhere and on
/// UNC paths (which the Dart side does not query).
fn attributes_key(path: &str, name: &str, metadata: Option<&fs::Metadata>) -> String {
    #[cfg(windows)]
    if !path.starts_with(r"\\") {
        use std::os::windows::fs::MetadataExt;
        const LETTERS: [(u32, char); 8] = [
            (0x1, 'R'),
            (0x2, 'H'),
            (0x4, 'S'),
            (0x20, 'A'),
            (0x800, 'C'),
            (0x4000, 'E'),
            (0x1000, 'O'),
            (0x400, 'L'),
        ];
        let Some(metadata) = metadata else {
            return String::new();
        };
        let bits = metadata.file_attributes();
        return LETTERS
            .iter()
            .filter(|(bit, _)| bits & bit != 0)
            .map(|(_, letter)| *letter)
            .collect();
    }
    #[cfg(not(windows))]
    let _ = path;
    let read_only = metadata.is_some_and(|metadata| {
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            metadata.permissions().mode() & 0o200 == 0
        }
        #[cfg(not(unix))]
        {
            metadata.permissions().readonly()
        }
    });
    let mut key = String::new();
    if read_only {
        key.push('R');
    }
    if name.starts_with('.') {
        key.push('H');
    }
    key
}

/// The sort key and stats of one entry. `metadata` is required for the
/// orders that [Sort::needs_stats]; without it they read as zero.
fn make_entry(
    sort: Sort,
    full: String,
    name: &str,
    is_dir: bool,
    metadata: Option<&fs::Metadata>,
) -> Entry {
    let (mut size, mut modified, mut changed, mut accessed) = (0, 0, 0, 0);
    if let Some(metadata) = metadata {
        size = if is_dir { 0 } else { metadata.len() };
        modified = fsx::modified_ms(metadata);
        changed = fsx::changed_ms(metadata);
        accessed = fsx::epoch_ms(metadata.accessed());
    }
    let key = match sort {
        Sort::ExtensionAsc | Sort::ExtensionDesc => extension_key(&full),
        Sort::NameAsc | Sort::NameDesc => dart_lower(name),
        Sort::TypeAsc | Sort::TypeDesc => type_key(name),
        Sort::PathAsc | Sort::PathDesc => dart_lower(&full),
        Sort::AttributesAsc | Sort::AttributesDesc => attributes_key(&full, name, metadata),
        _ => String::new(),
    };
    Entry {
        kind: if is_dir { KIND_DIRECTORY } else { KIND_FILE },
        path: full,
        key,
        size,
        modified,
        changed,
        accessed,
    }
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
        let metadata = if with_stats {
            entry.metadata().ok()
        } else {
            None
        };
        let item = make_entry(sort, full, &name, is_dir, metadata.as_ref());
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

/// One path to sort: its name, its index in the request and the path.
type Wanted<'a> = (&'a str, usize, &'a str);

/// Metadata of every [Wanted] path of one folder. Listing the folder is one
/// call instead of one per file, and on Windows its entries carry the size,
/// times and attributes. Paths it does not match are stat'ed directly.
fn folder_metadata(parent: &str, wanted: &[Wanted]) -> Vec<(usize, fs::Metadata)> {
    let mut found = Vec::with_capacity(wanted.len());
    if wanted.len() > 1 {
        if let Ok(entries) = fs::read_dir(parent) {
            let by_name: HashMap<&str, usize> = wanted
                .iter()
                .map(|(name, index, _)| (*name, *index))
                .collect();
            for entry in entries.flatten() {
                let name = entry.file_name();
                let Some(&index) = name.to_str().and_then(|name| by_name.get(name)) else {
                    continue;
                };
                if let Ok(metadata) = entry.metadata() {
                    found.push((index, metadata));
                }
            }
        }
    }
    let have: HashSet<usize> = found.iter().map(|(index, _)| *index).collect();
    for (_, index, path) in wanted {
        if !have.contains(index) {
            if let Ok(metadata) = fs::metadata(path) {
                found.push((*index, metadata));
            }
        }
    }
    found
}

/// Sorts paths from anywhere (a video library, a playlist) in a folder
/// listing's order. Stats an order needs are read per parent folder on
/// worker threads.
fn sort_paths(job: &Job, sort: Sort, paths: &[String]) -> Result<(), String> {
    let mut metadata: Vec<Option<fs::Metadata>> = paths.iter().map(|_| None).collect();
    if sort.needs_stats() {
        let mut groups: HashMap<&str, Vec<Wanted>> = HashMap::new();
        for (index, path) in paths.iter().enumerate() {
            let as_path = Path::new(path);
            let parent = as_path.parent().and_then(Path::to_str).unwrap_or("");
            let name = as_path.file_name().and_then(|n| n.to_str()).unwrap_or("");
            groups.entry(parent).or_default().push((name, index, path));
        }
        let groups: Vec<(&str, Vec<Wanted>)> = groups.into_iter().collect();
        let next = AtomicUsize::new(0);
        let found = Mutex::new(Vec::with_capacity(paths.len()));
        let workers = thread::available_parallelism()
            .map_or(4, |n| n.get())
            .min(8)
            .min(groups.len())
            .max(1);
        thread::scope(|scope| {
            for _ in 0..workers {
                scope.spawn(|| loop {
                    let group = next.fetch_add(1, AtomicOrdering::Relaxed);
                    if group >= groups.len() || job.cancelled() {
                        break;
                    }
                    let (parent, wanted) = &groups[group];
                    let mut batch = folder_metadata(parent, wanted);
                    lock(&found).append(&mut batch);
                });
            }
        });
        if job.cancelled() {
            return Ok(());
        }
        for (index, value) in found.into_inner().unwrap_or_default() {
            metadata[index] = Some(value);
        }
    }
    let entries: Vec<Entry> = paths
        .iter()
        .zip(&metadata)
        .map(|(path, metadata)| {
            let name = Path::new(path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or(path);
            let is_dir = metadata.as_ref().is_some_and(fs::Metadata::is_dir);
            make_entry(sort, path.clone(), name, is_dir, metadata.as_ref())
        })
        .collect();
    let mut order: Vec<usize> = (0..entries.len()).collect();
    order.sort_by(|&a, &b| compare(sort, &entries[a], &entries[b]));

    let mut out = Writer::default();
    out.u32(order.len() as u32);
    for index in order {
        out.u32(index as u32);
    }
    job.set_counter(0, paths.len() as u64);
    job.append(&out.into_bytes());
    Ok(())
}

/// Config: sort index u8, paths. Output: count u32, then the indices of the
/// paths in display order as u32.
pub fn start_sort_paths(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let sort = Sort::from_index(r.u8()?);
    let paths = r.strs()?;
    if !r.is_empty() {
        return None;
    }
    Some(Job::spawn(port, "cb_native_sort_paths", move |job| {
        sort_paths(job, sort, &paths)
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

        // Type (package:path extension of the name) and path.
        assert_eq!(
            names(&config(&path, 11)).1[2..],
            ["b.txt".to_string(), "A.mp4".to_string()]
        );
        assert_eq!(
            names(&config(&path, 14)).1,
            ["alpha", "Zeta", "A.mp4", "b.txt"].map(String::from)
        );
        assert_eq!(type_key(".bashrc"), "");
        assert_eq!(type_key("Photo.JPG"), ".jpg");

        let missing = start_list_dir(0, &config(&root.join("nope").to_string_lossy(), 0)).unwrap();
        assert_eq!(wait(&missing).0, crate::job::JOB_FAILED);
        fs::remove_dir_all(&root).unwrap();
    }

    fn sorted(paths: &[String], sort: u8) -> Vec<usize> {
        let mut w = Writer::default();
        w.u8(sort);
        w.u32(paths.len() as u32);
        for path in paths {
            w.str(path);
        }
        let job = start_sort_paths(0, &w.into_bytes()).unwrap();
        let (state, out) = wait(&job);
        assert_eq!(state, JOB_DONE);
        let mut r = Reader::new(&out);
        (0..r.u32().unwrap())
            .map(|_| r.u32().unwrap() as usize)
            .collect()
    }

    #[test]
    fn sorts_paths_from_several_folders() {
        let root = std::env::temp_dir().join(format!("cb_native_sort_{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("one")).unwrap();
        fs::create_dir_all(root.join("two")).unwrap();
        let mut paths = Vec::new();
        for (dir, name, size) in [
            ("one", "b.mkv", 30),
            ("two", "a.mp4", 10),
            ("one", "c.avi", 20),
            ("two", "D.mp4", 40),
        ] {
            let path = root.join(dir).join(name);
            fs::write(&path, vec![0u8; size]).unwrap();
            paths.push(path.to_string_lossy().into_owned());
        }
        // Gone since the library was cached: no stats, so it sorts as empty.
        paths.push(
            root.join("two")
                .join("gone.mp4")
                .to_string_lossy()
                .into_owned(),
        );

        assert_eq!(sorted(&paths, 7), [3, 0, 2, 1, 4]); // size desc
        assert_eq!(sorted(&paths, 6), [4, 1, 2, 0, 3]); // size asc
        assert_eq!(sorted(&paths, 0), [1, 0, 2, 3, 4]); // name asc
        fs::remove_dir_all(&root).unwrap();
    }
}

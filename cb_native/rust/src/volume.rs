//! Volume facts and MFT enumeration for the Cleaner's leftover Deep Scan.
//!
//! [start_volume_disks] tells Dart which physical disks each drive sits on
//! (and whether they are spinning disks), so drives on different disks are
//! walked at the same time while two partitions of one disk are not: they
//! would make its heads seek back and forth.
//!
//! [start_mft_executables] lists the same runnable files as
//! `exec_walk::start_executable_walk` for a whole NTFS volume, but from the
//! Master File Table (`FSCTL_ENUM_USN_DATA`) instead of reading every
//! folder. That reads the MFT front to back, which takes seconds where a
//! folder walk seeks for minutes on a hard disk. It needs a volume handle,
//! which Windows only grants to an elevated process; anywhere else the job
//! fails at once and Dart walks the folders as before.
//!
//! Like the walk it must never see fewer files: folder names and paths are
//! skipped the same way, and every reparse point counts as incomplete. It
//! sees more (folders the walk cannot open, the contents of cloud
//! placeholder folders), which only protects more candidates. The
//! enumeration reports one name per file, so every other name of a matching
//! file (a hard link) is read back from the file. Still missed: a hard link
//! whose reported name is not runnable (`tool.dat`) but whose other name is.
//!
//! Output and counters are those of the executable walk: one string per
//! matching path; entries, directories, incomplete events, matches.

// Off Windows only the tests feed the index.
#![cfg_attr(not(windows), allow(dead_code))]

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use crate::fsx;
use crate::job::Job;
use crate::normalize::{dart_lower, dart_upper};
use crate::wire::{Reader, Writer};

const VISITED: usize = 0;
const DIRECTORIES: usize = 1;
const INCOMPLETE: usize = 2;
const MATCHES: usize = 3;

const FILE_ATTRIBUTE_DIRECTORY: u32 = 0x10;
const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;

/// MFT record 5 is the root folder of every NTFS volume.
const ROOT_RECORD: u64 = 5;
const RECORD_MASK: u64 = 0x0000_FFFF_FFFF_FFFF;

pub const SEEK_PENALTY_NO: u8 = 0;
pub const SEEK_PENALTY_YES: u8 = 1;
pub const SEEK_PENALTY_UNKNOWN: u8 = 2;

fn drive_letter(root: &str) -> Option<char> {
    let bytes = root.as_bytes();
    (bytes.len() >= 2 && bytes[1] == b':' && bytes[0].is_ascii_alphabetic())
        .then(|| bytes[0] as char)
}

/// `X:\` (or `X:`), the only roots an MFT enumeration can stand in for.
fn is_volume_root(root: &str) -> bool {
    drive_letter(root).is_some()
        && (root.len() == 2 || (root.len() == 3 && matches!(root.as_bytes()[2], b'\\' | b'/')))
}

// ---------------------------------------------------------------------------
// Physical disks per volume
// ---------------------------------------------------------------------------

/// Config: roots. Output per root, in order: seek penalty u8
/// ([SEEK_PENALTY_NO], [SEEK_PENALTY_YES], [SEEK_PENALTY_UNKNOWN]), then the
/// disk numbers it occupies (u32 count + u32s; none when unknown).
pub fn start_volume_disks(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let roots = r.strs()?;
    if !r.is_empty() {
        return None;
    }
    Some(Job::spawn(port, "cb_volume_disks", move |job| {
        let mut out = Writer::default();
        for root in &roots {
            let (seek, disks) = match drive_letter(root) {
                Some(letter) => win::volume_disks(letter),
                None => (SEEK_PENALTY_UNKNOWN, Vec::new()),
            };
            out.u8(seek);
            out.u32(disks.len() as u32);
            for disk in disks {
                out.u32(disk);
            }
        }
        job.append(&out.into_bytes());
        Ok(())
    }))
}

// ---------------------------------------------------------------------------
// Runnable files from the MFT
// ---------------------------------------------------------------------------

struct Dir {
    parent: u64,
    name: Box<str>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Reach {
    Reachable,
    /// The folder or one above it is skipped by name or path.
    Skipped,
    /// Its parent chain does not lead to the root (system metadata,
    /// records of a folder being deleted).
    Orphan,
}

/// Records of one volume, reduced to what the runnable-file answer needs:
/// every folder, entry counts per folder, matching files and reparse points.
pub(crate) struct MftIndex {
    root: String,
    extensions: HashSet<String>,
    skip_names: HashSet<String>,
    skip_paths: HashSet<String>,
    /// Folders deeper than this below the root cannot be in [skip_paths],
    /// so their paths are not built just to check.
    max_skip_depth: u32,
    dirs: HashMap<u64, Dir>,
    entries: HashMap<u64, u32>,
    files: Vec<(u64, Box<str>)>,
    /// Parent of each reparse point.
    reparse: Vec<u64>,
    pub(crate) records: u64,
}

fn is_root(id: u64) -> bool {
    id & RECORD_MASK == ROOT_RECORD
}

fn components(path: &str) -> u32 {
    path.split(['\\', '/'])
        .filter(|part| !part.is_empty())
        .count() as u32
}

impl MftIndex {
    pub(crate) fn new(
        root: String,
        extensions: &[String],
        skip_names: &[String],
        skip_paths: &[String],
    ) -> MftIndex {
        let root_upper = dart_upper(&root);
        let root_depth = components(&root);
        let skip_paths: HashSet<String> = skip_paths.iter().map(|p| dart_upper(p)).collect();
        let max_skip_depth = skip_paths
            .iter()
            .filter(|path| path.starts_with(root_upper.trim_end_matches(['\\', '/'])))
            .map(|path| components(path).saturating_sub(root_depth))
            .max()
            .unwrap_or(0);
        MftIndex {
            root,
            extensions: extensions.iter().map(|e| dart_lower(e)).collect(),
            skip_names: skip_names.iter().map(|n| dart_upper(n)).collect(),
            skip_paths,
            max_skip_depth,
            dirs: HashMap::new(),
            entries: HashMap::new(),
            files: Vec::new(),
            reparse: Vec::new(),
            records: 0,
        }
    }

    /// One MFT record: its reference number, its parent's, its attributes
    /// and its name.
    pub(crate) fn add(&mut self, id: u64, parent: u64, attributes: u32, name: &str) {
        self.records += 1;
        if is_root(id) {
            return;
        }
        *self.entries.entry(parent).or_insert(0) += 1;
        let directory = attributes & FILE_ATTRIBUTE_DIRECTORY != 0;
        if attributes & FILE_ATTRIBUTE_REPARSE_POINT != 0 {
            // The walk lists it as a Link: not entered, not evidence, and
            // the volume cannot be called fully checked.
            self.reparse.push(parent);
            if !directory {
                return;
            }
            // A junction or mount point has no records below it here; a
            // cloud folder does, and seeing them only protects more.
        }
        if directory {
            self.dirs.insert(
                id,
                Dir {
                    parent,
                    name: name.into(),
                },
            );
        } else if self
            .extensions
            .contains(&dart_lower(fsx::path_extension(name)))
        {
            self.files.push((parent, name.into()));
        }
    }

    fn path(&self, id: u64, paths: &mut HashMap<u64, String>) -> String {
        if is_root(id) {
            return self.root.clone();
        }
        if let Some(path) = paths.get(&id) {
            return path.clone();
        }
        let mut chain = Vec::new();
        let mut current = id;
        let mut base = loop {
            if is_root(current) {
                break self.root.clone();
            }
            if let Some(path) = paths.get(&current) {
                break path.clone();
            }
            // Only called for reachable folders, whose chain ends at the
            // root; the bound guards against a corrupt cycle all the same.
            let Some(dir) = self.dirs.get(&current) else {
                break self.root.clone();
            };
            if chain.len() > 4096 {
                break self.root.clone();
            }
            chain.push(current);
            current = dir.parent;
        };
        for &dir_id in chain.iter().rev() {
            base = fsx::join(&base, &self.dirs[&dir_id].name);
            paths.insert(dir_id, base.clone());
        }
        base
    }

    fn reach(
        &self,
        id: u64,
        memo: &mut HashMap<u64, (Reach, u32)>,
        paths: &mut HashMap<u64, String>,
    ) -> Reach {
        let mut chain = Vec::new();
        let mut current = id;
        let (mut state, mut depth) = loop {
            if is_root(current) {
                break (Reach::Reachable, 0);
            }
            if let Some(&known) = memo.get(&current) {
                break known;
            }
            match self.dirs.get(&current) {
                Some(dir) if chain.len() <= 4096 => {
                    chain.push(current);
                    current = dir.parent;
                }
                _ => break (Reach::Orphan, 0),
            }
        };
        for &dir_id in chain.iter().rev() {
            if state == Reach::Reachable {
                depth += 1;
                let name = &self.dirs[&dir_id].name;
                if self.skip_names.contains(&dart_upper(name))
                    || (depth <= self.max_skip_depth
                        && self
                            .skip_paths
                            .contains(&dart_upper(&self.path(dir_id, paths))))
                {
                    state = Reach::Skipped;
                }
            }
            memo.insert(dir_id, (state, depth));
        }
        state
    }

    /// Whether another name of a matched file (a hard link) is one the walk
    /// would list: a runnable extension, outside skipped folders.
    fn accepts(&self, path: &str) -> bool {
        let upper = dart_upper(path);
        let name = upper.rsplit(['\\', '/']).next().unwrap_or("");
        if !self
            .extensions
            .contains(&dart_lower(fsx::path_extension(name)))
        {
            return false;
        }
        let parent = &upper[..upper.len() - name.len()];
        if parent
            .split(['\\', '/'])
            .any(|part| self.skip_names.contains(part))
        {
            return false;
        }
        !self.skip_paths.iter().any(|skip| {
            upper.len() > skip.len()
                && upper.starts_with(skip.as_str())
                && matches!(upper.as_bytes()[skip.len()], b'\\' | b'/')
        })
    }

    /// Resolves every folder against the root and the skip rules, sets the
    /// job's counters and returns the matching paths.
    pub(crate) fn finish(&self, job: &Job) -> Vec<String> {
        let mut memo = HashMap::with_capacity(self.dirs.len());
        let mut paths = HashMap::new();
        let mut visited = 0u64;
        for (&parent, &count) in &self.entries {
            if self.reach(parent, &mut memo, &mut paths) == Reach::Reachable {
                visited += u64::from(count);
            }
        }
        let directories = 1 + self
            .dirs
            .keys()
            .filter(|&&id| self.reach(id, &mut memo, &mut paths) == Reach::Reachable)
            .count() as u64;
        let incomplete = self
            .reparse
            .iter()
            .filter(|&&parent| self.reach(parent, &mut memo, &mut paths) == Reach::Reachable)
            .count() as u64;
        let mut matches = Vec::new();
        for (parent, name) in &self.files {
            if self.reach(*parent, &mut memo, &mut paths) == Reach::Reachable {
                matches.push(fsx::join(&self.path(*parent, &mut paths), name));
            }
        }
        job.set_counter(VISITED, visited);
        job.set_counter(DIRECTORIES, directories);
        job.set_counter(INCOMPLETE, incomplete);
        job.set_counter(MATCHES, matches.len() as u64);
        matches
    }
}

/// Config: volume root (`X:\`), extensions (lower-case, with the dot),
/// folder names to skip, full folder paths to skip. Fails (so Dart walks the
/// folders) when the process may not open the volume or it is not NTFS.
pub fn start_mft_executables(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let root = r.str()?;
    let extensions = r.strs()?;
    let skip_names = r.strs()?;
    let skip_paths = r.strs()?;
    if !r.is_empty() || !is_volume_root(&root) {
        return None;
    }
    let letter = drive_letter(&root)?;
    let root = format!("{letter}:\\");
    Some(Job::spawn(port, "cb_mft_executables", move |job| {
        job.set_current(&root);
        let mut index = MftIndex::new(root.clone(), &extensions, &skip_names, &skip_paths);
        if !win::enumerate_mft(job, letter, &mut index)? {
            return Ok(()); // cancelled
        }
        // The MFT reports one name per file. A hard-linked program has its
        // other names (the walk lists each) read back from the file itself.
        let mut seen = HashSet::new();
        let mut out = Writer::default();
        let mut count = 0u64;
        for path in index.finish(job) {
            for name in std::iter::once(path.clone()).chain(win::link_names(letter, &path)) {
                if (name == path || index.accepts(&name)) && seen.insert(dart_upper(&name)) {
                    out.str(&name);
                    count += 1;
                }
            }
        }
        job.set_counter(MATCHES, count);
        job.append(&out.into_bytes());
        Ok(())
    }))
}

// ---------------------------------------------------------------------------
// Win32
// ---------------------------------------------------------------------------

#[cfg(not(windows))]
mod win {
    use super::*;

    pub fn volume_disks(_: char) -> (u8, Vec<u32>) {
        (SEEK_PENALTY_UNKNOWN, Vec::new())
    }

    pub fn enumerate_mft(_: &Job, _: char, _: &mut MftIndex) -> Result<bool, String> {
        Err("the MFT is only readable on Windows".into())
    }

    pub fn link_names(_: char, _: &str) -> Vec<String> {
        Vec::new()
    }
}

#[cfg(windows)]
mod win {
    use super::*;
    use std::io;
    use std::ptr;
    use windows_sys::Win32::Foundation::{
        CloseHandle, ERROR_HANDLE_EOF, HANDLE, INVALID_HANDLE_VALUE,
    };
    use windows_sys::Win32::Storage::FileSystem::{
        CreateFileW, GetVolumeInformationByHandleW, FILE_SHARE_DELETE, FILE_SHARE_READ,
        FILE_SHARE_WRITE, IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS, OPEN_EXISTING,
    };
    use windows_sys::Win32::System::Ioctl::{FSCTL_ENUM_USN_DATA, IOCTL_STORAGE_QUERY_PROPERTY};
    use windows_sys::Win32::System::IO::DeviceIoControl;

    const GENERIC_READ: u32 = 0x8000_0000;
    /// STORAGE_PROPERTY_ID::StorageDeviceSeekPenaltyProperty.
    const SEEK_PENALTY_PROPERTY: u32 = 7;

    struct Volume(HANDLE);

    impl Drop for Volume {
        fn drop(&mut self) {
            unsafe {
                CloseHandle(self.0);
            }
        }
    }

    impl Volume {
        /// `\\.\X:`. Access 0 is enough for the disk queries and needs no
        /// privilege; reading the MFT needs GENERIC_READ, which does.
        fn open(letter: char, access: u32) -> io::Result<Volume> {
            let wide: Vec<u16> = format!(r"\\.\{letter}:")
                .encode_utf16()
                .chain(Some(0))
                .collect();
            let handle = unsafe {
                CreateFileW(
                    wide.as_ptr(),
                    access,
                    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                    ptr::null(),
                    OPEN_EXISTING,
                    0,
                    ptr::null_mut(),
                )
            };
            if handle == INVALID_HANDLE_VALUE {
                return Err(io::Error::last_os_error());
            }
            Ok(Volume(handle))
        }

        /// Output buffers are u64s so the records in them are aligned.
        fn control(&self, code: u32, input: &[u8], output: &mut [u64]) -> io::Result<usize> {
            let mut returned = 0u32;
            let ok = unsafe {
                DeviceIoControl(
                    self.0,
                    code,
                    input.as_ptr().cast(),
                    input.len() as u32,
                    output.as_mut_ptr().cast(),
                    (output.len() * 8) as u32,
                    &mut returned,
                    ptr::null_mut(),
                )
            };
            if ok == 0 {
                return Err(io::Error::last_os_error());
            }
            Ok(returned as usize)
        }

        fn file_system(&self) -> Option<String> {
            let mut name = [0u16; 64];
            let ok = unsafe {
                GetVolumeInformationByHandleW(
                    self.0,
                    ptr::null_mut(),
                    0,
                    ptr::null_mut(),
                    ptr::null_mut(),
                    ptr::null_mut(),
                    name.as_mut_ptr(),
                    name.len() as u32,
                )
            };
            if ok == 0 {
                return None;
            }
            let len = name.iter().position(|&c| c == 0).unwrap_or(name.len());
            Some(String::from_utf16_lossy(&name[..len]))
        }
    }

    fn bytes(buffer: &[u64], len: usize) -> &[u8] {
        unsafe { std::slice::from_raw_parts(buffer.as_ptr().cast::<u8>(), len) }
    }

    fn u32_at(b: &[u8], at: usize) -> u32 {
        u32::from_le_bytes(b[at..at + 4].try_into().unwrap())
    }

    fn u16_at(b: &[u8], at: usize) -> usize {
        u16::from_le_bytes(b[at..at + 2].try_into().unwrap()) as usize
    }

    fn u64_at(b: &[u8], at: usize) -> u64 {
        u64::from_le_bytes(b[at..at + 8].try_into().unwrap())
    }

    pub fn volume_disks(letter: char) -> (u8, Vec<u32>) {
        let Ok(volume) = Volume::open(letter, 0) else {
            return (SEEK_PENALTY_UNKNOWN, Vec::new());
        };
        // VOLUME_DISK_EXTENTS: count u32 (+4), then 24-byte DISK_EXTENTs
        // starting with the disk number. 4 KiB holds 170 extents.
        let mut buffer = vec![0u64; 512];
        let mut disks = Vec::new();
        if let Ok(len) = volume.control(IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS, &[], &mut buffer) {
            let b = bytes(&buffer, len);
            if len >= 8 {
                let count = u32_at(b, 0) as usize;
                for i in 0..count {
                    let at = 8 + i * 24;
                    if at + 24 > len {
                        break;
                    }
                    let disk = u32_at(b, at);
                    if !disks.contains(&disk) {
                        disks.push(disk);
                    }
                }
            }
        }
        // STORAGE_PROPERTY_QUERY { PropertyId, PropertyStandardQuery, [0] }
        // -> DEVICE_SEEK_PENALTY_DESCRIPTOR { Version, Size, IncursSeekPenalty }.
        let mut query = [0u8; 12];
        query[..4].copy_from_slice(&SEEK_PENALTY_PROPERTY.to_le_bytes());
        let mut answer = [0u64; 2];
        let seek = match volume.control(IOCTL_STORAGE_QUERY_PROPERTY, &query, &mut answer) {
            Ok(len) if len >= 9 => {
                if bytes(&answer, len)[8] != 0 {
                    SEEK_PENALTY_YES
                } else {
                    SEEK_PENALTY_NO
                }
            }
            _ => SEEK_PENALTY_UNKNOWN,
        };
        (seek, disks)
    }

    /// Every name of the file at [path] (itself included) as full paths on
    /// drive [letter]; empty when they cannot be read.
    pub fn link_names(letter: char, path: &str) -> Vec<String> {
        use windows_sys::Win32::Storage::FileSystem::{
            FindClose, FindFirstFileNameW, FindNextFileNameW,
        };
        let wide: Vec<u16> = path.encode_utf16().chain(Some(0)).collect();
        let mut buffer = vec![0u16; 32_768];
        let mut names = Vec::new();
        let mut len = buffer.len() as u32;
        let find = unsafe { FindFirstFileNameW(wide.as_ptr(), 0, &mut len, buffer.as_mut_ptr()) };
        if find == INVALID_HANDLE_VALUE {
            return names;
        }
        loop {
            // Volume-relative, like `\dir\name.exe`, null-terminated.
            let end = buffer[..(len as usize).min(buffer.len())]
                .iter()
                .position(|&c| c == 0)
                .unwrap_or(len as usize);
            names.push(format!(
                "{letter}:{}",
                String::from_utf16_lossy(&buffer[..end])
            ));
            len = buffer.len() as u32;
            if unsafe { FindNextFileNameW(find, &mut len, buffer.as_mut_ptr()) } == 0 {
                break;
            }
        }
        unsafe {
            FindClose(find);
        }
        names
    }

    /// Feeds every MFT record of the volume to [index]. False when the job
    /// was cancelled part-way.
    pub fn enumerate_mft(job: &Job, letter: char, index: &mut MftIndex) -> Result<bool, String> {
        let volume = Volume::open(letter, GENERIC_READ)
            .map_err(|error| format!("cannot open volume {letter}: ({error})"))?;
        match volume.file_system() {
            Some(name) if name.eq_ignore_ascii_case("NTFS") => {}
            other => return Err(format!("not NTFS: {other:?}")),
        }
        // MFT_ENUM_DATA_V0 { StartFileReferenceNumber, LowUsn, HighUsn }:
        // every record, returned as USN_RECORD_V2.
        let mut input = [0u8; 24];
        input[16..24].copy_from_slice(&i64::MAX.to_le_bytes());
        let mut buffer = vec![0u64; 1024 * 1024 / 8];
        let mut name = Vec::<u16>::with_capacity(260);
        loop {
            if job.cancelled() {
                return Ok(false);
            }
            let len = match volume.control(FSCTL_ENUM_USN_DATA, &input, &mut buffer) {
                Ok(len) => len,
                Err(error) if error.raw_os_error() == Some(ERROR_HANDLE_EOF as i32) => break,
                Err(error) => return Err(format!("cannot enumerate the MFT: {error}")),
            };
            if len <= 8 {
                break;
            }
            let b = bytes(&buffer, len);
            let next = u64_at(b, 0);
            let mut at = 8;
            while at + 8 <= len {
                let record_len = u32_at(b, at) as usize;
                if record_len < 60 || at + record_len > len {
                    return Err("invalid USN record".into());
                }
                let r = &b[at..at + record_len];
                // V3 carries 128-bit IDs; NTFS ones fit in the low half.
                let (id, parent, attributes, name_len, name_at) = match u16_at(r, 4) {
                    2 => (
                        u64_at(r, 8),
                        u64_at(r, 16),
                        u32_at(r, 52),
                        u16_at(r, 56),
                        u16_at(r, 58),
                    ),
                    3 if record_len >= 76 => (
                        u64_at(r, 8),
                        u64_at(r, 24),
                        u32_at(r, 68),
                        u16_at(r, 72),
                        u16_at(r, 74),
                    ),
                    _ => return Err("unsupported USN record".into()),
                };
                if name_at + name_len > record_len {
                    return Err("invalid USN record name".into());
                }
                name.clear();
                name.extend(
                    r[name_at..name_at + name_len]
                        .chunks_exact(2)
                        .map(|c| u16::from_le_bytes([c[0], c[1]])),
                );
                index.add(id, parent, attributes, &String::from_utf16_lossy(&name));
                at += record_len;
            }
            job.set_counter(VISITED, index.records);
            if next == u64_at(&input, 0) {
                break;
            }
            input[..8].copy_from_slice(&next.to_le_bytes());
        }
        Ok(true)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(windows)]
    use crate::job::JOB_DONE;

    const ROOT: u64 = (5 << 48) | ROOT_RECORD;
    const DIR: u32 = FILE_ATTRIBUTE_DIRECTORY;
    const LINK: u32 = FILE_ATTRIBUTE_REPARSE_POINT;

    fn sorted(mut paths: Vec<String>) -> Vec<String> {
        paths.sort();
        paths
    }

    #[test]
    fn resolves_paths_and_skips_like_the_walk() {
        let root = if cfg!(windows) { "C:\\" } else { "/" };
        let sep = if cfg!(windows) { "\\" } else { "/" };
        let windows = format!("{root}windows");
        let mut index = MftIndex::new(
            root.into(),
            &[".exe".into(), ".cmd".into()],
            &["$recycle.bin".into()],
            &[windows],
        );
        // The root itself and records out of order (child before parent).
        index.add(ROOT, ROOT, DIR, ".");
        index.add(30, 20, 0, "Tool.EXE");
        index.add(20, ROOT, DIR, "Apps");
        index.add(31, 20, 0, "readme.txt");
        index.add(32, ROOT, 0, "top.cmd");
        // Skipped by path (case-insensitive) and by name, at any depth.
        index.add(40, ROOT, DIR, "Windows");
        index.add(41, 40, 0, "explorer.exe");
        index.add(42, 20, DIR, "$Recycle.Bin");
        index.add(43, 42, 0, "old.exe");
        // A junction and a symlinked exe: incomplete, never evidence.
        index.add(50, 20, DIR | LINK, "Linked");
        index.add(51, 20, LINK, "shim.exe");
        // Below a skipped folder, a reparse point does not count.
        index.add(52, 40, DIR | LINK, "inside");
        // A record whose parent is not on the volume.
        index.add(60, 999, 0, "lost.exe");

        let job = Job::new(0);
        let paths = sorted(index.finish(&job));
        assert_eq!(
            paths,
            [format!("{root}Apps{sep}Tool.EXE"), format!("{root}top.cmd"),]
        );
        let (counters, _) = job.progress();
        // root: Apps top.cmd Windows (3); Apps: Tool readme $Recycle.Bin
        // Linked shim.exe (5).
        assert_eq!(counters[VISITED], 8);
        // root, Apps, and the junction (empty here: its target is elsewhere).
        assert_eq!(counters[DIRECTORIES], 3);
        assert_eq!(counters[INCOMPLETE], 2);
        assert_eq!(counters[MATCHES], 2);
    }

    #[test]
    fn other_link_names_follow_the_walk_rules() {
        let index = MftIndex::new(
            "C:\\".into(),
            &[".exe".into()],
            &["$recycle.bin".into()],
            &[r"C:\Windows".into()],
        );
        assert!(index.accepts(r"C:\Tools\Git\git.EXE"));
        assert!(!index.accepts(r"C:\Tools\Git\git.dll"));
        assert!(!index.accepts(r"C:\$Recycle.Bin\S-1\old.exe"));
        assert!(!index.accepts(r"C:\Windows\System32\cmd.exe"));
        assert!(index.accepts(r"C:\WindowsApps2\tool.exe"));
    }

    #[test]
    fn only_volume_roots_are_accepted() {
        assert!(is_volume_root("C:\\"));
        assert!(is_volume_root("d:"));
        assert!(!is_volume_root("C:\\Users"));
        assert!(!is_volume_root("\\\\server\\share"));
        let mut config = Writer::default();
        config.str("C:\\Users");
        config.u32(0);
        config.u32(0);
        config.u32(0);
        assert!(start_mft_executables(0, &config.into_bytes()).is_none());
    }

    #[cfg(windows)]
    #[test]
    fn system_drive_reports_its_disk() {
        let drive = std::env::var("SystemDrive").unwrap_or_else(|_| "C:".into());
        let mut config = Writer::default();
        config.u32(2);
        config.str(&format!("{drive}\\"));
        config.str("not a drive");
        let job = start_volume_disks(0, &config.into_bytes()).unwrap();
        let (state, out) = crate::job::testing::wait(&job);
        assert_eq!(state, JOB_DONE);
        let mut r = Reader::new(&out);
        assert!(r.u8().unwrap() <= SEEK_PENALTY_UNKNOWN);
        assert!(r.u32().unwrap() >= 1, "no disk for {drive}");
        r.u32().unwrap();
        assert_eq!(r.u8().unwrap(), SEEK_PENALTY_UNKNOWN);
        assert_eq!(r.u32().unwrap(), 0);
        assert!(r.is_empty());
    }

    /// Elevated only: the MFT answer against the folder walk for one volume.
    /// `CB_MFT_ROOT=C:\ cargo test --release mft_matches_the_walk -- --ignored --nocapture`
    #[cfg(windows)]
    #[test]
    #[ignore]
    fn mft_matches_the_walk() {
        let root = std::env::var("CB_MFT_ROOT").unwrap_or_else(|_| "C:\\".into());
        let windows = std::env::var("SystemRoot").unwrap_or_else(|_| "C:\\Windows".into());
        let exts = [".exe", ".com", ".cmd", ".bat"];
        let skip = [
            "$RECYCLE.BIN",
            "SYSTEM VOLUME INFORMATION",
            "$WINDOWS.~BT",
            "$WINDOWS.~WS",
            "$WINREAGENT",
            "WINDOWS.OLD",
        ];
        let lists = |w: &mut Writer| {
            w.u32(exts.len() as u32);
            exts.iter().for_each(|e| w.str(e));
            w.u32(skip.len() as u32);
            skip.iter().for_each(|s| w.str(s));
            w.u32(1);
            w.str(&windows);
        };
        let read = |out: &[u8]| -> HashSet<String> {
            let mut r = Reader::new(out);
            let mut set = HashSet::new();
            while !r.is_empty() {
                set.insert(dart_upper(&r.str().unwrap()));
            }
            set
        };

        let started = std::time::Instant::now();
        let mut config = Writer::default();
        config.str(&root);
        lists(&mut config);
        let job = start_mft_executables(0, &config.into_bytes()).unwrap();
        let (state, out) = crate::job::testing::wait(&job);
        assert_eq!(state, JOB_DONE, "MFT job failed: {}", job.error());
        let mft = read(&out);
        let mft_counters = job.progress().0;
        let mft_time = started.elapsed();

        let started = std::time::Instant::now();
        let mut config = Writer::default();
        config.str(&root);
        config.u8(1);
        config.u64(0);
        lists(&mut config);
        let job = crate::exec_walk::start_executable_walk(0, &config.into_bytes()).unwrap();
        let (state, out) = crate::job::testing::wait(&job);
        assert_eq!(state, JOB_DONE);
        let walk = read(&out);
        let walk_counters = job.progress().0;
        let walk_time = started.elapsed();

        let missing: Vec<_> = walk.difference(&mft).collect();
        let extra = mft.difference(&walk).count();
        println!(
            "{root}: MFT {:.1?} {} matches {:?}; walk {:.1?} {} matches {:?}; \
             {extra} only in MFT; {} only in the walk",
            mft_time,
            mft.len(),
            mft_counters,
            walk_time,
            walk.len(),
            walk_counters,
            missing.len(),
        );
        for path in missing.iter().take(50) {
            println!("  only in the walk: {path}");
        }
        assert!(missing.is_empty());
    }
}

//! C ABI for `package:cb_native` (see ../lib/src/bindings.dart).
//!
//! Strings cross the boundary as UTF-8 pointer + length. Buffers returned to
//! Dart are boxed byte slices that Dart must hand back to `cb_buffer_free`.
//!
//! # Safety
//!
//! For every export: each `(ptr, len)` pair is null with `len == 0` or points
//! to `len` readable bytes, out-pointers are valid for one write, and a
//! search, disk-scan or job handle is one returned by its start function that
//! has not been passed to its `*_free` yet. A buffer given to `cb_job_start`
//! comes from `cb_buffer_alloc` and is owned by Rust from then on.
//! `package:cb_native` upholds this for all callers.
#![allow(clippy::missing_safety_doc)]

mod archive;
mod dart_api;
mod disk_scan;
mod fold_table;
mod fsx;
mod glob;
mod hashing;
mod imaging;
mod job;
mod listing;
mod normalize;
mod search;
mod walk;
#[cfg(windows)]
mod win_dir;
mod wire;

use std::ffi::c_void;
use std::path::PathBuf;
use std::sync::Arc;

use disk_scan::{Config, DiskScan};
use job::Job;
use search::{Matcher, Search};

/// Bumped whenever an exported signature changes; Dart refuses a mismatch.
const ABI_VERSION: u32 = 3;

pub const STATUS_OK: i32 = 0;
pub const STATUS_INVALID_ARGUMENT: i32 = 1;
pub const STATUS_INVALID_REGEX: i32 = 2;

/// `cb_job_start` kinds; mirrored in package:cb_native's bindings.dart.
const JOB_DIR_SIZE: u32 = 1;
const JOB_WALK: u32 = 2;
const JOB_JUNK_SCAN: u32 = 3;
const JOB_LIST_DIR: u32 = 4;
const JOB_THUMBNAIL: u32 = 5;
const JOB_ENCODE_IMAGE: u32 = 6;
const JOB_INPAINT: u32 = 7;
const JOB_HASH_FILE: u32 = 8;
const JOB_ARCHIVE_LIST: u32 = 9;
const JOB_ARCHIVE_EXTRACT: u32 = 10;

unsafe fn str_arg<'a>(ptr: *const u8, len: usize) -> Option<&'a str> {
    if len == 0 {
        return Some("");
    }
    if ptr.is_null() {
        return None;
    }
    std::str::from_utf8(std::slice::from_raw_parts(ptr, len)).ok()
}

fn into_buffer(bytes: Vec<u8>, out_ptr: *mut *mut u8, out_len: *mut usize) {
    if out_ptr.is_null() || out_len.is_null() {
        return;
    }
    let len = bytes.len();
    let ptr = if len == 0 {
        std::ptr::null_mut()
    } else {
        Box::into_raw(bytes.into_boxed_slice()) as *mut u8
    };
    unsafe {
        *out_ptr = ptr;
        *out_len = len;
    }
}

#[no_mangle]
pub extern "C" fn cb_native_abi_version() -> u32 {
    ABI_VERSION
}

/// Frees a buffer returned by this library.
#[no_mangle]
pub unsafe extern "C" fn cb_buffer_free(ptr: *mut u8, len: usize) {
    if !ptr.is_null() && len > 0 {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)));
    }
}

/// `TextUtils.searchKey` computed natively; used by the parity tests.
#[no_mangle]
pub unsafe extern "C" fn cb_search_key(
    ptr: *const u8,
    len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    let Some(value) = str_arg(ptr, len) else {
        return STATUS_INVALID_ARGUMENT;
    };
    into_buffer(normalize::search_key(value).into_bytes(), out_ptr, out_len);
    STATUS_OK
}

/// Starts a recursive search under `root`.
///
/// Without a regex, `words` holds the query's search-key words separated by
/// NUL bytes, and a name matches when its search key contains all of them.
/// With `regex_len > 0` the pattern is matched case-insensitively against the
/// raw name instead. On success `*out_handle` must later be passed to
/// `cb_search_free`.
#[no_mangle]
pub unsafe extern "C" fn cb_search_start(
    root_ptr: *const u8,
    root_len: usize,
    words_ptr: *const u8,
    words_len: usize,
    regex_ptr: *const u8,
    regex_len: usize,
    out_handle: *mut *const Search,
) -> i32 {
    if out_handle.is_null() {
        return STATUS_INVALID_ARGUMENT;
    }
    let (Some(root), Some(words), Some(regex)) = (
        str_arg(root_ptr, root_len),
        str_arg(words_ptr, words_len),
        str_arg(regex_ptr, regex_len),
    ) else {
        return STATUS_INVALID_ARGUMENT;
    };
    if root.is_empty() {
        return STATUS_INVALID_ARGUMENT;
    }

    let matcher = if regex.is_empty() {
        Matcher::Words(
            words
                .split('\0')
                .filter(|word| !word.is_empty())
                .map(str::to_string)
                .collect(),
        )
    } else {
        match Matcher::regex(regex) {
            Some(matcher) => matcher,
            None => return STATUS_INVALID_REGEX,
        }
    };

    *out_handle = Arc::into_raw(Search::start(PathBuf::from(root), matcher));
    STATUS_OK
}

/// Moves the matches found so far into a new buffer of
/// `[kind u8][utf-8 path][0]` records. Returns 1 once the walk is over and the
/// returned batch is the last one, otherwise 0.
#[no_mangle]
pub unsafe extern "C" fn cb_search_poll(
    handle: *const Search,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if handle.is_null() {
        into_buffer(Vec::new(), out_ptr, out_len);
        return 1;
    }
    let (batch, finished) = (*handle).take_results();
    into_buffer(batch, out_ptr, out_len);
    i32::from(finished)
}

/// Asks the workers to stop; they exit after the entry they are on.
#[no_mangle]
pub unsafe extern "C" fn cb_search_cancel(handle: *const Search) {
    if !handle.is_null() {
        (*handle).cancel();
    }
}

/// Cancels the search and releases Dart's reference. Workers still running
/// hold their own references and free the rest when they exit, so this never
/// waits on the filesystem.
#[no_mangle]
pub unsafe extern "C" fn cb_search_free(handle: *const Search) {
    if !handle.is_null() {
        let search = Arc::from_raw(handle);
        search.cancel();
        drop(search);
    }
}

/// Starts a disk scan described by the encoded config (see `disk_scan::Config`).
#[no_mangle]
pub unsafe extern "C" fn cb_disk_scan_start(
    config_ptr: *const u8,
    config_len: usize,
    out_handle: *mut *const DiskScan,
) -> i32 {
    if out_handle.is_null() || config_ptr.is_null() {
        return STATUS_INVALID_ARGUMENT;
    }
    let bytes = std::slice::from_raw_parts(config_ptr, config_len);
    let Some(config) = Config::decode(bytes) else {
        return STATUS_INVALID_ARGUMENT;
    };
    *out_handle = Arc::into_raw(DiskScan::start(config));
    STATUS_OK
}

/// Moves finished directory records into a new buffer. Returns 1 once the scan
/// is over and the returned batch is the last one, otherwise 0.
#[no_mangle]
pub unsafe extern "C" fn cb_disk_scan_poll(
    handle: *const DiskScan,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if handle.is_null() {
        into_buffer(Vec::new(), out_ptr, out_len);
        return 1;
    }
    let (batch, finished) = (*handle).take_records();
    into_buffer(batch, out_ptr, out_len);
    i32::from(finished)
}

/// Writes the running totals; the current path goes into a new buffer.
#[no_mangle]
pub unsafe extern "C" fn cb_disk_scan_progress(
    handle: *const DiskScan,
    out_counts: *mut u64,
    out_path_ptr: *mut *mut u8,
    out_path_len: *mut usize,
) {
    if handle.is_null() || out_counts.is_null() {
        return;
    }
    let progress = (*handle).progress();
    *out_counts = progress.dirs;
    *out_counts.add(1) = progress.files;
    *out_counts.add(2) = progress.bytes;
    into_buffer(
        progress.current_path.into_bytes(),
        out_path_ptr,
        out_path_len,
    );
}

#[no_mangle]
pub unsafe extern "C" fn cb_disk_scan_cancel(handle: *const DiskScan) {
    if !handle.is_null() {
        (*handle).cancel();
    }
}

/// Cancels the scan and releases Dart's reference without waiting on workers.
#[no_mangle]
pub unsafe extern "C" fn cb_disk_scan_free(handle: *const DiskScan) {
    if !handle.is_null() {
        let scan = Arc::from_raw(handle);
        scan.cancel();
        drop(scan);
    }
}

/// Lets jobs post their completion to a Dart port. `data` is
/// `NativeApi.initializeApiDLData`. Returns 1 when posting is available.
#[no_mangle]
pub unsafe extern "C" fn cb_native_init_dart_api(data: *mut c_void) -> i32 {
    i32::from(dart_api::init(data))
}

/// A zeroed buffer for Dart to fill with a job config. Pass it to
/// `cb_job_start` (which takes ownership) or free it with `cb_buffer_free`.
#[no_mangle]
pub extern "C" fn cb_buffer_alloc(len: usize) -> *mut u8 {
    if len == 0 {
        return std::ptr::null_mut();
    }
    Box::into_raw(vec![0u8; len].into_boxed_slice()) as *mut u8
}

unsafe fn take_alloc(ptr: *mut u8, len: usize) -> Vec<u8> {
    if ptr.is_null() || len == 0 {
        return Vec::new();
    }
    Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)).into_vec()
}

/// Starts a job of `kind` from a `cb_buffer_alloc` config, which this call
/// always consumes. With `port != 0` the job posts its final state there.
#[no_mangle]
pub unsafe extern "C" fn cb_job_start(
    kind: u32,
    config_ptr: *mut u8,
    config_len: usize,
    port: i64,
    out_handle: *mut *const Job,
) -> i32 {
    let config = take_alloc(config_ptr, config_len);
    if out_handle.is_null() {
        return STATUS_INVALID_ARGUMENT;
    }
    let job = match kind {
        JOB_DIR_SIZE => walk::start_dir_size(port, &config),
        JOB_WALK => match walk::start_walk(port, &config) {
            walk::WalkStart::Started(job) => Some(job),
            walk::WalkStart::InvalidRegex => return STATUS_INVALID_REGEX,
            walk::WalkStart::InvalidConfig => None,
        },
        JOB_JUNK_SCAN => walk::start_junk_scan(port, &config),
        JOB_LIST_DIR => listing::start_list_dir(port, &config),
        JOB_THUMBNAIL => imaging::start_thumbnail(port, &config),
        JOB_ENCODE_IMAGE => imaging::start_encode(port, config),
        JOB_INPAINT => imaging::start_inpaint(port, config),
        JOB_HASH_FILE => hashing::start_hash_file(port, &config),
        JOB_ARCHIVE_LIST => archive::start_list(port, &config),
        JOB_ARCHIVE_EXTRACT => archive::start_extract(port, &config),
        _ => None,
    };
    match job {
        Some(job) => {
            *out_handle = Arc::into_raw(job);
            STATUS_OK
        }
        None => STATUS_INVALID_ARGUMENT,
    }
}

/// Moves the job's new output into a buffer and returns its state:
/// 0 running, 1 done, 2 failed, 3 cancelled. The state is read before the
/// output, so the batch returned with a final state is the last one.
#[no_mangle]
pub unsafe extern "C" fn cb_job_poll(
    handle: *const Job,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if handle.is_null() {
        into_buffer(Vec::new(), out_ptr, out_len);
        return job::JOB_CANCELLED;
    }
    let (state, output) = (*handle).poll();
    into_buffer(output, out_ptr, out_len);
    state
}

/// The failure message of a failed job.
#[no_mangle]
pub unsafe extern "C" fn cb_job_error(
    handle: *const Job,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) {
    let message = if handle.is_null() {
        String::new()
    } else {
        (*handle).error()
    };
    into_buffer(message.into_bytes(), out_ptr, out_len);
}

/// Writes the four progress counters; the current path goes into a buffer.
#[no_mangle]
pub unsafe extern "C" fn cb_job_progress(
    handle: *const Job,
    out_counts: *mut u64,
    out_path_ptr: *mut *mut u8,
    out_path_len: *mut usize,
) {
    if handle.is_null() || out_counts.is_null() {
        return;
    }
    let (counts, path) = (*handle).progress();
    for (i, count) in counts.iter().enumerate() {
        *out_counts.add(i) = *count;
    }
    into_buffer(path.into_bytes(), out_path_ptr, out_path_len);
}

#[no_mangle]
pub unsafe extern "C" fn cb_job_cancel(handle: *const Job) {
    if !handle.is_null() {
        (*handle).cancel();
    }
}

/// Cancels the job and releases Dart's reference without waiting for it.
#[no_mangle]
pub unsafe extern "C" fn cb_job_free(handle: *const c_void) {
    if !handle.is_null() {
        let job = Arc::from_raw(handle as *const Job);
        job.cancel();
        drop(job);
    }
}

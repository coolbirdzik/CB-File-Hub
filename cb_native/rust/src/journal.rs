//! NTFS journal refresh: parse and deduplicate parent IDs before crossing FFI.
#[cfg(windows)]
use crate::wire::Writer;
use crate::{job::Job, wire::Reader};
use std::sync::Arc;

pub fn start(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let drive = r.str()?;
    let id = r.u64()?;
    let previous = r.i64()?;
    if !r.is_empty() {
        return None;
    }
    Some(Job::spawn(port, "cb_usn_parents", move |job| {
        read(job, &drive, id, previous)
    }))
}

#[cfg(not(windows))]
fn read(_: &Job, _: &str, _: u64, _: i64) -> Result<(), String> {
    Err("USN Journal is only available on Windows".into())
}

#[cfg(windows)]
fn read(job: &Job, drive: &str, id: u64, previous: i64) -> Result<(), String> {
    use std::{collections::BTreeSet, ptr};
    use windows_sys::Win32::{
        Foundation::{CloseHandle, ERROR_HANDLE_EOF, INVALID_HANDLE_VALUE},
        Storage::FileSystem::{
            CreateFileW, FILE_SHARE_DELETE, FILE_SHARE_READ, FILE_SHARE_WRITE, OPEN_EXISTING,
        },
        System::{
            Ioctl::{FSCTL_QUERY_USN_JOURNAL, FSCTL_READ_USN_JOURNAL},
            IO::DeviceIoControl,
        },
    };
    let drive = drive.trim();
    if drive.len() < 2 || drive.as_bytes()[1] != b':' {
        return Err("invalid drive".into());
    }
    let wide: Vec<u16> = format!(r"\\.\{}", &drive[..2])
        .encode_utf16()
        .chain(Some(0))
        .collect();
    let handle = unsafe {
        CreateFileW(
            wide.as_ptr(),
            0x80000000,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            ptr::null(),
            OPEN_EXISTING,
            0,
            ptr::null_mut(),
        )
    };
    if handle == INVALID_HANDLE_VALUE {
        return Err(std::io::Error::last_os_error().to_string());
    }
    struct Handle(windows_sys::Win32::Foundation::HANDLE);
    impl Drop for Handle {
        fn drop(&mut self) {
            unsafe {
                CloseHandle(self.0);
            }
        }
    }
    let handle = Handle(handle);
    let mut returned = 0u32;
    let mut query = [0u64; 7];
    let ok = unsafe {
        DeviceIoControl(
            handle.0,
            FSCTL_QUERY_USN_JOURNAL,
            ptr::null(),
            0,
            query.as_mut_ptr().cast(),
            56,
            &mut returned,
            ptr::null_mut(),
        )
    };
    if ok == 0 || returned < 56 {
        return Err("cannot query USN Journal".into());
    }
    let next = query[2] as i64;
    if query[0] != id || previous < query[3] as i64 || previous > next {
        return Err("USN Journal cursor is no longer valid".into());
    }
    // READ_USN_JOURNAL_DATA_V1: explicit wire fields avoid alignment/version
    // differences between Win32 bindings. Zero timeout and bytes-to-wait.
    let mut input = [0u64; 6];
    let raw = unsafe { std::slice::from_raw_parts_mut(input.as_mut_ptr().cast::<u8>(), 48) };
    raw[8..12].copy_from_slice(&u32::MAX.to_le_bytes());
    raw[32..40].copy_from_slice(&id.to_le_bytes());
    raw[40..42].copy_from_slice(&2u16.to_le_bytes());
    raw[42..44].copy_from_slice(&2u16.to_le_bytes());
    let mut buffer = vec![0u64; 1024 * 1024 / 8];
    let mut cursor = previous;
    let mut parents = BTreeSet::new();
    let mut count = 0;
    while cursor < next {
        if job.cancelled() {
            return Ok(());
        }
        raw[..8].copy_from_slice(&cursor.to_le_bytes());
        let ok = unsafe {
            DeviceIoControl(
                handle.0,
                FSCTL_READ_USN_JOURNAL,
                raw.as_ptr().cast(),
                48,
                buffer.as_mut_ptr().cast(),
                1024 * 1024,
                &mut returned,
                ptr::null_mut(),
            )
        };
        if ok == 0 {
            let error = std::io::Error::last_os_error();
            if error.raw_os_error() == Some(ERROR_HANDLE_EOF as i32) {
                break;
            }
            return Err(error.to_string());
        }
        if returned < 8 {
            break;
        }
        let bytes =
            unsafe { std::slice::from_raw_parts(buffer.as_ptr().cast::<u8>(), returned as usize) };
        let new_cursor = i64::from_le_bytes(bytes[..8].try_into().unwrap());
        count += append_parents(bytes, &mut parents)?;
        if count > 100_000 {
            return Err("too many journal changes require a complete scan".into());
        }
        if new_cursor <= cursor {
            break;
        }
        cursor = new_cursor;
    }
    let mut w = Writer::default();
    w.u64(id);
    w.i64(next);
    w.u32(parents.len() as u32);
    for parent in parents {
        w.u64(parent);
    }
    job.append(&w.into_bytes());
    Ok(())
}

#[cfg(any(windows, test))]
fn append_parents(
    bytes: &[u8],
    parents: &mut std::collections::BTreeSet<u64>,
) -> Result<usize, String> {
    let mut offset = 8;
    let mut count = 0;
    while offset + 60 <= bytes.len() {
        let b = &bytes[offset..];
        let len = u32::from_le_bytes(b[..4].try_into().unwrap()) as usize;
        if len < 60 || len > b.len() {
            return Err("invalid USN record length".into());
        }
        let version = u16::from_le_bytes(b[4..6].try_into().unwrap());
        let name_len = u16::from_le_bytes(b[56..58].try_into().unwrap()) as usize;
        let name_at = u16::from_le_bytes(b[58..60].try_into().unwrap()) as usize;
        if version != 2 || name_at + name_len > len {
            return Err("unsupported or invalid USN record".into());
        }
        parents.insert(u64::from_le_bytes(b[16..24].try_into().unwrap()));
        count += 1;
        offset += len;
    }
    if offset != bytes.len() {
        return Err("truncated USN record".into());
    }
    Ok(count)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn deduplicates_and_rejects_truncation() {
        let mut bytes = vec![0u8; 8];
        let mut record = [0u8; 60];
        record[..4].copy_from_slice(&60u32.to_le_bytes());
        record[4..6].copy_from_slice(&2u16.to_le_bytes());
        record[16..24].copy_from_slice(&42u64.to_le_bytes());
        bytes.extend(record);
        bytes.extend(record);
        let mut parents = Default::default();
        assert_eq!(append_parents(&bytes, &mut parents).unwrap(), 2);
        assert_eq!(parents.into_iter().collect::<Vec<_>>(), [42]);
        bytes.pop();
        assert!(append_parents(&bytes, &mut Default::default()).is_err());
    }
}

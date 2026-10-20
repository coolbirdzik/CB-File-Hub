//! Windows directory enumeration that also returns each entry's file ID.
//!
//! `GetFileInformationByHandleEx(FileIdBothDirectoryInfo)` reports the NTFS
//! file reference number with the usual name, attributes, size and times, so
//! the Disk Cleaner gets the IDs its USN Journal refresh needs without the
//! CreateFile + GetFileInformationByHandle pair per folder that made the Dart
//! scanner skip them on cold scans.

use std::ffi::c_void;
use std::io;
use std::ptr;

use windows_sys::Win32::Foundation::{
    CloseHandle, GetLastError, ERROR_NO_MORE_FILES, HANDLE, INVALID_HANDLE_VALUE,
};
use windows_sys::Win32::Storage::FileSystem::{
    CreateFileW, FileIdBothDirectoryInfo, FileIdBothDirectoryRestartInfo,
    GetFileInformationByHandleEx, FILE_FLAG_BACKUP_SEMANTICS, FILE_ID_BOTH_DIR_INFO,
    FILE_LIST_DIRECTORY, FILE_SHARE_DELETE, FILE_SHARE_READ, FILE_SHARE_WRITE, OPEN_EXISTING,
};

pub struct WinEntry {
    pub name: String,
    pub attributes: u32,
    pub size: u64,
    /// FILETIME ticks, like `MetadataExt::last_write_time`.
    pub last_write: u64,
    pub last_access: u64,
    /// The value `DiskUsnJournalReader.readFileReferenceNumber` returns.
    pub file_id: u64,
}

struct Handle(HANDLE);

impl Drop for Handle {
    fn drop(&mut self) {
        unsafe {
            CloseHandle(self.0);
        }
    }
}

/// `\\?\` form so paths past MAX_PATH open like they do through std.
fn verbatim(path: &str) -> Vec<u16> {
    let path = path.replace('/', "\\");
    let full = if path.starts_with(r"\\?\") || path.starts_with(r"\\.\") {
        path
    } else if let Some(rest) = path.strip_prefix(r"\\") {
        format!(r"\\?\UNC\{rest}")
    } else if path.len() >= 2 && path.as_bytes()[1] == b':' {
        format!(r"\\?\{path}")
    } else {
        path
    };
    full.encode_utf16().chain(std::iter::once(0)).collect()
}

pub fn read_dir_with_ids(path: &str) -> io::Result<Vec<WinEntry>> {
    let wide = verbatim(path);
    let handle = unsafe {
        CreateFileW(
            wide.as_ptr(),
            FILE_LIST_DIRECTORY,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            ptr::null(),
            OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS,
            ptr::null_mut(),
        )
    };
    if handle == INVALID_HANDLE_VALUE {
        return Err(io::Error::last_os_error());
    }
    let handle = Handle(handle);

    // u64 storage keeps the records 8-byte aligned.
    let mut buffer = vec![0u64; 64 * 1024 / 8];
    let byte_len = (buffer.len() * 8) as u32;
    let mut class = FileIdBothDirectoryRestartInfo;
    let mut entries = Vec::new();
    loop {
        let ok = unsafe {
            GetFileInformationByHandleEx(
                handle.0,
                class,
                buffer.as_mut_ptr().cast::<c_void>(),
                byte_len,
            )
        };
        class = FileIdBothDirectoryInfo;
        if ok == 0 {
            let error = unsafe { GetLastError() };
            if error == ERROR_NO_MORE_FILES {
                break;
            }
            return Err(io::Error::from_raw_os_error(error as i32));
        }
        let base = buffer.as_ptr().cast::<u8>();
        let mut offset = 0usize;
        loop {
            // SAFETY: the API fills the buffer with a chain of records, each
            // starting at an 8-aligned offset given by NextEntryOffset.
            let info = unsafe { &*base.add(offset).cast::<FILE_ID_BOTH_DIR_INFO>() };
            let name_units = info.FileNameLength as usize / 2;
            let name_ptr = ptr::addr_of!(info.FileName).cast::<u16>();
            let name = String::from_utf16_lossy(unsafe {
                std::slice::from_raw_parts(name_ptr, name_units)
            });
            if name != "." && name != ".." {
                entries.push(WinEntry {
                    name,
                    attributes: info.FileAttributes,
                    size: info.EndOfFile as u64,
                    last_write: info.LastWriteTime as u64,
                    last_access: info.LastAccessTime as u64,
                    file_id: info.FileId as u64,
                });
            }
            if info.NextEntryOffset == 0 {
                break;
            }
            offset += info.NextEntryOffset as usize;
        }
    }
    Ok(entries)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn lists_names_sizes_and_distinct_ids() {
        let root = std::env::temp_dir().join(format!("cb_native_windir_{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("sub")).unwrap();
        fs::write(root.join("file.bin"), [0u8; 42]).unwrap();
        let mut entries = read_dir_with_ids(&root.to_string_lossy()).unwrap();
        entries.sort_by(|a, b| a.name.cmp(&b.name));
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].name, "file.bin");
        assert_eq!(entries[0].size, 42);
        assert_eq!(entries[1].name, "sub");
        assert_ne!(entries[1].attributes & 0x10, 0);
        assert_ne!(entries[0].file_id, entries[1].file_id);
        assert!(read_dir_with_ids(&root.join("missing").to_string_lossy()).is_err());
        fs::remove_dir_all(&root).unwrap();
    }
}

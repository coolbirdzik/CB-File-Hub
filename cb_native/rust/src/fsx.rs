//! Filesystem details shared by the walkers, kept identical to what Dart's
//! `Directory.list` and `FileStat` report.

use std::fs;
use std::time::{SystemTime, UNIX_EPOCH};

pub const KIND_DIRECTORY: u8 = 1;
pub const KIND_FILE: u8 = 2;

pub const SEPARATOR: char = if cfg!(windows) { '\\' } else { '/' };

/// `Directory.list` paths: the listed path, a separator unless it already
/// ends with one, then the name.
pub fn join(dir: &str, name: &str) -> String {
    let mut path = String::with_capacity(dir.len() + name.len() + 1);
    path.push_str(dir);
    if !(dir.ends_with('/') || (cfg!(windows) && dir.ends_with('\\'))) {
        path.push(SEPARATOR);
    }
    path.push_str(name);
    path
}

/// Milliseconds since the epoch; negative before 1970, 0 when unknown.
pub fn epoch_ms(time: std::io::Result<SystemTime>) -> i64 {
    match time {
        Ok(time) => match time.duration_since(UNIX_EPOCH) {
            Ok(after) => after.as_millis() as i64,
            Err(before) => -(before.duration().as_millis() as i64),
        },
        Err(_) => 0,
    }
}

pub fn modified_ms(metadata: &fs::Metadata) -> i64 {
    epoch_ms(metadata.modified())
}

/// `FileStat.changed`: the creation time on Windows, the inode change time
/// elsewhere.
pub fn changed_ms(metadata: &fs::Metadata) -> i64 {
    #[cfg(windows)]
    {
        epoch_ms(metadata.created())
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        metadata.ctime() * 1000 + metadata.ctime_nsec() / 1_000_000
    }
    #[cfg(not(any(windows, unix)))]
    {
        modified_ms(metadata)
    }
}

/// `FileTypeUtils.getFileExtension`: from the last dot of the name, so
/// `.bashrc` has the extension `.bashrc`.
pub fn last_dot_extension(name: &str) -> &str {
    name.rfind('.').map_or("", |dot| &name[dot..])
}

/// package:path `extension`: a leading dot does not start an extension.
pub fn path_extension(name: &str) -> &str {
    if name == ".." {
        return "";
    }
    match name.rfind('.') {
        Some(dot) if dot > 0 => &name[dot..],
        _ => "",
    }
}

/// Windows FILETIME ticks to epoch milliseconds.
pub fn filetime_to_ms(ticks: u64) -> i64 {
    (ticks / 10_000) as i64 - 11_644_473_600_000
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extensions_match_both_dart_flavours() {
        assert_eq!(last_dot_extension(".bashrc"), ".bashrc");
        assert_eq!(path_extension(".bashrc"), "");
        assert_eq!(path_extension("a.tar.gz"), ".gz");
        assert_eq!(path_extension("noext"), "");
        assert_eq!(last_dot_extension("x."), ".");
    }

    #[test]
    fn joins_like_directory_list() {
        let sep = SEPARATOR;
        assert_eq!(join("a", "b"), format!("a{sep}b"));
        assert_eq!(join("a/", "b"), "a/b");
    }
}

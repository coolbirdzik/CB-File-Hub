//! Batched metadata probes and streamed Recycle Bin metadata.
use crate::{
    job::{lock, Job},
    wire::{Reader, Writer},
};
use std::fs;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc, Mutex,
};

pub fn start_exists(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let paths = r.strs()?;
    if !r.is_empty() {
        return None;
    }
    Some(Job::spawn(port, "cb_exists_batch", move |job| {
        let next = AtomicUsize::new(0);
        let results = Mutex::new(vec![0u8; paths.len()]);
        std::thread::scope(|scope| {
            for _ in 0..4.min(paths.len()) {
                scope.spawn(|| loop {
                    if job.cancelled() {
                        break;
                    }
                    let i = next.fetch_add(1, Ordering::Relaxed);
                    let Some(path) = paths.get(i) else {
                        break;
                    };
                    let exists = fs::metadata(path).is_ok_and(|m| m.is_file());
                    lock(&results)[i] = u8::from(exists);
                });
            }
        });
        job.append(&lock(&results));
        Ok(())
    }))
}

fn u64_at(bytes: &[u8], at: usize) -> Option<u64> {
    Some(u64::from_le_bytes(bytes.get(at..at + 8)?.try_into().ok()?))
}

/// Metadata is tiny in ordinary bins. Bound reads to avoid loading a corrupt
/// multi-gigabyte $I file, without touching the $R payload.
fn recycle_record(path: &std::path::Path) -> Option<Vec<u8>> {
    use std::io::Read;
    let mut bytes = Vec::new();
    fs::File::open(path)
        .ok()?
        .take(1024 * 1024)
        .read_to_end(&mut bytes)
        .ok()?;
    let version = u64_at(&bytes, 0)?;
    let size = u64_at(&bytes, 8)? as i64;
    // Match the existing Dart reader's signed int64 and truncating division,
    // including damaged metadata with a negative timestamp.
    let filetime = u64_at(&bytes, 16)? as i64;
    let deleted = if filetime <= 0 {
        0
    } else {
        filetime / 10_000 - 11_644_473_600_000
    };
    let (start, end) = if version == 2 {
        let count = i32::from_le_bytes(bytes.get(24..28)?.try_into().ok()?);
        if count < 0 {
            return None;
        }
        (28, 28usize.checked_add((count as usize).checked_mul(2)?)?)
    } else {
        (24, 544)
    };
    let units: Vec<u16> = bytes
        .get(start..end)?
        .chunks_exact(2)
        .map(|v| u16::from_le_bytes([v[0], v[1]]))
        .take_while(|c| *c != 0)
        .collect();
    let original = String::from_utf16_lossy(&units);
    if original.is_empty() {
        return None;
    }
    let name = path.file_name()?.to_str()?.strip_prefix("$I")?;
    let companion = path.with_file_name(format!("$R{name}"));
    let metadata = fs::symlink_metadata(&companion).ok()?;
    let mut w = Writer::default();
    w.str(&companion.to_string_lossy());
    w.str(&original);
    w.i64(size.max(0));
    w.i64(deleted);
    w.u8(u8::from(metadata.is_dir()));
    Some(w.into_bytes())
}

pub fn start_recycle_bin(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let roots = r.strs()?;
    if !r.is_empty() {
        return None;
    }
    Some(Job::spawn(port, "cb_recycle_bin", move |job| {
        // One bounded work queue shared by four readers. Directory enumeration
        // and metadata reads stay off the Dart isolate, and output is streamed.
        let (sender, receiver) = std::sync::mpsc::sync_channel::<std::path::PathBuf>(128);
        let receiver = Mutex::new(receiver);
        std::thread::scope(|scope| {
            for _ in 0..4 {
                scope.spawn(|| loop {
                    if job.cancelled() {
                        break;
                    }
                    let path = match lock(&receiver).recv() {
                        Ok(path) => path,
                        Err(_) => break,
                    };
                    if let Some(record) = recycle_record(&path) {
                        job.append(&record);
                    }
                });
            }
            'roots: for root in roots {
                let Ok(sids) = fs::read_dir(root) else {
                    continue;
                };
                for sid in sids.flatten() {
                    if job.cancelled() {
                        break 'roots;
                    }
                    if !sid.file_type().is_ok_and(|t| t.is_dir()) {
                        continue;
                    }
                    let Ok(entries) = fs::read_dir(sid.path()) else {
                        continue;
                    };
                    for entry in entries.flatten() {
                        if !entry.file_type().is_ok_and(|t| t.is_file()) {
                            continue;
                        }
                        if !entry.file_name().to_string_lossy().starts_with("$I") {
                            continue;
                        }
                        let mut path = entry.path();
                        loop {
                            if job.cancelled() {
                                break 'roots;
                            }
                            match sender.try_send(path) {
                                Ok(()) => break,
                                Err(std::sync::mpsc::TrySendError::Full(p)) => {
                                    path = p;
                                    std::thread::sleep(std::time::Duration::from_millis(1));
                                }
                                Err(_) => break 'roots,
                            }
                        }
                    }
                }
            }
            drop(sender);
        });
        Ok(())
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::job::{testing::wait, JOB_DONE};
    #[test]
    fn exists_preserves_order_and_excludes_directories() {
        let mut w = Writer::default();
        w.u32(3);
        w.str(file!());
        w.str(".");
        w.str("missing-unique-file");
        let (state, out) = wait(&start_exists(0, &w.into_bytes()).unwrap());
        assert_eq!(state, JOB_DONE);
        assert_eq!(out, [1, 0, 0]);
    }
}

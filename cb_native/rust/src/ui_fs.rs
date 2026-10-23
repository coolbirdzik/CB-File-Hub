//! Small filesystem jobs used by interactive views. Never run on the UI thread.
use crate::{
    fsx,
    job::Job,
    normalize::{dart_compare, dart_lower},
    wire::{Reader, Writer},
};
use std::{fs, sync::Arc};

pub fn start_suggestions(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let root = r.str()?;
    let prefix = r.str()?;
    let insensitive = r.bool()?;
    let limit = r.u32()? as usize;
    if !r.is_empty() {
        return None;
    }
    Some(Job::spawn(port, "cb_path_suggestions", move |job| {
        let entries = fs::read_dir(&root).map_err(|e| e.to_string())?;
        let prefix = if insensitive {
            dart_lower(&prefix)
        } else {
            prefix
        };
        let mut out = Writer::default();
        let mut count = 0;
        for entry in entries {
            if count >= limit || job.cancelled() {
                break;
            }
            let entry = entry.map_err(|e| e.to_string())?;
            if !entry
                .file_type()
                .is_ok_and(|t| t.is_dir() && !t.is_symlink())
            {
                continue;
            }
            let name = entry.file_name().to_string_lossy().into_owned();
            let key = if insensitive {
                dart_lower(&name)
            } else {
                name.clone()
            };
            if key.starts_with(&prefix) {
                out.str(&fsx::join(&root, &name));
                count += 1;
            }
        }
        job.append(&out.into_bytes());
        Ok(())
    }))
}

pub fn start_child_counts(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let roots = r.strs()?;
    if !r.is_empty() {
        return None;
    }
    Some(Job::spawn(port, "cb_child_counts", move |job| {
        let mut out = Writer::default();
        for root in roots {
            if job.cancelled() {
                return Ok(());
            }
            let count = fs::read_dir(root)
                .and_then(|entries| {
                    let mut count = 0;
                    for entry in entries {
                        entry?;
                        count += 1;
                        if job.cancelled() {
                            break;
                        }
                    }
                    Ok(count)
                })
                .unwrap_or(-1);
            out.i64(count);
        }
        job.append(&out.into_bytes());
        Ok(())
    }))
}

struct CacheEntry {
    path: String,
    size: u64,
    modified: i64,
}
pub fn start_cache_plan(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let root = r.str()?;
    let cutoff = r.i64()?;
    let max_count = r.u32()? as usize;
    let max_bytes = r.u64()?;
    if !r.is_empty() {
        return None;
    }
    Some(Job::spawn(port, "cb_cache_plan", move |job| {
        let mut entries = Vec::new();
        for entry in fs::read_dir(&root).map_err(|e| e.to_string())? {
            if job.cancelled() {
                return Ok(());
            }
            let Ok(entry) = entry else {
                continue;
            };
            if !entry
                .file_type()
                .is_ok_and(|t| t.is_file() && !t.is_symlink())
            {
                continue;
            }
            let Ok(meta) = entry.metadata() else {
                continue;
            };
            entries.push(CacheEntry {
                path: fsx::join(&root, &entry.file_name().to_string_lossy()),
                size: meta.len(),
                modified: fsx::modified_ms(&meta),
            });
        }
        entries.sort_by(|a, b| {
            a.modified
                .cmp(&b.modified)
                .then_with(|| dart_compare(&a.path, &b.path))
        });
        let mut count = entries.len();
        let mut size: u64 = entries.iter().map(|e| e.size).sum();
        let mut out = Writer::default();
        for entry in entries {
            if job.cancelled() {
                return Ok(());
            }
            if entry.modified < cutoff || count > max_count || size > max_bytes {
                count -= 1;
                size = size.saturating_sub(entry.size);
                out.str(&entry.path);
                out.u64(entry.size);
                out.i64(entry.modified);
            }
        }
        job.append(&out.into_bytes());
        Ok(())
    }))
}

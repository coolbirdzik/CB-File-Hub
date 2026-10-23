//! Permanent deletion of exact approved targets, on bounded Rust workers.
//! Recycle Bin operations deliberately remain with the Windows Shell.
use crate::{
    job::Job,
    wire::{Reader, Writer},
};
use std::{
    fs, io,
    path::{Component, Path},
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    },
};

fn delete_target(path: &Path) -> io::Result<()> {
    // Never interpret an empty/relative path or a volume root as a target.
    if !path.is_absolute()
        || path.file_name().is_none()
        || path
            .components()
            .any(|part| matches!(part, Component::ParentDir))
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "expected an absolute file or directory target",
        ));
    }
    let metadata = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error),
    };
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        // Delete directory symlinks and junctions themselves, never their target.
        let attributes = metadata.file_attributes();
        if attributes & 0x400 != 0 && attributes & 0x10 != 0 {
            return fs::remove_dir(path);
        }
    }
    let result = if metadata.is_dir() {
        // Use std's symlink-safe implementation rather than a path-based walker
        // that could follow a directory replaced by a link during traversal.
        fs::remove_dir_all(path)
    } else {
        fs::remove_file(path)
    };
    match result {
        Err(error) if error.kind() == io::ErrorKind::NotFound => match fs::symlink_metadata(path) {
            Err(check) if check.kind() == io::ErrorKind::NotFound => Ok(()),
            _ => Err(error),
        },
        other => other,
    }
}

pub fn start(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let paths = r.strs()?;
    let concurrency = (r.u32()? as usize).clamp(1, 8);
    if !r.is_empty() {
        return None;
    }
    Some(Job::spawn(port, "cb_permanent_delete", move |job| {
        let next = AtomicUsize::new(0);
        job.set_counter(1, paths.len() as u64);
        std::thread::scope(|scope| {
            for _ in 0..concurrency.min(paths.len()) {
                let paths = &paths;
                let next = &next;
                scope.spawn(move || loop {
                    if job.cancelled() {
                        break;
                    }
                    let index = next.fetch_add(1, Ordering::Relaxed);
                    let Some(path) = paths.get(index) else {
                        break;
                    };
                    job.set_current(path);
                    let result = delete_target(Path::new(path));
                    let mut record = Writer::default();
                    record.u32(index as u32);
                    match result {
                        Ok(()) => {
                            record.i64(0);
                            record.str("");
                        }
                        Err(error) => {
                            record.i64(i64::from(error.raw_os_error().unwrap_or(-1)));
                            record.str(&error.to_string());
                            job.add_counter(2, 1);
                        }
                    }
                    // Append whole records so Dart never observes a partial one.
                    job.append(&record.into_bytes());
                    job.add_counter(0, 1);
                });
            }
        });
        Ok(())
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::job::{testing::wait, JOB_DONE};
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn deletes_only_requested_targets_and_reports_every_result() {
        let root = std::env::temp_dir().join(format!(
            "cb_delete_{}_{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(root.join("selected/deep")).unwrap();
        fs::write(root.join("selected/deep/file"), "delete").unwrap();
        fs::write(root.join("keep"), "keep").unwrap();
        let mut config = Writer::default();
        config.u32(3);
        config.str(root.join("selected").to_str().unwrap());
        config.str(root.join("missing").to_str().unwrap());
        config.str(""); // Invalid input must not fall back to deleting cwd.
        config.u32(4);
        let job = start(0, &config.into_bytes()).unwrap();
        let (state, output) = wait(&job);
        assert_eq!(state, JOB_DONE);
        let mut r = Reader::new(&output);
        let mut outcomes = Vec::new();
        while !r.is_empty() {
            outcomes.push((r.u32().unwrap(), r.i64().unwrap(), r.str().unwrap()));
        }
        outcomes.sort_by_key(|outcome| outcome.0);
        assert_eq!(outcomes.len(), 3);
        assert_eq!(outcomes[0].1, 0);
        assert_eq!(outcomes[1].1, 0);
        assert_ne!(outcomes[2].1, 0);
        assert!(!root.join("selected").exists());
        assert_eq!(fs::read_to_string(root.join("keep")).unwrap(), "keep");
        assert_eq!(job.progress().0[..3], [3, 3, 1]);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn directory_links_do_not_delete_their_destination() {
        let root = std::env::temp_dir().join(format!(
            "cb_delete_links_{}_{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(root.join("outside")).unwrap();
        fs::create_dir_all(root.join("selected")).unwrap();
        fs::write(root.join("outside/keep"), "keep").unwrap();
        #[cfg(windows)]
        let linked =
            std::os::windows::fs::symlink_dir(root.join("outside"), root.join("selected/link"));
        #[cfg(not(windows))]
        let linked = std::os::unix::fs::symlink(root.join("outside"), root.join("selected/link"));
        if let Err(error) = linked {
            // Windows without Developer Mode requires symlink privilege.
            assert_eq!(error.raw_os_error(), Some(1314));
            fs::remove_dir_all(root).unwrap();
            return;
        }
        delete_target(&root.join("selected/link")).unwrap();
        assert_eq!(
            fs::read_to_string(root.join("outside/keep")).unwrap(),
            "keep"
        );
        #[cfg(windows)]
        std::os::windows::fs::symlink_dir(root.join("outside"), root.join("selected/link"))
            .unwrap();
        #[cfg(not(windows))]
        std::os::unix::fs::symlink(root.join("outside"), root.join("selected/link")).unwrap();
        delete_target(&root.join("selected")).unwrap();
        assert_eq!(
            fs::read_to_string(root.join("outside/keep")).unwrap(),
            "keep"
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[cfg(windows)]
    #[test]
    fn reports_locked_target_and_continues_with_other_targets() {
        use std::os::windows::fs::OpenOptionsExt;
        let root = std::env::temp_dir().join(format!(
            "cb_delete_locked_{}_{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&root).unwrap();
        fs::write(root.join("locked"), "keep").unwrap();
        fs::write(root.join("other"), "delete").unwrap();
        let held = fs::OpenOptions::new()
            .read(true)
            .share_mode(0)
            .open(root.join("locked"))
            .unwrap();
        let mut config = Writer::default();
        config.u32(2);
        config.str(root.join("locked").to_str().unwrap());
        config.str(root.join("other").to_str().unwrap());
        config.u32(2);
        let (state, output) = wait(&start(0, &config.into_bytes()).unwrap());
        assert_eq!(state, JOB_DONE);
        let mut r = Reader::new(&output);
        let mut codes = [0, -1];
        while !r.is_empty() {
            let index = r.u32().unwrap() as usize;
            codes[index] = r.i64().unwrap();
            let message = r.str().unwrap();
            assert_eq!(message.is_empty(), codes[index] == 0);
        }
        assert!(
            codes[0] == 32 || codes[0] == 5,
            "expected sharing violation/access denied: {codes:?}"
        );
        assert_eq!(codes[1], 0);
        assert!(!root.join("other").exists());
        drop(held);
        assert_eq!(fs::read_to_string(root.join("locked")).unwrap(), "keep");
        fs::remove_dir_all(root).unwrap();
    }
}

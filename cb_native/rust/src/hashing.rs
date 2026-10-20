//! File checksums. `sha2` picks the SHA-NI / ARMv8 instructions at runtime,
//! several times faster than `package:crypto` on large files.

use std::fs::File;
use std::io::Read;
use std::sync::Arc;

use sha2::{Digest, Sha256};

use crate::job::Job;
use crate::wire::Reader;

const ALGORITHM_SHA256: u8 = 0;
const CHUNK: usize = 1 << 20;

fn hash_file(job: &Job, path: &str) -> Result<(), String> {
    let mut file = File::open(path).map_err(|e| e.to_string())?;
    if let Ok(metadata) = file.metadata() {
        job.set_counter(1, metadata.len());
    }
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; CHUNK];
    loop {
        if job.cancelled() {
            return Ok(());
        }
        let read = match file.read(&mut buffer) {
            Ok(0) => break,
            Ok(read) => read,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e.to_string()),
        };
        hasher.update(&buffer[..read]);
        job.add_counter(0, read as u64);
    }
    job.append(&hasher.finalize());
    Ok(())
}

/// Config: path, algorithm u8 (0 = SHA-256). Output: the digest bytes.
/// Counters: bytes hashed, file size.
pub fn start_hash_file(port: i64, config: &[u8]) -> Option<Arc<Job>> {
    let mut r = Reader::new(config);
    let path = r.str()?;
    let algorithm = r.u8()?;
    if !r.is_empty() || path.is_empty() || algorithm != ALGORITHM_SHA256 {
        return None;
    }
    Some(Job::spawn(port, "cb_native_hash", move |job| {
        hash_file(job, &path)
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::job::testing::wait;
    use crate::job::JOB_DONE;
    use crate::wire::Writer;

    #[test]
    fn hashes_a_file() {
        let path = std::env::temp_dir().join(format!("cb_native_hash_{}", std::process::id()));
        std::fs::write(&path, b"abc").unwrap();
        let mut config = Writer::default();
        config.str(&path.to_string_lossy());
        config.u8(ALGORITHM_SHA256);
        let job = start_hash_file(0, &config.into_bytes()).unwrap();
        let (state, digest) = wait(&job);
        assert_eq!(state, JOB_DONE);
        let hex: String = digest.iter().map(|b| format!("{b:02x}")).collect();
        assert_eq!(
            hex,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        std::fs::remove_file(&path).unwrap();
    }
}

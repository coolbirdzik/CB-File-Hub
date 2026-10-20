//! A background job whose result Dart collects through `cb_job_*`.
//!
//! Every newer native operation (sizes, listings, walks, images, hashes,
//! archives) is a `Job`: it runs off the caller's thread, appends its output
//! to a buffer, exposes four progress counters plus a current path, and ends
//! in exactly one terminal state. When Dart passes a native port, the terminal
//! state is posted to it so Dart wakes up immediately instead of polling.
//!
//! A job stops on its own once its owner is gone: with a port, a periodic ping
//! that fails means the isolate shut down; without one, nobody polling for
//! `ABANDON_AFTER_MS` means the same. The Disk Cleaner kills isolates to
//! cancel, so this keeps native work from outliving them.

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread;
use std::time::Instant;

use crate::dart_api;

pub const JOB_RUNNING: i32 = 0;
pub const JOB_DONE: i32 = 1;
pub const JOB_FAILED: i32 = 2;
pub const JOB_CANCELLED: i32 = 3;

/// Posted while running so a closed port is noticed; Dart ignores it.
const PING: i64 = -1;
const PING_EVERY_MS: u64 = 500;
const ABANDON_AFTER_MS: u64 = if cfg!(test) { 200 } else { 15_000 };

pub struct Job {
    output: Mutex<Vec<u8>>,
    error: Mutex<String>,
    state: AtomicI32,
    cancelled: AtomicBool,
    counters: [AtomicU64; 4],
    current: Mutex<String>,
    port: i64,
    started: Instant,
    last_contact_ms: AtomicU64,
    last_ping_ms: AtomicU64,
}

pub fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(|e| e.into_inner())
}

impl Job {
    pub fn new(port: i64) -> Arc<Job> {
        Arc::new(Job {
            output: Mutex::new(Vec::new()),
            error: Mutex::new(String::new()),
            state: AtomicI32::new(JOB_RUNNING),
            cancelled: AtomicBool::new(false),
            counters: Default::default(),
            current: Mutex::new(String::new()),
            // Without the dart_api_dl table a port cannot be posted to, so the
            // job behaves like a polled one.
            port: if dart_api::available() { port } else { 0 },
            started: Instant::now(),
            last_contact_ms: AtomicU64::new(0),
            last_ping_ms: AtomicU64::new(0),
        })
    }

    /// Runs `work` on a new thread and completes the job with its result.
    pub fn spawn<F>(port: i64, name: &str, work: F) -> Arc<Job>
    where
        F: FnOnce(&Job) -> Result<(), String> + Send + 'static,
    {
        let job = Job::new(port);
        let worker = Arc::clone(&job);
        let spawned = thread::Builder::new()
            .name(name.to_string())
            .spawn(move || worker.run(work));
        if spawned.is_err() {
            job.complete(Err("could not start a native thread".into()));
        }
        job
    }

    /// Runs `work` here, turning a panic into a failure.
    pub fn run<F>(&self, work: F)
    where
        F: FnOnce(&Job) -> Result<(), String>,
    {
        let result = catch_unwind(AssertUnwindSafe(|| work(self)))
            .unwrap_or_else(|_| Err("native code panicked".into()));
        self.complete(result);
    }

    fn elapsed_ms(&self) -> u64 {
        self.started.elapsed().as_millis() as u64
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
    }

    /// True once cancelled or abandoned. Cheap enough to call per entry.
    pub fn cancelled(&self) -> bool {
        if self.cancelled.load(Ordering::Acquire) {
            return true;
        }
        let now = self.elapsed_ms();
        if self.port != 0 {
            let last = self.last_ping_ms.load(Ordering::Relaxed);
            if now.saturating_sub(last) >= PING_EVERY_MS {
                self.last_ping_ms.store(now, Ordering::Relaxed);
                if !dart_api::post_int(self.port, PING) {
                    self.cancel();
                }
            }
        } else if now.saturating_sub(self.last_contact_ms.load(Ordering::Relaxed))
            > ABANDON_AFTER_MS
        {
            self.cancel();
        }
        self.cancelled.load(Ordering::Acquire)
    }

    /// Sets the terminal state once and wakes Dart.
    pub fn complete(&self, result: Result<(), String>) {
        let state = if self.cancelled.load(Ordering::Acquire) {
            JOB_CANCELLED
        } else {
            match result {
                Ok(()) => JOB_DONE,
                Err(message) => {
                    *lock(&self.error) = message;
                    JOB_FAILED
                }
            }
        };
        if state == JOB_CANCELLED {
            // Nobody will read it; do not hold on to a large buffer.
            *lock(&self.output) = Vec::new();
        }
        if self
            .state
            .compare_exchange(JOB_RUNNING, state, Ordering::AcqRel, Ordering::Acquire)
            .is_ok()
            && self.port != 0
        {
            dart_api::post_int(self.port, i64::from(state));
        }
    }

    pub fn append(&self, bytes: &[u8]) {
        if !bytes.is_empty() {
            lock(&self.output).extend_from_slice(bytes);
        }
    }

    pub fn append_vec(&self, bytes: &mut Vec<u8>) {
        if !bytes.is_empty() {
            lock(&self.output).append(bytes);
        }
    }

    pub fn set_counter(&self, index: usize, value: u64) {
        self.counters[index].store(value, Ordering::Relaxed);
    }

    pub fn add_counter(&self, index: usize, delta: u64) -> u64 {
        self.counters[index].fetch_add(delta, Ordering::Relaxed) + delta
    }

    pub fn counter(&self, index: usize) -> u64 {
        self.counters[index].load(Ordering::Relaxed)
    }

    /// Best effort: skipped when another thread is updating it.
    pub fn set_current(&self, path: &str) {
        if let Ok(mut current) = self.current.try_lock() {
            current.clear();
            current.push_str(path);
        }
    }

    fn touch(&self) {
        self.last_contact_ms
            .store(self.elapsed_ms(), Ordering::Relaxed);
    }

    /// The state, read before draining so a final batch is never missed, and
    /// the output produced since the previous call.
    pub fn poll(&self) -> (i32, Vec<u8>) {
        self.touch();
        let state = self.state.load(Ordering::Acquire);
        (state, std::mem::take(&mut *lock(&self.output)))
    }

    pub fn error(&self) -> String {
        lock(&self.error).clone()
    }

    pub fn progress(&self) -> ([u64; 4], String) {
        self.touch();
        (
            [0, 1, 2, 3].map(|i| self.counter(i)),
            lock(&self.current).clone(),
        )
    }
}

#[cfg(test)]
pub mod testing {
    use super::*;
    use std::time::Duration;

    /// Polls `job` like Dart would until it ends; returns state and output.
    pub fn wait(job: &Job) -> (i32, Vec<u8>) {
        let deadline = Instant::now() + Duration::from_secs(30);
        let mut out = Vec::new();
        loop {
            let (state, batch) = job.poll();
            out.extend(batch);
            if state != JOB_RUNNING {
                return (state, out);
            }
            assert!(Instant::now() < deadline, "job did not finish");
            thread::sleep(Duration::from_millis(2));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn reports_output_errors_and_panics() {
        let ok = Job::spawn(0, "t", |job| {
            job.append(b"abc");
            Ok(())
        });
        assert_eq!(testing::wait(&ok), (JOB_DONE, b"abc".to_vec()));

        let failed = Job::spawn(0, "t", |_| Err("boom".into()));
        assert_eq!(testing::wait(&failed).0, JOB_FAILED);
        assert_eq!(failed.error(), "boom");

        let panicked = Job::spawn(0, "t", |_| panic!("x"));
        assert_eq!(testing::wait(&panicked).0, JOB_FAILED);
    }

    #[test]
    fn unpolled_job_is_abandoned() {
        let job = Job::new(0);
        assert!(!job.cancelled());
        thread::sleep(Duration::from_millis(ABANDON_AFTER_MS + 50));
        assert!(job.cancelled());
        job.complete(Ok(()));
        assert_eq!(job.poll().0, JOB_CANCELLED);
    }
}

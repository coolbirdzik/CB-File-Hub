//! FFmpeg pipe parsing and child lifetime management off the Dart isolate.
//! Media packets still flow directly through FFmpeg, never over FFI.
use crate::{
    job::Job,
    wire::{Reader, Writer},
};
use std::{
    io::Read,
    process::{Child, Command, Stdio},
    sync::Arc,
    thread,
    time::Duration,
};

const LOG_LIMIT: usize = 16_000;
const LINE_LIMIT: usize = 1024;

struct Config {
    executable: String,
    arguments: Vec<String>,
    duration_us: u64,
}

impl Config {
    fn parse(bytes: &[u8]) -> Option<Self> {
        let mut reader = Reader::new(bytes);
        let executable = reader.str()?;
        let duration_us = reader.u64()?;
        let arguments = reader.strs()?;
        if executable.is_empty()
            || duration_us == 0
            || !reader.is_empty()
            || executable.contains('\0')
            || arguments.iter().any(|arg| arg.contains('\0'))
        {
            return None;
        }
        Some(Self {
            executable,
            arguments,
            duration_us,
        })
    }
}

pub fn start(port: i64, bytes: &[u8]) -> Option<Arc<Job>> {
    let config = Config::parse(bytes)?;
    Some(Job::spawn(port, "cb-ffmpeg", move |job| run(job, config)))
}

struct ChildGuard {
    child: Child,
    #[cfg(windows)]
    _job: Option<windows_job::KillOnClose>,
}

impl Drop for ChildGuard {
    fn drop(&mut self) {
        // Rust's Child itself does not kill or reap on drop.
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn run(job: &Job, config: Config) -> Result<(), String> {
    if job.cancelled() {
        return Ok(());
    }
    thread::scope(|scope| {
        let mut command = Command::new(config.executable);
        command
            .args(config.arguments)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            // CREATE_NO_WINDOW | BELOW_NORMAL_PRIORITY_CLASS.
            command.creation_flags(0x0800_0000 | 0x0000_4000);
        }
        let child = command.spawn().map_err(|error| error.to_string())?;
        #[cfg(windows)]
        let process_job = windows_job::KillOnClose::attach(&child);
        let mut child = ChildGuard {
            child,
            #[cfg(windows)]
            _job: process_job,
        };
        // Both pipes must be drained concurrently to avoid a full-pipe deadlock.
        let stdout = child.child.stdout.take().ok_or("FFmpeg stdout missing")?;
        let stderr = child.child.stderr.take().ok_or("FFmpeg stderr missing")?;
        let output_reader = scope.spawn(|| read_progress(stdout, job, config.duration_us));
        let error_reader = scope.spawn(|| read_tail(stderr));
        let status = loop {
            if job.cancelled() {
                return Ok(());
            }
            if let Some(status) = child.child.try_wait().map_err(|error| error.to_string())? {
                break status;
            }
            thread::sleep(Duration::from_millis(20));
        };
        // Close the process job before joining readers, including descendants
        // that might otherwise retain pipe handles after their parent exits.
        drop(child);
        output_reader
            .join()
            .map_err(|_| "FFmpeg progress reader panicked")??;
        let diagnostic = error_reader
            .join()
            .map_err(|_| "FFmpeg error reader panicked")??;
        let mut output = Writer::default();
        output.i32(status.code().unwrap_or(-1));
        output.str(String::from_utf8_lossy(&diagnostic).trim());
        job.append(&output.into_bytes());
        Ok(())
    })
}

fn read_tail(mut input: impl Read) -> Result<Vec<u8>, String> {
    let mut tail = Vec::with_capacity(LOG_LIMIT);
    let mut buffer = [0_u8; 4096];
    loop {
        let count = input.read(&mut buffer).map_err(|error| error.to_string())?;
        if count == 0 {
            return Ok(tail);
        }
        let overflow = (tail.len() + count).saturating_sub(LOG_LIMIT);
        tail.drain(..overflow);
        tail.extend_from_slice(&buffer[..count]);
    }
}

fn read_progress(mut input: impl Read, job: &Job, duration_us: u64) -> Result<(), String> {
    let mut buffer = [0_u8; 4096];
    let mut line = Vec::with_capacity(LINE_LIMIT);
    let mut overflow = false;
    loop {
        let count = input.read(&mut buffer).map_err(|error| error.to_string())?;
        if count == 0 {
            return Ok(());
        }
        for &byte in &buffer[..count] {
            if byte == b'\n' {
                if !overflow {
                    update_progress(&line, job, duration_us);
                }
                line.clear();
                overflow = false;
            } else if line.len() < LINE_LIMIT {
                line.push(byte);
            } else {
                overflow = true;
            }
        }
    }
}

fn update_progress(line: &[u8], job: &Job, duration_us: u64) {
    if let Some(value) = std::str::from_utf8(line)
        .ok()
        .and_then(|line| line.strip_prefix("out_time_us="))
        .and_then(|value| value.trim().parse::<u64>().ok())
    {
        job.set_counter(0, value.min(duration_us).max(job.counter(0)));
    }
}

#[cfg(windows)]
mod windows_job {
    use std::{
        mem::{size_of, zeroed},
        os::windows::io::AsRawHandle,
        process::Child,
        ptr,
    };
    use windows_sys::Win32::{
        Foundation::{CloseHandle, HANDLE},
        System::JobObjects::{
            AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
            SetInformationJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
            JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
        },
    };

    pub struct KillOnClose(HANDLE);

    impl KillOnClose {
        pub fn attach(child: &Child) -> Option<Self> {
            unsafe {
                let handle = CreateJobObjectW(ptr::null(), ptr::null());
                if handle.is_null() {
                    return None;
                }
                let mut info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = zeroed();
                info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
                if SetInformationJobObject(
                    handle,
                    JobObjectExtendedLimitInformation,
                    (&info as *const JOBOBJECT_EXTENDED_LIMIT_INFORMATION).cast(),
                    size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
                ) == 0
                    || AssignProcessToJobObject(handle, child.as_raw_handle()) == 0
                {
                    CloseHandle(handle);
                    return None;
                }
                Some(Self(handle))
            }
        }
    }

    impl Drop for KillOnClose {
        fn drop(&mut self) {
            unsafe {
                CloseHandle(self.0);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::job::{testing, JOB_CANCELLED, JOB_DONE, JOB_FAILED};

    fn config(executable: &str, arguments: &[&str]) -> Vec<u8> {
        let mut writer = Writer::default();
        writer.str(executable);
        writer.u64(1_000_000);
        writer.u32(arguments.len() as u32);
        for arg in arguments {
            writer.str(arg);
        }
        writer.into_bytes()
    }

    #[test]
    fn bounds_and_monotonic_progress() {
        let job = Job::new(0);
        let bytes = b"out_time_us=500000\r\nout_time_us=-4\nout_time_us=bad\nout_time_us=100\nout_time_us=9999999\n";
        read_progress(&bytes[..], &job, 1_000_000).unwrap();
        assert_eq!(job.counter(0), 1_000_000);
        let mut hostile = vec![b'x'; 1_000_000];
        hostile.extend_from_slice(b"out_time_us=123\nout_time_us=600000\n");
        let job = Job::new(0);
        read_progress(&hostile[..], &job, 1_000_000).unwrap();
        assert_eq!(job.counter(0), 600_000);
        assert_eq!(
            read_tail(&vec![b'z'; LOG_LIMIT * 4][..]).unwrap().len(),
            LOG_LIMIT
        );
    }

    #[test]
    fn invalid_config_and_missing_executable() {
        assert!(start(0, &config("", &[])).is_none());
        assert!(start(0, &config("bad\0name", &[])).is_none());
        assert!(start(0, &[1, 2]).is_none());
        let job = start(0, &config("__cb_missing_ffmpeg__", &[])).unwrap();
        assert_eq!(testing::wait(&job).0, JOB_FAILED);
    }

    #[cfg(windows)]
    #[test]
    fn reads_exit_diagnostics_and_cancels_child() {
        let shell = std::env::var("ComSpec").unwrap();
        let job = start(0, &config(&shell, &["/C", "echo failure 1>&2 & exit /b 7"])).unwrap();
        let (state, output) = testing::wait(&job);
        assert_eq!(state, JOB_DONE);
        let mut reader = Reader::new(&output);
        assert_eq!(reader.i32(), Some(7));
        assert!(reader.str().unwrap().contains("failure"));
        let job = start(0, &config(&shell, &["/C", "ping -n 30 127.0.0.1 >nul"])).unwrap();
        thread::sleep(Duration::from_millis(30));
        job.cancel();
        assert_eq!(testing::wait(&job).0, JOB_CANCELLED);
    }
}

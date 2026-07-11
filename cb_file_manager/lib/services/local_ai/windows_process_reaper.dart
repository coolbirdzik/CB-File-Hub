import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Attaches child processes to a Windows Job Object configured with
/// `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`.
///
/// This guarantees that any process assigned to the job is killed by the OS
/// when the parent (this app) exits — for any reason, including a crash or an
/// external `taskkill`. Without this, a bundled `llama-server.exe` child could
/// be orphaned and keep holding VRAM/ports if the app dies before it can call
/// `dispose()` on the graceful path.
///
/// The job handle is intentionally never closed: it stays open for the whole
/// app lifetime and is released only when the process exits, which is exactly
/// when kill-on-close should fire.
///
/// win32 5.x exposes the Job Object *functions* but not the
/// `JOBOBJECT_EXTENDED_LIMIT_INFORMATION` struct or its constants, so the
/// struct is written as a raw byte buffer: on x64 the `LimitFlags` DWORD sits
/// at offset 16 inside the leading `JOBOBJECT_BASIC_LIMIT_INFORMATION`, and the
/// full extended struct is 144 bytes. Zero-initialising the buffer and setting
/// only `LimitFlags` is sufficient for a kill-on-close job.
class WindowsProcessReaper {
  WindowsProcessReaper._();

  static final WindowsProcessReaper instance = WindowsProcessReaper._();

  // JOBOBJECT_INFOCLASS.JobObjectExtendedLimitInformation
  static const int _jobObjectExtendedLimitInformation = 9;
  // JOBOBJECT_BASIC_LIMIT_INFORMATION.LimitFlags value.
  static const int _jobObjectLimitKillOnJobClose = 0x2000;
  // Offset of LimitFlags within the extended struct (x64).
  static const int _limitFlagsOffset = 16;
  // sizeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION) on x64.
  static const int _extendedLimitInfoSize = 144;
  // Access rights needed to assign a process to a job.
  static const int _processSetQuota = 0x0100;
  static const int _processTerminate = 0x0001;

  int _jobHandle = 0;
  bool _initialized = false;
  bool _available = false;

  /// Lazily creates the kill-on-close job object. Returns false if the job
  /// could not be created (in which case [assignProcess] is a no-op).
  bool _ensureJob() {
    if (_initialized) return _available;
    _initialized = true;

    final job = CreateJobObject(nullptr, nullptr);
    if (job == 0) {
      _available = false;
      return false;
    }

    final info = calloc<Uint8>(_extendedLimitInfoSize);
    try {
      (Pointer<Uint8>.fromAddress(info.address + _limitFlagsOffset))
          .cast<Uint32>()
          .value = _jobObjectLimitKillOnJobClose;
      final ok = SetInformationJobObject(
        job,
        _jobObjectExtendedLimitInformation,
        info.cast(),
        _extendedLimitInfoSize,
      );
      if (ok == 0) {
        CloseHandle(job);
        _available = false;
        return false;
      }
    } finally {
      calloc.free(info);
    }

    _jobHandle = job;
    _available = true;
    return true;
  }

  /// Assigns the process identified by [pid] to the kill-on-close job so it is
  /// terminated automatically when this app exits. Safe to call for every
  /// spawned server; failures are swallowed (best-effort hardening).
  void assignProcess(int pid) {
    if (!_ensureJob()) return;

    final handle = OpenProcess(_processSetQuota | _processTerminate, 0, pid);
    if (handle == 0) return;
    try {
      AssignProcessToJobObject(_jobHandle, handle);
    } finally {
      CloseHandle(handle);
    }
  }
}

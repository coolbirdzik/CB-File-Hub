import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

/// Volume metadata for one Windows drive root, as plain data so it can be sent
/// back from the probe isolate.
class WindowsVolumeProbe {
  final String root;
  final int driveType;
  final String label;
  final String filesystem;
  final String? serial;
  final int totalBytes;
  final int freeBytes;

  const WindowsVolumeProbe({
    required this.root,
    this.driveType = win32.DRIVE_UNKNOWN,
    this.label = '',
    this.filesystem = '',
    this.serial,
    this.totalBytes = 0,
    this.freeBytes = 0,
  });
}

/// `compute` entry point: read drive type, label and free space for each root.
///
/// Every call in here blocks the calling thread until the OS answers, and the
/// OS takes as long as it takes: spinning up a sleeping disk, waiting out the
/// SMB timeout on a mapped share whose server is gone, retrying an empty card
/// reader. Running it on the UI isolate froze the whole window for the length
/// of the slowest volume, which is why this lives in its own isolate.
List<WindowsVolumeProbe> probeWindowsVolumes(List<String> roots) {
  if (!Platform.isWindows) return const <WindowsVolumeProbe>[];

  _silenceWindowsHardErrors();

  return <WindowsVolumeProbe>[for (final root in roots) _probeVolume(root)];
}

/// Return "no disk in the drive" as a plain error code instead of letting the
/// OS park the thread on its hard-error retry path.
void _silenceWindowsHardErrors() {
  try {
    win32.SetThreadErrorMode(
      win32.SEM_FAILCRITICALERRORS | win32.SEM_NOOPENFILEERRORBOX,
      nullptr,
    );
  } catch (_) {
    // Best effort — the probes below still work without it, just slower on a
    // drive with no media.
  }
}

WindowsVolumeProbe _probeVolume(String root) {
  final drive = root.endsWith('\\') ? root : '$root\\';
  final type = windowsDriveType(drive);

  // An optical or removable letter with no media answers neither of the calls
  // below, so skip straight to the bare entry instead of paying the timeout.
  if (type == win32.DRIVE_NO_ROOT_DIR) {
    return WindowsVolumeProbe(root: root, driveType: type);
  }

  final meta = _readVolumeInformation(drive);
  final space = _readDiskFreeSpace(drive);

  return WindowsVolumeProbe(
    root: root,
    driveType: type,
    label: meta.label,
    filesystem: meta.filesystem,
    serial: meta.serial,
    totalBytes: space.$1,
    freeBytes: space.$2,
  );
}

/// `GetDriveType` reads what the mount table already knows, so unlike the other
/// volume calls it stays cheap even for a drive that is not ready.
int windowsDriveType(String root) {
  final drive = root.endsWith('\\') ? root : '$root\\';
  final pathPtr = drive.toNativeUtf16();
  try {
    return win32.GetDriveType(win32.PCWSTR(pathPtr));
  } catch (_) {
    return win32.DRIVE_UNKNOWN;
  } finally {
    calloc.free(pathPtr);
  }
}

class _VolumeMeta {
  final String label;
  final String filesystem;
  final String? serial;

  const _VolumeMeta({this.label = '', this.filesystem = '', this.serial});
}

_VolumeMeta _readVolumeInformation(String drive) {
  final volumeNameBuffer = calloc<Uint16>(win32.MAX_PATH + 1).cast<Utf16>();
  final fileSystemNameBuffer = calloc<Uint16>(win32.MAX_PATH + 1).cast<Utf16>();
  final volumeSerialNumber = calloc<Uint32>();
  final maximumComponentLength = calloc<Uint32>();
  final fileSystemFlags = calloc<Uint32>();
  final pathPtr = drive.toNativeUtf16();

  try {
    final ok = win32.GetVolumeInformation(
      win32.PCWSTR(pathPtr),
      win32.PWSTR(volumeNameBuffer),
      win32.MAX_PATH + 1,
      volumeSerialNumber,
      maximumComponentLength,
      fileSystemFlags,
      win32.PWSTR(fileSystemNameBuffer),
      win32.MAX_PATH + 1,
    ).value;
    if (!ok) return const _VolumeMeta();
    return _VolumeMeta(
      label: volumeNameBuffer.toDartString(),
      filesystem: fileSystemNameBuffer.toDartString(),
      serial: volumeSerialNumber.value
          .toRadixString(16)
          .padLeft(8, '0')
          .toUpperCase(),
    );
  } catch (_) {
    return const _VolumeMeta();
  } finally {
    calloc.free(volumeNameBuffer);
    calloc.free(fileSystemNameBuffer);
    calloc.free(volumeSerialNumber);
    calloc.free(maximumComponentLength);
    calloc.free(fileSystemFlags);
    calloc.free(pathPtr);
  }
}

/// Returns `(totalBytes, freeBytes)`, both 0 when the volume cannot answer.
(int, int) _readDiskFreeSpace(String drive) {
  final lpFreeBytesAvailable = calloc<Uint64>();
  final lpTotalNumberOfBytes = calloc<Uint64>();
  final lpTotalNumberOfFreeBytes = calloc<Uint64>();
  final pathPtr = drive.toNativeUtf16();

  try {
    final ok = win32.GetDiskFreeSpaceEx(
      win32.PCWSTR(pathPtr),
      lpFreeBytesAvailable,
      lpTotalNumberOfBytes,
      lpTotalNumberOfFreeBytes,
    ).value;
    if (!ok) return (0, 0);
    return (lpTotalNumberOfBytes.value, lpFreeBytesAvailable.value);
  } catch (_) {
    return (0, 0);
  } finally {
    calloc.free(lpFreeBytesAvailable);
    calloc.free(lpTotalNumberOfBytes);
    calloc.free(lpTotalNumberOfFreeBytes);
    calloc.free(pathPtr);
  }
}

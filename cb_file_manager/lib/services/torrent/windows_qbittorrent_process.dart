import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

final class _ProcessEntry extends Struct {
  @Uint32()
  external int size;
  @Uint32()
  external int usage;
  @Uint32()
  external int processId;
  @UintPtr()
  external int heapId;
  @Uint32()
  external int moduleId;
  @Uint32()
  external int threads;
  @Uint32()
  external int parentId;
  @Int32()
  external int priority;
  @Uint32()
  external int flags;
  @Array(260)
  external Array<Uint16> executable;
}

/// Read-only process inventory. Never starts, closes or kills qBittorrent.
class WindowsQbittorrentProcess {
  static final _kernel = DynamicLibrary.open('kernel32.dll');
  static final _snapshot = _kernel
      .lookupFunction<IntPtr Function(Uint32, Uint32), int Function(int, int)>(
        'CreateToolhelp32Snapshot',
      );
  static final _first = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<_ProcessEntry>),
        int Function(int, Pointer<_ProcessEntry>)
      >('Process32FirstW');
  static final _next = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<_ProcessEntry>),
        int Function(int, Pointer<_ProcessEntry>)
      >('Process32NextW');
  static final _error = _kernel
      .lookupFunction<Uint32 Function(), int Function()>(
        'GetLastError',
        isLeaf: true,
      );
  static final _close = _kernel
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

  static bool isRunning() {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows qBittorrent profiles only');
    }
    // Resolve GetLastError before enumeration: the first lazy DLL lookup can
    // overwrite ERROR_NO_MORE_FILES from Process32NextW.
    _error();
    final snapshot = _snapshot(2, 0); // TH32CS_SNAPPROCESS
    if (snapshot == -1) throw StateError('Cannot check qBittorrent processes');
    final entry = calloc<_ProcessEntry>();
    try {
      entry.ref.size = sizeOf<_ProcessEntry>();
      var found = _first(snapshot, entry);
      while (found != 0) {
        final units = <int>[];
        for (var i = 0; i < 260 && entry.ref.executable[i] != 0; i++) {
          units.add(entry.ref.executable[i]);
        }
        if (String.fromCharCodes(units).toLowerCase().contains('qbittorrent')) {
          return true;
        }
        found = _next(snapshot, entry);
      }
      if (_error() != 18) {
        throw StateError('Cannot finish qBittorrent process check');
      }
      return false;
    } finally {
      calloc.free(entry);
      _close(snapshot);
    }
  }
}

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

// Shell DROPEFFECT flags (not exposed by package:win32).
const _dropEffectCopy = 1;
const _dropEffectMove = 2;

class WindowsFileClipboardSnapshot {
  final int sequence;
  final List<String> paths;
  final bool isCut;

  const WindowsFileClipboardSnapshot({
    required this.sequence,
    required this.paths,
    this.isCut = false,
  });
}

/// Reads Explorer's file clipboard without replacing or taking ownership of it.
class WindowsFileClipboard {
  const WindowsFileClipboard();

  int? get sequenceNumber =>
      Platform.isWindows ? win32.GetClipboardSequenceNumber() : null;

  Future<WindowsFileClipboardSnapshot?> read() async {
    if (!Platform.isWindows) return null;
    // GetClipboardData may ask Explorer to render delayed clipboard data.
    // Keep that work, and retries while another app holds it open, off the UI.
    return Isolate.run(_readClipboard);
  }
}

WindowsFileClipboardSnapshot _readClipboard() {
  for (var attempt = 0; attempt < 10; attempt++) {
    final opened = win32.OpenClipboard(null);
    if (!opened.value) {
      if (attempt == 9) {
        throw OSError(
          'Could not open the Windows file clipboard',
          opened.error,
        );
      }
      sleep(const Duration(milliseconds: 20));
      continue;
    }

    try {
      final paths = <String>[];
      var isCut = false;
      if (win32.IsClipboardFormatAvailable(win32.CF_HDROP).value) {
        final handle = win32.GetClipboardData(win32.CF_HDROP);
        if (handle.value == nullptr) {
          throw OSError(
            'Could not read the Windows file clipboard',
            handle.error,
          );
        }
        final drop = win32.HDROP(handle.value);
        final count = win32.DragQueryFile(drop, 0xffffffff, null, 0);
        for (var index = 0; index < count; index++) {
          final length = win32.DragQueryFile(drop, index, null, 0);
          if (length == 0) {
            throw StateError('Could not read a Windows clipboard file path');
          }
          final buffer = calloc<Uint16>(length + 1).cast<Utf16>();
          try {
            if (win32.DragQueryFile(
                  drop,
                  index,
                  win32.PWSTR(buffer),
                  length + 1,
                ) >
                0) {
              paths.add(buffer.toDartString());
            } else {
              throw StateError('Could not read a Windows clipboard file path');
            }
          } finally {
            calloc.free(buffer);
          }
        }

        final name = 'Preferred DropEffect'.toNativeUtf16();
        try {
          final format = win32.RegisterClipboardFormat(
            win32.PCWSTR(name),
          ).value;
          if (format != 0 && win32.IsClipboardFormatAvailable(format).value) {
            final effect = win32.HGLOBAL(win32.GetClipboardData(format).value);
            if (effect != nullptr && win32.GlobalSize(effect).value >= 4) {
              final data = win32.GlobalLock(effect).value;
              if (data != nullptr) {
                try {
                  final flags = data.cast<Uint32>().value;
                  isCut =
                      flags & _dropEffectMove != 0 &&
                      flags & _dropEffectCopy == 0;
                } finally {
                  win32.GlobalUnlock(effect);
                }
              }
            }
          }
        } finally {
          calloc.free(name);
        }
      }
      return WindowsFileClipboardSnapshot(
        sequence: win32.GetClipboardSequenceNumber(),
        paths: paths.toSet().toList(growable: false),
        isCut: isCut,
      );
    } finally {
      // Clipboard handles belong to Windows; do not GlobalFree or DragFinish.
      win32.CloseClipboard();
    }
  }
  throw StateError('Could not read the Windows file clipboard');
}

import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

/// Run Shell deletion away from the UI isolate so progress can keep animating.
Future<void> emptyWindowsRecycleBinNative() => Isolate.run(() {
  final comInit = win32.CoInitializeEx(
    win32.COINIT(win32.COINIT_APARTMENTTHREADED | win32.COINIT_DISABLE_OLE1DDE),
  );
  if (comInit.isError) throw win32.WindowsException(comInit);
  final info = calloc<win32.SHQUERYRBINFO>();
  try {
    info.ref.cbSize = sizeOf<win32.SHQUERYRBINFO>();
    bool isEmpty() {
      try {
        win32.SHQueryRecycleBin(null, info);
        return info.ref.i64NumItems == 0;
      } on win32.WindowsException {
        return false;
      }
    }

    // Some Shell versions report an error when the bin is already empty.
    if (isEmpty()) return;
    try {
      win32.SHEmptyRecycleBin(
        null,
        null,
        win32.SHERB_NOCONFIRMATION |
            win32.SHERB_NOPROGRESSUI |
            win32.SHERB_NOSOUND,
      );
    } on win32.WindowsException {
      // A partial Shell failure may still have removed every item.
      if (!isEmpty()) rethrow;
    }
  } finally {
    calloc.free(info);
    if (comInit.isOk) win32.CoUninitialize();
  }
});

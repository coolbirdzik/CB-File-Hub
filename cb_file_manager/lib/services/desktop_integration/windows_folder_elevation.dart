import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win32;

import 'folder_launch_request.dart';

class WindowsFolderElevation {
  static const _openFolderFlag = '--open-folder-as-administrator';
  static bool _requestInProgress = false;
  static bool _isFolderWindow = false;

  static final bool isElevated = Platform.isWindows && _hasElevatedToken();
  static bool get isFolderWindow => _isFolderWindow;

  static String? takeStartupPath(List<String> args) {
    if (!Platform.isWindows ||
        args.length != 2 ||
        args.first != _openFolderFlag) {
      return null;
    }
    final location = args.last;
    args.clear();
    if (!isElevated) return null;
    _isFolderWindow = true;
    try {
      return FolderLaunchRequest.normalizeLocation(location);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  static Future<void> open(String path) async {
    if (!Platform.isWindows || isElevated || _requestInProgress) return;
    // A file URI preserves spaces, Unicode, percent signs and trailing slashes
    // as one Windows argument, including when reopening a drive root.
    final parameters = '$_openFolderFlag ${Uri.directory(path, windows: true)}';
    _requestInProgress = true;
    try {
      await Isolate.run(() => _requestElevation(parameters));
    } finally {
      _requestInProgress = false;
    }
  }

  static bool _hasElevatedToken() => using((arena) {
    final tokenElevation = arena<win32.TOKEN_ELEVATION>();
    final returnLength = arena<Uint32>();
    final token = win32.HANDLE(
      Pointer.fromAddress(win32.GetCurrentProcessToken()),
    );
    final result = win32.GetTokenInformation(
      token,
      win32.TokenElevation,
      tokenElevation,
      sizeOf<win32.TOKEN_ELEVATION>(),
      returnLength,
    );
    return result.value && tokenElevation.ref.TokenIsElevated != 0;
  });

  static void _requestElevation(String parameters) {
    final com = win32.CoInitializeEx(
      win32.COINIT(win32.COINIT_APARTMENTTHREADED),
    );
    try {
      using((arena) {
        const seeMaskNoAsync = 0x00000100;
        const seeMaskFlagNoUi = 0x00000400;
        final executable = Platform.resolvedExecutable;
        final info = arena<win32.SHELLEXECUTEINFO>();
        info.ref
          ..cbSize = sizeOf<win32.SHELLEXECUTEINFO>()
          ..fMask = seeMaskNoAsync | seeMaskFlagNoUi
          ..lpVerb = win32.PWSTR('runas'.toNativeUtf16(allocator: arena))
          ..lpFile = win32.PWSTR(executable.toNativeUtf16(allocator: arena))
          ..lpParameters = win32.PWSTR(
            parameters.toNativeUtf16(allocator: arena),
          )
          ..lpDirectory = win32.PWSTR(
            p.dirname(executable).toNativeUtf16(allocator: arena),
          )
          ..nShow = win32.SW_SHOWNORMAL;
        final result = win32.ShellExecuteEx(info);
        if (!result.value && result.error != win32.ERROR_CANCELLED) {
          throw win32.WindowsException(result.error.toHRESULT());
        }
      });
    } finally {
      if (com.isOk) win32.CoUninitialize();
    }
  }
}

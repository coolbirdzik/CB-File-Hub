import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart' as win32;

import '../../helpers/files/windows_shell_context_menu.dart';
import 'android_storage_volumes.dart';
import 'drive_info.dart';
import 'drive_inventory_service.dart';

/// Platform drive actions used by DriveView menus/sheets.
class DriveActions {
  DriveActions._();

  static Future<bool> eject(DriveInfo drive) async {
    if (!drive.canEject || drive.isSystemVolume) return false;

    if (Platform.isWindows) {
      return _ejectWindows(drive.path);
    }
    if (Platform.isAndroid) {
      final ok = await AndroidStorageVolumes.ejectVolume(
        path: drive.path,
        uuid: drive.uuid,
      );
      if (ok) DriveInventoryService.invalidateCache();
      return ok;
    }
    return false;
  }

  static Future<bool> rename(DriveInfo drive, String newLabel) async {
    final label = newLabel.trim();
    if (!drive.canRename || drive.isSystemVolume) return false;
    if (label.isEmpty || label.length > 32) return false;

    if (Platform.isWindows) {
      final ok = await _renameWindows(drive.path, label);
      if (ok) DriveInventoryService.invalidateCache();
      return ok;
    }
    if (Platform.isAndroid) {
      final ok = await AndroidStorageVolumes.renameVolume(
        path: drive.path,
        label: label,
        uuid: drive.uuid,
      );
      if (ok) DriveInventoryService.invalidateCache();
      return ok;
    }
    return false;
  }

  static Future<bool> openFormat(DriveInfo drive) async {
    if (!Platform.isWindows || drive.isSystemVolume) return false;
    final root = DriveInfo.normalizeWindowsRoot(drive.path);
    try {
      final invoked = await WindowsShellContextMenu.invokeVerb(
        paths: <String>[root],
        verb: 'format',
      );
      if (invoked) return true;

      final escaped = root.replaceAll("'", "''");
      await Process.start(
        'powershell.exe',
        <String>[
          '-NoProfile',
          '-Command',
          "Start-Process -FilePath '$escaped' -Verb Format",
        ],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (e) {
      debugPrint('DriveActions.openFormat failed: $e');
      return false;
    }
  }

  static Future<bool> openCleanup(String drivePath) async {
    if (!Platform.isWindows) return false;
    try {
      final letter = drivePath.replaceAll('\\', '').replaceAll('/', '');
      await Process.start(
        'cleanmgr.exe',
        <String>['/d', letter],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (e) {
      debugPrint('DriveActions.openCleanup failed: $e');
      return false;
    }
  }

  static Future<bool> openTerminal(String drivePath) async {
    if (!Platform.isWindows) return false;
    try {
      await Process.start(
        'wt.exe',
        <String>['-d', drivePath],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (_) {
      try {
        await Process.start(
          'powershell.exe',
          <String>[
            '-NoExit',
            '-Command',
            "Set-Location -LiteralPath '${drivePath.replaceAll("'", "''")}'",
          ],
          mode: ProcessStartMode.detached,
        );
        return true;
      } catch (e) {
        debugPrint('DriveActions.openTerminal failed: $e');
        return false;
      }
    }
  }

  static Future<bool> openBitLocker() async {
    if (!Platform.isWindows) return false;

    Future<bool> tryStart(
      String executable,
      List<String> arguments, {
      bool runInShell = false,
    }) async {
      try {
        await Process.start(
          executable,
          arguments,
          mode: ProcessStartMode.detached,
          runInShell: runInShell,
        );
        return true;
      } catch (_) {
        return false;
      }
    }

    if (await tryStart(
      'control.exe',
      <String>['/name', 'Microsoft.BitLockerDriveEncryption'],
    )) {
      return true;
    }
    if (await tryStart('cmd.exe', <String>[
      '/c',
      'start',
      '',
      'control.exe',
      '/name',
      'Microsoft.BitLockerDriveEncryption',
    ])) {
      return true;
    }
    return tryStart(
      'cmd.exe',
      <String>['/c', 'start', '', 'ms-settings:deviceencryption'],
      runInShell: true,
    );
  }

  static Future<bool> _ejectWindows(String drivePath) async {
    final root = DriveInfo.normalizeWindowsRoot(drivePath);
    try {
      final invoked = await WindowsShellContextMenu.invokeVerb(
        paths: <String>[root],
        verb: 'eject',
      );
      if (invoked) {
        DriveInventoryService.invalidateCache();
        return true;
      }
    } catch (e) {
      debugPrint('DriveActions shell eject failed: $e');
    }

    // Shell.Application Namespace(17) = My Computer; InvokeVerb('Eject').
    final letter = root.substring(0, 2); // e.g. E:
    try {
      await Process.run(
        'powershell.exe',
        <String>[
          '-NoProfile',
          '-Command',
          "\$shell = New-Object -ComObject Shell.Application; "
              "\$item = \$shell.Namespace(17).ParseName('$letter'); "
              "if (\$null -eq \$item) { exit 2 }; "
              "\$item.InvokeVerb('Eject');",
        ],
      ).timeout(const Duration(seconds: 15));
      DriveInventoryService.invalidateCache();
      return true;
    } catch (e) {
      debugPrint('DriveActions powershell eject failed: $e');
      return false;
    }
  }

  static Future<bool> _renameWindows(String drivePath, String label) async {
    final root = DriveInfo.normalizeWindowsRoot(drivePath);
    final rootPtr = root.toNativeUtf16();
    final labelPtr = label.toNativeUtf16();
    try {
      final ok = win32.SetVolumeLabel(rootPtr, labelPtr);
      return ok != 0;
    } catch (e) {
      debugPrint('DriveActions.SetVolumeLabel failed: $e');
      return false;
    } finally {
      calloc.free(rootPtr);
      calloc.free(labelPtr);
    }
  }
}

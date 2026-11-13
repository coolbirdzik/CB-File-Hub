import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/drive/drive_actions.dart';
import 'package:cb_file_manager/services/drive/drive_info.dart';
import 'package:cb_file_manager/services/drive/windows_wsl_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<int> utf16(String value, {bool bom = false}) => [
    if (bom) ...[0xff, 0xfe],
    for (final unit in value.codeUnits) ...[unit & 0xff, unit >> 8],
  ];

  test(
    'reads actual redirected WSL UTF-16 output with and without a BOM',
    () async {
      for (final bom in [false, true]) {
        final drives = await WindowsWslInventory.load(
          listDistributions: () async => ProcessResult(
            1,
            0,
            utf16('Debian\r\nUbuntu-24.04\r\n', bom: bom),
            [],
          ),
        );
        expect(drives.map((d) => d.displayName), ['Debian', 'Ubuntu-24.04']);
        expect(drives.first.path, '\\\\wsl.localhost\\Debian\\');
        expect(drives.first.kind, DriveKind.wsl);
        expect(drives.first.group, DriveGroup.wsl);
        expect(drives.first.space.hasDetails, isFalse);
        expect(drives.first.canEject, isFalse);
        expect(drives.first.canRename, isFalse);
        expect(drives.first.isWindowsVolume, isFalse);
      }
    },
  );

  test(
    'UTF-8 names, empty lines and repeated distributions are handled',
    () async {
      final drives = await WindowsWslInventory.load(
        listDistributions: () async => ProcessResult(
          1,
          0,
          utf8.encode('\ufeffDebian\n\nDebian\n开发环境\n'),
          [],
        ),
      );
      expect(drives.map((d) => d.displayName), ['Debian', '开发环境']);
      expect(
        WindowsWslInventory.parseNames('..\n.\nBad/Name\nBad\\Name\nDebian'),
        ['Debian'],
      );
    },
  );

  test(
    'unavailable WSL and command failures leave the other drive inventory usable',
    () async {
      expect(
        await WindowsWslInventory.load(
          listDistributions: () async =>
              ProcessResult(1, 1, 'WSL unavailable', ''),
        ),
        isEmpty,
      );
      expect(
        await WindowsWslInventory.load(
          listDistributions: () async =>
              throw const ProcessException('wsl.exe', []),
        ),
        isEmpty,
      );
      expect(
        await WindowsWslInventory.load(
          listDistributions: () async => throw TimeoutException('WSL'),
        ),
        isEmpty,
      );
    },
  );

  test('WSL shares cannot be sent to Windows volume formatting', () async {
    const drive = DriveInfo(
      path: '\\\\wsl.localhost\\Debian\\',
      displayName: 'Debian',
      kind: DriveKind.wsl,
    );
    expect(await DriveActions.openFormat(drive), isFalse);
    expect(
      const DriveInfo(path: 'C:\\', displayName: 'Windows').isWindowsVolume,
      isTrue,
    );
  });
}

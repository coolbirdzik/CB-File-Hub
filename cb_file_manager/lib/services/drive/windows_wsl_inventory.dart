import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'drive_info.dart';

/// Enumerates registered distros without opening their shares or starting Linux.
/// WSL's redirected output is normally UTF-16LE, unlike most Windows commands.
abstract final class WindowsWslInventory {
  static const timeout = Duration(seconds: 4);

  static Future<List<DriveInfo>> load({
    Future<ProcessResult> Function()? listDistributions,
  }) async {
    if (!Platform.isWindows && listDistributions == null) return const [];
    try {
      final result = await (listDistributions ?? _list)();
      if (result.exitCode != 0) return const [];
      final output = result.stdout;
      final names = parseNames(
        output is String ? output : decodeOutput(output as List<int>),
      );
      return [
        for (final name in names)
          DriveInfo(
            path: '\\\\wsl.localhost\\$name\\',
            displayName: name,
            label: name,
            kind: DriveKind.wsl,
            filesystem: 'WSL',
          ),
      ];
    } on ProcessException {
      return const [];
    } on TimeoutException {
      return const [];
    }
  }

  static Future<ProcessResult> _list() async {
    final process = await Process.start('wsl.exe', const ['--list', '--quiet']);
    final stdout = process.stdout.fold<List<int>>(
      [],
      (buffer, bytes) => buffer..addAll(bytes),
    );
    final stderr = process.stderr.fold<List<int>>(
      [],
      (buffer, bytes) => buffer..addAll(bytes),
    );
    try {
      final results = await Future.wait<Object>([
        process.exitCode,
        stdout,
        stderr,
      ]).timeout(timeout);
      return ProcessResult(
        process.pid,
        results[0] as int,
        results[1],
        results[2],
      );
    } on TimeoutException {
      process.kill();
      rethrow;
    }
  }

  static String decodeOutput(List<int> bytes) {
    final littleBom = bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe;
    final bigBom = bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff;
    if (littleBom || bigBom || bytes.contains(0)) {
      final offset = littleBom || bigBom ? 2 : 0;
      return String.fromCharCodes([
        for (var i = offset; i + 1 < bytes.length; i += 2)
          bigBom
              ? (bytes[i] << 8) | bytes[i + 1]
              : bytes[i] | (bytes[i + 1] << 8),
      ]);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static List<String> parseNames(String output) {
    final names = <String, String>{};
    for (final line in const LineSplitter().convert(
      output.replaceAll('\ufeff', ''),
    )) {
      final name = line.trim();
      if (name.isEmpty ||
          name == '.' ||
          name == '..' ||
          name.contains(RegExp(r'[\\/\x00-\x1f:*?"<>|]'))) {
        continue;
      }
      names.putIfAbsent(name.toLowerCase(), () => name);
    }
    return names.values.toList();
  }
}

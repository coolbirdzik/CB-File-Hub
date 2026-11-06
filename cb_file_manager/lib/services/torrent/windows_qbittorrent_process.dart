import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Read-only process inventory. Never starts, closes or kills qBittorrent.
class WindowsQbittorrentProcess {
  static Future<bool> isRunning({
    Future<ProcessResult> Function(String, List<String>)? runProcess,
  }) async {
    if (!Platform.isWindows && runProcess == null) {
      throw UnsupportedError('Windows qBittorrent profiles only');
    }
    final systemRoot =
        Platform.environment['SystemRoot'] ?? Platform.environment['WINDIR'];
    final executable = systemRoot == null
        ? 'tasklist.exe'
        : p.join(systemRoot, 'System32', 'tasklist.exe');
    // Toolhelp's last-error value cannot safely cross a Dart/VM FFI transition.
    // Read the native utility's exit code and CSV instead, off the UI thread.
    final result = await (runProcess ?? _runTasklist)(executable, const [
      '/FO',
      'CSV',
      '/NH',
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'Cannot check qBittorrent processes: tasklist exited '
                '${result.exitCode}. ${result.stderr}'
            .trim(),
      );
    }
    var rows = 0;
    final image = RegExp(r'^"([^"]+)","[0-9]+"(?:,|$)');
    for (final line in const LineSplitter().convert('${result.stdout}')) {
      final row = line.replaceFirst('\uFEFF', '').trim();
      if (row.isEmpty) continue;
      final match = image.firstMatch(row);
      if (match == null) {
        throw StateError('Cannot read the Windows process inventory.');
      }
      rows++;
      if (match.group(1)!.toLowerCase().contains('qbittorrent')) return true;
    }
    if (rows == 0) {
      throw StateError('The Windows process inventory is empty.');
    }
    return false;
  }

  static Future<ProcessResult> _runTasklist(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(executable, arguments);
    await process.stdin.close();
    final output = process.stdout.transform(systemEncoding.decoder).join();
    final errors = process.stderr.transform(systemEncoding.decoder).join();
    try {
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 15),
      );
      return ProcessResult(process.pid, exitCode, await output, await errors);
    } on TimeoutException {
      // This is only our inventory helper, never the user's torrent client.
      process.kill();
      await process.exitCode;
      await Future.wait([output, errors]);
      throw StateError('Windows process inventory timed out.');
    }
  }
}

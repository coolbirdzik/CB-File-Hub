import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/services/torrent/windows_qbittorrent_process.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<bool> inventory(String output, {int exitCode = 0}) =>
      WindowsQbittorrentProcess.isRunning(
        runProcess: (executable, arguments) async {
          expect(executable.toLowerCase(), endsWith('tasklist.exe'));
          expect(arguments, ['/FO', 'CSV', '/NH']);
          return ProcessResult(
            1,
            exitCode,
            output,
            exitCode == 0 ? '' : 'access denied',
          );
        },
      );

  test('detects qBittorrent image names regardless of case', () async {
    expect(
      await inventory(
        '"System Idle Process","0","Services"\r\n'
        '"QBITTORRENT.EXE","123","Console"\r\n',
      ),
      isTrue,
    );
    expect(await inventory('"qbittorrent-nox.exe","123","Console"'), isTrue);
  });

  test(
    'checks only the image name and accepts localized session columns',
    () async {
      expect(
        await inventory(
          '\uFEFF"explorer.exe","123","qbittorrent"\r\n'
          '"other.exe","456","Phiên người dùng"\r\n',
        ),
        isFalse,
      );
    },
  );

  test('command failure never reports that cleanup is safe', () async {
    await expectLater(inventory('', exitCode: 5), throwsStateError);
    await expectLater(
      inventory('"qbittorrent.exe","123"', exitCode: 1),
      throwsStateError,
    );
  });

  test(
    'empty and malformed inventory never report that cleanup is safe',
    () async {
      for (final output in [
        '',
        '\r\n',
        'unreadable process inventory',
        '"explorer.exe","123"\ncorrupt row',
      ]) {
        await expectLater(inventory(output), throwsStateError);
      }
    },
  );

  test('waiting for the OS inventory does not block the caller', () async {
    final gate = Completer<ProcessResult>();
    final running = WindowsQbittorrentProcess.isRunning(
      runProcess: (_, _) => gate.future,
    );
    var completed = false;
    unawaited(running.then((_) => completed = true));
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    gate.complete(ProcessResult(1, 0, '"explorer.exe","123"', ''));
    expect(await running, isFalse);
  });
}

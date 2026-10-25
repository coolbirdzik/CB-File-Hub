import 'dart:io';

import 'package:cb_file_manager/services/app_insights/app_leftover_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Sets the write and creation time of everything under [root], and of
/// [root] itself. Creation time cannot be set through dart:io, so this is
/// Windows only.
void _ageWindows(Directory root, DateTime when) {
  final result = Process.runSync('powershell.exe', <String>[
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    "\$t = [DateTime]::Parse('${when.toIso8601String()}'); "
        "Get-ChildItem -LiteralPath '${root.path}' -Recurse -Force | "
        'ForEach-Object { \$_.CreationTime = \$t; \$_.LastWriteTime = \$t }; '
        "\$r = Get-Item -LiteralPath '${root.path}'; "
        '\$r.CreationTime = \$t; \$r.LastWriteTime = \$t',
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cb_leftover_measure_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File write(String relative, [String content = 'x']) {
    return File(p.join(root.path, relative))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  test('reports the newest file however deep, relative to the folder', () {
    write('old.txt');
    write(p.join('deep', 'er', 'newest.dat'));
    // Far in the future so it beats every timestamp created just now.
    File(
      p.join(root.path, 'deep', 'er', 'newest.dat'),
    ).setLastModifiedSync(DateTime.now().add(const Duration(days: 30)));

    final measurement = measureAppLeftoverSync(root.path, 1000);

    expect(measurement.newestEntry, p.join('deep', 'er', 'newest.dat'));
    expect(
      measurement.lastModified!.isAfter(
        DateTime.now().add(const Duration(days: 29)),
      ),
      isTrue,
    );
    expect(measurement.fileCount, 2);
    expect(measurement.isComplete, isTrue);
  });

  test('a file copied in with an old write time still counts as recent', () {
    final file = write('restored.dat');
    file.setLastModifiedSync(
      DateTime.now().subtract(const Duration(days: 900)),
    );

    final measurement = measureAppLeftoverSync(root.path, 1000);

    // Creation time (change time off Windows) is new even though the write
    // time is old, so the folder was touched recently.
    expect(
      DateTime.now().difference(measurement.lastModified!).inDays,
      lessThan(2),
    );
  });

  test('stops at the entry budget and says the result is partial', () {
    for (var i = 0; i < 5; i++) {
      write('file$i.txt');
    }
    expect(measureAppLeftoverSync(root.path, 2).isComplete, isFalse);
  });

  group('on Windows', () {
    final old = DateTime.now().subtract(const Duration(days: 400));

    test('an untouched tree is reported as old', () {
      write('a.txt');
      write(p.join('sub', 'b.txt'));
      _ageWindows(root, old);

      final measurement = measureAppLeftoverSync(root.path, 1000);

      expect(
        DateTime.now().difference(measurement.lastModified!).inDays,
        inInclusiveRange(398, 402),
      );
    });

    test('deleting a file changes the folder itself, which counts', () {
      write('a.txt');
      write('b.txt');
      write(p.join('sub', 'c.txt'));
      _ageWindows(root, old);
      // Every remaining file is still old; only the folder's own time moved.
      File(p.join(root.path, 'b.txt')).deleteSync();

      final measurement = measureAppLeftoverSync(root.path, 1000);

      expect(
        DateTime.now().difference(measurement.lastModified!).inDays,
        lessThan(2),
      );
      expect(measurement.newestEntry, isNull, reason: 'the folder itself');
    });

    test('a missing folder has no date', () {
      final measurement = measureAppLeftoverSync(p.join(root.path, 'nope'), 10);
      expect(measurement.lastModified, isNull);
      expect(measurement.isComplete, isFalse);
    });
  }, skip: Platform.isWindows ? false : 'needs to set creation times');
}

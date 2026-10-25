@TestOn('windows')
library;

import 'dart:io';

import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/app_insights/app_leftover_finder.dart';
import 'package:cb_file_manager/services/app_insights/app_leftover_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Map<String, String> environment;

  const apps = <InstalledAppInfo>[
    InstalledAppInfo(
      id: 'editor',
      displayName: 'Acme Editor',
      publisher: 'Acme Inc',
      source: InstalledAppSource.win32,
    ),
  ];

  File write(String relative, String content) {
    return File('${root.path}\\$relative')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('cb_leftover_scan_');
    final local = '${root.path}\\Users\\me\\AppData\\Local';
    environment = <String, String>{
      'LOCALAPPDATA': local,
      'APPDATA': '${root.path}\\Users\\me\\AppData\\Roaming',
      'PROGRAMDATA': '${root.path}\\ProgramData',
    };
    write(r'Users\me\AppData\Local\OldGame\save.dat', 'x' * 2048);
    write(r'Users\me\AppData\Local\OldGame\sub\more.dat', 'y' * 1024);
    write(r'Users\me\AppData\Local\AcmeEditor\settings.json', '{}');
    write(r'Users\me\AppData\Local\Temp\junk.tmp', 'z');
    write(r'Users\me\AppData\Roaming\Forgotten\a.txt', 'a');
    write(r'ProgramData\OldVendor\b.txt', 'b');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('lists base folders and keeps their real casing', () {
    final bases = AppLeftoverFinder.baseDirectories(environment);
    expect(bases, contains(environment['LOCALAPPDATA']));
    expect(bases, contains('${environment['LOCALAPPDATA']}\\Programs'));
    expect(bases, contains('${root.path}\\Users\\me\\AppData\\LocalLow'));
  });

  test('discovers unmatched folders from the filesystem', () async {
    final report = await const AppLeftoverScanner().discover(
      inventory: const AppLeftoverInventory(apps: apps),
      environment: environment,
      operatingSystem: 'windows',
    );
    final names = report.candidates.map((c) => c.displayName).toSet();

    expect(names, containsAll(<String>['OldGame', 'Forgotten', 'OldVendor']));
    expect(names, isNot(contains('AcmeEditor')));
    expect(names, isNot(contains('Temp')));
    expect(
      report.candidates.firstWhere((c) => c.displayName == 'OldGame').path,
      '${environment['LOCALAPPDATA']}\\OldGame',
    );
  });

  test('streams one measurement per folder', () async {
    final oldGame = '${environment['LOCALAPPDATA']}\\OldGame';
    final forgotten = '${environment['APPDATA']}\\Forgotten';
    final job = await const AppLeftoverScanner().measure(<String>[
      oldGame,
      forgotten,
    ]);
    final results = await job.results.toList();

    expect(results.map((r) => r.$1), <String>[oldGame, forgotten]);
    final game = results.first.$2;
    expect(game.sizeBytes, 3072);
    expect(game.fileCount, 2);
    expect(game.isComplete, isTrue);
    expect(game.lastModified, isNotNull);
  });

  test('a cancelled job stops streaming', () async {
    final job = await const AppLeftoverScanner().measure(<String>[
      '${environment['LOCALAPPDATA']}\\OldGame',
    ]);
    job.cancel();
    expect(await job.results.toList(), hasLength(lessThanOrEqualTo(1)));
  });

  test('a missing folder is measured as incomplete', () {
    final measurement = measureAppLeftoverSync('${root.path}\\missing', 100);
    expect(measurement.isComplete, isFalse);
    expect(measurement.sizeBytes, 0);
  });
}

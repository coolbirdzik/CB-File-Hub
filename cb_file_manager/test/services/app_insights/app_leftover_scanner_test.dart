@TestOn('windows')
library;

import 'dart:io';

import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/app_insights/app_leftover_finder.dart';
import 'package:cb_file_manager/services/app_insights/app_leftover_scanner.dart';
import 'package:cb_file_manager/services/app_insights/windows_leftover_presence.dart';
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

  test('normal discovery does not report portable executable folders', () {
    write(r'Users\me\AppData\Local\PortableApp\bin\app.exe', 'exe');
    write(r'Users\me\AppData\Local\Programs\MiniEditor\editor.exe', 'exe');
    write(r'Users\me\AppData\Local\ScriptEditor\launch.cmd', 'echo off');
    write(r'Users\me\AppData\Local\RemovedTool\unins000.exe', 'exe');
    write(r'Users\me\AppData\Local\RemovedTool\cache.dat', 'cache');
    final report = discoverAppLeftoversSync(
      apps: apps,
      environment: environment,
    );
    final names = report.candidates.map((candidate) => candidate.displayName);
    expect(names, isNot(contains('PortableApp')));
    expect(names, isNot(contains('MiniEditor')));
    expect(names, isNot(contains('ScriptEditor')));
    expect(names, contains('RemovedTool'));
    expect(names, contains('OldGame'));
  });

  for (final useNative in [true, false]) {
    test('deep discovery finds portable apps outside examined data roots '
        '(native: $useNative)', () {
      final otherRoot = Directory.systemTemp.createTempSync(
        'cb_portable_apps_',
      );
      addTearDown(() => otherRoot.deleteSync(recursive: true));
      write(r'Users\me\AppData\Local\OpticPlayer\settings.json', '{}');
      write(r'Users\me\AppData\Roaming\com.vendor.ScriptTool\config', '{}');
      write(r'Users\me\AppData\Roaming\NewBrowser\settings.json', '{}');
      File('${otherRoot.path}\\Tools\\OpticPlayer (Portable)\\bin\\client.exe')
        ..createSync(recursive: true)
        ..writeAsStringSync('exe');
      File('${otherRoot.path}\\Renamed\\ScriptTool.cmd')
        ..createSync(recursive: true)
        ..writeAsStringSync('echo off');
      File('${otherRoot.path}\\NewBrowser (64-bit)\\launcher.exe')
        ..createSync(recursive: true)
        ..writeAsStringSync('exe');
      environment['PATH'] = '${otherRoot.path}\\Renamed';

      final normal = discoverAppLeftoversSync(
        apps: apps,
        environment: environment,
      );
      final normalNames = normal.candidates.map(
        (candidate) => candidate.displayName,
      );
      expect(
        normalNames,
        containsAll(['OpticPlayer', 'com.vendor.ScriptTool', 'NewBrowser']),
      );
      final deep = discoverAppLeftoversSync(
        apps: apps,
        environment: environment,
        deepScan: true,
        deepSearchRoots: [otherRoot.path],
        useNative: useNative,
      );
      final deepNames = deep.candidates.map(
        (candidate) => candidate.displayName,
      );
      expect(deepNames, isNot(contains('OpticPlayer')));
      expect(deepNames, isNot(contains('com.vendor.ScriptTool')));
      expect(deepNames, isNot(contains('NewBrowser')));
      expect(deepNames, containsAll(['OldGame', 'Forgotten', 'OldVendor']));
      expect(deep.isPartial, isFalse);
    });

    test('deep presence does not mistake a newer for an older app version '
        '(native: $useNative)', () {
      final candidateFolder = Directory(
        '${root.path}\\EditorData\\AcmeEditor2021.3',
      )..createSync(recursive: true);
      final externalRoot = Directory('${root.path}\\Portable')
        ..createSync(recursive: true);
      write(r'Portable\AcmeEditor2024.1\AcmeEditor.exe', 'exe');
      final candidate = AppLeftoverCandidate(
        path: candidateFolder.path,
        displayName: 'AcmeEditor2021.3',
        location: AppLeftoverLocation.localAppData,
        reason: AppLeftoverReason.olderVersion,
        sizeBytes: 0,
      );
      final newerOnly = verifyWindowsLeftoverPresence(
        candidates: [candidate],
        environment: environment,
        deepScan: true,
        deepSearchRoots: [externalRoot.path],
        useNative: useNative,
      );
      expect(newerOnly.candidates, [candidate]);
      write(r'Portable\AcmeEditor-v2021.3.1 (Portable)\AcmeEditor.exe', 'exe');
      final oldPatchPresent = verifyWindowsLeftoverPresence(
        candidates: [candidate],
        environment: environment,
        deepScan: true,
        deepSearchRoots: [externalRoot.path],
        useNative: useNative,
      );
      expect(oldPatchPresent.candidates, isEmpty);
    });
  }

  test('deep presence searches roots on different disks at the same time', () {
    final first = Directory('${root.path}\\DiskOne')..createSync();
    final second = Directory('${root.path}\\DiskTwo')..createSync();
    write(r'DiskOne\Games\Unrelated\game.exe', 'exe');
    write(r'DiskTwo\Tools\OldVendor\vendor.exe', 'exe');
    AppLeftoverCandidate candidate(String name) => AppLeftoverCandidate(
      path: '${root.path}\\Data\\$name',
      displayName: name,
      location: AppLeftoverLocation.localAppData,
      reason: AppLeftoverReason.noInstalledApp,
      sizeBytes: 0,
    );
    for (final name in ['OldVendor', 'Forgotten']) {
      Directory('${root.path}\\Data\\$name').createSync(recursive: true);
    }
    final candidates = [candidate('OldVendor'), candidate('Forgotten')];

    final events = <AppLeftoverScanProgress>[];
    final together = verifyWindowsLeftoverPresence(
      candidates: candidates,
      environment: environment,
      deepScan: true,
      deepSearchRoots: [first.path, second.path],
      groupByDisk: false,
      onProgress: events.add,
    );
    final oneByOne = verifyWindowsLeftoverPresence(
      candidates: candidates,
      environment: environment,
      deepScan: true,
      deepSearchRoots: [first.path, second.path],
      useNative: false,
    );

    // The executable in the second root still protects its folder.
    expect(together.candidates.map((c) => c.displayName), ['Forgotten']);
    expect(together.isPartial, isFalse);
    expect(
      oneByOne.candidates.map((c) => c.displayName),
      together.candidates.map((c) => c.displayName),
    );
    final drives = events
        .where((e) => e.stage == AppLeftoverScanStage.searchingDrive)
        .toList();
    expect(drives.first.root, '${first.path}, ${second.path}');
    expect(drives.first.total, 2);
  });

  test(
    'unreadable candidate or exhausted local evidence budget is withheld',
    () {
      final missing = AppLeftoverCandidate(
        path: '${root.path}\\Missing',
        displayName: 'Missing',
        location: AppLeftoverLocation.localAppData,
        reason: AppLeftoverReason.noInstalledApp,
        sizeBytes: 0,
      );
      final tooLarge = AppLeftoverCandidate(
        path: '${environment['LOCALAPPDATA']}\\OldGame',
        displayName: 'OldGame',
        location: AppLeftoverLocation.localAppData,
        reason: AppLeftoverReason.noInstalledApp,
        sizeBytes: 0,
      );
      final result = verifyWindowsLeftoverPresence(
        candidates: [missing, tooLarge],
        environment: environment,
        deepScan: false,
        maxCandidateEntries: 1,
      );
      expect(result.candidates, isEmpty);
      expect(result.isPartial, isTrue);
    },
  );

  for (final useNative in [true, false]) {
    test('bounded deep discovery reports incomplete coverage '
        '(native: $useNative)', () {
      final report = discoverAppLeftoversSync(
        apps: apps,
        environment: environment,
        deepScan: true,
        deepSearchRoots: [root.path],
        maxDeepEntriesPerRoot: 1,
        useNative: useNative,
      );
      expect(report.isPartial, isTrue);
      expect(report.candidates, isNotEmpty);
    });
  }

  test('deep discovery reports which folder and drive it is reading', () {
    final otherRoot = Directory.systemTemp.createTempSync('cb_progress_walk_');
    addTearDown(() => otherRoot.deleteSync(recursive: true));
    File('${otherRoot.path}\\Tools\\Unrelated\\tool.exe')
      ..createSync(recursive: true)
      ..writeAsStringSync('exe');
    final events = <AppLeftoverScanProgress>[];
    final withProgress = discoverAppLeftoversSync(
      apps: apps,
      environment: environment,
      deepScan: true,
      deepSearchRoots: [otherRoot.path],
      onProgress: events.add,
    );
    final without = discoverAppLeftoversSync(
      apps: apps,
      environment: environment,
      deepScan: true,
      deepSearchRoots: [otherRoot.path],
    );

    expect(
      withProgress.candidates.map((c) => c.path),
      without.candidates.map((c) => c.path),
    );
    final stages = events.map((e) => e.stage).toList();
    expect(
      stages,
      containsAllInOrder(<AppLeftoverScanStage>[
        AppLeftoverScanStage.listingFolders,
        AppLeftoverScanStage.checkingCandidates,
        AppLeftoverScanStage.searchingDrive,
      ]),
    );
    final drive = events.firstWhere(
      (e) => e.stage == AppLeftoverScanStage.searchingDrive,
    );
    expect(drive.root, otherRoot.path);
    expect(drive.path, startsWith(otherRoot.path));
    expect(drive.total, 1);
    final listing = events.firstWhere(
      (e) => e.stage == AppLeftoverScanStage.listingFolders,
    );
    expect(listing.path, startsWith(root.path));
  });

  test('progress ticks do not end discovery or measuring jobs', () async {
    final discoveryEvents = <AppLeftoverScanProgress>[];
    final job = await const AppLeftoverScanner().startDiscovery(
      inventory: const AppLeftoverInventory(apps: apps),
      environment: environment,
      operatingSystem: 'windows',
      onProgress: discoveryEvents.add,
    );
    final report = await job.result;
    expect(report, isNotNull);
    expect(report!.candidates, isNotEmpty);
    expect(discoveryEvents, isNotEmpty);

    final oldGame = '${environment['LOCALAPPDATA']}\\OldGame';
    final forgotten = '${environment['APPDATA']}\\Forgotten';
    final measureEvents = <AppLeftoverScanProgress>[];
    final measure = await const AppLeftoverScanner().measure(<String>[
      oldGame,
      forgotten,
    ], onProgress: measureEvents.add);
    final results = await measure.results.toList();
    expect(results.map((r) => r.$1), <String>[oldGame, forgotten]);
    expect(measureEvents.map((e) => (e.path, e.done, e.total)), [
      (oldGame, 0, 2),
      (forgotten, 1, 2),
    ]);
  });

  test(
    'cancelling discovery resolves its result without waiting for a walk',
    () async {
      final job = await const AppLeftoverScanner().startDiscovery(
        inventory: const AppLeftoverInventory(apps: apps),
        environment: environment,
        operatingSystem: 'windows',
      );
      job.cancel();
      expect(await job.result, isNull);
    },
  );

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

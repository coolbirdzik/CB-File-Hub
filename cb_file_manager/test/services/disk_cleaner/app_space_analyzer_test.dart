import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:cb_file_manager/services/disk_cleaner/app_storage/app_space_analyzer.dart';
import 'package:cb_file_manager/services/disk_cleaner/app_storage/app_space_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/app_storage/running_processes.dart';
import 'package:cb_file_manager/services/disk_cleaner/editor_storage/editor_root_sizes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Records what reaches the Trash without touching anything.
class _Trash implements TrashManager {
  final moved = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  @override
  Future<Set<String>> moveMultipleToTrashBatched(
    List<String> filePaths, {
    int chunkSize = 200,
    void Function(String, int, int)? onChunkStart,
    void Function(int, int)? onChunkDone,
    Duration? timeoutOverride,
    void Function(String, Object)? onError,
  }) async {
    moved.addAll(filePaths);
    return filePaths.toSet();
  }
}

/// Every target of every clean group, sent through the real cleanup
/// pipeline with a recording Trash, as the page does.
Future<void> expectReachesTrash(AppSpaceReport report) async {
  final targets = [
    for (final entry in report.entries)
      for (final group in AppCleanGroup.of(entry))
        for (final target in group.targets) target.path,
  ];
  expect(targets, isNotEmpty);
  final trash = _Trash();
  final result =
      await DiskCleanerService.forTesting(
        fullDiskScanSpawner: spawnFullDiskScan,
        trashManager: trash,
      ).cleanJunk(
        items: [
          for (final path in targets)
            JunkItem(
              path: path,
              sizeBytes: 1,
              categoryId: 'selected_item',
              isUserSelected: true,
            ),
        ],
        permanent: false,
      );
  expect(result.skippedUnsafe, isEmpty);
  expect(trash.moved, unorderedEquals(targets));
}

void main() {
  late Directory home;
  final now = DateTime.now().add(const Duration(days: 3));

  void write(String path, int bytes, {DateTime? modified}) {
    final file = File(path)..createSync(recursive: true);
    file.writeAsBytesSync(List.filled(bytes, 0));
    if (modified != null) file.setLastModifiedSync(modified);
  }

  setUp(() => home = Directory.systemTemp.createTempSync('cb_app_space_'));
  tearDown(() => home.deleteSync(recursive: true));

  group('macOS', () {
    late String library;
    late String support;
    late List<InstalledAppInfo> apps;
    late String chatterBundle;
    late String runnerBundle;

    InstalledAppInfo app(
      String id,
      String name,
      String bundleId, {
      String? bundle,
    }) => InstalledAppInfo(
      id: id,
      displayName: name,
      source: InstalledAppSource.macApp,
      packageFamilyName: bundleId,
      installLocation: bundle,
      executablePaths: [if (bundle != null) '$bundle/Contents/MacOS/$name'],
    );

    setUp(() {
      library = p.join(home.path, 'Library');
      support = p.join(library, 'Application Support');
      chatterBundle = p.join(home.path, 'Applications', 'Chatter.app');
      runnerBundle = p.join(home.path, 'Applications', 'Runner.app');
      write(p.join(chatterBundle, 'Contents', 'MacOS', 'Chatter'), 50);
      write(p.join(runnerBundle, 'Contents', 'MacOS', 'Runner'), 20);
      apps = [
        app('chatter', 'Chatter', 'com.chatter.app', bundle: chatterBundle),
        app('notes', 'Noteworthy', 'com.notes.Notes'),
        app('alpha', 'Alpha', 'com.acme.alpha'),
        app('runner', 'Runner', 'com.run.runner', bundle: runnerBundle),
        app('vscode', 'Visual Studio Code', 'com.microsoft.VSCode'),
        // A command on PATH: never sized as an install.
        const InstalledAppInfo(
          id: 'tool',
          displayName: 'tool',
          source: InstalledAppSource.executable,
          installLocation: '/usr/bin',
        ),
      ];

      // Chromium layout.
      final chatter = p.join(support, 'Chatter');
      write(p.join(chatter, 'Cache', 'Cache_Data', 'f'), 30);
      write(p.join(chatter, 'Code Cache', 'js', 'x'), 10);
      write(p.join(chatter, 'GPUCache', 'y'), 5);
      write(p.join(chatter, 'Local Storage', 'leveldb', 'z'), 7);
      write(p.join(chatter, 'logs', '20260101T0900', 'main.log'), 3);
      write(p.join(chatter, 'logs', '20260102T0900', 'main.log'), 2);
      write(p.join(chatter, 'Crashpad', 'completed', 'c.dmp'), 9);
      write(p.join(chatter, 'Crashpad', 'settings.dat'), 1);
      write(p.join(chatter, 'Preferences'), 4);
      write(p.join(library, 'Caches', 'com.chatter.app', 'f'), 40);
      write(p.join(library, 'Logs', 'Chatter', 'x.log'), 6);
      write(
        p.join(library, 'Group Containers', 'ABCDE12345.com.chatter.app', 'g'),
        3,
      );
      write(p.join(library, 'HTTPStorages', 'com.chatter.app', 'h'), 2);
      write(
        p.join(
          library,
          'Saved Application State',
          'com.chatter.app.savedState',
          's',
        ),
        1,
      );

      // Sandboxed app: the container's Caches are its cache.
      final container = p.join(library, 'Containers', 'com.notes.Notes');
      write(p.join(container, 'Data', 'Library', 'Caches', 'c'), 11);
      write(p.join(container, 'Data', 'Library', 'Preferences', 'p'), 2);
      write(p.join(container, 'Data', 'Documents', 'd'), 13);
      write(p.join(container, '.com.apple.containermanagerd.metadata'), 1);

      // Same vendor as Alpha, but no app of its own: shared.
      write(p.join(support, 'com.acme.beta', 'x'), 8);

      // A running app keeps its caches.
      write(p.join(support, 'Runner', 'Cache', 'q'), 20);
      write(p.join(library, 'Caches', 'com.run.runner', 'r'), 15);

      // No installed app: the Leftovers page reports it.
      write(p.join(support, 'Forgotten', 'u'), 5);

      // A VS Code data folder and one extension.
      write(p.join(support, 'Code', 'User', 'settings.json'), 3);
      write(p.join(support, 'Code', 'Cache', 'c'), 12);
      final extension = p.join(
        home.path,
        '.vscode',
        'extensions',
        'pub.ext-1.0.0',
      );
      File(p.join(extension, 'package.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({'publisher': 'pub', 'name': 'ext', 'version': '1.0.0'}),
        );
    });

    Future<(AppSpaceReport, List<AppSpaceReport>)> analyze({
      List<String> alsoRunning = const [],
    }) async {
      final partials = <AppSpaceReport>[];
      final report =
          await AppSpaceAnalyzer(
            environment: AppSpaceEnvironment(
              operatingSystem: 'macos',
              home: home.path,
            ),
            apps: apps,
            processes: RunningProcesses(
              operatingSystem: 'macos',
              executables: [
                '$runnerBundle/Contents/MacOS/Runner',
                ...alsoRunning,
              ],
            ),
            sizer: dartEditorRootSizes,
            now: () => now,
            isProcessAlive: (_) => false,
          ).analyze(
            onPartial: partials.add,
            // Several chunks, so progress and the partial report are real.
            chunkSize: 4,
          );
      return (report, partials);
    }

    AppSpaceEntry entryOf(AppSpaceReport report, String id) =>
        report.entries.singleWhere((e) => e.app.id == id);

    int bytes(AppSpaceEntry entry, AppSpaceKind kind, AppSpaceTier tier) =>
        entry.items
            .where((i) => i.kind == kind && i.tier == tier)
            .fold(0, (sum, i) => sum + i.bytes);

    test('attributes folders to apps and splits them by kind', () async {
      final (report, _) = await analyze();
      expect(
        report.entries.map((e) => e.app.id),
        unorderedEquals(['chatter', 'notes', 'alpha', 'runner', 'vscode']),
      );
      // Leftovers stay on the Leftovers page.
      expect(
        report.entries.expand((e) => e.items).map((i) => i.path),
        isNot(contains(p.join(support, 'Forgotten'))),
      );

      final chatter = entryOf(report, 'chatter');
      expect(chatter.isRunning, isFalse);
      expect(bytes(chatter, AppSpaceKind.install, AppSpaceTier.review), 50);
      // Chromium caches, the older log session and old dumps are safe.
      expect(bytes(chatter, AppSpaceKind.cache, AppSpaceTier.safe), 45);
      expect(bytes(chatter, AppSpaceKind.logs, AppSpaceTier.safe), 3);
      expect(bytes(chatter, AppSpaceKind.logs, AppSpaceTier.review), 2);
      expect(bytes(chatter, AppSpaceKind.crashReports, AppSpaceTier.safe), 9);
      expect(bytes(chatter, AppSpaceKind.crashReports, AppSpaceTier.review), 1);
      // A whole Caches/<app> or Logs/<app> folder is opt-in.
      expect(bytes(chatter, AppSpaceKind.cache, AppSpaceTier.optional), 40);
      expect(bytes(chatter, AppSpaceKind.logs, AppSpaceTier.optional), 6);
      // Shown only.
      expect(bytes(chatter, AppSpaceKind.webStorage, AppSpaceTier.review), 9);
      expect(bytes(chatter, AppSpaceKind.userData, AppSpaceTier.review), 4);
      expect(bytes(chatter, AppSpaceKind.sharedData, AppSpaceTier.review), 3);
      expect(bytes(chatter, AppSpaceKind.settings, AppSpaceTier.review), 1);
      expect(chatter.safeBytes, 45 + 3 + 9);

      final notes = entryOf(report, 'notes');
      expect(bytes(notes, AppSpaceKind.cache, AppSpaceTier.optional), 11);
      expect(bytes(notes, AppSpaceKind.userData, AppSpaceTier.review), 16);

      final alpha = entryOf(report, 'alpha');
      expect(alpha.items.single.kind, AppSpaceKind.sharedData);
      expect(alpha.items.single.tier, AppSpaceTier.review);
    });

    test('a whole cache folder is offered entry by entry', () async {
      final cache = p.join(library, 'Caches', 'com.chatter.app');
      write(p.join(cache, 'images', 'a'), 2);
      final (report, _) = await analyze();
      final group = AppCleanGroup.of(entryOf(report, 'chatter')).singleWhere(
        (g) => g.kind == AppCleanKind.cache && g.tier == AppSpaceTier.optional,
      );
      expect(
        {for (final t in group.targets) t.path: t.label},
        {
          p.join(cache, 'f'): 'com.chatter.app/f',
          p.join(cache, 'images'): 'com.chatter.app/images',
        },
      );
    });

    test('a cache folder with very many entries stays one row', () async {
      final cache = p.join(library, 'Caches', 'com.chatter.app');
      for (var i = 0; i < 201; i++) {
        write(p.join(cache, 'blob$i'), 1);
      }
      final (report, _) = await analyze();
      final group = AppCleanGroup.of(entryOf(report, 'chatter')).singleWhere(
        (g) => g.kind == AppCleanKind.cache && g.tier == AppSpaceTier.optional,
      );
      expect(group.targets.single.path, cache);
    });

    test('a running app offers nothing that it may hold', () async {
      final (report, _) = await analyze();
      final runner = entryOf(report, 'runner');
      expect(runner.isRunning, isTrue);
      expect(runner.items.every((i) => i.tier == AppSpaceTier.review), isTrue);
      expect(runner.bytesOf(AppSpaceKind.cache), 35);
      expect(AppCleanGroup.of(runner), isEmpty);
    });

    test('a VS Code data folder becomes the editor report', () async {
      final (report, _) = await analyze();
      final code = entryOf(report, 'vscode');
      expect(code.items, isEmpty);
      expect(code.editor!.extensions.single.id, 'pub.ext');
      expect(
        code.totalBytes,
        greaterThanOrEqualTo(15 + code.editor!.extensionInstallBytes),
      );
    });

    group('Xcode', () {
      late String xcodeBundle;
      late String developer;
      late String derived;
      late String deviceSupport;

      setUp(() {
        xcodeBundle = p.join(home.path, 'Applications', 'Xcode.app');
        write(p.join(xcodeBundle, 'Contents', 'MacOS', 'Xcode'), 1);
        apps.add(
          app('xcode', 'Xcode', 'com.apple.dt.Xcode', bundle: xcodeBundle),
        );

        developer = p.join(library, 'Developer');
        derived = p.join(developer, 'Xcode', 'DerivedData');
        final project = p.join(derived, 'Runner-abc');
        write(p.join(project, 'Build', 'Products', 'Debug', 'app'), 100);
        write(p.join(project, 'Build', 'Intermediates.noindex', 'x'), 50);
        write(p.join(project, 'Index.noindex', 'i'), 25);
        write(p.join(project, 'SourcePackages', 'checkouts', 'pkg', 's'), 13);
        write(p.join(project, 'Logs', 'l'), 2);
        write(p.join(derived, 'ModuleCache.noindex', 'm'), 7);

        deviceSupport = p.join(developer, 'Xcode', 'iOS DeviceSupport');
        write(p.join(deviceSupport, 'iPhone 1.0', 'Symbols', 'a'), 300);
        write(
          p.join(deviceSupport, 'iPhone 2.0', 'Symbols', 'b'),
          200,
          modified: now,
        );

        write(
          p.join(
            developer,
            'Xcode',
            'Archives',
            '2026-01-01',
            'App.xcarchive',
            'x',
          ),
          40,
        );
        write(p.join(developer, 'Xcode', 'DocumentationCache', 'v1', 'd'), 6);
        write(p.join(developer, 'Xcode', 'DeviceLogs', 'phone', 'l'), 8);
        write(p.join(developer, 'Xcode', 'UserData', 'keep'), 5);
        write(
          p.join(developer, 'Shared', 'Documentation', 'DocSets', 'old', 'x'),
          12,
        );
        write(p.join(developer, 'CoreSimulator', 'Devices', 'd', 'data'), 60);
        write(p.join(developer, 'CoreSimulator', 'Caches', 'c'), 9);
        write(p.join(developer, 'XCTestDevices', 'x'), 3);
        write(p.join(library, 'Caches', 'com.apple.dt.Xcode', 'c'), 11);
        write(p.join(library, 'Logs', 'CoreSimulator', 'l'), 4);
        write(p.join(library, 'Caches', 'com.apple.Safari', 'x'), 5);
      });

      Map<AppCleanKind, int> rows(AppSpaceEntry xcode) => {
        for (final group in AppCleanGroup.of(xcode)) group.kind: group.bytes,
      };

      test('offers the rows of macOS Developer storage', () async {
        final (report, _) = await analyze();
        final xcode = entryOf(report, 'xcode');
        expect(rows(xcode), {
          AppCleanKind.cache: 9 + 11,
          AppCleanKind.logs: 4,
          AppCleanKind.xcodeDeviceSupport: 300 + 200,
          AppCleanKind.xcodeArchives: 40,
          AppCleanKind.xcodeDerivedData: 100 + 50 + 25 + 13 + 2 + 7,
          AppCleanKind.xcodeDocumentationCache: 6,
          AppCleanKind.xcodeOldLogs: 8,
          AppCleanKind.xcodeOldDocumentationDownloads: 12,
        });
        // Nothing is ticked for you; simulators and settings are only shown.
        expect(
          AppCleanGroup.of(xcode).any((group) => group.selectedByDefault),
          isFalse,
        );
        expect(
          bytes(xcode, AppSpaceKind.userData, AppSpaceTier.review),
          60 + 5 + 3,
        );
        expect(bytes(xcode, AppSpaceKind.install, AppSpaceTier.review), 1);
        expect(
          AppCleanGroup.of(
            xcode,
          ).expand((group) => group.targets).map((target) => target.path),
          containsAll([
            p.join(derived, 'Runner-abc'),
            p.join(deviceSupport, 'iPhone 2.0'),
          ]),
        );

        // Other Apple folders stay with macOS.
        expect(
          report.entries.expand((e) => e.items).map((i) => i.path),
          isNot(contains(p.join(library, 'Caches', 'com.apple.Safari'))),
        );
      });

      test('names each Derived Data project and archive', () async {
        const runner = 'Runner-cojxdkvgvwylomdtsymbrzsfsfjl';
        File(p.join(derived, runner, 'info.plist'))
          ..createSync(recursive: true)
          ..writeAsStringSync('''
<dict>
  <key>WorkspacePath</key>
  <string>${home.path}/Code/app/ios/Runner.xcworkspace</string>
</dict>''');
        final hashed = p.join(derived, 'Other-gbnlvvootdekcsaxzyvzymzkaeaf');
        write(p.join(hashed, 'Build', 'x'), 1);
        final archive = p.join(
          developer,
          'Xcode',
          'Archives',
          '2026-01-02',
          'App 2-1-2026, 10.00.xcarchive',
        );
        write(p.join(archive, 'x'), 2);

        final (report, _) = await analyze();
        final labels = {
          for (final group in AppCleanGroup.of(entryOf(report, 'xcode')))
            for (final target in group.targets) target.path: target.label,
        };
        expect(labels[p.join(derived, runner)], 'Runner · ~/Code/app/ios');
        // No workspace to name it: the hash still tells it apart.
        expect(labels[hashed], 'Other-gbnlvvootdekcsaxzyvzymzkaeaf');
        expect(
          labels[p.join(derived, 'ModuleCache.noindex')],
          'ModuleCache.noindex',
        );
        expect(labels[archive], 'App 2-1-2026, 10.00');
      });

      test('every Xcode target reaches the Trash', () async {
        final (report, _) = await analyze();
        await expectReachesTrash(
          AppSpaceReport(
            entries: [entryOf(report, 'xcode')],
            generatedAt: report.generatedAt,
          ),
        );
      });

      test('stays cleanable while Xcode and its helpers run', () async {
        final (closed, _) = await analyze();
        final (open, _) = await analyze(
          alsoRunning: [
            '$xcodeBundle/Contents/MacOS/Xcode',
            '$xcodeBundle/Contents/Developer/usr/bin/make',
            '$xcodeBundle/Contents/SharedFrameworks/SWBBuildService',
          ],
        );
        final xcode = entryOf(open, 'xcode');
        expect(xcode.isRunning, isFalse);
        expect(rows(xcode), rows(entryOf(closed, 'xcode')));
      });
    });

    test('data folders arrive before app bundles', () async {
      final (report, partials) = await analyze();
      expect(partials, hasLength(1));
      expect(partials.single.complete, isFalse);
      expect(
        partials.single.entries.expand((e) => e.items).map((i) => i.kind),
        isNot(contains(AppSpaceKind.install)),
      );
      expect(report.complete, isTrue);
    });

    test('every macOS target reaches the Trash as a whole', () async {
      final (report, _) = await analyze();
      await expectReachesTrash(report);
    });

    test('clean groups: safe ones checked, whole folders opt-in', () async {
      final (report, _) = await analyze();
      final groups = AppCleanGroup.of(entryOf(report, 'chatter'));
      expect(
        {for (final g in groups) (g.kind, g.tier): g.bytes},
        {
          (AppCleanKind.cache, AppSpaceTier.safe): 45,
          (AppCleanKind.logs, AppSpaceTier.safe): 3,
          (AppCleanKind.crashReports, AppSpaceTier.safe): 9,
          (AppCleanKind.cache, AppSpaceTier.optional): 40,
          (AppCleanKind.logs, AppSpaceTier.optional): 6,
        },
      );
      expect(
        groups.where((g) => g.selectedByDefault).map((g) => g.tier).toSet(),
        {AppSpaceTier.safe},
      );
      final cleaned = report.withoutPaths({
        for (final g in groups) ...g.targets.map((t) => t.path),
      });
      expect(AppCleanGroup.of(entryOf(cleaned, 'chatter')), isEmpty);
    });
  });

  test('Linux: XDG folders and Flatpak data', () async {
    final config = p.join(home.path, '.config');
    write(p.join(config, 'Slackish', 'GPUCache', 'g'), 6);
    write(p.join(config, 'Slackish', 'storage.json'), 2);
    write(p.join(home.path, '.cache', 'slackish', 'c'), 9);
    write(p.join(home.path, '.local', 'share', 'Slackish', 'db'), 4);
    final flat = p.join(home.path, '.var', 'app', 'org.example.Flat');
    write(p.join(flat, 'cache', 'c'), 7);
    write(p.join(flat, 'data', 'd'), 5);
    final report = await AppSpaceAnalyzer(
      environment: AppSpaceEnvironment(
        operatingSystem: 'linux',
        home: home.path,
      ),
      apps: const [
        InstalledAppInfo(
          id: 'slackish',
          displayName: 'Slackish',
          source: InstalledAppSource.linuxDesktop,
          packageFamilyName: 'slackish.desktop',
        ),
        InstalledAppInfo(
          id: 'flat',
          displayName: 'Flat Example',
          source: InstalledAppSource.linuxDesktop,
          packageFamilyName: 'org.example.Flat',
        ),
      ],
      processes: const RunningProcesses(
        operatingSystem: 'linux',
        executables: [],
      ),
      sizer: dartEditorRootSizes,
      now: () => now,
      isProcessAlive: (_) => false,
    ).analyze();
    final slackish = report.entries.singleWhere((e) => e.app.id == 'slackish');
    expect(slackish.safeBytes, 6);
    expect(slackish.tierBytes(AppSpaceTier.optional), 9);
    expect(slackish.bytesOf(AppSpaceKind.userData), 2 + 4);
    final flatEntry = report.entries.singleWhere((e) => e.app.id == 'flat');
    expect(flatEntry.tierBytes(AppSpaceTier.optional), 7);
    expect(flatEntry.bytesOf(AppSpaceKind.userData), 5);
    await expectReachesTrash(report);
  });

  test('Linux: wrapped Electron apps and Flatpak apps count as running', () {
    const slack = InstalledAppInfo(
      id: 'slack',
      displayName: 'Slack',
      source: InstalledAppSource.linuxDesktop,
      executablePaths: ['/usr/bin/slack'],
    );
    const flat = InstalledAppInfo(
      id: 'flat',
      displayName: 'Flat Example',
      source: InstalledAppSource.linuxDesktop,
      packageFamilyName: 'org.example.Flat',
    );
    const running = RunningProcesses(
      operatingSystem: 'linux',
      // The wrapper script runs the real binary from another folder.
      executables: ['/usr/lib/slack/slack', '/usr/bin/bwrap'],
      commandLines: ['bwrap --args 42 org.example.Flat --file-forwarding'],
    );
    expect(running.runs(slack), isTrue);
    expect(running.runs(flat), isTrue);
    const idle = RunningProcesses(
      operatingSystem: 'linux',
      executables: ['/usr/bin/bash'],
      commandLines: ['bash'],
    );
    expect(idle.runs(slack), isFalse);
    expect(idle.runs(flat), isFalse);
  });

  test('Windows: install-folder executables count when none is known', () {
    const app = InstalledAppInfo(
      id: 'w',
      displayName: 'W',
      source: InstalledAppSource.win32,
    );
    const running = RunningProcesses(
      operatingSystem: 'windows',
      executables: ['w-app.exe'],
    );
    expect(running.runs(app), isFalse);
    expect(
      running.runs(app, installExecutables: [r'C:\Program Files\W\W-App.exe']),
      isTrue,
    );
  });

  test('an unknown process list counts every app as running', () {
    const app = InstalledAppInfo(
      id: 'x',
      displayName: 'X',
      source: InstalledAppSource.macApp,
      installLocation: '/Applications/X.app',
    );
    expect(const RunningProcesses.unknown('macos').runs(app), isTrue);
    expect(
      const RunningProcesses(
        operatingSystem: 'macos',
        executables: ['/Applications/X.app/Contents/MacOS/X'],
      ).runs(app),
      isTrue,
    );
    expect(
      const RunningProcesses(
        operatingSystem: 'macos',
        executables: ['/Applications/X.app2/Contents/MacOS/X'],
      ).runs(app),
      isFalse,
    );
    expect(
      const RunningProcesses(
        operatingSystem: 'windows',
        executables: ['x.exe'],
      ).runs(
        const InstalledAppInfo(
          id: 'w',
          displayName: 'W',
          source: InstalledAppSource.win32,
          executablePaths: [r'C:\Program Files\X\X.exe'],
        ),
      ),
      isTrue,
    );
  });
}

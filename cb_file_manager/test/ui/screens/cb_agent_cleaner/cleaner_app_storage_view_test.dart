import 'dart:async';

import 'package:cb_file_manager/bloc/cleaner_app_storage/cleaner_app_storage.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/app_storage/app_space_models.dart';
import 'dart:io';

import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/docker/docker_storage.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_app_storage_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const int _mb = 1024 * 1024;
const String _support = '/Users/me/Library/Application Support';

AppSpaceEntry _entry(
  String id,
  String name, {
  bool running = false,
  List<AppSpaceItem> items = const [],
}) => AppSpaceEntry(
  app: InstalledAppInfo(
    id: id,
    displayName: name,
    source: InstalledAppSource.macApp,
  ),
  isRunning: running,
  items: items,
);

AppSpaceReport _report({bool complete = true}) => AppSpaceReport(
  generatedAt: DateTime(2026, 11, 7),
  complete: complete,
  entries: [
    _entry(
      'chat',
      'Chatter',
      items: [
        if (complete)
          const AppSpaceItem(
            path: '/Applications/Chatter.app',
            kind: AppSpaceKind.install,
            tier: AppSpaceTier.review,
            bytes: 300 * _mb,
          ),
        const AppSpaceItem(
          path: '$_support/Chatter/Cache',
          kind: AppSpaceKind.cache,
          tier: AppSpaceTier.safe,
          bytes: 120 * _mb,
        ),
        const AppSpaceItem(
          path: '/Users/me/Library/Caches/com.chatter.app',
          kind: AppSpaceKind.cache,
          tier: AppSpaceTier.optional,
          bytes: 80 * _mb,
        ),
        const AppSpaceItem(
          path: '$_support/Chatter/IndexedDB',
          kind: AppSpaceKind.webStorage,
          tier: AppSpaceTier.review,
          bytes: 40 * _mb,
        ),
      ],
    ),
    _entry(
      'busy',
      'Busy App',
      running: true,
      items: const [
        AppSpaceItem(
          path: '$_support/Busy/Cache',
          kind: AppSpaceKind.cache,
          tier: AppSpaceTier.review,
          bytes: 60 * _mb,
        ),
      ],
    ),
  ],
);

/// Hands out reports when the test says so.
class _Scanner implements AppStorageScanner {
  Completer<AppSpaceReport?>? done;
  void Function(int, int)? progress;
  void Function(AppSpaceReport)? partial;
  int cancels = 0;

  @override
  Future<AppSpaceReport?> scan({
    required void Function(int done, int total) onProgress,
    required void Function(AppSpaceReport partial) onPartial,
  }) {
    progress = onProgress;
    partial = onPartial;
    return (done = Completer<AppSpaceReport?>()).future;
  }

  @override
  void cancel() {
    cancels++;
    if (done?.isCompleted == false) done!.complete(null);
  }
}

void main() {
  test('partial then final report keeps the user choices', () async {
    final scanner = _Scanner();
    final cubit = CleanerAppStorageCubit(scanner: scanner);
    addTearDown(cubit.close);
    final run = cubit.scan();
    scanner.progress!(3, 10);
    scanner.partial!(_report(complete: false));
    expect(cubit.state.status, CleanerAppStorageStatus.scanning);
    expect(cubit.state.isMeasuring, isTrue);
    // Safe groups start checked; whole cache folders do not.
    expect(cubit.state.selectedBytes, 120 * _mb);
    cubit.toggleGroup('chat/data/cache/safe');
    cubit.toggleGroup('chat/data/cache/optional');
    scanner.done!.complete(_report());
    await run;
    expect(cubit.state.status, CleanerAppStorageStatus.ready);
    expect(cubit.state.isMeasuring, isFalse);
    expect(cubit.state.selectedBytes, 80 * _mb);

    cubit.markPending(['/Users/me/Library/Caches/com.chatter.app']);
    expect(cubit.state.selectedBytes, 0);
    cubit.finishClean(
      ['/Users/me/Library/Caches/com.chatter.app'],
      ['/Users/me/Library/Caches/com.chatter.app'],
    );
    expect(cubit.state.pendingPaths, isEmpty);
    expect(
      cubit.state.report!.entries.first.items.map((i) => i.path),
      isNot(contains('/Users/me/Library/Caches/com.chatter.app')),
    );
  });

  test('cancel keeps a partial report on screen', () async {
    final scanner = _Scanner();
    final cubit = CleanerAppStorageCubit(scanner: scanner);
    addTearDown(cubit.close);
    final run = cubit.scan();
    scanner.partial!(_report(complete: false));
    cubit.cancel();
    await run;
    expect(scanner.cancels, 1);
    expect(cubit.state.status, CleanerAppStorageStatus.ready);
    expect(cubit.state.report!.complete, isFalse);
    // Nothing runs any more: the page must not keep spinning.
    expect(cubit.state.isMeasuring, isFalse);
  });

  test('a failed scan is reported', () async {
    final scanner = _Scanner();
    final cubit = CleanerAppStorageCubit(scanner: scanner);
    addTearDown(cubit.close);
    final run = cubit.scan();
    scanner.done!.completeError(StateError('boom'));
    await run;
    expect(cubit.state.status, CleanerAppStorageStatus.failure);
    expect(cubit.state.errorMessage, contains('boom'));
  });

  Future<(_Scanner, CleanerAppStorageCubit, List<List<JunkItem>>, List<int>)>
  pump(WidgetTester tester, {double width = 1000, DockerTool? docker}) async {
    final scanner = _Scanner();
    final cubit = CleanerAppStorageCubit(scanner: scanner, docker: docker);
    addTearDown(cubit.close);
    final cleaned = <List<JunkItem>>[];
    final leftovers = <int>[];
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: CbThemeBuilder.build(
          brightness: Brightness.light,
          accent: const Color(0xFF0078D4),
        ),
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('vi')],
        home: Scaffold(
          body: CleanerAppStorageView(
            cubit: cubit,
            usesTrash: true,
            onOpenFolder: (_) {},
            onOpenLeftovers: () => leftovers.add(1),
            onClean: (items, onProgress) async {
              cleaned.add(items);
              return CleanReport(
                freedBytes: 0,
                succeeded: [for (final i in items) i.path],
                failed: const {},
                skippedUnsafe: const [],
                skippedInUse: const [],
                wasPermanent: false,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (scanner, cubit, cleaned, leftovers);
  }

  testWidgets('lists apps while measuring, then cleans the checked groups', (
    tester,
  ) async {
    final (scanner, cubit, cleaned, leftovers) = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('cleaner-app-storage-scan')));
    await tester.pump();
    scanner.progress!(5, 20);
    await tester.pump();
    expect(find.text('Measuring app folders... 5 of 20'), findsOneWidget);

    scanner.partial!(_report(complete: false));
    await tester.pump();
    expect(find.text('Chatter'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cleaner-app-storage-measuring')),
      findsOneWidget,
    );
    // No cleaning while the scan still runs.
    final clean = tester.widget<CbButton>(
      find.byKey(const ValueKey('cleaner-app-storage-clean')),
    );
    expect(clean.onPressed, isNull);

    scanner.done!.complete(_report());
    await tester.pumpAndSettle();
    expect(find.text('120.0 MB safe'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('cleaner-app-storage-toggle-chat')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Documents and app data'), findsNothing);
    expect(find.text('Web storage of extension views'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey('cleaner-app-storage-check-chat/data/cache/optional'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('200.0 MB selected'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('cleaner-app-storage-leftovers-link')),
    );
    expect(leftovers, [1]);

    await tester.tap(find.byKey(const ValueKey('cleaner-app-storage-clean')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('cleaner-app-storage-confirm-clean')),
    );
    await tester.pumpAndSettle();
    expect(
      cleaned.single.map((i) => i.path),
      unorderedEquals([
        '$_support/Chatter/Cache',
        '/Users/me/Library/Caches/com.chatter.app',
      ]),
    );
    expect(cleaned.single.every((i) => i.isUserSelected), isTrue);
    expect(cubit.state.groups, isEmpty);
    expect(
      find.byKey(const ValueKey('cleaner-app-storage-clean')),
      findsNothing,
    );
  });

  testWidgets('a cancelled scan says the apps were not measured', (
    tester,
  ) async {
    final (scanner, cubit, _, _) = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('cleaner-app-storage-scan')));
    await tester.pump();
    scanner.partial!(_report(complete: false));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cleaner-app-storage-cancel')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('cleaner-app-storage-measuring')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('cleaner-app-storage-not-measured')),
      findsOneWidget,
    );
    expect(cubit.state.report!.entries, isNotEmpty);
  });

  testWidgets('the filter hides apps with nothing to clean', (tester) async {
    final (scanner, _, _, _) = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('cleaner-app-storage-scan')));
    await tester.pump();
    scanner.done!.complete(_report());
    await tester.pumpAndSettle();
    expect(find.text('Busy App'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('cleaner-app-storage-cleanable-only')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Busy App'), findsNothing);
    expect(find.text('Chatter'), findsOneWidget);
  });

  testWidgets('lays out without overflow in a narrow pane', (tester) async {
    final (scanner, _, _, _) = await pump(tester, width: 380);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('cleaner-app-storage-scan')));
    await tester.pump();
    scanner.done!.complete(_report());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('cleaner-app-storage-toggle-chat')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('Docker', () {
    const report = DockerReport(
      status: DockerStatus.ready,
      images: [
        DockerImage(
          id: 'sha256:aaaaaaaaaaaaaaaa',
          repository: 'app/web',
          tag: 'old',
          size: 200 * _mb,
          uniqueSize: 150 * _mb,
          containers: 0,
        ),
        DockerImage(
          id: 'sha256:bbbbbbbbbbbbbbbb',
          repository: '<none>',
          tag: '<none>',
          size: 50 * _mb,
          uniqueSize: 40 * _mb,
          containers: 0,
        ),
      ],
      volumes: [DockerVolume(name: 'old-data', links: 0, size: 30 * _mb)],
      buildCache: [
        DockerBuildCacheEntry(
          id: 'x',
          description: 'npm install',
          size: 500 * _mb,
          inUse: false,
        ),
      ],
    );

    /// A Docker CLI that records prunes and is empty once pruned.
    (DockerTool, List<List<String>>) fakeDocker() {
      final calls = <List<String>>[];
      var pruned = false;
      return (
        DockerTool(
          locate: () => 'docker',
          run: (_, args) async {
            calls.add(args);
            if (args.contains('prune')) {
              pruned = true;
              return ProcessResult(0, 0, 'Total reclaimed space: 540MB', '');
            }
            if (args.contains('--verbose')) {
              return ProcessResult(
                0,
                0,
                pruned
                    ? '{"Images":[],"Containers":[],"Volumes":[{"Name":"old-data","Links":"0","Size":"30MB"}],"BuildCache":[]}'
                    : '{}',
                '',
              );
            }
            return ProcessResult(0, 0, '', '');
          },
        ),
        calls,
      );
    }

    test('regenerable prunes start checked; volumes are opt-in', () async {
      final scanner = _Scanner();
      final cubit = CleanerAppStorageCubit(scanner: scanner);
      addTearDown(cubit.close);
      final run = cubit.scan();
      scanner.done!.complete(_report().withDocker(report));
      await run;
      expect(cubit.state.dockerSelected, {
        DockerCleanKind.danglingImages,
        DockerCleanKind.buildCache,
      });
      expect(cubit.state.dockerSelectedBytes, 540 * _mb);
      cubit.toggleDocker(DockerCleanKind.unusedImages);
      // Unused images include the untagged one: not counted twice.
      expect(cubit.state.dockerSelectedBytes, (500 + 150 + 40) * _mb);
    });

    testWidgets('the Docker card cleans after a confirmation', (tester) async {
      final (docker, calls) = fakeDocker();
      final (scanner, cubit, cleaned, _) = await pump(tester, docker: docker);
      await tester.tap(find.byKey(const ValueKey('cleaner-app-storage-scan')));
      await tester.pump();
      scanner.done!.complete(_report().withDocker(report));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cleaner-app-storage-docker')),
        findsOneWidget,
      );
      expect(find.text('Unused volumes (1)'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('cleaner-app-storage-docker-clean')),
      );
      await tester.pumpAndSettle();
      // Nothing runs before the confirmation.
      expect(calls.where((c) => c.contains('prune')), isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('cleaner-app-storage-docker-confirm')),
      );
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.contains('prune')).toList(), [
        ['image', 'prune', '--force'],
        ['builder', 'prune', '--all', '--force'],
      ]);
      // Files never went through the Trash pipeline.
      expect(cleaned, isEmpty);
      expect(
        find.byKey(const ValueKey('cleaner-app-storage-docker-freed')),
        findsOneWidget,
      );
      expect(cubit.state.report!.docker!.images, isEmpty);
      expect(cubit.state.dockerSelected, isEmpty);
    });

    testWidgets('the Docker card fits a narrow pane', (tester) async {
      final (scanner, _, _, _) = await pump(tester, width: 380);
      await tester.tap(find.byKey(const ValueKey('cleaner-app-storage-scan')));
      await tester.pump();
      scanner.done!.complete(_report().withDocker(report));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cleaner-app-storage-docker-unusedVolumes')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a stopped Docker says how to start it', (tester) async {
      final (scanner, _, _, _) = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('cleaner-app-storage-scan')));
      await tester.pump();
      scanner.done!.complete(
        _report().withDocker(
          const DockerReport(status: DockerStatus.notRunning),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Docker is not running'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cleaner-app-storage-docker-clean')),
        findsNothing,
      );
    });
  });
}

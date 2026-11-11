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

const String _derived = '/Users/me/Library/Developer/Xcode/DerivedData';
const String _derivedGroup = 'dev/data/xcodeDerivedData/optional';

AppSpaceReport _projectsReport() => AppSpaceReport(
  generatedAt: DateTime(2026, 11, 9),
  entries: [
    _entry(
      'dev',
      'Xcode',
      items: const [
        AppSpaceItem(
          path: '$_derived/Unity-iPhone-abc',
          kind: AppSpaceKind.cache,
          tier: AppSpaceTier.optional,
          bytes: 70 * _mb,
          cleanGroup: AppCleanKind.xcodeDerivedData,
          label: 'Unity-iPhone · ~/Code/game',
        ),
        AppSpaceItem(
          path: '$_derived/Runner-abc',
          kind: AppSpaceKind.cache,
          tier: AppSpaceTier.optional,
          bytes: 20 * _mb,
          cleanGroup: AppCleanKind.xcodeDerivedData,
          label: 'Runner · ~/Code/app/ios',
        ),
        AppSpaceItem(
          path: '$_derived/ModuleCache.noindex',
          kind: AppSpaceKind.cache,
          tier: AppSpaceTier.optional,
          bytes: 10 * _mb,
          cleanGroup: AppCleanKind.xcodeDerivedData,
          label: 'ModuleCache.noindex',
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

  group('checking single items', () {
    late CleanerAppStorageCubit cubit;
    late AppCleanGroup projects;

    setUp(() async {
      final scanner = _Scanner();
      cubit = CleanerAppStorageCubit(scanner: scanner);
      final run = cubit.scan();
      scanner.done!.complete(_projectsReport());
      await run;
      projects = cubit.state.groups.single;
    });
    tearDown(() => cubit.close());

    List<String> selected() => [
      for (final target in cubit.state.selectedTargets) target.path,
    ];

    test('one item of an unchecked group is checked alone', () {
      expect(cubit.state.groupSelection(projects), isFalse);
      cubit.toggleTarget(projects, '$_derived/Runner-abc');
      expect(selected(), ['$_derived/Runner-abc']);
      expect(cubit.state.selectedBytes, 20 * _mb);
      expect(cubit.state.groupSelection(projects), isNull);
    });

    test('unchecking the last item unchecks the group', () {
      cubit.toggleTarget(projects, '$_derived/Runner-abc');
      cubit.toggleTarget(projects, '$_derived/Runner-abc');
      expect(selected(), isEmpty);
      expect(cubit.state.groupSelection(projects), isFalse);
    });

    test('a partly checked group becomes fully checked, then empty', () {
      cubit.toggleTarget(projects, '$_derived/Runner-abc');
      cubit.toggleGroup(projects.id);
      expect(cubit.state.groupSelection(projects), isTrue);
      expect(selected(), hasLength(3));
      cubit.toggleGroup(projects.id);
      expect(cubit.state.groupSelection(projects), isFalse);
      expect(selected(), isEmpty);
    });

    test('one item can be left out of a checked group', () {
      cubit.toggleGroup(projects.id);
      cubit.toggleTarget(projects, '$_derived/ModuleCache.noindex');
      expect(
        selected(),
        unorderedEquals(['$_derived/Unity-iPhone-abc', '$_derived/Runner-abc']),
      );
    });

    test('items left unchecked do not read as checked after a clean', () {
      cubit.toggleTarget(projects, '$_derived/Runner-abc');
      cubit.markPending(['$_derived/Runner-abc']);
      cubit.finishClean(['$_derived/Runner-abc'], ['$_derived/Runner-abc']);
      expect(selected(), isEmpty);
      expect(cubit.state.groupSelection(cubit.state.groups.single), isFalse);
    });
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

  testWidgets('cleans only the project that was checked', (tester) async {
    final (scanner, cubit, cleaned, _) = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('cleaner-app-storage-scan')));
    await tester.pump();
    scanner.done!.complete(_projectsReport());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('cleaner-app-storage-toggle-dev')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Derived Data'));
    await tester.pumpAndSettle();
    expect(find.text('Runner · ~/Code/app/ios'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('cleaner-app-storage-target-$_derived/Runner-abc'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('20.0 MB selected'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(
              const ValueKey('cleaner-app-storage-check-$_derivedGroup'),
            ),
          )
          .value,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('cleaner-app-storage-clean')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('cleaner-app-storage-confirm-clean')),
    );
    await tester.pumpAndSettle();
    expect(cleaned.single.map((i) => i.path), ['$_derived/Runner-abc']);
    expect(cubit.state.groups.single.targets, hasLength(2));
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

    Future<CleanerAppStorageCubit> ready(DockerTool docker) async {
      final scanner = _Scanner();
      final cubit = CleanerAppStorageCubit(scanner: scanner, docker: docker);
      addTearDown(cubit.close);
      final run = cubit.scan();
      scanner.done!.complete(_report().withDocker(report));
      await run;
      return cubit;
    }

    DockerItem item(
      CleanerAppStorageCubit cubit,
      DockerCleanKind kind,
      String label,
    ) => cubit.state.report!.docker!
        .itemsOf(kind)
        .singleWhere((i) => i.label == label);

    test(
      'one image is removed by itself; the other rows still prune',
      () async {
        final (docker, calls) = fakeDocker();
        final cubit = await ready(docker);
        cubit.toggleDockerItem(
          DockerCleanKind.unusedImages,
          item(cubit, DockerCleanKind.unusedImages, 'app/web:old'),
        );
        expect(
          cubit.state.dockerSelection(DockerCleanKind.unusedImages),
          isNull,
        );
        expect(cubit.state.dockerSelectedBytes, (150 + 40 + 500) * _mb);

        await cubit.cleanDocker();
        expect(calls.where((c) => c.contains('prune') || c.contains('rm')), [
          ['image', 'prune', '--force'],
          ['image', 'rm', 'app/web:old'],
          ['builder', 'prune', '--all', '--force'],
        ]);
      },
    );

    test('an image left out is kept even with both image rows on', () {
      final plan = report.plan(
        {DockerCleanKind.danglingImages, DockerCleanKind.unusedImages},
        {
          DockerReport.excludedKey(
            DockerCleanKind.unusedImages,
            report
                .itemsOf(DockerCleanKind.unusedImages)
                .singleWhere((i) => i.label == 'app/web:old'),
          ),
        },
      );
      // The dangling prune covers the rest of the unused row.
      expect(plan.prunes, {DockerCleanKind.danglingImages});
      expect(plan.removals, isEmpty);
    });

    test('a dangling image is left out of a whole unused prune only if '
        'unused images are partly checked', () {
      final dangling = report.itemsOf(DockerCleanKind.danglingImages).single;
      final plan = report.plan(
        {DockerCleanKind.danglingImages, DockerCleanKind.unusedImages},
        {DockerReport.excludedKey(DockerCleanKind.danglingImages, dangling)},
      );
      // Unused images is fully checked, and it includes that image.
      expect(plan.prunes, {DockerCleanKind.unusedImages});
      expect(plan.removals, isEmpty);
    });

    test('unchecking every item checks nothing', () async {
      final (docker, _) = fakeDocker();
      final cubit = await ready(docker);
      final volume = item(cubit, DockerCleanKind.unusedVolumes, 'old-data');
      cubit.toggleDockerItem(DockerCleanKind.unusedVolumes, volume);
      expect(
        cubit.state.dockerSelection(DockerCleanKind.unusedVolumes),
        isTrue,
      );
      cubit.toggleDockerItem(DockerCleanKind.unusedVolumes, volume);
      expect(
        cubit.state.dockerSelection(DockerCleanKind.unusedVolumes),
        isFalse,
      );
      expect(cubit.state.dockerSelected, isNot(isEmpty));
      expect(
        cubit.state.dockerPlan.removals.containsKey(
          DockerCleanKind.unusedVolumes,
        ),
        isFalse,
      );
      expect(
        cubit.state.dockerPlan.prunes,
        isNot(contains(DockerCleanKind.unusedVolumes)),
      );
    });

    test('one failed removal does not stop the others', () async {
      final calls = <List<String>>[];
      final tool = DockerTool(
        locate: () => 'docker',
        run: (_, args) async {
          calls.add(args);
          return args.last == 'busy'
              ? ProcessResult(0, 1, '', 'volume is in use')
              : ProcessResult(0, 0, '', '');
        },
      );
      const a = DockerItem(
        type: 'volume',
        reference: 'busy',
        label: 'busy',
        bytes: 1,
      );
      const b = DockerItem(
        type: 'volume',
        reference: 'free',
        label: 'free',
        bytes: 2,
      );
      await expectLater(
        tool.apply(
          const DockerCleanPlan(
            removals: {
              DockerCleanKind.unusedVolumes: [a, b],
            },
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('busy: volume is in use'),
          ),
        ),
      );
      expect(calls, [
        ['volume', 'rm', 'busy'],
        ['volume', 'rm', 'free'],
      ]);
    });

    test('an image with no tag is removed by id', () {
      const image = DockerImage(
        id: 'sha256:abcdef0123456789',
        repository: 'app/web',
        tag: '<none>',
        size: 1,
        uniqueSize: 1,
        containers: 0,
      );
      expect(image.reference, 'abcdef0123456789');
    });

    testWidgets('a single volume can be ticked and removed', (tester) async {
      final (docker, calls) = fakeDocker();
      final (scanner, cubit, _, _) = await pump(tester, docker: docker);
      await tester.tap(find.byKey(const ValueKey('cleaner-app-storage-scan')));
      await tester.pump();
      scanner.done!.complete(_report().withDocker(report));
      await tester.pumpAndSettle();
      // Only this volume: the regenerable rows are unticked first.
      cubit.toggleDocker(DockerCleanKind.danglingImages);
      cubit.toggleDocker(DockerCleanKind.buildCache);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cleaner-app-storage-docker-unusedVolumes')),
      );
      await tester.pumpAndSettle();
      expect(find.text('old-data'), findsOneWidget);
      await tester.tap(
        find.byKey(
          const ValueKey(
            'cleaner-app-storage-docker-item-unusedVolumes-volume:old-data',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cleaner-app-storage-docker-clean')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cleaner-app-storage-docker-confirm')),
      );
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.contains('rm') || c.contains('prune')), [
        ['volume', 'prune', '--all', '--force'],
      ]);
      expect(tester.takeException(), isNull);
    });

    AppSpaceReport withDockerEntry(InstalledAppInfo app) => AppSpaceReport(
      generatedAt: DateTime(2026, 11, 9),
      docker: report,
      entries: [
        AppSpaceEntry(
          app: app,
          isRunning: true,
          items: const [
            AppSpaceItem(
              path: '/Users/me/Library/Containers/com.docker.docker',
              kind: AppSpaceKind.userData,
              tier: AppSpaceTier.review,
              bytes: 900 * _mb,
            ),
          ],
        ),
        ..._report().entries,
      ],
    );
    const dockerApp = InstalledAppInfo(
      id: 'mac:com.docker.docker',
      displayName: 'Docker',
      source: InstalledAppSource.macApp,
      packageFamilyName: 'com.docker.docker',
    );

    testWidgets('Docker is one row: the app holds its cleaning', (
      tester,
    ) async {
      final (docker, calls) = fakeDocker();
      final (scanner, _, cleaned, _) = await pump(tester, docker: docker);
      await tester.tap(find.byKey(const ValueKey('cleaner-app-storage-scan')));
      await tester.pump();
      scanner.done!.complete(withDockerEntry(dockerApp));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('cleaner-app-storage-docker')),
        findsNothing,
      );
      expect(find.text('Docker'), findsOneWidget);
      expect(find.text('540.0 MB safe'), findsOneWidget);
      expect(find.text('Unused volumes (1)'), findsNothing);

      await tester.tap(
        find.byKey(
          const ValueKey('cleaner-app-storage-toggle-mac:com.docker.docker'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unused volumes (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey('cleaner-app-storage-docker-clean')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cleaner-app-storage-docker-confirm')),
      );
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.contains('prune')).toList(), [
        ['image', 'prune', '--force'],
        ['builder', 'prune', '--all', '--force'],
      ]);
      expect(cleaned, isEmpty);
    });

    testWidgets('the cleanable filter keeps the Docker app', (tester) async {
      final (scanner, _, _, _) = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('cleaner-app-storage-scan')));
      await tester.pump();
      scanner.done!.complete(withDockerEntry(dockerApp));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cleaner-app-storage-cleanable-only')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Docker'), findsOneWidget);
      expect(find.text('Busy App'), findsNothing);
    });

    testWidgets('the docker command alone is not the Docker app', (
      tester,
    ) async {
      final (scanner, _, _, _) = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('cleaner-app-storage-scan')));
      await tester.pump();
      scanner.done!.complete(
        withDockerEntry(
          const InstalledAppInfo(
            id: 'exe:docker',
            displayName: 'docker',
            source: InstalledAppSource.executable,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cleaner-app-storage-docker')),
        findsOneWidget,
      );
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

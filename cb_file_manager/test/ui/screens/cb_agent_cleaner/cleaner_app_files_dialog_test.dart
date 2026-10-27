import 'dart:async';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/app_insights/app_storage_file_browser.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_app_files_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _cache = AppStorageEntry(
  path: '/app/cache',
  kind: AppStorageKind.cache,
  sizeBytes: 4096,
  measurementQuality: MeasurementQuality.measured,
  attributionConfidence: AttributionConfidence.confirmed,
  isCleanable: true,
  categoryId: 'app_cache',
);
const _data = AppStorageEntry(
  path: '/app/data',
  kind: AppStorageKind.localData,
  sizeBytes: 8192,
  measurementQuality: MeasurementQuality.measured,
  attributionConfidence: AttributionConfidence.likely,
  // Even a malformed likely entry must never expose a cleanup action.
  isCleanable: true,
);
const _profile = AppStorageProfile(
  app: InstalledAppInfo(
    id: 'editor',
    displayName: 'Editor',
    source: InstalledAppSource.win32,
  ),
  entries: [_cache, _data],
);

Future<void> _openDialog(
  WidgetTester tester, {
  required AppStorageFilesLoader loader,
  AppStorageEntry? initialEntry,
  void Function(AppStorageProfile)? onReview,
  void Function(AppStorageEntry)? onOpenFolder,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => CleanerAppFilesDialog(
                profile: _profile,
                initialEntry: initialEntry,
                loadDirectory: loader,
                onReviewCleanable: onReview,
                onOpenFolder: onOpenFolder,
              ),
            ),
            child: const Text('Inspect'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Inspect'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'browses folders and sends only the inspected junk root to review',
    (tester) async {
      AppStorageProfile? reviewed;
      final visited = <String>[];
      await _openDialog(
        tester,
        onReview: (profile) => reviewed = profile,
        loader: (path) async {
          visited.add(path);
          return path == _cache.path
              ? [
                  const AppStorageFileEntry(
                    path: '/app/cache/nested',
                    isDirectory: true,
                  ),
                  const AppStorageFileEntry(
                    path: '/app/cache/index.bin',
                    isDirectory: false,
                    sizeBytes: 512,
                  ),
                ]
              : [];
        },
      );

      expect(visited, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('cleaner-app-files-root-/app/cache')),
      );
      await tester.pumpAndSettle();
      expect(find.text('index.bin'), findsOneWidget);
      expect(find.text('512.0 B'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(reviewed, isNull);

      await tester.tap(find.text('nested'));
      await tester.pumpAndSettle();
      expect(find.text('Empty folder'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cleaner-app-files-back')));
      await tester.pumpAndSettle();
      expect(find.text('index.bin'), findsOneWidget);
      await tester.tap(find.text('nested'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cleaner-app-files-review')));
      await tester.pumpAndSettle();
      expect(reviewed?.app.id, 'editor');
      expect(reviewed?.entries, [_cache]);
      expect(
        find.byKey(const ValueKey('cleaner-app-files-dialog')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'opening a folder closes the preview and preserves its exact path',
    (tester) async {
      AppStorageEntry? opened;
      await _openDialog(
        tester,
        initialEntry: _data,
        onOpenFolder: (entry) => opened = entry,
        loader: (_) async => [],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open folder'));
      await tester.pumpAndSettle();
      expect(opened?.path, _data.path);
      expect(opened?.isCleanable, isFalse);
      expect(
        find.byKey(const ValueKey('cleaner-app-files-dialog')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'shows read failures with retry and never offers to clean likely data',
    (tester) async {
      var attempts = 0;
      await _openDialog(
        tester,
        initialEntry: _data,
        onReview: (_) => fail('Data must not become a cleanup target'),
        loader: (_) async {
          if (++attempts == 1) throw StateError('Permission denied: /app/data');
          return [];
        },
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Permission denied: /app/data'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cleaner-app-files-review')),
        findsNothing,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('Empty folder'), findsOneWidget);
    },
  );

  testWidgets('late results cannot replace another storage location', (
    tester,
  ) async {
    final oldListing = Completer<List<AppStorageFileEntry>>();
    await _openDialog(
      tester,
      initialEntry: _cache,
      loader: (path) => path == _cache.path
          ? oldListing.future
          : Future.value([
              const AppStorageFileEntry(
                path: '/app/data/personal.txt',
                isDirectory: false,
                sizeBytes: 42,
              ),
            ]),
    );
    await tester.tap(find.byKey(const ValueKey('cleaner-app-files-back')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('cleaner-app-files-root-/app/data')),
    );
    await tester.pumpAndSettle();
    oldListing.complete([
      const AppStorageFileEntry(
        path: '/app/cache/stale.bin',
        isDirectory: false,
        sizeBytes: 1,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('personal.txt'), findsOneWidget);
    expect(find.text('stale.bin'), findsNothing);
  });

  testWidgets('compact Vietnamese dialog stays usable', (tester) async {
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openDialog(
      tester,
      locale: const Locale('vi'),
      initialEntry: _cache,
      loader: (_) async => [],
      onReview: (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.text('Xem file · Editor'), findsOneWidget);
    expect(find.text('Thư mục trống'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('cleaner-app-files-dialog')),
      findsNothing,
    );
  });
}

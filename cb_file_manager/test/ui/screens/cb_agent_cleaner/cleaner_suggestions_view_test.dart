import 'dart:async';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_suggestions.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_suggestions_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _mb = 1024 * 1024;

const _temp = JunkItem(
  path: r'C:\Users\Tester\AppData\Local\Temp\a.tmp',
  sizeBytes: 300 * _mb,
  categoryId: 'windows_temp',
);
const _installer = JunkItem(
  path: r'C:\Users\Tester\Downloads\setup.exe',
  sizeBytes: 100 * _mb,
  categoryId: 'user_selected',
  isUserSelected: true,
);

CleanerSuggestionReport _report() => CleanerSuggestionReport(
  drivePath: r'C:\',
  usedDiskScan: false,
  warnings: const [],
  scannedAt: DateTime.utc(2026, 10, 10),
  suggestions: const [
    CleanerSuggestion(
      id: 'junk:windows_temp',
      categoryId: 'windows_temp',
      tier: CleanerSuggestionTier.clean,
      sizeBytes: 300 * _mb,
      items: [_temp],
      selectedByDefault: true,
    ),
    CleanerSuggestion(
      id: 'downloads_leftovers',
      tier: CleanerSuggestionTier.review,
      sizeBytes: 100 * _mb,
      items: [_installer],
      folderPath: r'C:\Users\Tester\Downloads',
    ),
    CleanerSuggestion(
      id: 'hibernation_file',
      tier: CleanerSuggestionTier.guided,
      sizeBytes: 6 * 1024 * _mb,
      command: 'powercfg /h off',
    ),
  ],
);

void main() {
  testWidgets('scan lists tiers and cleans only checked items', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    List<JunkItem>? cleaned;
    var openedDiskUsage = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('vi')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: CleanerSuggestionsView(
            drivePath: r'C:\',
            hasDiskScan: false,
            enabled: true,
            onScan: (onProgress) async => _report(),
            onClean: (items, onProgress) async {
              onProgress(items.length, items.length, null);
              cleaned = items;
              return CleanReport(
                freedBytes: items.fold(0, (s, i) => s + i.sizeBytes),
                succeeded: items.map((i) => i.path).toList(),
                failed: const {},
                skippedUnsafe: const [],
                skippedInUse: const [],
                wasPermanent: false,
              );
            },
            onOpenFolder: (_) {},
            onOpenSettings: (_) {},
            onOpenDiskUsage: () => openedDiskUsage = true,
            categoryLabel: (id) => 'Temporary files',
            categoryReason: (id) => 'Recreated by Windows.',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cleaner-suggestions-scan')));
    await tester.pumpAndSettle();

    expect(find.text('Safe to clean'), findsOneWidget);
    expect(find.text('Review before cleaning'), findsOneWidget);
    expect(find.text('Free up with Windows tools'), findsOneWidget);
    expect(find.text('Temporary files'), findsOneWidget);
    expect(find.text('Hibernation file'), findsOneWidget);
    expect(find.text('Copy command'), findsOneWidget);
    expect(find.text('Selected: 300.0 MB in 1 items'), findsOneWidget);

    // Opt in to the Downloads installer, which is a personal file.
    await tester.tap(
      find.byKey(
        const ValueKey('cleaner-suggestion-check-downloads_leftovers'),
      ),
    );
    await tester.pump();
    expect(find.text('Selected: 400.0 MB in 2 items'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cleaner-suggestions-clean')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 of them are your own files'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('cleaner-suggestions-confirm-clean')),
    );
    await tester.pumpAndSettle();

    expect(cleaned!.map((i) => i.path), [_temp.path, _installer.path]);
    // Cleaned suggestions disappear; guided advice stays.
    expect(find.text('Temporary files'), findsNothing);
    expect(find.text('Hibernation file'), findsOneWidget);
    expect(find.text('Selected: 0 B in 0 items'), findsOneWidget);

    await tester.tap(find.text('Disk usage'));
    expect(openedDiskUsage, isTrue);
  });

  testWidgets('scan shows live per-source progress', (tester) async {
    final done = Completer<CleanerSuggestionReport>();
    late void Function(CleanerSuggestionProgress) report;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('vi')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: CleanerSuggestionsView(
            drivePath: r'C:\',
            hasDiskScan: false,
            enabled: true,
            onScan: (onProgress) {
              report = onProgress;
              return done.future;
            },
            onClean: (_, _) async => null,
            onOpenFolder: (_) {},
            onOpenSettings: (_) {},
            onOpenDiskUsage: () {},
            categoryLabel: (id) => switch (id) {
              'windows_temp' => 'Temporary files',
              'browser_cache' => 'Browser caches',
              _ => id,
            },
            categoryReason: (id) => '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cleaner-suggestions-scan')));
    await tester.pump();

    report(
      const CleanerSuggestionProgress(
        step: CleanerSuggestionStep.junk,
        sources: [
          'windows_temp',
          'browser_cache',
          CleanerSuggestionSource.downloads,
          CleanerSuggestionSource.system,
        ],
        activeSource: 'browser_cache',
        doneSources: {},
        sourceBytes: {'windows_temp': 300 * _mb, 'browser_cache': 150 * _mb},
        itemsFound: 42,
        fraction: 0.35,
        currentPath: r'C:\Users\Tester\AppData\Local\Google\Chrome\Cache',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Checking caches and temporary files...'), findsOneWidget);
    expect(
      find.text(r'C:\Users\Tester\AppData\Local\Google\Chrome\Cache'),
      findsOneWidget,
    );
    expect(find.text('42 items found'), findsOneWidget);
    expect(find.text('450.0 MB found'), findsOneWidget);
    expect(find.text('35%'), findsOneWidget);
    expect(find.text('Temporary files'), findsOneWidget);
    expect(find.text('300.0 MB'), findsOneWidget);
    expect(find.text('Downloads folder'), findsOneWidget);
    expect(find.text('Windows system files'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('cleaner-suggestions-progress-bar')),
    );
    expect(bar.value, closeTo(0.35, 0.001));

    done.complete(_report());
    await tester.pumpAndSettle();
    expect(find.text('Safe to clean'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cleaner-suggestions-progress')),
      findsNothing,
    );
  });

  testWidgets('scan again runs a new scan and shows skipped parts', (
    tester,
  ) async {
    var scans = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('vi')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: CleanerSuggestionsView(
            drivePath: r'C:\',
            hasDiskScan: false,
            enabled: true,
            onScan: (onProgress) async {
              scans++;
              final report = _report();
              return CleanerSuggestionReport(
                drivePath: report.drivePath,
                suggestions: report.suggestions,
                usedDiskScan: false,
                warnings: const [],
                scannedAt: DateTime.utc(2026, 10, 10, 0, 0, scans),
                errors: [
                  if (scans == 2)
                    const CleanerSuggestionError(
                      CleanerSuggestionErrorKind.junkScanBusy,
                      'busy',
                    ),
                ],
              );
            },
            onClean: (_, _) async => null,
            onOpenFolder: (_) {},
            onOpenSettings: (_) {},
            onOpenDiskUsage: () {},
            categoryLabel: (id) => id,
            categoryReason: (id) => '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cleaner-suggestions-scan')));
    await tester.pumpAndSettle();
    const busyBanner = ValueKey('cleaner-suggestions-error-junkScanBusy');
    expect(find.byKey(busyBanner), findsNothing);

    await tester.tap(find.byKey(const ValueKey('cleaner-suggestions-rescan')));
    await tester.pumpAndSettle();
    expect(scans, 2);
    expect(find.byKey(busyBanner), findsOneWidget);
    expect(find.textContaining('Another junk scan is running'), findsOneWidget);
  });
}

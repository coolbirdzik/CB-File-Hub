import 'package:cb_file_manager/bloc/cleaner_smart_clean/cleaner_smart_clean.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_smart_clean_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const int _mb = 1024 * 1024;
const String _temp = r'C:\Users\me\AppData\Local\Temp\old.tmp';
const String _bin = r'C:\$Recycle.Bin\S-1\$R1.txt';
const String _vendorTemp =
    r'C:\Users\me\AppData\Local\Temp\SomeVendorSetup\setup.msi';
const String _chromeTemp =
    r'C:\Users\me\AppData\Local\Temp\chrome_url_fetcher_1\x.tmp';

void main() {
  final now = DateTime(2026, 10, 26, 12);
  final old = now.subtract(const Duration(days: 30));

  ScanReport report({required bool bySource}) => ScanReport(
    drivesScanned: const [r'C:\'],
    itemsByCategory: {
      'windows_temp': [
        if (!bySource)
          JunkItem(
            path: _temp,
            sizeBytes: 3 * _mb,
            categoryId: 'windows_temp',
            lastModified: old,
          ),
        if (bySource) ...[
          JunkItem(
            path: _vendorTemp,
            sizeBytes: 3 * _mb,
            categoryId: 'windows_temp',
            lastModified: old,
          ),
          JunkItem(
            path: _chromeTemp,
            sizeBytes: 2 * _mb,
            categoryId: 'windows_temp',
            lastModified: old,
          ),
        ],
      ],
      'recycle_bin': [
        JunkItem(
          path: _bin,
          sizeBytes: 40 * _mb,
          categoryId: 'recycle_bin',
          lastModified: old,
          isRecycleBinItem: true,
        ),
      ],
    },
    warnings: const [],
    scannedAt: now,
  );

  Future<(CleanerSmartCleanCubit, List<List<JunkItem>>)> pump(
    WidgetTester tester, {
    bool bySource = false,
    List<InstalledAppInfo> apps = const [],
    ScanReport? scanReport,
    ValueChanged<String>? onOpenReviewFile,
    Locale locale = const Locale('en'),
  }) async {
    final cleaned = <List<JunkItem>>[];
    final cubit = CleanerSmartCleanCubit(
      scan: (_) async => scanReport ?? report(bySource: bySource),
      clean: (items, _) async {
        cleaned.add(items);
        return CleanReport(
          freedBytes: 0,
          succeeded: items.map((i) => i.path).toList(),
          failed: const {},
          skippedUnsafe: const [],
          skippedInUse: const [],
          wasPermanent: false,
        );
      },
      nowProvider: () => now,
      groupOffThread: false,
      installedApps: () async => apps,
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('vi')],
        home: Scaffold(
          body: CleanerSmartCleanView(
            cubit: cubit,
            categoryIds: const ['windows_temp', 'recycle_bin'],
            categoryTitle: (id) => 'title:$id',
            categoryReason: (id) => 'reason:$id',
            onOpenReviewFile: onOpenReviewFile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (cubit, cleaned);
  }

  testWidgets('scan, review and clean only the checked groups', (tester) async {
    final (cubit, cleaned) = await pump(tester);
    expect(find.text('Smart Clean'), findsOneWidget);
    expect(find.text('title:windows_temp'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cleaner-smart-clean-scan')));
    await tester.pumpAndSettle();

    // The Recycle Bin is listed but not counted until checked.
    expect(cubit.state.status, CleanerSmartCleanStatus.ready);
    expect(find.text('Permanent'), findsOneWidget);
    expect(find.text('Clean 3.0 MB'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cleaner-smart-clean-clean')));
    await tester.pumpAndSettle();

    expect(cleaned.single.map((i) => i.path), [_temp]);
    expect(find.text('Clean complete'), findsOneWidget);
    expect(find.textContaining('Moved 3.0 MB'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cleaner-smart-clean-done')));
    await tester.pumpAndSettle();
    expect(cubit.state.status, CleanerSmartCleanStatus.idle);
  });

  testWidgets('a group lists who made its files, each one can be left out', (
    tester,
  ) async {
    final (cubit, cleaned) = await pump(tester, bySource: true);
    await tester.tap(find.byKey(const ValueKey('cleaner-smart-clean-scan')));
    await tester.pumpAndSettle();

    // Only recognised apps are named on the collapsed card.
    expect(find.text('Mostly from Google Chrome'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('cleaner-smart-clean-expand-windows_temp')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Folder "SomeVendorSetup"'), findsOneWidget);
    expect(find.text('Installer leftovers'), findsOneWidget);
    expect(find.text('Google Chrome'), findsOneWidget);
    expect(find.text('Temporary files'), findsOneWidget);
    expect(find.text('No longer used'), findsNWidgets(2));
    expect(find.text('Clean 5.0 MB'), findsOneWidget);

    final chrome = cubit.state.groups
        .firstWhere((g) => g.categoryId == 'windows_temp')
        .sources
        .firstWhere((s) => s.origin.app == 'Google Chrome');
    await tester.tap(
      find.byKey(
        ValueKey(
          'cleaner-smart-clean-source-toggle-windows_temp/${chrome.key}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(cubit.state.groupSelection('windows_temp'), isNull);
    expect(find.text('Clean 3.0 MB'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cleaner-smart-clean-clean')));
    await tester.pumpAndSettle();
    expect(cleaned.single.map((i) => i.path), [_vendorTemp]);
  });

  testWidgets('files of an installed app show its name and Installed', (
    tester,
  ) async {
    await pump(
      tester,
      bySource: true,
      apps: const [
        InstalledAppInfo(
          id: 'vendor',
          displayName: 'SomeVendor 2.1.0',
          source: InstalledAppSource.win32,
        ),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('cleaner-smart-clean-scan')));
    await tester.pumpAndSettle();
    expect(find.text('Mostly from SomeVendor, Google Chrome'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('cleaner-smart-clean-expand-windows_temp')),
    );
    await tester.pumpAndSettle();
    expect(find.text('SomeVendor'), findsOneWidget);
    expect(find.text('Folder "SomeVendorSetup"'), findsNothing);
    expect(find.text('Installed'), findsOneWidget);
  });

  testWidgets(
    'package downloads show their tool and redownload cost before cleanup',
    (tester) async {
      const archive =
          r'C:\Users\me\AppData\Local\npm-cache\_cacache\content-v2\blob';
      final (_, cleaned) = await pump(
        tester,
        scanReport: ScanReport(
          drivesScanned: const [r'C:\'],
          itemsByCategory: {
            'package_download_cache': [
              JunkItem(
                path: archive,
                sizeBytes: _mb,
                categoryId: 'package_download_cache',
                lastModified: old,
              ),
            ],
          },
          warnings: const [],
          scannedAt: now,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('cleaner-smart-clean-scan')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('cleaner-smart-clean-expand-package_download_cache'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('npm'), findsOneWidget);
      expect(find.text('May download again'), findsOneWidget);
      expect(find.text('Package download caches'), findsOneWidget);
      expect(
        find.textContaining('Future installs may download'),
        findsOneWidget,
      );
      expect(cleaned, isEmpty);
      await tester.tap(find.byKey(const ValueKey('cleaner-smart-clean-clean')));
      await tester.pumpAndSettle();
      expect(cleaned.single.map((i) => i.path), [archive]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('old downloads can be inspected without any cleanup controls', (
    tester,
  ) async {
    const path = r'C:\Users\me\Downloads\old-personal.zip';
    String? opened;
    final (cubit, cleaned) = await pump(
      tester,
      onOpenReviewFile: (value) => opened = value,
      scanReport: ScanReport(
        drivesScanned: const [r'C:\'],
        itemsByCategory: {
          'old_downloads_review': [
            JunkItem(
              path: path,
              sizeBytes: _mb,
              categoryId: 'old_downloads_review',
              lastModified: now.subtract(const Duration(days: 100)),
            ),
          ],
        },
        warnings: const [],
        scannedAt: now,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('cleaner-smart-clean-scan')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('cleaner-old-files-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('cleaner-smart-clean-clean')),
      findsNothing,
    );
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.byKey(const ValueKey('cleaner-old-files-expand')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('does not prove a file is unused'),
      findsOneWidget,
    );
    expect(find.text('old-personal.zip'), findsOneWidget);
    expect(find.textContaining('Last modified:'), findsOneWidget);
    final open = find.byKey(const ValueKey('cleaner-old-file-open-$path'));
    await tester.ensureVisible(open);
    await tester.tap(open);
    expect(opened, path);
    expect(cubit.state.selectedCount, 0);
    await cubit.clean();
    expect(cleaned, isEmpty);
  });

  testWidgets(
    'compact Vietnamese Xcode cleanup leaves old downloads visible for review',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const buildFile =
          '/Users/me/Library/Developer/Xcode/DerivedData/App/Build/Intermediates.noindex/file.o';
      const download = '/Users/me/Downloads/keep.zip';
      final (cubit, cleaned) = await pump(
        tester,
        locale: const Locale('vi'),
        scanReport: ScanReport(
          drivesScanned: const ['/'],
          itemsByCategory: {
            'xcode_build_cache': [
              JunkItem(
                path: buildFile,
                sizeBytes: _mb,
                categoryId: 'xcode_build_cache',
                lastModified: old,
              ),
            ],
            'old_downloads_review': [
              JunkItem(
                path: download,
                sizeBytes: 9 * _mb,
                categoryId: 'old_downloads_review',
                lastModified: now.subtract(const Duration(days: 100)),
              ),
            ],
          },
          warnings: const [],
          scannedAt: now,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('cleaner-smart-clean-scan')));
      await tester.pumpAndSettle();
      expect(cubit.state.selectedBytes, _mb);
      await tester.tap(
        find.byKey(
          const ValueKey('cleaner-smart-clean-expand-xcode_build_cache'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Xcode'), findsOneWidget);
      expect(find.text('File build Xcode cũ'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('cleaner-smart-clean-clean')));
      await tester.pumpAndSettle();
      expect(cleaned.single.map((item) => item.path), [buildFile]);
      expect(
        find.byKey(const ValueKey('cleaner-old-files-panel')),
        findsOneWidget,
      );
      final expand = find.byKey(const ValueKey('cleaner-old-files-expand'));
      await tester.ensureVisible(expand);
      await tester.tap(expand);
      await tester.pumpAndSettle();
      expect(find.text('keep.zip'), findsOneWidget);
      expect(
        find.textContaining('Lần sửa đổi không phải lần mở'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('including the Recycle Bin asks before deleting permanently', (
    tester,
  ) async {
    final (cubit, cleaned) = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('cleaner-smart-clean-scan')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('cleaner-smart-clean-toggle-recycle_bin')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cleaner-smart-clean-clean')));
    await tester.pumpAndSettle();

    expect(find.text('Empty the Recycle Bin?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cleaned, isEmpty);
    expect(cubit.state.status, CleanerSmartCleanStatus.ready);

    await tester.tap(find.byKey(const ValueKey('cleaner-smart-clean-clean')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('cleaner-smart-clean-confirm-permanent')),
    );
    await tester.pumpAndSettle();
    expect(cleaned.single.map((i) => i.path), unorderedEquals([_temp, _bin]));
    expect(find.textContaining('Permanently deleted'), findsOneWidget);
  });
}

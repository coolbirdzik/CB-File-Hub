import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/torrent/qbittorrent_backup_importer.dart';
import 'package:cb_file_manager/ui/screens/torrent/qbittorrent_import_dialog.dart';

void main() {
  late QbittorrentImportPlan plan;
  final requests =
      <({QbittorrentImportPlan plan, bool remove, bool confirmed})>[];
  var cleanupChecks = 0;
  var running = false;
  setUp(() {
    requests.clear();
    cleanupChecks = 0;
    running = false;
    plan = QbittorrentImportPlan(
      [r'C:\qBittorrent\BT_backup'],
      List.generate(1000, (index) {
        final hash = index.toRadixString(16).padLeft(40, '0');
        return QbittorrentBackupItem(hash, [
          QbittorrentSourceFile(
            r'C:\qBittorrent\BT_backup\'
            '$hash.torrent',
            1,
            100,
          ),
          QbittorrentSourceFile(
            r'C:\qBittorrent\BT_backup\'
            '$hash.fastresume',
            1,
            100,
          ),
        ]);
      }),
    );
  });
  Future<void> mount(WidgetTester tester, {double width = 1100}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      fluent.FluentApp(
        theme: fluent.FluentThemeData(brightness: Brightness.light),
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Theme(
          data: CbThemeBuilder.build(
            brightness: Brightness.light,
            accent: Colors.teal,
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Center(
            child: CbButton(
              label: 'Open',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => QbittorrentImportDialog(
                  initialDestination: r'C:\library',
                  logPath: r'C:\log',
                  discover: () async => plan.roots,
                  loadPlan: (_) async => plan,
                  checkCleanup: (_) async {
                    cleanupChecks++;
                    if (running) {
                      throw const QbittorrentImportException(
                        QbittorrentImportProblem.running,
                      );
                    }
                  },
                  onImport:
                      (
                        preview,
                        destination, {
                        required removeSources,
                        required confirmedRemoval,
                        required isCancelled,
                        required onProgress,
                      }) async {
                        requests.add((
                          plan: preview,
                          remove: removeSources,
                          confirmed: confirmedRemoval,
                        ));
                        onProgress(1000, 1000);
                        return QbittorrentImportResult(
                          processed: 1000,
                          stored: 1000,
                          cleaned: removeSources ? 1000 : 0,
                          failed: 0,
                          cancelled: false,
                          stoppedBy: null,
                          errors: const [],
                        );
                      },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'direct file import defaults to keeping qBit state and builds previews lazily',
    (tester) async {
      await mount(tester);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('qbittorrent-remove-sources')),
            )
            .value,
        isFalse,
      );
      expect(
        find.text('Tìm thấy 1000 torrent · 2000 file nguồn'),
        findsOneWidget,
      );
      expect(find.byType(SelectableText).evaluate().length, lessThan(30));
      await tester.tap(
        find.byKey(const ValueKey('qbittorrent-import-confirm')),
      );
      await tester.pumpAndSettle();
      expect(requests.single.remove, isFalse);
      expect(requests.single.confirmed, isFalse);
      expect(cleanupChecks, 0);
      expect(find.textContaining('Đã lưu: 1000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final confirm in [false, true]) {
    testWidgets('direct qBit cleanup requires explicit confirmation $confirm', (
      tester,
    ) async {
      await mount(tester, width: confirm ? 390 : 1100);
      final remove = find.byKey(const ValueKey('qbittorrent-remove-sources'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('qbittorrent-import-confirm')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('qbittorrent-cleanup-confirmation')),
        findsOneWidget,
      );
      expect(requests, isEmpty);
      expect(find.textContaining('2000 file nguồn bên dưới'), findsOneWidget);
      await tester.tap(
        find.byKey(
          ValueKey(
            confirm
                ? 'qbittorrent-cleanup-confirm'
                : 'qbittorrent-cleanup-cancel',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests.length, confirm ? 1 : 0);
      if (confirm) {
        expect(requests.single.plan, same(plan));
        expect(requests.single.remove, isTrue);
        expect(requests.single.confirmed, isTrue);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'running qBittorrent shows the close-app instruction without importing or cleanup',
    (tester) async {
      running = true;
      await mount(tester);
      final remove = find.byKey(const ValueKey('qbittorrent-remove-sources'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('qbittorrent-import-confirm')),
      );
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      expect(
        find.textContaining('Hãy tắt qBittorrent hoàn toàn'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('qbittorrent-cleanup-confirmation')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

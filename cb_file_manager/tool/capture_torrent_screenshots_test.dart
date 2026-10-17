// Opt-in widget rendering with sample data; no E2E runner, user library,
// native application, tracker connection or download is involved.
// Run from cb_file_manager:
// flutter test --no-pub tool/capture_torrent_screenshots_test.dart \
//   --dart-define=CB_CAPTURE_SCREENSHOTS=true
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/config/languages/english_localizations.dart';
import 'package:cb_file_manager/config/languages/vietnamese_localizations.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/torrent/qbittorrent_backup_importer.dart';
import 'package:cb_file_manager/ui/screens/torrent/qbittorrent_import_dialog.dart';
import 'package:cb_file_manager/ui/screens/torrent/torrent_client_import_dialog.dart';
import 'package:cb_file_manager/ui/screens/torrent/torrent_download_dialog.dart';
import 'package:cb_file_manager/ui/screens/torrent/torrent_link_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _ShowcaseLocalizations extends LocalizationsDelegate<AppLocalizations> {
  const _ShowcaseLocalizations();
  @override
  bool isSupported(Locale locale) => ['en', 'vi'].contains(locale.languageCode);
  @override
  Future<AppLocalizations> load(Locale locale) async =>
      locale.languageCode == 'vi'
      ? VietnameseLocalizations()
      : EnglishLocalizations();
  @override
  bool shouldReload(_ShowcaseLocalizations old) => false;
}

void main() {
  testWidgets('Capture torrent feature dialogs in English and Vietnamese', (
    tester,
  ) async {
    final originalShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? {
                'text':
                    'magnet:?xt=urn:btih:${'1' * 40}&dn=Community%20Linux%20Desktop%202026.iso',
              }
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.runAsync(() async {
        final manifest =
            jsonDecode(await rootBundle.loadString('FontManifest.json'))
                as List;
        for (final entry in manifest) {
          final loader = FontLoader(entry['family'] as String);
          for (final font in entry['fonts'] as List) {
            loader.addFont(rootBundle.load(font['asset'] as String));
          }
          await loader.load();
        }
      });

      final plan = QbittorrentImportPlan(
        [r'D:\Torrent Sources\qBittorrent\BT_backup'],
        List.generate(128, (index) {
          final hash = index.toRadixString(16).padLeft(40, '0');
          return QbittorrentBackupItem(hash, [
            QbittorrentSourceFile(
              'D:\\Torrent Sources\\qBittorrent\\BT_backup\\$hash.torrent',
              1,
              1024,
            ),
            QbittorrentSourceFile(
              'D:\\Torrent Sources\\qBittorrent\\BT_backup\\$hash.fastresume',
              1,
              512,
            ),
          ]);
        }),
      );

      for (final locale in ['en', 'vi']) {
        for (final scene in [
          'qbittorrent',
          'client-import',
          'add-link',
          'download',
        ]) {
          final Widget dialog = switch (scene) {
            'qbittorrent' => QbittorrentImportDialog(
              initialDestination: r'D:\Torrent Library',
              logPath: '',
              discover: () async => plan.roots,
              loadPlan: (_) async => plan,
              checkCleanup: (_) async {},
              onImport:
                  (
                    plan,
                    destination, {
                    required removeSources,
                    required confirmedRemoval,
                    required isCancelled,
                    required onProgress,
                  }) async =>
                      throw StateError('Screenshot scenes cannot import files'),
            ),
            'client-import' => TorrentClientImportDialog(
              client: 'Transmission',
              storageMode: 'copy',
              discover: () async => [
                r'C:\Users\You\AppData\Local\transmission\torrents',
              ],
            ),
            'add-link' => TorrentLinkDialog(
              onAdd: (_) async =>
                  throw StateError('Screenshot scenes cannot add downloads'),
            ),
            _ => const TorrentDownloadDialog(
              name: 'Community Linux Desktop 2026.iso',
              initialDestination: r'D:\Downloads\Linux',
              startImmediately: false,
            ),
          };
          final boundaryKey = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: CbThemeBuilder.build(
                  brightness: Brightness.light,
                  accent: Colors.teal,
                ),
                locale: Locale(locale),
                supportedLocales: const [Locale('en'), Locale('vi')],
                localizationsDelegates: const [
                  _ShowcaseLocalizations(),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: Scaffold(body: Center(child: dialog)),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = Directory(
              '../screenshots/features/torrents/$locale',
            );
            await directory.create(recursive: true);
            await File(
              '${directory.path}/$scene.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }
    } finally {
      debugDisableShadows = originalShadows;
    }
  }, skip: !const bool.fromEnvironment('CB_CAPTURE_SCREENSHOTS'));
}

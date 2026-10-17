import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/torrent/torrent_launch_request.dart';
import 'package:cb_file_manager/services/torrent/bencode_reader.dart';
import 'package:cb_file_manager/services/torrent/windows_qbittorrent_process.dart';
import 'package:cb_file_manager/services/torrent/torrent_metainfo.dart';
import 'package:cb_file_manager/ui/components/common/search_text_field.dart';
import 'package:cb_file_manager/ui/components/common/soft_checkbox.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/torrent/qbittorrent_import_dialog.dart';
import 'package:cb_file_manager/ui/screens/torrent/torrent_download_dialog.dart';
import 'package:cb_file_manager/ui/screens/torrent/torrent_screen.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'e2e_helpers.dart';
import 'e2e_keys.dart';
import 'e2e_report.dart';
import 'torrent_e2e_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerE2EAppSandbox();

  Finder keyed(String key) => find.byKey(ValueKey(key));
  Future<void> tap(WidgetTester tester, String key) async {
    final finder = keyed(key);
    await waitForTorrentWidget(tester, finder);
    final widget = tester.widget(finder);
    final target = widget is CbSelect<String> || widget is CbSelect<int>
        ? find.descendant(of: finder, matching: find.byType(CbPressable)).first
        : finder;
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  Future<void> cancelOptions(WidgetTester tester) async {
    await waitForTorrentWidget(tester, find.byType(TorrentDownloadDialog));
    final dialog = find.byType(TorrentDownloadDialog);
    final cancel = find.descendant(
      of: dialog,
      matching: find.byWidgetPredicate(
        (widget) => widget is CbButton && widget.label == 'Cancel',
      ),
    );
    await tester.tap(cancel);
    await waitForTorrentCondition(
      tester,
      () => find.byType(TorrentDownloadDialog).evaluate().isEmpty,
      reason: 'Cancel should dismiss download options',
    );
  }

  bool immediate(WidgetTester tester) => tester
      .widget<SoftCheckboxInline>(
        find.descendant(
          of: keyed('torrent-start-immediately'),
          matching: find.byType(SoftCheckboxInline),
        ),
      )
      .value;

  Future<void> saveOptions(
    WidgetTester tester,
    String destination, {
    required bool start,
  }) async {
    await waitForTorrentWidget(tester, find.byType(TorrentDownloadDialog));
    await tester.enterText(keyed('torrent-download-destination'), destination);
    if (immediate(tester) != start) {
      await tap(tester, 'torrent-start-immediately');
    }
    await tap(tester, 'torrent-download-confirm');
    await waitForTorrentCondition(
      tester,
      () => find.byType(TorrentDownloadDialog).evaluate().isEmpty,
      reason: 'Saving download options should dismiss the dialog',
    );
  }

  Future<void> refresh(
    WidgetTester tester,
    TorrentE2EFixture fixture,
    int count, {
    bool keyboard = false,
  }) async {
    if (keyboard) {
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    } else {
      await tap(tester, 'shared-refresh-action');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (!fixture.service.scan.running &&
          (await fixture.repository.page()).total == count) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect((await fixture.repository.page()).total, count);
    await tester.pump(const Duration(milliseconds: 800));
  }

  Future<void> contextAction(
    WidgetTester tester,
    String path,
    String action,
  ) async {
    await waitForFileRowVisible(tester, path);
    await rightClickFileRow(tester, path);
    final item = find.byWidgetPredicate(
      (widget) =>
          widget is PopupMenuItem<String> && widget.value == 'torrent_$action',
    );
    await waitForTorrentWidget(tester, item);
    await tester.tap(item);
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Torrent Library', () {
    testWidgets(
      'torrent file opens from browser, saves paused, remembers choice and survives temp cleanup',
      (tester) async {
        final f = await TorrentE2EFixture.create();
        final et = E2ETester(tester);
        File? source;
        try {
          source = await f.torrent('browser.bin');
          await (await SharedPreferences.getInstance()).setString(
            'torrent.storageMode',
            'move',
          );
          if (Platform.isWindows) {
            expect(
              (await Process.run('attrib', ['+R', source.path])).exitCode,
              0,
            );
          }
          await f.start(tester, path: f.sources);
          await et.init(
            'Torrent Library browser file and sticky download options',
          );
          await waitForFileRowVisible(tester, source.path);
          final row = keyed('file-item-${source.path}');
          await tester.tap(row);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tap(row);
          await waitForTorrentWidget(
            tester,
            find.byType(TorrentDownloadDialog),
          );
          expect(immediate(tester), isTrue);
          await saveOptions(tester, f.payload, start: false);
          final entry = await f.waitForStatus(
            tester,
            (await f.entry(source)).hash,
            'paused',
          );
          expect((await f.repository.get(entry.hash))!.status, 'paused');
          expect((await f.repository.get(entry.hash))!.downloadDir, f.payload);
          expect(
            (await f.waitForTask(tester, entry.hash, 'paused'))['status'],
            'paused',
          );
          expect(await source.exists(), isTrue);
          expect(entry.torrentPath, isNot(source.path));
          if (Platform.isWindows) {
            await Process.run('attrib', ['-R', source.path]);
          }
          await source.delete();
          expect(
            TorrentMetainfo.parse(
              await File(entry.torrentPath).readAsBytes(),
            ).hash,
            entry.hash,
          );
          final next = await f.torrent('next.bin');
          final tab = f.tabs(tester).state.activeTabId;
          await f.launch(tester, next.path);
          await waitForTorrentWidget(
            tester,
            find.byType(TorrentDownloadDialog),
          );
          expect(immediate(tester), isFalse);
          expect(f.tabs(tester).state.activeTabId, tab);
          await cancelOptions(tester);
          expect((await f.repository.page()).total, 2);
          expect((await f.entry(next)).status, 'library');
          await waitForFileRowVisible(tester, entry.torrentPath);
          await waitForFileRowVisible(
            tester,
            (await f.entry(next)).torrentPath,
          );
          await et.screenshot(
            'paused destination, full list, durable metainfo',
          );
        } finally {
          if (source != null && Platform.isWindows && await source.exists()) {
            await Process.run('attrib', ['-R', source.path]);
          }
          await f.close(tester);
        }
      },
    );

    testWidgets(
      'magnet IPC restores and focuses one existing tab and asks before merging',
      (tester) async {
        final f = await TorrentE2EFixture.create();
        final previousClipboard = await Clipboard.getData('text/plain');
        final et = E2ETester(tester);
        try {
          await f.start(tester);
          await et.init(
            'Torrent Library magnet focus reuse merge and clipboard',
          );
          final tab = f.tabs(tester).state.activeTabId;
          const hash = '1111111111111111111111111111111111111111';
          const original =
              'magnet:?xt=urn:btih:$hash&dn=First&tr=http%3A%2F%2F127.0.0.1%3A1%2Fold';
          await windowManager.minimize();
          expect(await windowManager.isMinimized(), isTrue);
          await f.launch(tester, original);
          await waitForTorrentWidget(
            tester,
            find.byType(TorrentDownloadDialog),
          );
          expect(await windowManager.isMinimized(), isFalse);
          expect(await windowManager.isFocused(), isTrue);
          await cancelOptions(tester);
          expect(f.tabs(tester).state.activeTabId, tab);
          expect(
            f
                .tabs(tester)
                .state
                .tabs
                .where((t) => TorrentLaunchRequest.isPath(t.path)),
            hasLength(1),
          );
          const incoming =
              'magnet:?xt=urn:btih:$hash&dn=Renamed&tr=http%3A%2F%2F127.0.0.1%3A1%2Fnew';
          await f.launch(tester, incoming);
          await tap(tester, 'torrent-merge-cancel');
          expect((await f.repository.get(hash))!.trackers, hasLength(1));
          expect(find.byType(TorrentDownloadDialog), findsNothing);
          await f.launch(tester, incoming);
          await tap(tester, 'torrent-merge-confirm');
          await cancelOptions(tester);
          expect((await f.repository.page()).total, 1);
          expect((await f.repository.get(hash))!.trackers, hasLength(2));
          await contextAction(tester, '#torrents/$hash.torrent', 'copy_magnet');
          final copied = (await Clipboard.getData('text/plain'))!.text!;
          expect(copied, contains(hash));
          expect(Uri.parse(copied).queryParametersAll['tr'], hasLength(2));
          await tap(tester, 'torrent-add-link-action');
          await waitForTorrentWidget(tester, keyed('torrent-link-input'));
          expect(
            tester
                .widget<CbTextField>(keyed('torrent-link-input'))
                .controller!
                .text,
            copied,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await et.screenshot('one tab and merged magnet copied');
          expect(f.engine.running, isFalse);
        } finally {
          await Clipboard.setData(
            previousClipboard ?? const ClipboardData(text: ''),
          );
          await f.close(tester);
        }
      },
    );

    testWidgets(
      'F5 imports new source files, skips existing names, and supports paging views search and sort',
      (tester) async {
        final f = await TorrentE2EFixture.create();
        final et = E2ETester(tester);
        try {
          for (var i = 0; i < 85; i++) {
            await f.torrent('Item${i.toString().padLeft(3, '0')}.bin');
          }
          await f.start(tester);
          await et.init('Torrent Library F5 pagination views search sort');
          await refresh(tester, f, 85);
          expect(find.text('1–80 of 85 torrents'), findsOneWidget);
          await tap(tester, 'torrent-page-size');
          await waitForTorrentWidget(tester, find.text('20').last);
          await tester.tap(find.text('20').last);
          await waitForTorrentWidget(tester, find.text('1–20 of 85 torrents'));
          expect(find.byKey(const ValueKey('torrent-toolbar')), findsOneWidget);
          final l = AppLocalizations.of(
            tester.element(find.byType(TorrentScreen)),
          )!;
          final nextPage = find.byWidgetPredicate(
            (widget) => widget is CbButton && widget.tooltip == l.nextPage,
          );
          await tester.tap(nextPage);
          await waitForTorrentWidget(tester, find.text('21–40 of 85 torrents'));
          await tester.tap(
            find.byWidgetPredicate(
              (widget) =>
                  widget is CbButton && widget.tooltip == l.previousPage,
            ),
          );
          await waitForTorrentWidget(tester, find.text('1–20 of 85 torrents'));
          final duplicate = File(
            p.join(f.sources, 'nested', 'Item000.bin.torrent'),
          );
          await duplicate.parent.create();
          await duplicate.writeAsString(
            'invalid metainfo should be skipped by name',
          );
          final newest = await f.torrent('Newest.bin');
          final qbit = await f.torrent(
            'FromQbit.bin',
            directory: p.join(f.root.path, 'qbit', 'BT_backup'),
          );
          final qbitHash = TorrentMetainfo.parse(await qbit.readAsBytes()).hash;
          await qbit.rename(p.join(qbit.parent.path, '$qbitHash.torrent'));
          await refresh(tester, f, 87, keyboard: true);
          expect((await f.repository.get(qbitHash))!.name, 'FromQbit.bin');
          expect(f.service.scan.failed, 0);
          expect(f.service.scan.duplicates, greaterThanOrEqualTo(85));
          expect(find.text('1–20 of 87 torrents'), findsOneWidget);
          await waitForFileRowVisible(
            tester,
            (await f.entry(newest)).torrentPath,
          );
          for (final mode in [
            ViewMode.details,
            ViewMode.grid,
            ViewMode.tiles,
            ViewMode.tree,
            ViewMode.columns,
            ViewMode.list,
          ]) {
            await tap(tester, 'shared-view-mode-menu');
            final choice = find.byWidgetPredicate(
              (widget) =>
                  widget is PopupMenuItem<ViewMode> && widget.value == mode,
            );
            await tester.tap(choice);
            await tester.pump(const Duration(milliseconds: 300));
            expect(
              find.text('Newest.bin'),
              findsWidgets,
              reason: 'Torrent names must render in ${mode.name} view',
            );
            expect(
              (await SharedPreferences.getInstance()).getString(
                'torrent.viewMode',
              ),
              mode.name,
            );
          }
          await tap(tester, 'shared-sort-menu');
          await tester.tap(
            find.byWidgetPredicate(
              (widget) =>
                  widget is PopupMenuItem<SortOption> &&
                  widget.value == SortOption.nameAsc,
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            (await SharedPreferences.getInstance()).getString(
              'torrent.browserSortOption',
            ),
            'nameAsc',
          );
          await tap(tester, 'shared-search-action');
          final search = find.descendant(
            of: find.byType(SearchTextField),
            matching: find.byType(EditableText),
          );
          await tester.enterText(search, 'Item042');
          await waitForTorrentWidget(tester, find.text('1–1 of 1 torrents'));
          expect(find.text('Item042.bin'), findsWidgets);
          await tester.enterText(search, '');
          await waitForTorrentWidget(tester, find.text('1–20 of 87 torrents'));
          // Duplicate checks must include entries outside the current page.
          final offPage = await f.entry(
            File(p.join(f.sources, 'Item084.bin.torrent')),
          );
          expect(
            find.byKey(ValueKey('file-item-${offPage.torrentPath}')),
            findsNothing,
          );
          await f.launch(
            tester,
            'magnet:?xt=urn:btih:${offPage.hash}&dn=AlreadyIndexed',
          );
          await tap(tester, 'torrent-merge-cancel');
          expect((await f.repository.page()).total, 87);
          expect(find.byType(TorrentDownloadDialog), findsNothing);
          await et.screenshot('shared browser controls and bounded page');
        } finally {
          await f.close(tester);
        }
      },
    );

    testWidgets(
      'settings can skip download options using the saved folder and unchecked start',
      (tester) async {
        final f = await TorrentE2EFixture.create();
        try {
          await f.start(tester);
          await tap(tester, 'torrent-settings-action');
          await tap(tester, 'torrent-show-download-dialog');
          final directory = keyed('torrent-default-download-directory');
          await tester.ensureVisible(directory);
          await tester.enterText(directory, f.payload);
          await tap(tester, 'torrent-default-download-save');
          await tap(tester, 'torrent-default-start-immediately');
          await waitForTorrentCondition(
            tester,
            () =>
                !f.service.showDownloadDialog &&
                !f.service.startDownloadsImmediately,
            reason: 'Settings should persist both opening choices',
          );
          expect(f.service.defaultDownloadDirectory, f.payload);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump(const Duration(milliseconds: 250));
          const hash = '2222222222222222222222222222222222222222';
          await f.launch(tester, 'magnet:?xt=urn:btih:$hash&dn=Silent');
          final deadline = DateTime.now().add(const Duration(seconds: 20));
          while ((await f.repository.get(hash))?.status != 'paused' &&
              DateTime.now().isBefore(deadline)) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect((await f.repository.get(hash))!.status, 'paused');
          expect((await f.repository.get(hash))!.downloadDir, f.payload);
          expect(find.byType(TorrentDownloadDialog), findsNothing);
          await f.waitForTask(tester, hash, 'paused');
          final tasks = await f.engine.call('tellWaiting', [0, 10]) as List;
          expect(tasks, hasLength(1));
          expect((tasks.single as Map)['status'], 'paused');
        } finally {
          await f.close(tester);
        }
      },
    );

    testWidgets(
      'Copy to Move asks for confirmation and removes only approved metainfo sources',
      (tester) async {
        final f = await TorrentE2EFixture.create();
        try {
          final source = await f.torrent('organize.bin');
          final content = File(p.join(f.payload, 'keep.txt'))
            ..writeAsStringSync('retain payload');
          await f.service.importFile(source.path);
          final entry = await f.entry(source);
          await f.start(tester);
          await tap(tester, 'torrent-settings-action');
          final l = AppLocalizations.of(
            tester.element(find.byType(TorrentScreen)),
          )!;
          Future<void> chooseMove() async {
            await tap(tester, 'torrent-storage-mode');
            final move = find.text(l.torrentStorageMode('move'));
            await waitForTorrentWidget(tester, move);
            await tester.tap(move.last);
            await waitForTorrentWidget(
              tester,
              keyed('torrent-move-confirmation'),
            );
          }

          await chooseMove();
          expect(find.text(source.path), findsWidgets);
          await tap(tester, 'torrent-move-cancel');
          expect(await source.exists(), isTrue);
          expect(f.service.storageMode, 'copy');
          await chooseMove();
          await tap(tester, 'torrent-move-confirm');
          final deadline = DateTime.now().add(const Duration(seconds: 20));
          while (await source.exists() && DateTime.now().isBefore(deadline)) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(await source.exists(), isFalse);
          expect(await File(entry.torrentPath).exists(), isTrue);
          expect(await content.readAsString(), 'retain payload');
          expect(f.service.storageMode, 'move');
        } finally {
          await f.close(tester);
        }
      },
    );

    testWidgets(
      'qBittorrent imports only the fixture backup and retains its downloaded files',
      (tester) async {
        final f = await TorrentE2EFixture.create();
        final et = E2ETester(tester);
        try {
          final source = await f.torrent(
            'qbit.bin',
            directory: p.join(f.root.path, 'qbit', 'BT_backup'),
          );
          final info = TorrentMetainfo.parse(await source.readAsBytes());
          final backup = await source.rename(
            p.join(source.parent.path, '${info.hash}.torrent'),
          );
          final recoverable = await f.torrent(
            'resume.bin',
            directory: backup.parent.path,
          );
          final recoverableBytes = await recoverable.readAsBytes();
          final recoveredHash = TorrentMetainfo.parse(recoverableBytes).hash;
          final decoded =
              BencodeReader(recoverableBytes).read() as Map<String, Object>;
          final resume = File(
            p.join(backup.parent.path, '$recoveredHash.fastresume'),
          );
          await resume.writeAsBytes(
            encodeTorrentFixture({
              'file-format': 'libtorrent resume file',
              'info-hash': Uint8List.fromList([
                for (var i = 0; i < recoveredHash.length; i += 2)
                  int.parse(recoveredHash.substring(i, i + 2), radix: 16),
              ]),
              'qBt-name': 'resume.bin',
              'qBt-savePath': f.payload,
              'info': decoded['info']!,
            }),
          );
          await recoverable.delete();
          final downloaded = File(p.join(f.payload, 'qbit.bin'))
            ..writeAsStringSync('existing data');
          await f.start(tester);
          await et.init('Torrent Library qBittorrent sandbox import');
          await tap(tester, 'torrent-import-action');
          await tap(tester, 'torrent-qbittorrent-import-action');
          await waitForTorrentWidget(
            tester,
            find.byType(QbittorrentImportDialog),
          );
          final confirm = keyed('qbittorrent-import-confirm');
          await waitForTorrentCondition(
            tester,
            () =>
                confirm.evaluate().isNotEmpty &&
                tester.widget<CbButton>(confirm).onPressed != null,
            reason: 'qBittorrent backup preview should finish',
          );
          expect(find.text(backup.path), findsWidgets);
          expect(
            tester
                .widget<CheckboxListTile>(keyed('qbittorrent-remove-sources'))
                .value,
            isFalse,
          );
          await tap(tester, 'qbittorrent-import-confirm');
          await waitForTorrentCondition(
            tester,
            () => confirm.evaluate().isEmpty,
            reason: 'qBittorrent import should finish and show its result',
          );
          expect((await f.repository.page()).total, 2);
          expect(await backup.exists(), isTrue);
          expect(await downloaded.readAsString(), 'existing data');
          expect(
            await File(
              (await f.repository.get(info.hash))!.torrentPath,
            ).exists(),
            isTrue,
          );
          expect((await f.repository.get(recoveredHash))!.name, 'resume.bin');
          expect(await resume.exists(), isTrue);
          await et.screenshot('backup imported without payload deletion');
          final close = find.descendant(
            of: find.byType(QbittorrentImportDialog),
            matching: find.byWidgetPredicate(
              (widget) => widget is CbButton && widget.label == 'Close',
            ),
          );
          await tester.tap(close);
          await tester.pump(const Duration(milliseconds: 300));
          await tap(tester, 'torrent-import-action');
          await tap(tester, 'torrent-qbittorrent-import-action');
          await waitForTorrentCondition(
            tester,
            () =>
                confirm.evaluate().isNotEmpty &&
                tester.widget<CbButton>(confirm).onPressed != null,
            reason: 'Re-import should preview the same test-owned backup',
          );
          await tap(tester, 'qbittorrent-remove-sources');
          final clientRunning = WindowsQbittorrentProcess.isRunning();
          await tap(tester, 'qbittorrent-import-confirm');
          if (clientRunning) {
            final l = AppLocalizations.of(
              tester.element(find.byType(TorrentScreen)),
            )!;
            await waitForTorrentWidget(
              tester,
              find.text(l.qbittorrentProblem('running')),
            );
            expect(keyed('qbittorrent-cleanup-confirmation'), findsNothing);
            expect(await backup.exists(), isTrue);
            expect(await resume.exists(), isTrue);
            expect(await downloaded.readAsString(), 'existing data');
            return;
          }
          await waitForTorrentWidget(
            tester,
            keyed('qbittorrent-cleanup-confirmation'),
          );
          expect(
            find.descendant(
              of: keyed('qbittorrent-cleanup-preview'),
              matching: find.text(backup.path),
            ),
            findsWidgets,
          );
          await tap(tester, 'qbittorrent-cleanup-cancel');
          expect(await backup.exists(), isTrue);
          expect(await resume.exists(), isTrue);
          await tap(tester, 'qbittorrent-import-confirm');
          await tap(tester, 'qbittorrent-cleanup-confirm');
          await waitForTorrentCondition(
            tester,
            () => confirm.evaluate().isEmpty,
            reason:
                'Confirmed cleanup should complete or report the running-client guard',
          );
          if (clientRunning) {
            expect(await backup.exists(), isTrue);
            expect(await resume.exists(), isTrue);
          } else {
            expect(await backup.exists(), isFalse);
            expect(await resume.exists(), isFalse);
          }
          expect(await downloaded.readAsString(), 'existing data');
        } finally {
          await f.close(tester);
        }
      },
      skip: !Platform.isWindows,
    );

    testWidgets(
      'HTTP metainfo link uses the same destination dialog without starting a download on cancel',
      (tester) async {
        final f = await TorrentE2EFixture.create();
        try {
          final source = await f.torrent('http.bin');
          final url = await f.httpTorrent(source);
          await f.start(tester);
          await tap(tester, 'torrent-add-link-action');
          await tester.enterText(keyed('torrent-link-input'), url);
          await tap(tester, 'torrent-link-confirm');
          await cancelOptions(tester);
          final entry = await f.entry(source);
          expect(entry.status, 'library');
          expect(entry.sourceUris, contains(url));
          expect(await File(entry.torrentPath).exists(), isTrue);
          expect(f.engine.running, isFalse);
        } finally {
          await f.close(tester);
        }
      },
    );

    testWidgets(
      'real aria2 pauses resumes and verifies a torrent payload from a loopback web seed',
      (tester) async {
        final f = await TorrentE2EFixture.create();
        final et = E2ETester(tester);
        try {
          final source = await f.torrent('download.bin', webSeed: true);
          final hash = TorrentMetainfo.parse(await source.readAsBytes()).hash;
          await f.start(tester);
          await et.init('Torrent Library real loopback payload download');
          await f.launch(tester, source.path);
          await saveOptions(tester, f.payload, start: false);
          var entry = await f.waitForStatus(tester, hash, 'paused');
          var status = await f.waitForTask(tester, hash, 'paused');
          expect(status['status'], 'paused');
          expect(status['completedLength'], '0');
          await contextAction(tester, entry.torrentPath, 'resume');
          final activeDeadline = DateTime.now().add(
            const Duration(seconds: 20),
          );
          while (DateTime.now().isBefore(activeDeadline)) {
            await f.service.sync();
            status = await f.engine.call('tellStatus', [entry.gid]) as Map;
            if (status['status'] == 'active' &&
                int.parse(status['completedLength'] as String) > 0) {
              break;
            }
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(status['status'], 'active');
          await tester.pump(const Duration(milliseconds: 800));
          await contextAction(tester, entry.torrentPath, 'pause');
          await f.service.sync();
          status = await f.engine.call('tellStatus', [entry.gid]) as Map;
          expect(status['status'], 'paused');
          await tester.pump(const Duration(milliseconds: 800));
          await contextAction(tester, entry.torrentPath, 'resume');
          final deadline = DateTime.now().add(const Duration(seconds: 40));
          while (DateTime.now().isBefore(deadline)) {
            await f.service.sync();
            entry = (await f.repository.get(hash))!;
            if (entry.status == 'complete' || entry.status == 'error') break;
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(entry.status, 'complete', reason: entry.error);
          final downloaded = File(p.join(f.payload, 'download.bin'));
          expect(await downloaded.exists(), isTrue);
          expect(
            sha256.convert(await downloaded.readAsBytes()),
            sha256.convert(f.payloadBytes('download.bin')),
          );
          expect(entry.completedBytes, entry.totalBytes);
          await et.screenshot('verified complete payload in chosen folder');
        } finally {
          await f.close(tester);
        }
      },
    );
  });
}

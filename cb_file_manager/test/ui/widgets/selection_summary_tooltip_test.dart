import 'dart:io';

import 'package:cb_file_manager/bloc/selection/selection_state.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/components/common/screen_scaffold.dart';
import 'package:cb_file_manager/ui/widgets/selection_summary_tooltip.dart';
import 'package:cb_native/cb_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile status bar shows size and creation date for one file', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(280, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final directory = Directory.systemTemp.createTempSync('cb_status_bar_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/selected.txt')..writeAsStringSync('x');
    file.setLastModifiedSync(DateTime(2000));
    final stat = file.statSync();
    final created = Platform.isWindows
        ? stat.changed
        : await tester.runAsync(() => NativeFs.fileCreated(file.path));
    if (created == null) {
      markTestSkipped('Temporary filesystem does not report creation time');
      return;
    }
    final date = created.toString().split('.').first;
    expect(created, isNot(stat.modified));

    Future<void> select({
      required List<String> files,
      List<String> folders = const [],
    }) {
      final selection = SelectionState(
        selectedFilePaths: files.toSet(),
        selectedFolderPaths: folders.toSet(),
        isSelectionMode: true,
      );
      return tester.pumpWidget(
        MaterialApp(
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: ScreenScaffold(
            selectionState: selection,
            body: const SizedBox.expand(key: ValueKey('file-list')),
            isNetworkPath: false,
            onClearSelection: () {},
            showRemoveTagsDialog: (_) {},
            showManageAllTagsDialog: (_) {},
            showDeleteConfirmationDialog: (_) {},
            showAppBar: false,
            showSearchBar: false,
            searchBar: const SizedBox.shrink(),
            pathNavigationBar: const SizedBox.shrink(),
            actions: const [],
            mobileSelectionSummary: SelectionSummaryTooltip.forSelection(
              selection,
              totalSizeOverride: stat.size,
              allowWrap: true,
            ),
          ),
        ),
      );
    }

    final creationDate = find.textContaining('Tạo lúc: $date');
    final creationLabel = find.textContaining('Tạo lúc:');
    await select(files: [file.path]);
    // FileStat resolves through real I/O while widget tests use fake time.
    for (
      var attempt = 0;
      attempt < 50 && creationDate.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(creationDate, findsOneWidget);
    expect(find.textContaining('1.0 B'), findsOneWidget);
    final bar = tester.getRect(find.byType(SelectionSummaryTooltip));
    final list = tester.getRect(find.byKey(const ValueKey('file-list')));
    expect(bar.height, greaterThan(SelectionSummaryTooltip.height));
    expect(list.height, greaterThan(bar.height));
    expect(list.bottom, bar.top);

    await select(files: [file.path], folders: [directory.path]);
    expect(creationLabel, findsNothing);

    // Switch to a missing file before the pending lookup can publish its date.
    await select(files: [file.path]);
    await select(files: ['${directory.path}/missing.txt']);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(creationLabel, findsNothing);
  }, skip: !Platform.isWindows && !CbNative.isAvailable);
}

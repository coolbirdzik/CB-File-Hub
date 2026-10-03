import 'dart:async';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/ui/screens/trash_bin/trash_bin_screen.dart';
import 'package:cb_file_manager/ui/components/common/file_view_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTrashManager implements TrashManager {
  final pending = Completer<bool>();
  int emptyCalls = 0;
  int loads = 0;
  List<TrashItem> items = [
    TrashItem(
      trashFileName: 'folder',
      originalPath: 'C:/original/folder',
      actualFilePath: 'C:/trash/folder',
      size: 0,
      trashedDate: DateTime(2026),
      isFolder: true,
    ),
  ];

  @override
  Stream<List<TrashItem>> getTrashItemsStreaming({
    int firstPageSize = 50,
    int pageSize = 500,
  }) {
    loads++;
    return Stream.value(items);
  }

  @override
  Future<bool> emptyTrash({
    void Function(String path, String error)? onError,
  }) async {
    emptyCalls++;
    final success = await pending.future;
    if (!success) onError?.call('Windows Recycle Bin', 'Access denied');
    return success;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserPreferences.instance.init();
  });

  Future<void> mount(WidgetTester tester, _FakeTrashManager manager) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('vi')],
        home: TrashBinScreen(tabId: 'trash-test', trashManager: manager),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
        .onSelected!('empty');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Empty Trash'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
  }

  testWidgets(
    'empty shows loading, blocks refresh, then displays empty state',
    (tester) async {
      final manager = _FakeTrashManager();
      await mount(tester, manager);
      expect(find.text('Emptying trash…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(manager.emptyCalls, 1);
      final shells = tester.widgetList<FileViewShell>(
        find.byType(FileViewShell),
      );
      expect(shells.every((shell) => !shell.enableKeyboardShortcuts), isTrue);
      shells.last.onRefresh!();
      await tester.pump();
      expect(manager.loads, 1);
      expect(
        tester
            .widget<AbsorbPointer>(
              find
                  .descendant(
                    of: find.byType(TrashBinScreen),
                    matching: find.byType(AbsorbPointer),
                  )
                  .first,
            )
            .absorbing,
        isTrue,
      );
      manager.items = [];
      manager.pending.complete(true);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text('Emptying trash…'), findsNothing);
      expect(find.text('Trash is empty'), findsOneWidget);
      expect(manager.loads, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
    },
  );

  testWidgets('partial failure reloads remaining items and shows the error', (
    tester,
  ) async {
    final manager = _FakeTrashManager();
    await mount(tester, manager);
    manager.pending.complete(false);
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.text('Emptying trash…'), findsNothing);
    expect(
      find.textContaining('Windows Recycle Bin: Access denied'),
      findsOneWidget,
    );
    expect(find.text('folder'), findsOneWidget);
    expect(manager.loads, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets(
    'closing the screen during empty does not update disposed state',
    (tester) async {
      final manager = _FakeTrashManager();
      await mount(tester, manager);
      await tester.pumpWidget(const SizedBox.shrink());
      manager.pending.complete(true);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

import 'dart:io';

import 'package:cb_file_manager/ui/screens/folder_list/components/file_item.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/folder_item.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/widgets/adaptive_file_list.dart';
import 'package:cb_file_manager/ui/widgets/compact_file_list_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_keyboard_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'List fills top to bottom before moving right and reflows on resize',
    (tester) async {
      int? rows;
      Future<void> show(
        double width, {
        double height = 416,
        bool desktop = true,
        double scale = 1,
      }) async {
        await tester.binding.setSurfaceSize(Size(width, height));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: AdaptiveFileList(
                isDesktop: desktop,
                itemCount: 60,
                onCrossAxisCountChanged: (value) => rows = value,
                itemBuilder: (_, index) =>
                    CompactFileListContent(path: 'Document $index.txt'),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }

      Offset location(int index) =>
          tester.getTopLeft(find.text('Document $index.txt'));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await show(1100);
      expect(rows, 10);
      expect(location(0).dx, location(9).dx);
      expect(location(9).dy, greaterThan(location(0).dy));
      expect(location(10).dy, location(0).dy);
      expect(location(10).dx, greaterThan(location(0).dx));
      expect(location(30).dx, lessThan(1100));
      await show(600);
      expect(rows, 10);
      expect(location(10).dx, lessThan(600));
      expect(find.text('Document 20.txt'), findsNothing);
      await show(1100, height: 216);
      expect(rows, 5);
      expect(location(4).dx, location(0).dx);
      expect(location(5).dy, location(0).dy);
      expect(location(5).dx, greaterThan(location(0).dx));
      await show(1100, scale: 2);
      expect(rows, 5);
      await show(1100, desktop: false);
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(ListView), findsOneWidget);
    },
  );

  testWidgets('List wheel and keyboard reveal columns outside the viewport', (
    tester,
  ) async {
    final keyboard = TabbedFolderKeyboardController();
    addTearDown(keyboard.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(600, 416));
    int rows = 1;
    double columnStride = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveFileList(
          isDesktop: true,
          controller: keyboard.scrollController,
          itemCount: 1000,
          onCrossAxisCountChanged: (value) => rows = value!,
          onItemMainAxisExtentChanged: (value) => columnStride = value!,
          itemBuilder: (_, index) => SizedBox(
            key: keyboard.itemKeyForPath('item$index'),
            child: CompactFileListContent(path: 'item$index'),
          ),
        ),
      ),
    );
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(200, 200),
        scrollDelta: Offset(0, 200),
      ),
    );
    await tester.pumpAndSettle();
    expect(keyboard.scrollController.offset, greaterThan(0));
    expect(find.text('item990'), findsNothing);
    keyboard.ensurePathVisible(
      'item990',
      index: 990,
      crossAxisCount: rows,
      itemMainAxisExtent: columnStride,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('item990'), findsOneWidget);
    final position = tester.getTopLeft(find.text('item990'));
    expect(position.dx, inInclusiveRange(0, 599));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Compact file name and icon select on click and open on double click',
    (tester) async {
      var selections = 0;
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 270,
              child: FileItem(
                file: File(r'C:\list\a very long document filename.txt'),
                state: FolderListState(r'C:\list'),
                compact: true,
                showItemBackground: false,
                isDesktopMode: true,
                isSelectionMode: false,
                isSelected: false,
                toggleFileSelection:
                    (_, {bool shiftSelect = false, bool ctrlSelect = false}) =>
                        selections++,
                showDeleteTagDialog: (_, _, _) {},
                showAddTagToFileDialog: (_, _) {},
                onFileTap: (_, _) => opens++,
              ),
            ),
          ),
        ),
      );
      final item = find.byType(FileItem);
      final namePosition = tester.getTopLeft(item) + const Offset(110, 20);
      await tester.tapAt(namePosition);
      await tester.pump(const Duration(milliseconds: 400));
      expect(selections, greaterThan(0));
      expect(opens, 0);
      await tester.tapAt(namePosition);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(namePosition);
      await tester.pump(const Duration(milliseconds: 400));
      expect(opens, 1);
      final iconPosition = tester.getTopLeft(item) + const Offset(18, 20);
      await tester.tapAt(iconPosition);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(iconPosition);
      await tester.pump(const Duration(milliseconds: 400));
      expect(opens, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Compact virtual folders render without metadata IO and open', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 270,
            child: FolderItem(
              folder: Directory('#network/server/share'),
              compact: true,
              showItemBackground: false,
              isDesktopMode: true,
              isSelected: true,
              toggleFolderSelection:
                  (_, {bool shiftSelect = false, bool ctrlSelect = false}) {},
              onTap: (_) => opens++,
            ),
          ),
        ),
      ),
    );
    final target =
        tester.getTopLeft(find.byType(FolderItem)) + const Offset(110, 20);
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 400));
    expect(opens, 1);
    expect(find.text('Loading...'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

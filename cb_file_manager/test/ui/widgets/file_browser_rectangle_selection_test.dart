import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/ui/widgets/file_drag_drop_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import '../../support/file_browser_drag_harness.dart';

void main() {
  for (final mode in [
    ViewMode.grid,
    ViewMode.list,
    ViewMode.details,
    ViewMode.tiles,
    ViewMode.columns,
    ViewMode.tree,
    ViewMode.gridPreview,
  ]) {
    testWidgets('mouse drags from empty space in ${mode.name}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey<FileBrowserDragHarnessState>();
      final file = File(p.join('C:', 'rectangle', 'last.txt'));
      var moves = 0;
      await tester.pumpWidget(
        Padding(
          padding: const EdgeInsets.only(left: 37, top: 63),
          child: FileBrowserDragHarness(
            key: key,
            files: [File(p.join('C:', 'rectangle', 'first.txt')), file],
            destination: Directory(p.join('C:', 'rectangle', 'destination')),
            mode: mode,
            onMove: (_, _) async {
              moves++;
            },
            onExternalDrag: (_) {
              moves++;
            },
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final target = find.byWidgetPredicate(
        (widget) => widget is FileDragDropItem && widget.path == file.path,
      );
      final rect = tester.getRect(target.first);
      final start = Offset(rect.center.dx - 8, rect.bottom + 12);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(rect.center + const Offset(8, 0));
      await tester.pump();
      expect(key.currentState!.dragSelection.isDragging.value, isTrue);
      final surface =
          key.currentState!.dragSelection.stackKey.currentContext!
                  .findRenderObject()!
              as RenderBox;
      expect(
        key.currentState!.dragSelection.dragStartPosition.value,
        surface.globalToLocal(start),
      );
      await gesture.up();
      await tester.pump();
      expect(key.currentState!.selection.state.selectedFilePaths, {file.path});
      expect(key.currentState!.selection.state.selectedFolderPaths, isEmpty);
      expect(key.currentState!.dragSelection.isDragging.value, isFalse);
      expect(moves, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('rectangle hits only the visible item in ${mode.name}', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey<FileBrowserDragHarnessState>();
      final files = List.generate(
        100,
        (i) => File(p.join('C:', 'rectangle', 'file-$i.txt')),
      );
      await tester.pumpWidget(
        FileBrowserDragHarness(
          key: key,
          files: files,
          destination: Directory(p.join('C:', 'rectangle', 'destination')),
          mode: mode,
          onMove: (_, _) async {},
          onExternalDrag: (_) {},
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      Future<void> checkVisibleItem() async {
        final file = files.firstWhere((file) {
          final finder = find.byWidgetPredicate(
            (widget) => widget is FileDragDropItem && widget.path == file.path,
          );
          if (finder.evaluate().isEmpty) return false;
          final rect = tester.getRect(finder.first);
          return rect.center.dy > 80 &&
              rect.center.dy < 550 &&
              rect.center.dx > 0 &&
              rect.center.dx < 1280;
        });
        final center = tester.getCenter(
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is FileDragDropItem && widget.path == file.path,
              )
              .first,
        );
        final controller = key.currentState!.dragSelection;
        expect(controller.hitTestItem(center), file.path);
        final surface =
            controller.stackKey.currentContext!.findRenderObject()!
                as RenderBox;
        final local = surface.globalToLocal(center);
        controller.start(local - const Offset(2, 2));
        controller.update(local + const Offset(2, 2));
        await tester.pump();
        controller.end();
        await tester.pump();
        expect(key.currentState!.selection.state.selectedFilePaths, {
          file.path,
        });
        expect(key.currentState!.selection.state.selectedFolderPaths, isEmpty);
      }

      await checkVisibleItem();
      final scrollable = tester.state<ScrollableState>(
        find
            .ancestor(
              of: find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is FileDragDropItem &&
                        widget.path == files.first.path,
                  )
                  .first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scrollable.position.jumpTo(350);
      await tester.pump();
      await checkVisibleItem();
      if (mode == ViewMode.details) {
        final viewport = scrollable.context.findRenderObject()! as RenderBox;
        final headerPoint = viewport.localToGlobal(
          Offset(viewport.size.width / 2, -5),
        );
        expect(
          key.currentState!.dragSelection.hitTestItem(headerPoint),
          isNull,
          reason: 'cached rows behind the header must not be hit',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }
}

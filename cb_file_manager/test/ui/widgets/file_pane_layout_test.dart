import 'dart:async';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/widgets/file_pane_layout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StatefulContent extends StatefulWidget {
  const _StatefulContent();
  @override
  State<_StatefulContent> createState() => _StatefulContentState();
}

class _StatefulContentState extends State<_StatefulContent> {
  int count = 0;
  int builds = 0;
  @override
  Widget build(BuildContext context) {
    builds++;
    return TextButton(
      onPressed: () => setState(() => count++),
      child: Text('Selection $count'),
    );
  }
}

void main() {
  test(
    'loading cannot overwrite a user edit and saves finish in order',
    () async {
      final read = Completer<String>();
      final firstWrite = Completer<bool>();
      final lastWrite = Completer<void>();
      final writes = <String>[];
      final controller = FilePaneLayoutController(
        read: () => read.future,
        write: (encoded) async {
          writes.add(encoded);
          if (writes.length == 1) return firstWrite.future;
          lastWrite.complete();
          return true;
        },
      );
      final loading = controller.load();
      final first = FilePaneLayoutNode.defaults.dock(
        FilePane.preview,
        FilePane.files,
        FilePaneEdge.left,
      );
      final last = first.resize(first.first!.splitId, .35);
      controller.update(first);
      controller.update(last);
      read.complete(FilePaneLayoutNode.defaults.encode());
      await loading;
      expect(controller.value.encode(), last.encode());
      expect(writes, [first.encode()]);
      firstWrite.complete(true);
      await lastWrite.future;
      expect(writes, [first.encode(), last.encode()]);
      controller.dispose();
    },
  );

  test('every pane can dock on every edge and survives a saved round trip', () {
    for (final moving in FilePane.values) {
      for (final target in FilePane.values.where((p) => p != moving)) {
        for (final edge in FilePaneEdge.values) {
          final layout = FilePaneLayoutNode.defaults.dock(moving, target, edge);
          expect(layout.panes.toSet(), FilePane.values.toSet());
          expect(layout.panes.length, 3);
          final restored = FilePaneLayoutNode.decode(layout.encode());
          expect(restored.encode(), layout.encode());
          final before = edge == FilePaneEdge.left || edge == FilePaneEdge.top;
          expect(
            restored.panes.indexOf(moving) < restored.panes.indexOf(target),
            before,
          );
        }
      }
    }
  });

  test('hidden panes preserve geometry and the original split identity', () {
    final layout = FilePaneLayoutNode.defaults.resize(
      'files-preview-properties',
      .7,
    );
    final visible = layout.visible({FilePane.files, FilePane.properties})!;
    expect(visible.splitId, 'files-preview-properties');
    final changed = layout.resize(visible.splitId, .6);
    expect(changed.ratio, .6);
    expect(changed.panes, FilePane.values);
  });

  test('invalid, duplicate, or incomplete saved layouts restore defaults', () {
    for (final invalid in [
      '',
      '{',
      '{"pane":"files"}',
      '{"axis":"horizontal","first":{"pane":"files"},"second":{"pane":"files"}}',
      FilePaneLayoutNode.defaults.encode().replaceFirst('null', '1.5'),
      FilePaneLayoutNode.defaults.encode().replaceFirst('preview', 'unknown'),
    ]) {
      expect(
        FilePaneLayoutNode.decode(invalid).encode(),
        FilePaneLayoutNode.defaults.encode(),
      );
    }
  });

  late FilePaneLayoutController controller;
  setUp(() => controller = FilePaneLayoutController());
  tearDown(() => controller.dispose());

  Widget app({bool preview = true, bool properties = true, Key? key}) =>
      MaterialApp(
        localizationsDelegates: const [AppLocalizationsDelegate()],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: FilePaneLayout(
            key: key,
            controller: controller,
            previewVisible: preview,
            propertiesVisible: properties,
            previewWidth: 360,
            propertiesHeight: 260,
            files: const _StatefulContent(),
            preview: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilePaneDragHandle(pane: FilePane.preview),
                Expanded(child: SizedBox(key: ValueKey('preview-body'))),
              ],
            ),
            properties: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilePaneDragHandle(pane: FilePane.properties),
                Expanded(child: SizedBox(key: ValueKey('properties-body'))),
              ],
            ),
          ),
        ),
      );

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('default positions, live resize, commit, hide/show, and reset', (
    tester,
  ) async {
    desktop(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final files = find.text('Selection 0');
    final preview = find.byKey(const ValueKey('preview-body'));
    final properties = find.byKey(const ValueKey('properties-body'));
    expect(
      tester.getCenter(preview).dx,
      greaterThan(tester.getCenter(files).dx),
    );
    expect(
      tester.getCenter(properties).dy,
      greaterThan(tester.getCenter(files).dy),
    );
    expect(tester.getSize(preview).width, 360);

    final resize = find.byKey(const ValueKey('file-pane-resize-files-preview'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    final center = tester.getCenter(resize);
    final savedBeforeDrag = controller.value.encode();
    final fileState = tester.state<_StatefulContentState>(
      find.byType(_StatefulContent),
    );
    final buildsBeforeDrag = fileState.builds;
    await mouse.down(center);
    await mouse.moveTo(center - const Offset(100, 0));
    await tester.pump();
    expect(
      tester.getSize(preview).width,
      460,
      reason: 'Pane geometry follows the pointer before release',
    );
    expect(tester.getCenter(resize).dx, closeTo(center.dx - 100, 1));
    expect(
      controller.value.encode(),
      savedBeforeDrag,
      reason: 'Persistent layout only updates on release',
    );
    // Multiple pointer events in one frame use the last position without
    // rebuilding the file content or notifying the shared controller.
    await mouse.moveTo(center - const Offset(130, 0));
    await mouse.moveTo(center - const Offset(160, 0));
    await tester.pump();
    expect(tester.getSize(preview).width, 520);
    expect(fileState.builds, buildsBeforeDrag);
    await mouse.moveTo(center - const Offset(100, 0));
    await tester.pump();
    expect(find.textContaining(' px'), findsNothing);
    await mouse.up();
    await tester.pump();
    expect(tester.getSize(preview).width, closeTo(460, 1));
    final saved = controller.value.encode();
    await tester.pumpWidget(app(preview: false));
    expect(preview, findsNothing);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(controller.value.encode(), saved);
    expect(tester.getSize(preview).width, closeTo(460, 1));

    await tester.tap(find.byKey(const ValueKey('file-pane-layout-reset')));
    await tester.pump();
    expect(controller.value.encode(), FilePaneLayoutNode.defaults.encode());
    expect(tester.getSize(preview).width, 360);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag docks beside a pane without losing its state', (
    tester,
  ) async {
    desktop(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selection 0'));
    await tester.pump();
    final target = tester.getRect(find.text('Selection 1'));
    final start = tester.getCenter(
      find.byKey(const ValueKey('file-pane-drag-preview')),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.down(start);
    await mouse.moveTo(start + const Offset(-30, 0));
    await tester.pump();
    await mouse.moveTo(Offset(4, target.center.dy));
    await tester.pump();
    await mouse.up();
    await tester.pump();
    expect(controller.value.first!.first!.pane, FilePane.preview);
    expect(find.text('Selection 1'), findsOneWidget);
    final preview = find.byKey(const ValueKey('preview-body'));
    expect(
      tester.getCenter(preview).dx,
      lessThan(tester.getCenter(find.text('Selection 1')).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('vertical resizing and cancelled resizing keep valid geometry', (
    tester,
  ) async {
    desktop(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final handle = find.byKey(
      const ValueKey('file-pane-resize-files-preview-properties'),
    );
    final properties = find.byKey(const ValueKey('properties-body'));
    final before = tester.getSize(properties).height;
    await tester.drag(handle, const Offset(0, -80));
    await tester.pump();
    expect(tester.getSize(properties).height, closeTo(before + 80, 1));
    final saved = controller.value.encode();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    final center = tester.getCenter(handle);
    await mouse.down(center);
    await mouse.moveTo(center + const Offset(0, 60));
    await tester.pump();
    expect(
      tester.getSize(properties).height,
      closeTo(before + 20, 1),
      reason: 'Vertical size follows the pointer before release',
    );
    expect(controller.value.encode(), saved);
    await mouse.cancel();
    await tester.pump();
    expect(controller.value.encode(), saved);
    expect(
      tester.getSize(properties).height,
      closeTo(before + 80, 1),
      reason: 'Cancellation restores the committed geometry',
    );
    expect(find.textContaining(' px'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved custom arrangement restores on remount and small windows do not overflow',
    (tester) async {
      desktop(tester);
      controller.update(
        FilePaneLayoutNode.defaults.dock(
          FilePane.properties,
          FilePane.files,
          FilePaneEdge.top,
        ),
        persist: false,
      );
      await tester.pumpWidget(app(key: const ValueKey('first')));
      await tester.pumpWidget(app(key: const ValueKey('second')));
      expect(
        tester.getCenter(find.byKey(const ValueKey('properties-body'))).dy,
        lessThan(tester.getCenter(find.text('Selection 0')).dy),
      );
      tester.view.physicalSize = const Size(320, 140);
      await tester.pump();
      expect(find.byKey(const ValueKey('preview-body')), findsNothing);
      expect(find.byKey(const ValueKey('properties-body')), findsNothing);
      expect(find.text('Selection 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

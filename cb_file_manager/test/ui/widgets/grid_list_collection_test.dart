import 'dart:async';
import 'package:cb_file_manager/ui/components/common/grid_list_collection.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';

class _DisposableCollection extends StatefulWidget {
  const _DisposableCollection({required this.selection, required this.mode});
  final SelectionBloc selection;
  final ViewMode mode;

  @override
  State<_DisposableCollection> createState() => _DisposableCollectionState();
}

class _DisposableCollectionState extends State<_DisposableCollection> {
  late final drag = TabbedFolderDragSelectionController(
    selectionBloc: widget.selection,
  );

  @override
  void dispose() {
    drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GridListCollection<String>(
    mode: widget.mode,
    supportedModes: const {ViewMode.grid, ViewMode.list, ViewMode.details},
    items: const ['host'],
    isDesktop: true,
    identity: (item) => item,
    itemBuilder: (_, item, _) => SizedBox(height: 44, child: Text(item)),
    onRefresh: () async {},
    dragSelectionController: drag,
  );
}

void main() {
  for (final mode in [ViewMode.grid, ViewMode.list, ViewMode.details]) {
    for (final cancel in [false, true]) {
      testWidgets(
        '${mode.name} ignores mouse ${cancel ? 'cancel' : 'release'} after navigation disposes its controller',
        (tester) async {
          final selection = SelectionBloc();
          addTearDown(selection.close);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: _DisposableCollection(selection: selection, mode: mode),
              ),
            ),
          );
          final gesture = await tester.startGesture(
            tester.getCenter(find.text('host')),
            kind: PointerDeviceKind.mouse,
          );
          // Pointer routing retains the old hit-test result until release, even
          // when navigating on pointer down has already removed the collection.
          await tester.pumpWidget(
            const MaterialApp(home: Scaffold(body: Text('SSH session'))),
          );
          await gesture.moveBy(const Offset(5, 5));
          if (cancel) {
            await gesture.cancel();
          } else {
            await gesture.up();
          }
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(selection.state.selectedFilePaths, isEmpty);
        },
      );
    }
  }
  test(
    'restores saved choice when reopening and excludes other modes',
    () async {
      var saved = ViewMode.details;
      GridListViewController create() => GridListViewController(
        load: () async => saved,
        save: (mode) async {
          saved = mode;
        },
      );
      final first = create();
      await first.initialize();
      expect(first.mode, ViewMode.grid);
      await first.select(ViewMode.list);
      first.dispose();
      final reopened = create();
      await reopened.initialize();
      expect(reopened.mode, ViewMode.list);
      reopened.dispose();
    },
  );

  test('late restore cannot overwrite a user switch', () async {
    final restoring = Completer<ViewMode>();
    final controller = GridListViewController(load: () => restoring.future);
    final loaded = controller.initialize();
    await controller.select(ViewMode.list);
    restoring.complete(ViewMode.grid);
    await loaded;
    expect(controller.mode, ViewMode.list);
    controller.dispose();
  });

  test('rapid switches save in order', () async {
    final firstWrite = Completer<void>();
    final saved = <ViewMode>[];
    final controller = GridListViewController(
      save: (mode) async {
        if (saved.isEmpty) await firstWrite.future;
        saved.add(mode);
      },
    );
    final first = controller.select(ViewMode.list);
    final second = controller.select(ViewMode.grid);
    expect(controller.mode, ViewMode.grid);
    firstWrite.complete();
    await Future.wait([first, second]);
    expect(saved, [ViewMode.list, ViewMode.grid]);
    controller.dispose();
  });
}

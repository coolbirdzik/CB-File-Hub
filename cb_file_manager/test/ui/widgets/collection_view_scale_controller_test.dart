import 'dart:async';

import 'package:cb_file_manager/ui/components/common/collection_view_scale_controller.dart';
import 'package:cb_file_manager/ui/components/common/grid_list_collection.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zooming before view restoration keeps the visible grid', () async {
    final restore = Completer<ViewMode>();
    final view = GridListViewController(load: () => restore.future);
    final scale = CollectionViewScaleController(view: view);
    final initialized = scale.initialize();
    await scale.step(1, 1200);
    restore.complete(ViewMode.list);
    await initialized;
    expect(view.mode, ViewMode.grid);
    expect(scale.zoom, 3);
    scale.dispose();
    view.dispose();
  });
  test(
    'wheel changes modes, then grid size, and restores both on reopen',
    () async {
      var mode = ViewMode.details;
      var zoom = 4;
      GridListViewController view() => GridListViewController(
        initialMode: ViewMode.details,
        supportedModes: const {ViewMode.details, ViewMode.list, ViewMode.grid},
        load: () async => mode,
        save: (value) async {
          mode = value;
        },
      );
      final firstView = view();
      final first = CollectionViewScaleController(
        view: firstView,
        loadZoom: () async => zoom,
        saveZoom: (value) async {
          zoom = value;
        },
      );
      await first.initialize();
      await first.step(1, 600);
      expect(firstView.mode, ViewMode.list);
      await first.step(1, 600);
      expect(firstView.mode, ViewMode.grid);
      final small = first.zoom;
      await first.step(1, 600);
      expect(first.zoom, small - 1);
      final reopenedView = view();
      final reopened = CollectionViewScaleController(
        view: reopenedView,
        loadZoom: () async => zoom,
      );
      await reopened.initialize();
      expect(reopenedView.mode, ViewMode.grid);
      expect(reopened.zoom, first.zoom);
      first.dispose();
      reopened.dispose();
      firstView.dispose();
      reopenedView.dispose();
    },
  );

  test(
    'late zoom restoration preserves wheel input and rapid writes stay ordered',
    () async {
      final restore = Completer<int>();
      final write = Completer<void>();
      final saved = <int>[];
      final view = GridListViewController();
      final scale = CollectionViewScaleController(
        view: view,
        loadZoom: () => restore.future,
        saveZoom: (zoom) async {
          await write.future;
          saved.add(zoom);
        },
      );
      final initialized = scale.initialize();
      final first = scale.step(1, 1200);
      final second = scale.step(1, 1200);
      expect(scale.zoom, 2);
      restore.complete(15);
      await initialized;
      expect(scale.zoom, 2);
      write.complete();
      await Future.wait([first, second]);
      expect(saved, [3, 2]);
      scale.dispose();
      view.dispose();
    },
  );
}

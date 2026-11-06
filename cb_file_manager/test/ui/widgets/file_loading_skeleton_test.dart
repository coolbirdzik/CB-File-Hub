import 'package:cb_file_manager/ui/components/common/file_loading_skeleton.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/widgets/adaptive_file_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in ViewMode.values) {
    testWidgets('$mode fits a narrow pane and needs no animation ticks', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                height: 400,
                child: FileLoadingSkeleton(viewMode: mode),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      if (mode == ViewMode.list) {
        expect(find.byType(AdaptiveFileList), findsOneWidget);
      }
    });
  }

  testWidgets('Grid uses pane width and the real file tile ratio', (
    tester,
  ) async {
    for (final (width, columns) in [(320.0, 1), (700.0, 2)]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 400,
                child: const FileLoadingSkeleton(
                  viewMode: ViewMode.grid,
                  gridZoomLevel: 4,
                ),
              ),
            ),
          ),
        ),
      );
      final grid = tester.widget<GridView>(find.byType(GridView));
      final geometry =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(geometry.crossAxisCount, columns);
      expect(geometry.mainAxisExtent, 292.5); // 234px target tile / 0.8.
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('unknown automatic view does not show a misleading List/Grid', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FileLoadingSkeleton(
            viewMode: ViewMode.list,
            layoutKnown: false,
          ),
        ),
      ),
    );
    expect(find.byType(AdaptiveFileList), findsNothing);
    expect(find.byType(GridView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

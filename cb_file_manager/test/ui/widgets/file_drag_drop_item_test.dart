import 'dart:ui' show PointerDeviceKind;
import 'package:cb_file_manager/ui/widgets/file_drag_drop_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('leaving the view hands all selected files to native drag once', (
    tester,
  ) async {
    const paths = {'/files/one.txt', '/files/two.txt'};
    final handedOff = <List<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileDragDropItem(
            path: paths.first,
            isFolder: false,
            selectedPaths: paths,
            onStartFileDrag: handedOff.add,
            child: const SizedBox(
              width: 120,
              height: 60,
              child: Text('source'),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      const Offset(40, 30),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(25, 0));
    await tester.pump();
    expect(handedOff, isEmpty);
    await gesture.moveTo(const Offset(-20, 30));
    await tester.pump();
    expect(handedOff, hasLength(1));
    expect(handedOff.single, unorderedEquals(paths));
    await gesture.up();
    await tester.pump();
    expect(find.text('2 items'), findsNothing);
  });

  testWidgets(
    'selected files drop as one move and native hit test finds the same folder',
    (tester) async {
      const sources = {'/files/one.txt', '/files/two.txt'};
      const destination = '/files/destination';
      List<String>? moved;
      String? movedTo;
      late BuildContext viewContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                viewContext = context;
                return Padding(
                  padding: const EdgeInsets.only(left: 83, top: 67),
                  child: Column(
                    children: [
                      FileDragDropItem(
                        path: sources.first,
                        isFolder: false,
                        selectedPaths: sources,
                        child: const SizedBox(
                          key: ValueKey('source'),
                          width: 200,
                          height: 60,
                          child: Text('one.txt'),
                        ),
                      ),
                      const SizedBox(height: 90),
                      FileDragDropItem(
                        path: destination,
                        isFolder: true,
                        selectedPaths: sources,
                        onMoveItemsToFolder: (paths, folder) async {
                          moved = paths;
                          movedTo = folder;
                        },
                        child: const SizedBox(
                          key: ValueKey('destination'),
                          width: 200,
                          height: 60,
                          child: Text('destination'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      final target = tester.getCenter(
        find.byKey(const ValueKey('destination')),
      );
      expect(FileDragDropItem.folderAt(viewContext, target), destination);
      expect(
        FileDragDropItem.folderAt(viewContext, const Offset(1, 1)),
        isNull,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('source'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(moved, unorderedEquals(sources));
      expect(movedTo, destination);
    },
  );
}

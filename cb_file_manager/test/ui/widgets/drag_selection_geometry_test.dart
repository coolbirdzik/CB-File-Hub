import 'package:cb_file_manager/ui/widgets/drag_selection_geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'converts a local drag rectangle to the global item coordinate space',
    (tester) async {
      final interactionSurfaceKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.only(left: 37, top: 113),
              child: SizedBox(
                key: interactionSurfaceKey,
                width: 300,
                height: 300,
              ),
            ),
          ),
        ),
      );

      final interactionSurface =
          interactionSurfaceKey.currentContext!.findRenderObject()!
              as RenderBox;
      const localRect = Rect.fromLTWH(10, 20, 100, 80);
      final globalRect = dragSelectionRectToGlobal(
        localRect,
        interactionSurface,
      );

      expect(globalRect, localRect.shift(const Offset(37, 113)));

      const tagInsideVisibleDrag = Rect.fromLTWH(90, 160, 20, 20);
      expect(
        globalRect.overlaps(tagInsideVisibleDrag),
        isTrue,
        reason: 'a tag visibly inside the local drag rectangle must be hit',
      );
      expect(
        localRect.overlaps(tagInsideVisibleDrag),
        isFalse,
        reason: 'the old local-vs-global comparison skipped this tag',
      );
    },
  );

  test('keeps the local rectangle when the surface is unavailable', () {
    const localRect = Rect.fromLTWH(10, 20, 100, 80);

    expect(dragSelectionRectToGlobal(localRect, null), localRect);
  });
}

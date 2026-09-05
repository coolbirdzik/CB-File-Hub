// Pins how the in-place rename editor behaves inside a grid tile.
//
// Grid tiles budget a fixed-height band for the file name — 40px, 58px when
// tags are shown — and that budget is measured for the bare label, which is
// free to ellipsise. An editor cannot ellipsise: hiding the text being typed
// is the one thing a rename box must never do. So the editor is lifted into
// the overlay, pinned to the band, and allowed to wrap downward over the tiles
// below. These tests hold that line: the name stays whole, and nothing
// overflows the tile it came from.
import 'package:cb_file_manager/design_system/primitives/cb_inline_rename.dart';
import 'package:cb_file_manager/ui/controllers/inline_rename_controller.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/widgets/inline_rename_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tile at the default grid zoom, and the band inside it once both grid
/// items have applied their 4px inset.
const double _tileWidth = 174.6;
const double _bandInset = 4.0;
const double _bandWithoutTags =
    GridZoomConstraints.gridItemNameAreaHeight - _bandInset;

/// The label style the grid passes to the editor.
const TextStyle _gridLabelStyle = TextStyle(
  fontSize: GridZoomConstraints.gridItemFilenameFontSize,
  fontWeight: FontWeight.w500,
);

const String _longName =
    'holiday-2026-reykjavik-northern-lights-final-export-v3.mp4';

InlineRenameController _renaming(String name) {
  final controller = InlineRenameController();
  addTearDown(controller.dispose);
  controller.startRename('C:\\photos\\$name');
  return controller;
}

/// The tile's name area: a fixed band holding the label, with the editor
/// lifted out of it while a rename runs.
Widget _tile({
  required InlineRenameController controller,
  required bool renaming,
  String name = _longName,
  double bandHeight = GridZoomConstraints.gridItemNameAreaHeight,
  List<Widget> below = const <Widget>[],
}) {
  final label = Text(
    name,
    style: _gridLabelStyle,
    textAlign: TextAlign.center,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );

  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: _tileWidth,
          child: SizedBox(
            height: bandHeight,
            child: Padding(
              padding: const EdgeInsets.only(
                top: _bandInset,
                left: _bandInset,
                right: _bandInset,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: renaming
                        ? CbInlineRenameOverlay(
                            active: true,
                            label: label,
                            editorBuilder: (context) => InlineRenameField(
                              controller: controller,
                              onCommit: () async {},
                              onCancel: () {},
                              textStyle: _gridLabelStyle,
                              textAlign: TextAlign.center,
                              maxLines: cbInlineRenameMaxLines,
                            ),
                          )
                        : label,
                  ),
                  ...below,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the lifted editor wraps instead of cutting the name off', (
    tester,
  ) async {
    final controller = _renaming(_longName);

    await tester.pumpWidget(_tile(controller: controller, renaming: true));
    // Second frame: the band has reported its width to the overlay.
    await tester.pump();

    final editor = find.byType(InlineRenameField);
    expect(editor, findsOneWidget);

    // Wrapped, not clipped: taller than the band it was lifted out of.
    expect(
      tester.getSize(editor).height,
      greaterThan(_bandWithoutTags),
      reason: 'a name this long cannot fit the band, so the editor must grow',
    );

    // The whole name is still in the editor, untouched.
    expect(controller.textController!.text, _longName);
  });

  testWidgets('the lifted editor is mounted and focused on the first frame', (
    tester,
  ) async {
    final controller = _renaming(_longName);

    // One frame only: the editor must be in the overlay immediately, or the
    // focus request the rename controller schedules lands on nothing and the
    // user is left typing into the void.
    await tester.pumpWidget(_tile(controller: controller, renaming: true));
    expect(find.byType(InlineRenameField), findsOneWidget);

    await tester.pump();
    expect(controller.focusNode!.hasFocus, isTrue);
  });

  testWidgets('a short name gets a one-line box, not the full cap', (
    tester,
  ) async {
    const short = 'notes.txt';
    final controller = _renaming(short);

    await tester.pumpWidget(
      _tile(controller: controller, renaming: true, name: short),
    );
    await tester.pump();

    final double height = tester.getSize(find.byType(InlineRenameField)).height;

    // A multi-line TextField reserves every one of its `maxLines` unless it is
    // also told where to start, which opened a five-line box for "notes.txt".
    expect(
      height,
      lessThan(_bandWithoutTags),
      reason: 'a name this short must not reserve room it does not need',
    );
  });

  testWidgets('the editor is as wide as the band it covers', (tester) async {
    final controller = _renaming(_longName);

    await tester.pumpWidget(_tile(controller: controller, renaming: true));
    await tester.pump();

    expect(
      tester.getSize(find.byType(InlineRenameField)).width,
      moreOrLessEquals(_tileWidth - _bandInset * 2, epsilon: 0.5),
    );
  });

  testWidgets('growing past the band does not overflow the tile', (
    tester,
  ) async {
    final controller = _renaming(_longName);

    await tester.pumpWidget(
      _tile(
        controller: controller,
        renaming: true,
        bandHeight: GridZoomConstraints.gridItemNameAreaHeightWithTags,
        below: const <Widget>[
          SizedBox(height: 2),
          SizedBox(height: 16, width: 60),
        ],
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the label keeps the band while the editor is open', (
    tester,
  ) async {
    final controller = _renaming(_longName);

    await tester.pumpWidget(_tile(controller: controller, renaming: false));
    await tester.pump();
    final Size labelSlot = tester.getSize(find.byType(Text).first);

    await tester.pumpWidget(_tile(controller: controller, renaming: true));
    await tester.pump();

    // Same slot, so nothing in the tile reflows when the rename starts.
    expect(tester.getSize(find.byType(Text).first), labelSlot);
  });
}

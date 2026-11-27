import 'dart:ui' as ui;

import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The keyboard focus ring used to be a spread BoxShadow. Flutter paints a
/// shadow as a solid shape behind the box, so behind a translucent fill
/// (secondary/ghost buttons, cards) the whole control turned the ring colour
/// and its label became hard to read. The ring must stay outside the shape.
void main() {
  for (final dark in [false, true]) {
    testWidgets('focusing a secondary button leaves its fill alone '
        '(dark: $dark)', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: dark
              ? ThemeConfig.getDarkTheme()
              : ThemeConfig.getLightTheme(),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundary,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: CbButton(
                    focusNode: focus,
                    onPressed: () {},
                    // An empty label keeps the sampled pixel on the fill.
                    label: ' ',
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      Future<Color> centre() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        // Left inner edge of the button, clear of the ring and the label.
        final x = 8 + 4;
        final y = image.height ~/ 2;
        final i = (y * image.width + x) * 4;
        final color = Color.fromARGB(
          bytes.getUint8(i + 3),
          bytes.getUint8(i),
          bytes.getUint8(i + 1),
          bytes.getUint8(i + 2),
        );
        image.dispose();
        return color;
      }

      final resting = (await tester.runAsync(centre))!;
      focus.requestFocus();
      // Keyboard focus highlight mode is what shows the ring.
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      await tester.pumpAndSettle();
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(CbButton),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.boxShadow, isNull);
      expect(
        (decoration.border! as Border).top.strokeAlign,
        BorderSide.strokeAlignOutside,
      );
      final focused = (await tester.runAsync(centre))!;
      expect(focused, resting);
    });
  }
}

import 'dart:ui' as ui;

import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets('loading highlight travels from left to right', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      host(
        RepaintBoundary(
          key: key,
          child: const CbLoadingText(
            text: 'MMMMMMMM',
            baseColor: Colors.red,
            highlightColor: Colors.blue,
            style: TextStyle(fontFamily: 'Ahem', fontSize: 20),
          ),
        ),
      ),
    );
    Future<double> blueCenter() async {
      final result = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final width = image.width;
        final height = image.height;
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        image.dispose();
        var weight = 0.0;
        var weightedX = 0.0;
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            final i = (y * width + x) * 4;
            final blue = data.getUint8(i + 2) - data.getUint8(i);
            if (blue > 0 && data.getUint8(i + 3) > 0) {
              weight += blue;
              weightedX += blue * x;
            }
          }
        }
        expect(weight, greaterThan(0));
        return weightedX / weight / width;
      });
      return result!;
    }

    await tester.pump(const Duration(milliseconds: 300));
    final first = await blueCenter();
    await tester.pump(const Duration(milliseconds: 550));
    final second = await blueCenter();
    expect(first, lessThan(.5));
    expect(second, greaterThan(.5));
    expect(second, greaterThan(first));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('motion disabled uses a static accessible label', (tester) async {
    await tester.pumpWidget(
      host(const CbLoadingText(text: 'Processing'), reduceMotion: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Processing'), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('compact loading marker fits icon slots and retains its label', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const SizedBox.square(
          dimension: 10,
          child: CbLoadingText(text: 'Loading content', compact: true),
        ),
      ),
    );
    expect(
      tester.widget<Text>(find.text('…')).semanticsLabel,
      'Loading content',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

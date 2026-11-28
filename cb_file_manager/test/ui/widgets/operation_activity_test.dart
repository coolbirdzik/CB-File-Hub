import 'package:cb_file_manager/design_system/primitives/cb_loading_text.dart';
import 'package:cb_file_manager/ui/widgets/operation_activity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('activity frames do not repaint the surrounding content', (
    tester,
  ) async {
    var surroundingPaints = 0;
    await tester.pumpWidget(
      host(
        CustomPaint(
          painter: _PaintCounter(() => surroundingPaints++),
          child: const OperationActivityIcon(
            running: true,
            icon: Icons.delete_outline,
            color: Colors.blue,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    surroundingPaints = 0;
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(surroundingPaints, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'progress interpolates from the displayed value to the new count',
    (tester) async {
      Widget bar(double value) =>
          host(OperationProgressBar(value: value, color: Colors.blue));
      await tester.pumpWidget(bar(0));
      await tester.pumpWidget(bar(0.8));
      await tester.pump(const Duration(milliseconds: 120));
      final midway = tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;
      expect(midway, greaterThan(0));
      expect(midway, lessThan(0.8));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.8,
      );
    },
  );

  testWidgets('running activity transitions to a static completion icon', (
    tester,
  ) async {
    Widget activity(bool running) => host(
      OperationActivityIcon(
        running: running,
        icon: Icons.check_circle,
        color: Colors.green,
      ),
    );
    await tester.pumpWidget(activity(true));
    expect(find.byType(CbLoadingText), findsOneWidget);
    await tester.pumpWidget(activity(false));
    await tester.pumpAndSettle();
    expect(find.byType(CbLoadingText), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion keeps activity static and progress immediate', (
    tester,
  ) async {
    Widget content(double? value) => host(
      Column(
        children: [
          const OperationActivityIcon(
            running: true,
            icon: Icons.delete_outline,
            color: Colors.blue,
          ),
          OperationProgressBar(value: value, color: Colors.blue),
        ],
      ),
      reduceMotion: true,
    );
    await tester.pumpWidget(content(null));
    await tester.pumpAndSettle();
    expect(find.byType(CbLoadingText), findsNothing);
    await tester.pumpWidget(content(0.7));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.7,
    );
  });
}

class _PaintCounter extends CustomPainter {
  _PaintCounter(this.onPaint);

  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) => onPaint();

  @override
  bool shouldRepaint(_PaintCounter oldDelegate) => false;
}

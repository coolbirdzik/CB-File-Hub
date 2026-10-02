import 'package:cb_file_manager/ui/widgets/stable_layout_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inherited changes invalidate a reused builder widget', (
    tester,
  ) async {
    final theme = ValueNotifier<Color>(Colors.blue);
    addTearDown(theme.dispose);
    var builds = 0;
    final body = StableLayoutBuilder<int>(
      layoutValue: (_) => 1,
      builder: (context, _) {
        builds++;
        return ColoredBox(
          key: const ValueKey('color'),
          color: Theme.of(context).colorScheme.primary,
        );
      },
    );
    await tester.pumpWidget(
      ValueListenableBuilder<Color>(
        valueListenable: theme,
        child: body,
        builder: (_, color, child) => MaterialApp(
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: color)),
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester
        .widget<ColoredBox>(find.byKey(const ValueKey('color')))
        .color;
    final count = builds;
    theme.value = Colors.red;
    await tester.pumpAndSettle();
    expect(builds, greaterThan(count));
    expect(
      tester.widget<ColoredBox>(find.byKey(const ValueKey('color'))).color,
      isNot(before),
    );
  });

  testWidgets(
    'pixel resize relayouts without rebuilding until geometry changes',
    (tester) async {
      final width = ValueNotifier<double>(300);
      addTearDown(width.dispose);
      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: ValueListenableBuilder<double>(
              valueListenable: width,
              child: StableLayoutBuilder<int>(
                layoutValue: (constraints) =>
                    (constraints.maxWidth / 100).floor(),
                builder: (_, columns) {
                  builds++;
                  return SizedBox(
                    key: const ValueKey('body'),
                    height: 100,
                    child: Text('$columns'),
                  );
                },
              ),
              builder: (_, w, child) => SizedBox(width: w, child: child),
            ),
          ),
        ),
      );
      for (var i = 1; i <= 50; i++) {
        width.value = 300 + i.toDouble();
        await tester.pump();
        expect(
          tester.getSize(find.byKey(const ValueKey('body'))).width,
          width.value,
        );
      }
      expect(builds, 1);
      width.value = 400;
      await tester.pump();
      expect(builds, 2);
      expect(find.text('4'), findsOneWidget);
    },
  );

  testWidgets('data and inherited theme updates invalidate cached contents', (
    tester,
  ) async {
    var builds = 0;
    Widget app(String text, Color color) => MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: color)),
      home: StableLayoutBuilder<int>(
        layoutValue: (_) => 1,
        builder: (context, _) {
          builds++;
          return Text(
            text,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          );
        },
      ),
    );
    await tester.pumpWidget(app('first', Colors.blue));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app('second', Colors.blue));
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
    final before = tester.widget<Text>(find.text('second')).style!.color;
    final count = builds;
    await tester.pumpWidget(app('second', Colors.red));
    await tester.pumpAndSettle();
    expect(builds, greaterThan(count));
    expect(
      tester.widget<Text>(find.text('second')).style!.color,
      isNot(before),
    );
  });
}

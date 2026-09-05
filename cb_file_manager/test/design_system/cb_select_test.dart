import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the behaviour a `DropdownButton` gave for free, so replacing it did
/// not quietly cost the app keyboard support or dismissal.
void _ignore(String _) {}

void main() {
  Widget host(Widget child, {Alignment alignment = Alignment.center}) {
    return MaterialApp(
      theme: ThemeConfig.getLightTheme(),
      home: Scaffold(
        body: Align(alignment: alignment, child: child),
      ),
    );
  }

  const items = <CbSelectItem<String>>[
    CbSelectItem(value: 'cover', label: 'Cover'),
    CbSelectItem(value: 'contain', label: 'Contain'),
    CbSelectItem(value: 'fill', label: 'Fill'),
  ];

  testWidgets('shows the selected label and no Material dropdown', (t) async {
    await t.pumpWidget(
      host(CbSelect<String>(items: items, value: 'contain', onChanged: (_) {})),
    );

    expect(find.text('Contain'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
  });

  testWidgets('falls back to the placeholder when the value matches nothing', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        CbSelect<String>(
          items: items,
          value: 'stretch',
          placeholder: 'Choose a fit',
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Choose a fit'), findsOneWidget);
  });

  testWidgets('tapping opens the popover and picking reports the value', (
    t,
  ) async {
    String? picked;
    await t.pumpWidget(
      host(
        CbSelect<String>(
          items: items,
          value: 'cover',
          onChanged: (value) => picked = value,
        ),
      ),
    );

    await t.tap(find.text('Cover'));
    await t.pumpAndSettle();

    // Every option is on screen; the trigger's own label is the second
    // 'Cover'.
    expect(find.text('Contain'), findsOneWidget);
    expect(find.text('Fill'), findsOneWidget);

    await t.tap(find.text('Fill'));
    await t.pumpAndSettle();

    expect(picked, 'fill');
    expect(find.text('Contain'), findsNothing, reason: 'menu should be closed');
  });

  testWidgets('arrow keys move the highlight and Enter commits it', (t) async {
    String? picked;
    await t.pumpWidget(
      host(
        CbSelect<String>(
          items: items,
          value: 'cover',
          onChanged: (value) => picked = value,
        ),
      ),
    );

    await t.tap(find.text('Cover'));
    await t.pumpAndSettle();

    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();

    expect(picked, 'contain');
  });

  testWidgets('Escape dismisses without reporting a value', (t) async {
    String? picked;
    await t.pumpWidget(
      host(
        CbSelect<String>(
          items: items,
          value: 'cover',
          onChanged: (value) => picked = value,
        ),
      ),
    );

    await t.tap(find.text('Cover'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();

    expect(picked, isNull);
    expect(find.text('Contain'), findsNothing);
  });

  testWidgets('tapping outside dismisses without reporting a value', (t) async {
    String? picked;
    await t.pumpWidget(
      host(
        CbSelect<String>(
          items: items,
          value: 'cover',
          onChanged: (value) => picked = value,
        ),
      ),
    );

    await t.tap(find.text('Cover'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(4, 4));
    await t.pumpAndSettle();

    expect(picked, isNull);
    expect(find.text('Contain'), findsNothing);
  });

  testWidgets('a disabled select does not open', (t) async {
    await t.pumpWidget(
      host(
        CbSelect<String>(
          items: items,
          value: 'cover',
          enabled: false,
          onChanged: (_) {},
        ),
      ),
    );

    await t.tap(find.text('Cover'));
    await t.pumpAndSettle();

    expect(find.text('Contain'), findsNothing);
  });

  testWidgets('a null onChanged leaves the control inert', (t) async {
    await t.pumpWidget(
      host(
        const CbSelect<String>(items: items, value: 'cover', onChanged: null),
      ),
    );

    await t.tap(find.text('Cover'));
    await t.pumpAndSettle();

    expect(find.text('Contain'), findsNothing);
  });

  testWidgets('the popover anchors to the trigger, not to the label above it', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        CbSelect<String>(
          items: items,
          value: 'cover',
          label: 'Thumbnail fit',
          helperText: 'How thumbnails fill their tile',
          onChanged: (_) {},
        ),
      ),
    );

    final Rect trigger = t.getRect(find.byType(CbPressable));
    await t.tap(find.text('Cover'));
    await t.pumpAndSettle();

    final Rect menu = t.getRect(find.byType(ListView));
    expect(menu.top, greaterThanOrEqualTo(trigger.bottom));
    // Helper text sits below the trigger; anchoring to the whole column would
    // push the menu past it.
    expect(menu.top - trigger.bottom, lessThan(12));
  });

  testWidgets('flips above the trigger when there is no room below', (t) async {
    await t.pumpWidget(
      host(
        CbSelect<String>(items: items, value: 'cover', onChanged: (_) {}),
        alignment: Alignment.bottomCenter,
      ),
    );

    final Rect trigger = t.getRect(find.byType(CbPressable));
    await t.tap(find.text('Cover'));
    await t.pumpAndSettle();

    expect(
      t.getRect(find.byType(ListView)).bottom,
      lessThanOrEqualTo(trigger.top),
    );
  });

  testWidgets('survives the unbounded width a Row or Wrap hands it', (t) async {
    // A `Row`/`Wrap` lays out a non-flex child with unbounded width, which is
    // an error for anything flexible inside the trigger.
    await t.pumpWidget(
      host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sort'),
            CbSelect<String>(items: items, value: 'cover', onChanged: (_) {}),
          ],
        ),
      ),
    );

    expect(t.takeException(), isNull);
    expect(find.text('Cover'), findsOneWidget);

    await t.tap(find.text('Cover'));
    await t.pumpAndSettle();
    expect(find.text('Contain'), findsOneWidget);
  });

  testWidgets('ellipsises its label when the width is too small', (t) async {
    await t.pumpWidget(
      host(
        const SizedBox(
          width: 70,
          child: CbSelect<String>(
            items: [
              CbSelectItem(value: 'x', label: 'A very long option label'),
            ],
            value: 'x',
            onChanged: _ignore,
          ),
        ),
      ),
    );

    expect(t.takeException(), isNull);
    final Text label = t.widget<Text>(find.text('A very long option label'));
    expect(label.overflow, TextOverflow.ellipsis);
  });

  testWidgets('triggerLabel shortens the trigger but not the menu row', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        const CbSelect<String>(
          items: [
            CbSelectItem(
              value: 'c',
              label: 'C: (128 GB free)',
              triggerLabel: 'C:',
            ),
            CbSelectItem(
              value: 'd',
              label: 'D: (412 GB free)',
              triggerLabel: 'D:',
            ),
          ],
          value: 'c',
          onChanged: _ignore,
        ),
      ),
    );

    expect(find.text('C:'), findsOneWidget);
    expect(find.text('C: (128 GB free)'), findsNothing);

    await t.tap(find.text('C:'));
    await t.pumpAndSettle();

    expect(find.text('C: (128 GB free)'), findsOneWidget);
    expect(find.text('D: (412 GB free)'), findsOneWidget);
  });

  testWidgets('fromValues labels each value', (t) async {
    int? picked;
    await t.pumpWidget(
      host(
        CbSelect.fromValues<int>(
          values: const [5, 15, 30],
          value: 15,
          labelBuilder: (v) => '$v minutes',
          onChanged: (v) => picked = v,
        ),
      ),
    );

    expect(find.text('15 minutes'), findsOneWidget);

    await t.tap(find.text('15 minutes'));
    await t.pumpAndSettle();
    await t.tap(find.text('30 minutes'));
    await t.pumpAndSettle();

    expect(picked, 30);
  });
}

// Pins the reason the tags page detects double-clicks by hand.
//
// Clicking a tag used to take roughly half a second to highlight. Two delays
// were stacked: the grid's InkWell registered an `onDoubleTap`, which makes the
// recogniser hold every tap until its double-tap window closes, and on top of
// that `_handleTagTap` ran the selection behind a 250ms timer of its own.
//
// The first delay is framework behaviour, measured here so the fix is anchored
// to something real rather than to a remembered number: an InkWell that offers
// a double tap cannot report a single one promptly, so the page must do that
// arbitration itself and keep `onTap` alone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Taps the widget and reports how much simulated time passed before `onTap`
/// was delivered.
Future<Duration> _tapLatency(
  WidgetTester tester, {
  required bool offersDoubleTap,
}) async {
  Duration? firedAt;
  Duration elapsed = Duration.zero;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Material(
            child: InkWell(
              onTap: () => firedAt = elapsed,
              onDoubleTap: offersDoubleTap ? () {} : null,
              // Present in both cases on purpose: a long-press handler is the
              // usual suspect for a late tap, and holding it constant shows it
              // is not the one costing anything here.
              onLongPress: () {},
              child: const SizedBox(width: 120, height: 40),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.byType(InkWell));

  // Advance in small steps until the callback lands, so the result is the
  // delay itself rather than whatever a single large pump would hide.
  const step = Duration(milliseconds: 10);
  while (firedAt == null && elapsed < const Duration(seconds: 1)) {
    elapsed += step;
    await tester.pump(step);
  }

  expect(firedAt, isNotNull, reason: 'onTap never fired');
  return firedAt!;
}

void main() {
  testWidgets('an InkWell offering a double tap holds the single tap back', (
    tester,
  ) async {
    final delayed = await _tapLatency(tester, offersDoubleTap: true);

    // Measured at 300ms; asserted loosely so a framework tweak to the window
    // reads as a change in degree rather than a failure.
    expect(
      delayed,
      greaterThanOrEqualTo(const Duration(milliseconds: 200)),
      reason: 'this hold is what made a tag click feel late',
    );
  });

  testWidgets('without one, the tap is immediate even with a long press', (
    tester,
  ) async {
    final immediate = await _tapLatency(tester, offersDoubleTap: false);

    expect(
      immediate,
      lessThanOrEqualTo(const Duration(milliseconds: 10)),
      reason: 'the tags grid relies on this: no onDoubleTap, no hold',
    );
  });
}

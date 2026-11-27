import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

/// The viewport containing an item, rather than an unrelated sidebar or path bar.
/// Capture its Element so recycling the item does not invalidate later gestures.
Finder scrollableForE2EItem(Finder item) {
  final ancestors = find.ancestor(
    of: item.first,
    matching: find.byType(Scrollable),
  );
  if (ancestors.evaluate().isEmpty) {
    throw StateError(
      'No scrollable viewport contains the requested item: $item',
    );
  }
  final viewport = ancestors.evaluate().first;
  return find.byElementPredicate(
    (element) => identical(element, viewport),
    description: 'scrollable viewport containing the requested item',
  );
}

/// UI animation settling only. Async I/O must use [waitForE2ECondition] and
/// assert its result: an idle frame does not prove a directory/model is ready.
Future<void> settleE2EUi(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 50),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

/// Poll the observable result, returning as soon as it is ready. Bound both
/// wall time (desktop integration tests) and virtual time (widget tests).
Future<bool> waitForE2ECondition(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  const interval = Duration(milliseconds: 50);
  final clock = Stopwatch()..start();
  var pumped = Duration.zero;
  while (!condition()) {
    if (clock.elapsed >= timeout || pumped >= timeout) return false;
    await tester.pump(interval);
    pumped += interval;
  }
  return true;
}

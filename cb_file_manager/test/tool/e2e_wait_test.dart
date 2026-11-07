import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/e2e_wait.dart';

void main() {
  testWidgets(
    'idle UI settles with a short frame instead of a seconds-long wait',
    (tester) async {
      final start = tester.binding.clock.now();
      await settleE2EUi(tester);
      expect(
        tester.binding.clock.now().difference(start),
        const Duration(milliseconds: 50),
      );
    },
  );

  testWidgets(
    'condition waits for async results even with no scheduled frames',
    (tester) async {
      var ready = false;
      final task = Future<void>.delayed(const Duration(milliseconds: 250), () {
        ready = true;
      });
      expect(await waitForE2ECondition(tester, () => ready), isTrue);
      await task;
      final start = tester.binding.clock.now();
      expect(await waitForE2ECondition(tester, () => ready), isTrue);
      expect(tester.binding.clock.now(), start);
    },
  );

  testWidgets('missing condition terminates under the widget fake clock', (
    tester,
  ) async {
    final start = tester.binding.clock.now();
    expect(
      await waitForE2ECondition(
        tester,
        () => false,
        timeout: const Duration(milliseconds: 200),
      ),
      isFalse,
    );
    expect(
      tester.binding.clock.now().difference(start),
      const Duration(milliseconds: 200),
    );
  });

  testWidgets(
    'a permanent animation cannot silently pass a settling assertion',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: CircularProgressIndicator()),
      );
      Object? failure;
      try {
        await settleE2EUi(tester);
      } catch (error) {
        failure = error;
      }
      expect(failure, isA<FlutterError>());
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

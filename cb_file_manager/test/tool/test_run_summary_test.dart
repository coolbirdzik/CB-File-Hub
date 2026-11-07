import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_run_summary.dart';

void main() {
  String report({
    bool skipped = false,
    bool hidden = false,
    bool done = true,
    String result = 'success',
  }) => [
    'Building desktop app...',
    jsonEncode({
      'type': 'testStart',
      'time': 10,
      'test': {'id': 1, 'name': 'case'},
    }),
    jsonEncode({
      'type': 'testDone',
      'time': 60,
      'testID': 1,
      'hidden': hidden,
      'skipped': skipped,
      'result': result,
    }),
    if (done) jsonEncode({'type': 'done', 'success': result == 'success'}),
  ].join('\n');

  test('completed assertions produce a pass and duration', () {
    final summary = TestRunSummary.parse(report());
    expect(summary.successful, isTrue);
    expect(summary.passed, 1);
    expect(summary.durationsMs['case'], 50);
  });

  test(
    'empty, skipped-only and incomplete runs never become cached passes',
    () {
      for (final input in [
        '',
        report(skipped: true),
        report(done: false),
        report(hidden: true),
      ]) {
        expect(TestRunSummary.parse(input).successful, isFalse, reason: input);
      }
    },
  );

  test('setup failures count even when hidden', () {
    final summary = TestRunSummary.parse(report(hidden: true, result: 'error'));
    expect(summary.successful, isFalse);
    expect(summary.failed, 1);
  });
}

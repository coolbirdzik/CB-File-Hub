import 'dart:convert';

/// A zero exit code alone is insufficient: an empty filter, skipped suite or
/// truncated report must never be recorded as a successful E2E run.
class TestRunSummary {
  final int passed;
  final int failed;
  final int skipped;
  final bool finished;
  final Map<String, int> durationsMs;

  const TestRunSummary({
    required this.passed,
    required this.failed,
    required this.skipped,
    required this.finished,
    required this.durationsMs,
  });

  bool get successful => finished && passed > 0 && failed == 0;

  factory TestRunSummary.parse(String content) {
    final starts = <int, (String, int)>{};
    final durations = <String, int>{};
    var passed = 0;
    var failed = 0;
    var skipped = 0;
    var finished = false;
    for (final line in const LineSplitter().convert(content)) {
      final Object? value;
      try {
        value = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (value is! Map<String, dynamic>) continue;
      switch (value['type']) {
        case 'testStart':
          final test = value['test'] as Map<String, dynamic>;
          starts[test['id'] as int] = (
            test['name'] as String,
            value['time'] as int? ?? 0,
          );
        case 'testDone':
          if (value['result'] == 'error' || value['result'] == 'failure') {
            failed++;
          }
          if (value['hidden'] == true) continue;
          final start = starts[value['testID']];
          if (start == null || start.$1.startsWith('loading ')) continue;
          if (value['skipped'] == true) {
            skipped++;
          } else {
            if (value['result'] == 'success') passed++;
            durations[start.$1] =
                (value['time'] as int? ?? start.$2) - start.$2;
          }
        case 'done':
          finished = value['success'] == true;
      }
    }
    return TestRunSummary(
      passed: passed,
      failed: failed,
      skipped: skipped,
      finished: finished,
      durationsMs: durations,
    );
  }
}

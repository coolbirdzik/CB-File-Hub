// Read an existing Flutter JSON report; never launches a test or build hook.
import 'dart:convert';
import 'dart:io';

import 'test_run_summary.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart tool/test_timing_report.dart <report.jsonl>');
    exitCode = 64;
    return;
  }
  final summary = TestRunSummary.parse(await File(args.single).readAsString());
  final sorted = summary.durationsMs.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final output = File('${args.single}.timings.json');
  await output.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'passed': summary.passed,
      'failed': summary.failed,
      'skipped': summary.skipped,
      'finished': summary.finished,
      'tests': [
        for (final test in sorted)
          {'name': test.key, 'milliseconds': test.value},
      ],
    }),
  );
  stdout.writeln('Slowest executed tests (build/loading excluded):');
  for (final test in sorted.take(10)) {
    stdout.writeln('  ${(test.value / 1000).toStringAsFixed(2)}s  ${test.key}');
  }
  stdout.writeln('Full timings: ${output.path}');
}

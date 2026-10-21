// Prints only the failed unit/widget tests from a `--file-reporter json:...`
// report: each failure's error, stack trace and the output that test printed.
// Passing tests stay silent, so a CI log shows the failure and nothing else.
//
// Usage (from cb_file_manager):
//   flutter test --reporter silent --file-reporter json:build/unit_test_report.jsonl
//   dart tool/unit_test_failures.dart build/unit_test_report.jsonl
//
// Exits 1 when a test failed, a suite failed to load or the run never finished.

import 'dart:convert';
import 'dart:io';

/// Output a failing test printed before it failed, kept to the newest lines.
const _maxPrintedLines = 80;

class _Test {
  final String name;
  final int? suiteId;
  final prints = <String>[];
  final errors = <String>[];
  String? result;
  bool hidden = false;
  bool skipped = false;

  _Test(this.name, this.suiteId);

  bool get failed =>
      errors.isNotEmpty || (result != null && result != 'success');
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart tool/unit_test_failures.dart <report.jsonl>');
    exit(64);
  }
  final report = File(args.first);
  if (!report.existsSync()) {
    stderr.writeln(
      'No test report at ${report.path}; flutter test did not run.',
    );
    exit(1);
  }

  final suites = <int, String>{};
  final tests = <int, _Test>{};
  bool? success;
  for (final line in await report.readAsLines()) {
    final Map<String, dynamic> event;
    try {
      event = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
    switch (event['type']) {
      case 'suite':
        final suite = event['suite'] as Map<String, dynamic>;
        suites[suite['id'] as int] = suite['path'] as String? ?? '';
      case 'testStart':
        final test = event['test'] as Map<String, dynamic>;
        tests[test['id'] as int] = _Test(
          test['name'] as String,
          test['suiteID'] as int?,
        );
      case 'print':
        tests[event['testID']]?.prints.add(event['message'] as String);
      case 'error':
        tests[event['testID']]?.errors.add(
          '${event['error']}\n${event['stackTrace']}'.trim(),
        );
      case 'testDone':
        final test = tests[event['testID']];
        if (test == null) break;
        test
          ..result = event['result'] as String?
          ..hidden = event['hidden'] == true
          ..skipped = event['skipped'] == true;
      case 'done':
        success = event['success'] as bool?;
    }
  }

  final visible = tests.values.where((test) => !test.hidden);
  final skipped = visible.where((test) => test.skipped).length;
  // Hidden entries are suite loading and setUpAll/tearDownAll; they only
  // matter when they fail.
  final failed = tests.values.where((test) => test.failed).toList();
  final passed =
      visible.length - skipped - failed.where((t) => !t.hidden).length;

  final github = Platform.environment['GITHUB_ACTIONS'] == 'true';
  for (final test in failed) {
    final path = _relative(suites[test.suiteId] ?? '');
    stdout
      ..writeln()
      ..writeln('FAILED: $path')
      ..writeln('  ${test.name}');
    if (test.prints.isNotEmpty) {
      final lines = test.prints.expand(const LineSplitter().convert).toList();
      final shown = lines.length > _maxPrintedLines
          ? lines.sublist(lines.length - _maxPrintedLines)
          : lines;
      stdout.writeln(
        '  --- output${shown.length < lines.length ? ' (last $_maxPrintedLines lines)' : ''} ---',
      );
      for (final line in shown) {
        stdout.writeln('  $line');
      }
    }
    for (final error in test.errors) {
      stdout.writeln('  --- error ---');
      for (final line in const LineSplitter().convert(error)) {
        stdout.writeln('  $line');
      }
    }
    if (github) {
      final message = test.errors.isEmpty
          ? 'Test ${test.result ?? 'did not finish'}'
          : test.errors.first;
      stdout.writeln(
        '::error file=${_escape('cb_file_manager/$path', property: true)},'
        'title=${_escape(test.name, property: true)}::${_escape(message)}',
      );
    }
  }

  stdout
    ..writeln()
    ..writeln(
      'Unit/widget tests: $passed passed, $skipped skipped, '
      '${failed.length} failed${success == null ? ', run did not finish' : ''}',
    );
  if (failed.isNotEmpty || success != true) exit(1);
}

String _relative(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final index = normalized.lastIndexOf('/cb_file_manager/');
  return index == -1
      ? normalized
      : normalized.substring(index + '/cb_file_manager/'.length);
}

/// GitHub workflow command escaping; properties also escape `:` and `,`.
String _escape(String value, {bool property = false}) {
  var escaped = value
      .replaceAll('%', '%25')
      .replaceAll('\r', '%0D')
      .replaceAll('\n', '%0A');
  if (property) {
    escaped = escaped.replaceAll(':', '%3A').replaceAll(',', '%2C');
  }
  return escaped;
}

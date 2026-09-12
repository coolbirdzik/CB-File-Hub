// Summarizes failed E2E tests from a log file that may mix:
// - Flutter `--reporter expanded` lines (… ` [E]`)
// - Flutter `--reporter json` lines (testDone with result != success)
//
// Usage (from cb_file_manager):
//   dart run tool/e2e_summarize_failures.dart build/e2e_last_run.log

import 'dart:convert';
import 'dart:io';

final _expandedFailure = RegExp(r'^\d+:\d+\s+\+\d+\s+-\d+:\s+(.+)\s+\[E\]\s*$');

Future<void> main(List<String> args) async {
  final paths = args.where((a) => !a.startsWith('-')).toList();
  final List<String> allLines;
  if (paths.isEmpty) {
    allLines = await stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .toList();
  } else {
    allLines = await File(paths.first).readAsLines();
  }

  final jsonSummary = _failuresFromJson(allLines);
  final failed = <String>{};
  failed.addAll(_failuresFromExpanded(allLines));
  failed.addAll(jsonSummary.failedNames);

  _printBox(
    failed.toList()..sort(),
    logPath: paths.isEmpty ? null : paths.first,
    diagnosticsByTest: jsonSummary.diagnosticsByTest,
  );
}

Set<String> _failuresFromExpanded(List<String> allLines) {
  final failed = <String>{};
  for (final line in allLines) {
    final m = _expandedFailure.firstMatch(line.trimRight());
    if (m != null) {
      failed.add(m.group(1)!.trim());
    }
  }
  return failed;
}

/// Matches the placeholder flutter_test's own default exception reporter
/// substitutes for an uncaught FlutterError (e.g. a RenderFlex overflow
/// during layout). The real error text isn't lost — FlutterError.
/// dumpErrorToConsole prints it separately as plain "print" events — but
/// the structured "error" field only ever contains this generic sentence,
/// so a naive reader of the JSONL sees nothing useful. See
/// package:flutter_test/src/test_exception_reporter.dart.
bool _isGenericFlutterErrorPlaceholder(String diagnostic) =>
    diagnostic.startsWith('Test failed. See exception logs above.');

_JsonFailureSummary _failuresFromJson(List<String> allLines) {
  final idToName = <int, String>{};
  final failed = <String>{};
  final diagnosticsByTestId = <int, List<String>>{};
  final printsByTestId = <int, List<String>>{};
  for (final line in allLines) {
    final t = line.trim();
    if (t.isEmpty || !t.startsWith('{')) {
      continue;
    }
    final Map<String, dynamic>? decoded;
    try {
      decoded = jsonDecode(line) as Map<String, dynamic>?;
    } catch (_) {
      continue;
    }
    final j = decoded;
    if (j == null) continue;
    final type = j['type'] as String?;
    if (type == 'testStart') {
      final test = j['test'] as Map<String, dynamic>?;
      if (test != null) {
        final id = test['id'];
        final name = test['name'] as String?;
        if (id is int && name != null) {
          idToName[id] = name;
        }
      }
    } else if (type == 'print') {
      final testID = j['testID'];
      final message = j['message'];
      if (testID is int && message is String) {
        printsByTestId.putIfAbsent(testID, () => []).add(message);
      }
    } else if (type == 'error') {
      final testID = j['testID'];
      if (testID is! int) continue;
      final error = j['error'];
      final stackTrace = j['stackTrace'];
      final diagnostics = diagnosticsByTestId.putIfAbsent(testID, () => []);
      if (error is String && error.trim().isNotEmpty) {
        diagnostics.add(error.trim());
        if (_isGenericFlutterErrorPlaceholder(error.trim())) {
          final block = _extractFlutterErrorBlock(
            printsByTestId[testID] ?? const [],
          );
          if (block != null) diagnostics.add(block);
        }
      }
      if (stackTrace is String && stackTrace.trim().isNotEmpty) {
        diagnostics.add(stackTrace.trim());
      }
    } else if (type == 'testDone') {
      final result = j['result'] as String?;
      final testID = j['testID'];
      if (testID is int &&
          result != null &&
          result != 'success' &&
          j['hidden'] != true) {
        failed.add(idToName[testID] ?? 'testId=$testID');
      }
    }
  }
  final diagnosticsByTest = <String, List<String>>{};
  for (final entry in diagnosticsByTestId.entries) {
    final testName = idToName[entry.key] ?? 'testId=${entry.key}';
    diagnosticsByTest[testName] = entry.value;
  }
  return _JsonFailureSummary(
    failedNames: failed,
    diagnosticsByTest: diagnosticsByTest,
  );
}

/// Recovers the real FlutterError text for a test whose structured "error"
/// field is only the generic placeholder. `FlutterError.dumpErrorToConsole`
/// prints the actual box (`══╡ EXCEPTION CAUGHT BY ... ╞══`, the assertion,
/// the offending widget) as plain lines tagged with the same testID, so it's
/// recoverable from the test's own print stream — just not from the "error"
/// field flutter_test itself populates.
String? _extractFlutterErrorBlock(List<String> prints) {
  final start = prints.lastIndexWhere((m) => m.contains('EXCEPTION CAUGHT BY'));
  if (start == -1) return null;
  const maxLines = 40;
  final block = <String>[];
  for (var i = start; i < prints.length && block.length < maxLines; i++) {
    block.add(prints[i]);
    // The box closes with a full-width line of '═' — stop there rather than
    // spilling into whatever the test printed next.
    if (i > start &&
        prints[i].trim().isNotEmpty &&
        prints[i].trim().split('').toSet().length == 1 &&
        prints[i].contains('═')) {
      break;
    }
  }
  return block.join('\n');
}

void _printBox(
  List<String> failed, {
  String? logPath,
  Map<String, List<String>> diagnosticsByTest = const {},
}) {
  if (failed.isEmpty) {
    return;
  }
  const bar = '============================================================';
  final out = stderr;
  out.writeln('');
  out.writeln(bar);
  out.writeln('E2E FAILED / ERRORED (${failed.length}):');
  out.writeln(bar);
  for (final name in failed) {
    out.writeln('  - $name');
    final diagnostics = diagnosticsByTest[name];
    if (diagnostics == null) continue;
    for (final diagnostic in diagnostics) {
      for (final line in const LineSplitter().convert(diagnostic)) {
        out.writeln('      $line');
      }
    }
  }
  out.writeln(bar);
  final displayedLogPath = logPath ?? 'standard input';
  out.writeln('Full log: $displayedLogPath');
  if (logPath != null) {
    out.writeln('Quick grep: findstr /C:"\\"type\\":\\"error\\"" $logPath');
  }
  out.writeln('JSON log:   make dev-test-e2e-json -> build/e2e_report.jsonl');
  out.writeln('');
}

class _JsonFailureSummary {
  final Set<String> failedNames;
  final Map<String, List<String>> diagnosticsByTest;

  const _JsonFailureSummary({
    required this.failedNames,
    required this.diagnosticsByTest,
  });
}

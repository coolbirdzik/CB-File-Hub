// Summarizes failed E2E tests from a log file that may mix:
// - Flutter `--reporter expanded` lines (… ` [E]`)
// - Flutter `--reporter json` lines (testDone with result != success)
//
// Usage (from cb_file_manager):
//   dart run tool/e2e_summarize_failures.dart build/e2e_last_run.log

import 'dart:convert';
import 'dart:io';

final _expandedFailure = RegExp(
  r'^\d+:\d+\s+\+\d+\s+-\d+:\s+(.+)\s+\[E\]\s*$',
);

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

  final failed = <String>{};
  failed.addAll(_failuresFromExpanded(allLines));
  failed.addAll(_failuresFromJson(allLines));

  _printBox(failed.toList()..sort());
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

Set<String> _failuresFromJson(List<String> allLines) {
  final idToName = <int, String>{};
  final failed = <String>{};
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
  return failed;
}

void _printBox(List<String> failed) {
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
    out.writeln('  • $name');
  }
  out.writeln(bar);
  out.writeln('Full log: cb_file_manager/build/e2e_last_run.log');
  out.writeln('Quick grep: findstr /C:"[E]" build\\e2e_last_run.log   (PowerShell: Select-String)');
  out.writeln('JSON log:   make dev-test-e2e-json  → build/e2e_report.jsonl');
  out.writeln('');
}

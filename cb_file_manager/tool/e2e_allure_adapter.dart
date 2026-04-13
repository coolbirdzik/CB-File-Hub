// Converts Flutter `--reporter json` E2E output + screenshots
// into Allure JSON result files under build/allure-results/.
//
// Allure expects one JSON file per test in build/allure-results/:
//   {uuid}.json  — test result with status, labels, attachments
//
// How it works:
//   1. flutter test --reporter json → build/e2e_report.jsonl
//   2. Screenshots land in build/windows.png / build/linux.png etc.
//   3. This script reads both and emits Allure JSON files.
//
// Usage (from cb_file_manager):
//   dart run tool/e2e_allure_adapter.dart build/e2e_report.jsonl
//
// To also collect screenshots pass the build dir:
//   dart run tool/e2e_allure_adapter.dart build/e2e_report.jsonl --build-dir build

import 'dart:convert';
import 'dart:io';

const _kAllureResultsDir = 'build/allure-results';
const _kScreenshotsDir = 'build';

// ---------------------------------------------------------------------------
// Allure JSON result model
// ---------------------------------------------------------------------------

/// Simplified Allure test-result JSON schema.
/// https://allurereport.org/docs/how-it-works-test-result-file/
class AllureTestResult {
  final String uuid;
  final String name;
  final String status; // passed | failed | broken | skipped
  final int? duration; // milliseconds (optional)
  final String? message; // error message for failed/broken
  final String? trace; // stack trace
  final List<AllureLabel> labels;
  final List<AllureAttachment> attachments;

  AllureTestResult({
    required this.uuid,
    required this.name,
    required this.status,
    this.duration,
    this.message,
    this.trace,
    this.labels = const [],
    this.attachments = const [],
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'uuid': uuid,
      'name': name,
      'status': status,
      'labels': labels.map((l) => {'name': l.name, 'value': l.value}).toList(),
    };
    if (duration != null) map['duration'] = duration;
    if (message != null) map['message'] = message;
    if (trace != null) map['trace'] = trace;
    if (attachments.isNotEmpty) {
      map['attachments'] = attachments.map((a) => a.toJson()).toList();
    }
    return map;
  }
}

class AllureLabel {
  final String name;
  final String value;
  const AllureLabel(this.name, this.value);
}

class AllureAttachment {
  final String name;
  final String type; // screenshot | text | json
  final String source; // relative filename in allure-results directory
  const AllureAttachment(this.name, this.type, this.source);

  Map<String, dynamic> toJson() =>
      {'name': name, 'type': type, 'source': source};
}

// ---------------------------------------------------------------------------
// Flutter JSON → Allure conversion
// ---------------------------------------------------------------------------

/// Parses flutter `--reporter json` lines and produces AllureTestResult list.
List<AllureTestResult> parseFlutterJsonLog(String logContent,
    {String? buildDir}) {
  final results = <AllureTestResult>[];
  final idToName = <int, String>{};
  final idToStartTime = <int, DateTime>{};
  final idToEndTime = <int, DateTime>{};
  final idToError = <int, _ErrorInfo>{};

  for (final rawLine in logContent.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || !line.startsWith('{')) continue;

    Map<String, dynamic>? decoded;
    try {
      decoded = jsonDecode(line) as Map<String, dynamic>?;
    } catch (_) {
      continue;
    }
    if (decoded == null) continue;

    final type = decoded['type'] as String?;

    if (type == 'testStart') {
      final test = decoded['test'] as Map<String, dynamic>?;
      if (test != null) {
        final id = test['id'] as int?;
        final name = test['name'] as String?;
        if (id != null && name != null) {
          idToName[id] = name;
          idToStartTime[id] =
              DateTime.now(); // flutter json doesn't expose start time
        }
      }
    } else if (type == 'testDone') {
      final testID = decoded['testID'] as int?;
      if (testID == null || !idToName.containsKey(testID)) continue;

      idToEndTime[testID] = DateTime.now();

      final hidden = decoded['hidden'] as bool? ?? false;
      if (hidden) continue;

      // Extract error info
      final errorLines = decoded['error'] as String?;
      if (errorLines != null && errorLines.isNotEmpty) {
        idToError[testID] = _ErrorInfo(
          message: _firstLine(errorLines),
          trace: errorLines,
        );
      }
    } else if (type == 'sessionFinished') {
      // End of session — compute duration for tests that have end times
      for (final testID in idToName.keys) {
        if (idToEndTime.containsKey(testID)) {
          // duration will be set in final conversion below
        }
      }
    }
  }

  // Build Allure results
  for (final entry in idToName.entries) {
    final testID = entry.key;
    final name = entry.value;
    final error = idToError[testID];
    final endTime = idToEndTime[testID];
    final startTime = idToStartTime[testID];

    // Determine status
    String status;
    if (error != null) {
      status = 'failed';
    } else {
      status = 'passed'; // no error in log = passed
    }

    // Duration in ms
    int? durationMs;
    if (startTime != null && endTime != null) {
      durationMs = endTime.difference(startTime).inMilliseconds;
    }

    // Parse suite name from test name (e.g. "sandbox lists two files and a subfolder")
    final suiteLabel = _inferSuiteLabel(name);

    // Find matching screenshot if available
    final attachments = <AllureAttachment>[];
    final screenshotName =
        _screenshotForTest(name, buildDir ?? _kScreenshotsDir);
    if (screenshotName != null) {
      attachments.add(
          AllureAttachment('Failure screenshot', 'image/png', screenshotName));
    }

    results.add(AllureTestResult(
      uuid: _uuidForTest(name, testID),
      name: name,
      status: status,
      duration: durationMs,
      message: error?.message,
      trace: error?.trace,
      labels: [
        AllureLabel('package', 'cb_file_manager.e2e'),
        AllureLabel('testClass', suiteLabel),
        AllureLabel('suite', suiteLabel),
        AllureLabel('feature', suiteLabel),
        AllureLabel('severity', 'critical'),
      ],
      attachments: attachments,
    ));
  }

  return results;
}

class _ErrorInfo {
  final String message;
  final String trace;
  const _ErrorInfo({required this.message, required this.trace});
}

String _firstLine(String s) {
  final idx = s.indexOf('\n');
  return idx >= 0 ? s.substring(0, idx) : s;
}

/// Infers a suite/feature label from the test name.
String _inferSuiteLabel(String name) {
  // 1. Explicit group() prefix (present in JSON reporter output)
  const groupPrefixes = [
    'Navigation',
    'File Operations',
    'Cut & Move',
    'Folder Operations',
    'Multi-Select',
    'Keyboard Shortcuts',
    'Edge Cases',
  ];
  for (final prefix in groupPrefixes) {
    if (name.startsWith('$prefix ')) return prefix;
  }

  // 2. Keyword-based inference (backward compatibility)
  final lower = name.toLowerCase();
  if (lower.contains('cut') && lower.contains('move')) return 'Cut & Move';
  if (lower.contains('folder') &&
      (lower.contains('copy') ||
          lower.contains('delete') ||
          lower.contains('rename'))) {
    return 'Folder Operations';
  }
  if (lower.contains('f5') ||
      (lower.contains('refresh') && !lower.contains('folder'))) {
    return 'Keyboard Shortcuts';
  }
  if (lower.contains('select all') ||
      lower.contains('ctrl+a') ||
      lower.contains('batch')) {
    return 'Multi-Select';
  }
  if (lower.contains('multi-select') || lower.contains('multi select')) {
    return 'Multi-Select';
  }
  if (lower.contains('sandbox') ||
      lower.contains('subfolder') ||
      lower.contains('navigate') ||
      lower.contains('empty') ||
      lower.contains('backspace')) {
    return 'Navigation';
  }
  if (lower.contains('create') ||
      lower.contains('copy') ||
      lower.contains('paste') ||
      lower.contains('rename') ||
      lower.contains('delete') ||
      lower.contains('file operation')) {
    return 'File Operations';
  }
  return 'E2E Tests';
}

/// Generates a stable UUID-like ID for a test.
String _uuidForTest(String name, int testID) {
  // Simple deterministic ID: hash of name + testID
  final combined = '$name::$testID';
  var hash = 0;
  for (var i = 0; i < combined.length; i++) {
    hash = ((hash << 5) - hash + combined.codeUnitAt(i)) & 0xFFFFFFFF;
  }
  // Ensure positive
  if (hash < 0) hash = -hash;
  return '${hash.toRadixString(16).padLeft(8, '0')}-${testID.toRadixString(16).padLeft(8, '0')}';
}

/// Returns the basename of the screenshot if it exists in the build dir.
String? _screenshotForTest(String name, String buildDir) {
  // Screenshots from IntegrationTestWidgetsFlutterBinding.takeScreenshot
  // land in the build dir with the name we passed (e.g. "sandbox_lists_two_files_failure.png")
  final candidateBase = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s]'), '')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll('failure', 'failure'); // keep failure suffix as-is

  // Try both the exact name and the failure-suffixed variant
  final candidates = [
    '${candidateBase}.png',
    '${candidateBase}_failure.png',
  ];

  // Also try common suffixes that E2E tests use
  final knownSuffixes = ['_failure', '_error', ''];
  for (final suffix in knownSuffixes) {
    final base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    candidates.add('$base$suffix.png');
  }

  for (final candidate in candidates) {
    final file = File('$buildDir/$candidate');
    if (file.existsSync()) {
      return candidate;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Writing Allure results
// ---------------------------------------------------------------------------

Future<void> writeAllureResults(
    List<AllureTestResult> results, String resultsDir) async {
  final dir = Directory(resultsDir);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  int written = 0;
  for (final result in results) {
    final file = File('$resultsDir/${result.uuid}.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(result.toJson()),
    );
    written++;
  }

  print('[Allure] Wrote $written test results to $resultsDir/');
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  print('[Allure adapter] Starting...');

  String? logPath;
  String? buildDir;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--build-dir' && i + 1 < args.length) {
      buildDir = args[++i];
    } else if (!a.startsWith('--')) {
      logPath = a;
    }
  }

  if (logPath == null) {
    print(
        'Usage: dart run tool/e2e_allure_adapter.dart <jsonl-log> [--build-dir <build-dir>]');
    print(
        '  <jsonl-log>   Path to flutter --reporter json output (e.g. build/e2e_report.jsonl)');
    print('  --build-dir   Directory containing screenshots (default: build)');
    exit(1);
  }

  final logFile = File(logPath);
  if (!await logFile.exists()) {
    print('[Allure adapter] ERROR: Log file not found: $logPath');
    print('  Run: make dev-test-e2e-json');
    exit(1);
  }

  final logContent = await logFile.readAsString();
  if (logContent.trim().isEmpty) {
    print('[Allure adapter] ERROR: Log file is empty: $logPath');
    exit(1);
  }

  print('[Allure adapter] Parsing $logPath...');
  final results =
      parseFlutterJsonLog(logContent, buildDir: buildDir ?? 'build');

  if (results.isEmpty) {
    print('[Allure adapter] WARNING: No test results parsed from log.');
    print('  Make sure the log contains flutter --reporter json output.');
    exit(0);
  }

  // Also copy screenshots into allure-results/
  final resultsDir = _kAllureResultsDir;
  final resultsDirObj = Directory(resultsDir);
  if (!await resultsDirObj.exists()) {
    await resultsDirObj.create(recursive: true);
  }

  for (final result in results) {
    for (final attachment in result.attachments) {
      final src = File('${buildDir ?? 'build'}/${attachment.source}');
      if (await src.exists()) {
        final dst = File('$resultsDir/${attachment.source}');
        await src.copy(dst.path);
        print('[Allure] Copied screenshot: ${attachment.source}');
      }
    }
  }

  await writeAllureResults(results, resultsDir);

  print('');
  print('[Allure] Results written to $resultsDir/');
  print('[Allure] To generate HTML report:');
  print(
      "         npx allure generate $resultsDir --clean -o build/allure-report");
  print('[Allure] To serve report:');
  print("         npx allure serve $resultsDir");
  print('');
}

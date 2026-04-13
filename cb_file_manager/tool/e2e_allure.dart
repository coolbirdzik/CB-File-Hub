// Runs E2E tests and generates an HTML test dashboard.
//
// Flow:
//   1. Kill stray cb_file_hub.exe (Windows)
//   2. Run flutter test --reporter json  →  build/e2e_report.jsonl
//   3. Parse JSON → write Allure JSON results  →  build/allure-results/
//   4. Generate pure-Dart HTML dashboard  →  build/e2e_dashboard/index.html
//   5. Save failed test names for RERUN=1
//
// Usage (from cb_file_manager):
//   dart run tool/e2e_allure.dart                                # run all + dashboard
//   dart run tool/e2e_allure.dart --rerun-failed                 # skip passed, rerun failed
//   dart run tool/e2e_allure.dart --plain-name "Navigation"      # run only matching suite
//   dart run tool/e2e_allure.dart --no-open                      # skip auto-opening browser
//   dart run tool/e2e_allure.dart --full-startup                 # include production startup services
//   dart run tool/e2e_allure.dart --full-screenshots             # capture every E2E action
//
// Makefile:
//   make dev-test mode=e2e               # E2E + dashboard (auto-opens browser)
//   make dev-test mode=e2e RERUN=1       # skip passed, rerun failed only
//   make dev-test mode=e2e TEST=Navigation  # run only Navigation suite

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final rerunFailed = args.contains('--rerun-failed');
  final skipGenerate = args.contains('--no-generate');
  final noOpen = args.contains('--no-open');
  final dryRun = args.contains('--dry-run');
  final fullStartup = args.contains('--full-startup');
  final fullScreenshots = args.contains('--full-screenshots');

  // Extract --file value if provided (e.g. --file video_thumbnails_e2e_test)
  // FILE= takes priority over the default app_e2e_test.dart
  String testFile = 'integration_test/app_e2e_test.dart';
  final fileIdx = args.indexOf('--file');
  if (fileIdx >= 0 && fileIdx + 1 < args.length) {
    final fileArg = args[fileIdx + 1];
    final resolved = 'integration_test/$fileArg.dart';
    if (File(resolved).existsSync()) {
      testFile = resolved;
    } else {
      print('[Allure E2E] WARNING: file not found "$resolved" — using default.');
    }
  }

  // Extract --plain-name value if provided (e.g. --plain-name "Navigation")
  String? plainNameArg;
  final plainNameIdx = args.indexOf('--plain-name');
  if (plainNameIdx >= 0 && plainNameIdx + 1 < args.length) {
    plainNameArg = args[plainNameIdx + 1];
  }

  if (dryRun) {
    await _dryRun();
    return;
  }

  // Step 1: Kill stray Windows instances
  await _killCbFileHubOnWindows();

  // Step 2: Load failed tests for RERUN mode
  final device = Platform.environment['E2E_DEVICE'] ?? 'windows';
  final plainNameFilter = rerunFailed ? await _loadFailedTests() : null;

  if (rerunFailed && plainNameFilter == null) {
    print('[Allure E2E] No previous failures found — running all tests.');
  } else if (rerunFailed) {
    final count = plainNameFilter!.split('|').length;
    print('[Allure E2E] Rerunning $count failed test(s) only...');
  }

  // Build --plain-name filter:
  //   Priority: --rerun-failed (failed tests list) > explicit --plain-name arg
  final effectivePlainName = plainNameFilter ?? plainNameArg;
  if (plainNameArg != null && plainNameFilter == null) {
    print('[Allure E2E] Running suite filter: "$plainNameArg"');
  }

  // Step 3: Run flutter test --reporter json
  final logFile = File('build/e2e_report.jsonl');
  await logFile.parent.create(recursive: true);
  final logSink = logFile.openWrite();

  final List<String> extraArgs = effectivePlainName != null
      ? ['--plain-name', effectivePlainName]
      : <String>[];

  final flutterArgs = <String>[
    'test',
    testFile,
    '-d',
    device,
    '--dart-define=CB_E2E=true',
    '--dart-define=CB_E2E_FAST=${!fullStartup}',
    '--dart-define=CB_E2E_FULL_SCREENSHOTS=$fullScreenshots',
    '--reporter',
    'json',
    ...extraArgs,
  ];

  print('[Allure E2E] Running: flutter ${flutterArgs.join(' ')}');

  final proc = await Process.start(
    'flutter',
    flutterArgs,
    mode: ProcessStartMode.normal,
    runInShell: true,
  );

  await Future.wait<void>([
    _drain(proc.stdout, logSink, stdout),
    _drain(proc.stderr, stderr, stderr),
  ]);

  final testExitCode = await proc.exitCode;
  await logSink.close();

  // Step 4: Run Allure adapter (write Allure JSON results)
  print('[Allure E2E] Parsing results and generating Allure JSON...');

  final adapterResult = await Process.run(
    Platform.resolvedExecutable,
    [
      'run',
      'tool/e2e_allure_adapter.dart',
      'build/e2e_report.jsonl',
      '--build-dir',
      'build'
    ],
    workingDirectory: Directory.current.path,
  );

  stdout.write(adapterResult.stdout);
  if (adapterResult.stderr.isNotEmpty) stderr.write(adapterResult.stderr);

  // Step 5: Save failed tests for RERUN=1
  await _saveFailedTestsFromJson('build/e2e_report.jsonl');

  // Step 6: Write results.json so screenshot HTML shows pass/fail badges
  await _writeScreenshotResultsJson('build/e2e_report.jsonl');

  // Step 6b: Update screenshot HTML with embedded results (CORS workaround)
  await _updateScreenshotHtmlWithResults();

  // Step 7: Generate HTML dashboard
  if (!skipGenerate) {
    print('[Allure E2E] Generating HTML dashboard...');

    final dashResult = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'tool/e2e_dashboard.dart', '--build-dir', 'build'],
      workingDirectory: Directory.current.path,
    );

    stdout.write(dashResult.stdout);
    if (dashResult.stderr.isNotEmpty) stderr.write(dashResult.stderr);

    if (dashResult.exitCode == 0) {
      final absPath =
          '${Directory.current.path}/build/e2e_dashboard/index.html';
      print('[Allure E2E] Dashboard: file://$absPath');
      if (!noOpen) {
        await _openInBrowser(absPath);
      }
      // Dashboard is the deliverable — exit 0 so make stays happy
      await _killAllTestProcesses();
      exit(0);
    } else {
      print(
          '[Allure E2E] Dashboard generation failed (exit ${dashResult.exitCode}).');
    }
  }

  // Dashboard skipped or failed — exit with test exit code
  await _killAllTestProcesses();
  exit(testExitCode);
}

// ---------------------------------------------------------------------------
// Cleanup: kill all test processes after run
// ---------------------------------------------------------------------------

Future<void> _killAllTestProcesses() async {
  if (!Platform.isWindows) return;

  print('[Allure E2E] Cleaning up test processes...');

  final r1 = await Process.run(
    'taskkill',
    <String>['/F', '/IM', 'cb_file_hub.exe', '/T'],
    runInShell: false,
  );
  if (r1.exitCode != 0 && r1.exitCode != 128) {
    // May not exist — fine
  }

  final r2 = await Process.run(
    'taskkill',
    <String>['/F', '/IM', 'flutter_test.exe', '/T'],
    runInShell: false,
  );
  if (r2.exitCode != 0 && r2.exitCode != 128) {
    // May not exist — fine
  }

  print('[Allure E2E] Cleanup done.');
}

Future<void> _drain(
    Stream<List<int>> input, IOSink logSink, IOSink echoSink) async {
  await for (final chunk in input) {
    logSink.add(chunk);
    echoSink.add(chunk);
  }
}

/// Opens [filePath] in the default browser using a platform-native command.
/// Silently ignores errors so a missing browser never blocks the test run.
Future<void> _openInBrowser(String filePath) async {
  try {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', filePath],
          runInShell: false);
    } else if (Platform.isMacOS) {
      await Process.run('open', [filePath]);
    } else {
      await Process.run('xdg-open', [filePath]);
    }
  } catch (_) {
    // Opening the browser is best-effort; failures are non-fatal.
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> _killCbFileHubOnWindows() async {
  if (!Platform.isWindows) return;
  final r = await Process.run(
      'taskkill', <String>['/F', '/IM', 'cb_file_hub.exe', '/T'],
      runInShell: false);
  if (r.exitCode != 0 && r.exitCode != 128) {
    stderr.writeln('[E2E] taskkill exit ${r.exitCode} (continuing)');
  }
}

const _kFailedTestsFile = 'build/e2e_failed_tests.txt';

Future<String?> _loadFailedTests() async {
  final file = File(_kFailedTestsFile);
  if (!await file.exists()) return null;
  return (await file.readAsString()).trim();
}

Future<void> _saveFailedTestsFromJson(String logPath) async {
  final file = File(logPath);
  if (!await file.exists()) return;

  final content = await file.readAsString();
  final failedNames = _parseFailedTestsFromJson(content);

  final outFile = File(_kFailedTestsFile);
  await outFile.parent.create(recursive: true);

  if (failedNames.isEmpty) {
    await outFile.writeAsString('');
    print('[Allure E2E] All tests passed — cleared failure list.');
  } else {
    await outFile.writeAsString(failedNames.join('|'));
    print(
        '[Allure E2E] Saved ${failedNames.length} failed test(s) → $_kFailedTestsFile');
  }
}

List<String> _parseFailedTestsFromJson(String content) {
  final failed = <String>{};
  final idToName = <int, String>{};

  for (final rawLine in content.split('\n')) {
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
        if (id != null && name != null) idToName[id] = name;
      }
    } else if (type == 'testDone') {
      final result = decoded['result'] as String?;
      final testID = decoded['testID'] as int?;
      final hidden = decoded['hidden'] as bool? ?? false;
      if (testID != null && result != null && result != 'success' && !hidden) {
        failed.add(idToName[testID] ?? 'testId=$testID');
      }
    }
  }

  return failed.toList();
}

/// Parses the JSONL and writes build/e2e_report/results.json
/// so the screenshot HTML report can show pass/fail badges.
Future<void> _writeScreenshotResultsJson(String jsonlPath) async {
  final file = File(jsonlPath);
  if (!await file.exists()) return;
  final content = await file.readAsString();

  // Collect test results from JSONL
  final idToName = <int, String>{};
  final testResults = <String, bool>{};

  for (final line in content.split('\n')) {
    if (line.trim().isEmpty || !line.startsWith('{')) continue;
    dynamic decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      continue;
    }
    if (decoded is! Map) continue;
    final type = decoded['type'] as String?;
    if (type == 'testStart') {
      final test = decoded['test'] as Map?;
      if (test != null) {
        final id = test['id'] as int?;
        final name = test['name'] as String?;
        if (id != null && name != null) idToName[id] = name;
      }
    } else if (type == 'testDone') {
      final result = decoded['result'] as String?;
      final testID = decoded['testID'] as int?;
      final hidden = decoded['hidden'] as bool? ?? false;
      if (testID != null && result != null && !hidden) {
        final name = idToName[testID];
        if (name != null) testResults[name] = result == 'success';
      }
    }
  }

  // Write results.json for the screenshot report HTML
  // Strip suite prefix from test names to match HTML data-test-name attributes
  const suites = [
    'Navigation',
    'File Operations',
    'Cut & Move',
    'Folder Operations',
    'Multi-Select',
    'Keyboard Shortcuts',
    'Search & Filter',
    'View Mode',
    'Tab Management',
    'Edge Cases & Error Handling',
    'Extended File Operations',
    'Video Thumbnails',
  ];
  final strippedResults = <String, bool>{};
  for (final entry in testResults.entries) {
    final fullName = entry.key;
    final value = entry.value;
    // Strip suite prefix (e.g., "Navigation sandbox..." -> "sandbox...")
    String strippedName = fullName;
    for (final suite in suites) {
      if (fullName.startsWith('$suite ')) {
        strippedName = fullName.substring(suite.length + 1);
        break;
      }
    }
    strippedResults[strippedName] = value;
  }

  final reportDir = Directory('build/e2e_report');
  if (!await reportDir.exists()) await reportDir.create(recursive: true);
  final resultsFile = File('${reportDir.path}/results.json');
  final entries = strippedResults.entries
      .map((e) => '  "${_esc(e.key)}": ${e.value}')
      .join(',\n');
  await resultsFile.writeAsString('{\n$entries\n}');
  print(
      '[Allure E2E] Wrote ${strippedResults.length} test results → results.json');
}

String _esc(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll('"', '\\"')
    .replaceAll('\n', '\\n')
    .replaceAll('\r', '\\r')
    .replaceAll('\t', '\\t');

/// Updates the screenshot HTML to embed test results directly (CORS workaround).
/// Browsers block fetch() on file:// URLs, so we inject results into the HTML.
Future<void> _updateScreenshotHtmlWithResults() async {
  final htmlFile = File('build/e2e_report/report.html');
  final jsonFile = File('build/e2e_report/results.json');

  if (!await htmlFile.exists() || !await jsonFile.exists()) {
    print('[Allure E2E] Skipping HTML update - files not found');
    return;
  }

  final html = await htmlFile.readAsString();
  final jsonContent = await jsonFile.readAsString();

  // Replace the embedded _testResults variable with actual data
  // Look for: const _testResults = {...};
  final pattern = RegExp(r'const _testResults = \{[^}]*\};');
  final replacement = 'const _testResults = $jsonContent;';

  if (!pattern.hasMatch(html)) {
    print('[Allure E2E] Warning: Could not find _testResults in HTML');
    return;
  }

  final updatedHtml = html.replaceFirst(pattern, replacement);
  await htmlFile.writeAsString(updatedHtml);
  print('[Allure E2E] Updated screenshot HTML with embedded test results');
}

Future<void> _dryRun() async {
  print('[Dry run] E2E Allure runner');
  print('');
  print(
      '  dart run tool/e2e_allure.dart              Run all tests + dashboard');
  print(
      '  dart run tool/e2e_allure.dart --rerun-failed   Skip passed, rerun failed only');
  print('  dart run tool/e2e_allure.dart --no-generate    Skip dashboard');
  print(
      '  dart run tool/e2e_allure.dart --full-startup   Include production startup services');
  print(
      '  dart run tool/e2e_allure.dart --full-screenshots  Capture every E2E action');
  print(
      '  dart run tool/e2e_allure.dart --file video_thumbnails_e2e_test  Run by file name');
  print('  dart run tool/e2e_allure.dart --dry-run        This message');
  print('');
  final device = Platform.environment['E2E_DEVICE'] ?? 'windows';
  print('[Dry run] Device: $device');
}

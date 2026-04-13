// Runs E2E test groups in PARALLEL using multiple flutter test processes,
// then merges results into a single JSONL report for the dashboard.
//
// Key insight: each `flutter test -d windows` process spawns a desktop window.
// We can't share one window across groups, but we CAN run multiple windows
// in parallel — one process per group. This gives near-linear speedup
// when there are enough CPU cores / display servers.
//
// Usage (from cb_file_manager):
//   dart run tool/e2e_parallel.dart                      # all groups in parallel
//   dart run tool/e2e_parallel.dart --max-parallel 2     # limit concurrency
//   dart run tool/e2e_parallel.dart --plain-name "Navigation"   # single suite
//   dart run tool/e2e_parallel.dart --groups "View Mode|Search & Filter"
//   dart run tool/e2e_parallel.dart --no-generate         # skip dashboard
//   dart run tool/e2e_parallel.dart --no-open            # skip browser auto-open
//   dart run tool/e2e_parallel.dart --rerun-failed         # rerun previously failed
//   dart run tool/e2e_parallel.dart --full-startup         # include production startup services
//   dart run tool/e2e_parallel.dart --full-screenshots     # capture every E2E action
//
// After all workers finish, this script:
//   1. Merges per-group JSONL files into build/e2e_report.jsonl
//   2. Runs e2e_allure_adapter.dart on the merged report
//   3. Runs e2e_dashboard.dart to generate the HTML dashboard
//   4. Auto-opens the dashboard in the browser
//
// Individual worker logs are written to build/e2e_workers/ for debugging.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _kAllGroups = [
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

const _kWorkersDir = 'build/e2e_workers';
const _kWorkerBuildRoot = 'build/e2e_worker_builds';
const _kMergedJsonl = 'build/e2e_report.jsonl';
const _kMergedLog = 'build/e2e_last_run.log';
const _kFailedTestsFile = 'build/e2e_failed_tests.txt';

Future<void> main(List<String> args) async {
  // ---- Parse args ----
  final dryRun = args.contains('--dry-run');
  final noGenerate = args.contains('--no-generate');
  final noOpen = args.contains('--no-open') || noGenerate;
  final rerunFailed = args.contains('--rerun-failed');
  final fullStartup = args.contains('--full-startup');
  final fullScreenshots = args.contains('--full-screenshots');

  int maxParallel =
      Platform.numberOfProcessors < 4 ? Platform.numberOfProcessors : 4;
  final mpIdx = args.indexOf('--max-parallel');
  if (mpIdx >= 0 && mpIdx + 1 < args.length) {
    maxParallel = int.tryParse(args[mpIdx + 1]) ?? maxParallel;
  }
  if (maxParallel < 1) maxParallel = 1;

  String? plainNameArg;
  final pnIdx = args.indexOf('--plain-name');
  if (pnIdx >= 0 && pnIdx + 1 < args.length) {
    plainNameArg = args[pnIdx + 1];
  }
  String? groupsArg;
  final groupsIdx = args.indexOf('--groups');
  if (groupsIdx >= 0 && groupsIdx + 1 < args.length) {
    groupsArg = args[groupsIdx + 1];
  }

  // --file overrides the default test file (e.g. --file video_thumbnails_e2e_test)
  // When a file is specified, parallel mode is disabled — run in serial.
  String testFile = 'integration_test/app_e2e_test.dart';
  bool fileMode = false;
  final fileIdx = args.indexOf('--file');
  if (fileIdx >= 0 && fileIdx + 1 < args.length) {
    final fileArg = args[fileIdx + 1];
    final resolved = 'integration_test/$fileArg.dart';
    print('[Parallel E2E] Received --file: "$fileArg" → resolved: "$resolved"');
    if (File(resolved).existsSync()) {
      testFile = resolved;
      fileMode = true;
    } else {
      print('[Parallel E2E] WARNING: file not found "$resolved" — using default.');
    }
  }

  if (dryRun) {
    _printDryRun();
    await _killAllTestProcesses();
    return;
  }

  // ---- Kill stray Windows instances ----
  await _killCbFileHubOnWindows();

  // Avoid each worker running pub get concurrently against .dart_tool.
  await _runPubGetOnce();

  // ---- Determine groups to run ----
  List<String> groups;
  if (plainNameArg != null) {
    groups = [plainNameArg];
  } else if (groupsArg != null) {
    groups = groupsArg
        .split(RegExp(r'[|,]'))
        .map((group) => group.trim())
        .where((group) => group.isNotEmpty)
        .toList();
    if (groups.isEmpty) {
      stderr.writeln('[Parallel E2E] --groups did not contain any groups.');
      exit(64);
    }
  } else if (rerunFailed) {
    groups = await _loadFailedGroups();
    if (groups.isEmpty) {
      print('[Parallel E2E] No previous failures found — running all groups.');
      groups = _kAllGroups;
    } else {
      print('[Parallel E2E] Rerunning ${groups.length} failed group(s): '
          '${groups.join(", ")}');
    }
  } else {
    groups = _kAllGroups;
  }

  // ---- File mode: run single test file directly, skip parallel workers ----
  if (fileMode) {
    print('[Parallel E2E] Running file: $testFile');
    // Build extra args (plain name filter if provided)
    final extraArgs = plainNameArg != null
        ? ['--plain-name', plainNameArg]
        : <String>[];

    await _runSingleFile(
      testFile: testFile,
      extraArgs: extraArgs,
      fullStartup: fullStartup,
      fullScreenshots: fullScreenshots,
      doNotOpenBrowser: noOpen,
    );
    return;
  }

  if (maxParallel < groups.length) {
    print('[Parallel E2E] Limiting to $maxParallel parallel workers '
        '(${groups.length} groups total)');
  }

  // ---- Prepare output directories ----
  final workersDir = Directory(_kWorkersDir);
  if (await workersDir.exists()) {
    await workersDir.delete(recursive: true);
  }
  await workersDir.create(recursive: true);

  // ---- Warmup build cache, then launch workers in parallel ----
  //
  // On Windows, each `flutter test -d windows` compiles the app via MSBuild.
  // If multiple processes build simultaneously they can deadlock on file locks.
  // Strategy: run the FIRST group alone to warm the build cache, then run
  // remaining groups in parallel (they reuse the cached build — instant start).
  //
  // Skip warmup when running a single group or when --no-warmup is set.
  final noWarmup = args.contains('--no-warmup') || groups.length <= 1;

  final results = <String, _WorkerResult>{};

  if (!noWarmup) {
    final warmupGroup = groups.first;
    print('[Parallel E2E] Warmup build: running "$warmupGroup" first '
        'to cache the build...\n');
    results[warmupGroup] = await _runWorker(warmupGroup,
        fullStartup: fullStartup, fullScreenshots: fullScreenshots);

    final remaining = groups.skip(1).toList();
    print('\n[Parallel E2E] Build cached. Launching ${remaining.length} '
        'remaining group(s) ($maxParallel workers max)...\n');

    final semaphore = _Semaphore(maxParallel);
    final futures = <Future<void>>[];
    for (final group in remaining) {
      futures.add(() async {
        await semaphore.acquire();
        try {
          results[group] = await _runWorker(group,
              fullStartup: fullStartup, fullScreenshots: fullScreenshots);
        } finally {
          semaphore.release();
        }
      }());
    }
    await Future.wait(futures);
  } else {
    print('[Parallel E2E] Launching ${groups.length} test group(s) '
        '($maxParallel workers max)...\n');

    final semaphore = _Semaphore(maxParallel);
    final futures = <Future<void>>[];
    for (final group in groups) {
      futures.add(() async {
        await semaphore.acquire();
        try {
          results[group] = await _runWorker(group,
              fullStartup: fullStartup, fullScreenshots: fullScreenshots);
        } finally {
          semaphore.release();
        }
      }());
    }
    await Future.wait(futures);
  }

  // ---- Print summary ----
  _printSummary(results);

  // ---- Merge JSONL outputs ----
  print('\n[Parallel E2E] Merging worker outputs...');
  await _mergeWorkerOutputs(results);

  // ---- Extract test results from merged JSONL for screenshot HTML ----
  print('\n[Parallel E2E] Extracting test results...');
  await _writeScreenshotResultsJson(_kMergedJsonl);

  // ---- Update screenshot HTML with embedded results (CORS workaround) ----
  await _updateScreenshotHtmlWithResults();

  // ---- Save failed groups for RERUN ----
  await _saveFailedGroupsFromMerged(_kMergedJsonl);

  // ---- Generate dashboard (unless skipped) ----
  if (!noGenerate) {
    print('[Parallel E2E] Generating dashboard...');

    final adapter = await Process.run(
      Platform.resolvedExecutable,
      [
        'run',
        'tool/e2e_allure_adapter.dart',
        _kMergedJsonl,
        '--build-dir',
        'build'
      ],
      workingDirectory: Directory.current.path,
    );
    stdout.write(adapter.stdout);
    if (adapter.stderr.isNotEmpty) stderr.write(adapter.stderr);

    final dash = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'tool/e2e_dashboard.dart', '--build-dir', 'build'],
      workingDirectory: Directory.current.path,
    );
    stdout.write(dash.stdout);
    if (dash.stderr.isNotEmpty) stderr.write(dash.stderr);

    if (dash.exitCode == 0) {
      final absPath =
          '${Directory.current.path}/build/e2e_dashboard/index.html';
      print('[Parallel E2E] Dashboard: file://$absPath');
      if (!noOpen) await _openInBrowser(absPath);
      await _killAllTestProcesses();
      exit(0);
    } else {
      print(
          '[Parallel E2E] Dashboard generation failed (exit ${dash.exitCode}).');
    }
  }

  final hasFailures = results.values.any((r) => !r.success);
  await _killAllTestProcesses();
  exit(hasFailures ? 1 : 0);
}

// ---------------------------------------------------------------------------
// Single file runner (used by --file mode)
// ---------------------------------------------------------------------------

/// Runs a single test file directly, bypassing parallel group execution.
/// Used when --file is passed to run a specific test file like
/// video_thumbnails_e2e_test.dart.
Future<void> _runSingleFile({
  required String testFile,
  required List<String> extraArgs,
  required bool fullStartup,
  required bool fullScreenshots,
  required bool doNotOpenBrowser,
}) async {
  final device = Platform.environment['E2E_DEVICE'] ?? 'windows';

  final args = <String>[
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

  print('[Parallel E2E] Running: flutter ${args.join(' ')}');

  final stopwatch = Stopwatch()..start();

  final jsonlOut = 'build/e2e_report.jsonl';
  final logOut = 'build/e2e_last_run.log';
  final jsonlFile = File(jsonlOut);
  final jsonlSink = jsonlFile.openWrite();
  final logFile = File(logOut);
  final logSink = logFile.openWrite();

  final proc = await Process.start(
    'flutter',
    args,
    mode: ProcessStartMode.normal,
    runInShell: true,
  );

  await Future.wait<void>([
    _drain(proc.stdout, [jsonlSink, logSink, stdout]),
    _drain(proc.stderr, [logSink, stderr]),
  ]);

  final exitCode = await proc.exitCode;
  await jsonlSink.close();
  await logSink.close();
  stopwatch.stop();

  final passed = _countInJsonl(await jsonlFile.readAsString(), 'success');
  final failed = _countInJsonl(await jsonlFile.readAsString(), 'failure');

  final status = exitCode == 0 ? 'PASS' : 'FAIL';
  final elapsed = _formatDuration(stopwatch.elapsed);
  final filename = testFile.split('/').last;
  print('[File:$filename] $status ($elapsed) — '
      '$passed passed, $failed failed, ${passed + failed} total');

  // Generate the dashboard for the single-file results
  await _runPubGetOnce();
  final adapter = await Process.run(
    Platform.resolvedExecutable,
    ['run', 'tool/e2e_allure.dart', '--no-open', '--skip-generate'],
    workingDirectory: Directory.current.path,
  );
  if (adapter.stdout.isNotEmpty) stdout.write(adapter.stdout);
  if (adapter.stderr.isNotEmpty) stderr.write(adapter.stderr);

  final dash = await Process.run(
    Platform.resolvedExecutable,
    ['run', 'tool/e2e_dashboard.dart', '--build-dir', 'build'],
    workingDirectory: Directory.current.path,
  );
  stdout.write(dash.stdout);
  if (dash.stderr.isNotEmpty) stderr.write(dash.stderr);

  if (dash.exitCode == 0) {
    final absPath = '${Directory.current.path}/build/e2e_dashboard/index.html';
    print('[Parallel E2E] Dashboard: file://$absPath');
    if (!doNotOpenBrowser) await _openInBrowser(absPath);
  }

  await _killAllTestProcesses();
  exit(exitCode);
}

// ---------------------------------------------------------------------------
// Worker
// ---------------------------------------------------------------------------

Future<_WorkerResult> _runWorker(
  String group, {
  required bool fullStartup,
  required bool fullScreenshots,
}) async {
  final slug = group.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_').toLowerCase();
  final jsonlOut = '$_kWorkersDir/$slug.jsonl';
  final logOut = '$_kWorkersDir/$slug.log';

  final device = Platform.environment['E2E_DEVICE'] ?? 'windows';

  final args = <String>[
    'test',
    'integration_test/app_e2e_test.dart',
    '--no-pub',
    '-d',
    device,
    '--dart-define=CB_E2E=true',
    '--dart-define=CB_E2E_FAST=${!fullStartup}',
    '--dart-define=CB_E2E_FULL_SCREENSHOTS=$fullScreenshots',
    '--reporter',
    'json',
    '--plain-name',
    group,
  ];

  print('[Worker:$group] flutter ${args.join(' ')}');

  final stopwatch = Stopwatch()..start();

  final jsonlFile = File(jsonlOut);
  final jsonlSink = jsonlFile.openWrite();
  final logFile = File(logOut);
  final logSink = logFile.openWrite();
  final configDir = await _prepareWorkerFlutterConfig(slug);

  final proc = await Process.start(
    'flutter',
    args,
    mode: ProcessStartMode.normal,
    runInShell: true,
    environment: {
      if (Platform.isWindows) 'APPDATA': configDir.path,
      if (!Platform.isWindows) 'XDG_CONFIG_HOME': configDir.path,
    },
  );

  await Future.wait<void>([
    _drain(proc.stdout, [jsonlSink, logSink, stdout]),
    _drain(proc.stderr, [logSink, stderr]),
  ]);

  final exitCode = await proc.exitCode;
  await jsonlSink.close();
  await logSink.close();
  stopwatch.stop();

  final passed = _countInJsonl(await jsonlFile.readAsString(), 'success');
  final failed = _countInJsonl(await jsonlFile.readAsString(), 'failure');

  final status = exitCode == 0 ? 'PASS' : 'FAIL';
  final elapsed = _formatDuration(stopwatch.elapsed);
  print('[Worker:$group] $status ($elapsed) — '
      '$passed passed, $failed failed, ${passed + failed} total');

  return _WorkerResult(
    group: group,
    success: exitCode == 0,
    exitCode: exitCode,
    passed: passed,
    failed: failed,
    elapsedMs: stopwatch.elapsedMilliseconds,
    jsonlFile: jsonlOut,
    logFile: logOut,
  );
}

Future<void> _drain(Stream<List<int>> input, List<IOSink> sinks) async {
  await for (final chunk in input) {
    for (final sink in sinks) {
      sink.add(chunk);
    }
  }
}

Future<void> _runPubGetOnce() async {
  print('[Parallel E2E] Resolving Flutter dependencies once...');
  final result = await Process.run(
    'flutter',
    ['pub', 'get'],
    workingDirectory: Directory.current.path,
    runInShell: true,
  );
  stdout.write(result.stdout);
  if (result.stderr.isNotEmpty) {
    stderr.write(result.stderr);
  }
  if (result.exitCode != 0) {
    stderr.writeln('[Parallel E2E] flutter pub get failed.');
    exit(result.exitCode);
  }
}

Future<Directory> _prepareWorkerFlutterConfig(String slug) async {
  final configDir = Directory('$_kWorkersDir/flutter_config_$slug');
  await configDir.create(recursive: true);

  final buildDir = '$_kWorkerBuildRoot/$slug';
  final settings = <String, Object>{
    'build-dir': buildDir,
    'enable-windows-desktop': true,
  };

  final configFile = Platform.isWindows
      ? File('${configDir.path}/.flutter_settings')
      : File('${configDir.path}/flutter/settings');
  await configFile.parent.create(recursive: true);
  await configFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(settings),
  );

  return configDir;
}

// ---------------------------------------------------------------------------
// Merge
// ---------------------------------------------------------------------------

Future<void> _mergeWorkerOutputs(Map<String, _WorkerResult> results) async {
  final mergedJsonl = File(_kMergedJsonl);
  final mergedLog = File(_kMergedLog);
  if (await mergedJsonl.exists()) await mergedJsonl.delete();
  if (await mergedLog.exists()) await mergedLog.delete();

  // Pass 1: collect max ID per group
  final idOffset = <String, int>{};
  int runningMax = 0;
  for (final r in results.values) {
    idOffset[r.group] = runningMax;
    final file = File(r.jsonlFile);
    if (await file.exists()) {
      int localMax = 0;
      final content = await file.readAsString();
      for (final line in content.split('\n')) {
        if (line.trim().isEmpty || !line.startsWith('{')) continue;
        dynamic decoded;
        try {
          decoded = jsonDecode(line);
        } catch (_) {
          continue;
        }
        if (decoded is! Map) continue;
        final test = decoded['test'] as Map?;
        final startId = test?['id'] as int? ?? 0;
        final doneId = decoded['testID'] as int? ?? 0;
        if (startId > localMax) localMax = startId;
        if (doneId > localMax) localMax = doneId;
      }
      runningMax += localMax + 1;
    }
  }

  // Pass 2: write merged JSONL with offset IDs
  final jsonlSink = mergedJsonl.openWrite();
  final logSink = mergedLog.openWrite();

  for (final r in results.values) {
    final file = File(r.jsonlFile);
    final offset = idOffset[r.group] ?? 0;

    if (await file.exists()) {
      final content = await file.readAsString();
      for (final line in content.split('\n')) {
        if (line.trim().isEmpty || !line.startsWith('{')) continue;
        dynamic decoded;
        try {
          decoded = jsonDecode(line);
        } catch (_) {
          jsonlSink.writeln(line);
          continue;
        }
        if (decoded is! Map) {
          jsonlSink.writeln(line);
          continue;
        }

        if (decoded['test'] != null) {
          final test = decoded['test'] as Map;
          if (test['id'] != null) test['id'] = (test['id'] as int) + offset;
        }
        if (decoded['testID'] != null) {
          decoded['testID'] = (decoded['testID'] as int) + offset;
        }
        jsonlSink.writeln(jsonEncode(decoded));
      }
    }

    final logFile = File(r.logFile);
    if (await logFile.exists()) {
      logSink.writeln('${'=' * 60}\n=== Group: ${r.group} ===\n${'=' * 60}');
      logSink.add(await logFile.readAsBytes());
    }
  }

  await jsonlSink.close();
  await logSink.close();
}

// ---------------------------------------------------------------------------
// Failed tracking
// ---------------------------------------------------------------------------

Future<List<String>> _loadFailedGroups() async {
  final file = File(_kFailedTestsFile);
  if (!await file.exists()) return [];
  final content = (await file.readAsString()).trim();
  if (content.isEmpty) return [];

  final failedNames = content.split('|');
  final failedGroups = <String>{};

  for (final name in failedNames) {
    for (final group in _kAllGroups) {
      if (name.startsWith('$group ')) {
        failedGroups.add(group);
        break;
      }
    }
  }
  return failedGroups.toList();
}

Future<void> _saveFailedGroupsFromMerged(String jsonlPath) async {
  final file = File(jsonlPath);
  if (!await file.exists()) return;
  final failed = _parseFailedTestsFromJson(await file.readAsString());
  final outFile = File(_kFailedTestsFile);
  await outFile.parent.create(recursive: true);

  if (failed.isEmpty) {
    await outFile.writeAsString('');
    print('[Parallel E2E] All tests passed — cleared failure list.');
  } else {
    await outFile.writeAsString(failed.join('|'));
    print(
        '[Parallel E2E] Saved ${failed.length} failed test(s) → $_kFailedTestsFile');
  }
}

List<String> _parseFailedTestsFromJson(String content) {
  final failed = <String>{};
  final idToName = <int, String>{};

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
      if (testID != null && result != null && result != 'success' && !hidden) {
        failed.add(idToName[testID] ?? 'testId=$testID');
      }
    }
  }
  return failed.toList();
}

/// Parses the merged JSONL and writes build/e2e_report/results.json
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
  final strippedResults = <String, bool>{};
  for (final entry in testResults.entries) {
    final fullName = entry.key;
    final value = entry.value;
    // Strip suite prefix (e.g., "Navigation sandbox..." -> "sandbox...")
    String strippedName = fullName;
    for (final suite in _kAllGroups) {
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
      '[Parallel E2E] Wrote ${strippedResults.length} test results → results.json');
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
    print('[Parallel E2E] Skipping HTML update - files not found');
    return;
  }

  final html = await htmlFile.readAsString();
  final jsonContent = await jsonFile.readAsString();

  // Replace the embedded _testResults variable with actual data
  // Look for: const _testResults = {...};
  final pattern = RegExp(r'const _testResults = \{[^}]*\};');
  final replacement = 'const _testResults = $jsonContent;';

  if (!pattern.hasMatch(html)) {
    print('[Parallel E2E] Warning: Could not find _testResults in HTML');
    return;
  }

  final updatedHtml = html.replaceFirst(pattern, replacement);
  await htmlFile.writeAsString(updatedHtml);
  print('[Parallel E2E] Updated screenshot HTML with embedded test results');
}

// ---------------------------------------------------------------------------
// Count helpers
// ---------------------------------------------------------------------------

int _countInJsonl(String content, String result) {
  int count = 0;
  for (final line in content.split('\n')) {
    if (line.trim().isEmpty || !line.startsWith('{')) continue;
    dynamic decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      continue;
    }
    if (decoded is! Map) continue;
    if (decoded['type'] == 'testDone' &&
        decoded['result'] == result &&
        !(decoded['hidden'] as bool? ?? false)) {
      count++;
    }
  }
  return count;
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

void _printSummary(Map<String, _WorkerResult> results) {
  final divider = '─' * 55;
  print('\n$divider');
  print('  E2E PARALLEL RESULTS');
  print(divider);

  int totalPassed = 0;
  int totalFailed = 0;
  int totalTests = 0;
  int maxMs = 0;

  final sorted = results.entries.toList()
    ..sort((a, b) => a.value.elapsedMs.compareTo(b.value.elapsedMs));

  for (final entry in sorted) {
    final r = entry.value;
    final elapsed = _formatDuration(Duration(milliseconds: r.elapsedMs));
    final status = r.success ? '\x1B[32mPASS\x1B[0m' : '\x1B[31mFAIL\x1B[0m';
    print('  [$status] ${r.group.padRight(30)} $elapsed  '
        '${r.passed}/${r.passed + r.failed}');
    totalPassed += r.passed;
    totalFailed += r.failed;
    totalTests += r.passed + r.failed;
    if (r.elapsedMs > maxMs) {
      maxMs = r.elapsedMs;
    }
  }

  final passRate =
      totalTests > 0 ? ((totalTests - totalFailed) / totalTests * 100) : 0.0;

  print(divider);
  print('  ${'[Parallel]'.padRight(30)} Combined: '
      '$totalPassed/$totalTests (${passRate.toStringAsFixed(1)}%)');
  print('  ${'Max group wall time:'.padRight(30)} '
      '${_formatDuration(Duration(milliseconds: maxMs))}');
  print('$divider\n');
}

// ---------------------------------------------------------------------------
// Cleanup: kill all test processes after run
// ---------------------------------------------------------------------------

/// Kills all cb_file_hub.exe and flutter test processes.
/// Called after the run completes (success or failure) to ensure no stray
/// windows or processes are left hanging.
Future<void> _killAllTestProcesses() async {
  if (!Platform.isWindows) return;

  print('[Parallel E2E] Cleaning up test processes...');

  // Kill app process
  final r1 = await Process.run(
    'taskkill',
    <String>['/F', '/IM', 'cb_file_hub.exe', '/T'],
    runInShell: false,
  );
  if (r1.exitCode != 0 && r1.exitCode != 128) {
    // Not critical — may simply not exist
  }

  // Kill flutter test runner processes
  final r2 = await Process.run(
    'taskkill',
    <String>['/F', '/IM', 'flutter_test.exe', '/T'],
    runInShell: false,
  );
  if (r2.exitCode != 0 && r2.exitCode != 128) {
    // May not exist — fine
  }

  print('[Parallel E2E] Cleanup done.');
}

// ---------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------

String _formatDuration(Duration d) {
  if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
  return '${d.inSeconds}s ${d.inMilliseconds % 1000}ms';
}

Future<void> _killCbFileHubOnWindows() async {
  if (!Platform.isWindows) return;
  final r = await Process.run(
    'taskkill',
    <String>['/F', '/IM', 'cb_file_hub.exe', '/T'],
    runInShell: false,
  );
  if (r.exitCode != 0 && r.exitCode != 128) {
    stderr.writeln('[Parallel E2E] taskkill exit ${r.exitCode} (continuing)');
  }
}

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
  } catch (_) {}
}

void _printDryRun() {
  print('[Dry run] E2E Parallel runner');
  print('');
  print(
      '  dart run tool/e2e_parallel.dart                   All groups in parallel');
  print(
      '  dart run tool/e2e_parallel.dart --max-parallel 2  Limit concurrency');
  print(
      '  dart run tool/e2e_parallel.dart --plain-name "Navigation"  Single suite');
  print(
      '  dart run tool/e2e_parallel.dart --groups "View Mode|Search & Filter"');
  print(
      '  dart run tool/e2e_parallel.dart --file video_thumbnails_e2e_test  Run by file name');
  print('  dart run tool/e2e_parallel.dart --no-generate    Skip dashboard');
  print(
      '  dart run tool/e2e_parallel.dart --rerun-failed   Rerun previously failed');
  print(
      '  dart run tool/e2e_parallel.dart --full-startup   Include production startup services');
  print(
      '  dart run tool/e2e_parallel.dart --full-screenshots  Capture every E2E action');
  print(
      '  dart run tool/e2e_parallel.dart --no-warmup      Skip build warmup (risky on Windows)');
  print('  dart run tool/e2e_parallel.dart --dry-run          This message');
  print('');
  print('[Dry run] Available groups (${_kAllGroups.length}):');
  for (final g in _kAllGroups) {
    print('  - $g');
  }
  print('');
  print('[Dry run] Device: ${Platform.environment['E2E_DEVICE'] ?? 'windows'}');
  final defaultWorkers =
      Platform.numberOfProcessors < 4 ? Platform.numberOfProcessors : 4;
  print('[Dry run] CPU cores: ${Platform.numberOfProcessors}');
  print('[Dry run] Default max parallel: $defaultWorkers');
}

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

class _WorkerResult {
  final String group;
  final bool success;
  final int exitCode;
  final int passed;
  final int failed;
  final int elapsedMs;
  final String jsonlFile;
  final String logFile;

  _WorkerResult({
    required this.group,
    required this.success,
    required this.exitCode,
    required this.passed,
    required this.failed,
    required this.elapsedMs,
    required this.jsonlFile,
    required this.logFile,
  });
}

// ---------------------------------------------------------------------------
// Simple semaphore (pure Dart, no dart:async import needed beyond top-level)
// ---------------------------------------------------------------------------

class _Semaphore {
  final int max;
  int _running = 0;
  final _waiters = <Completer<void>>[];

  _Semaphore(this.max);

  Future<void> acquire() async {
    if (_running < max) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final c = _waiters.removeAt(0);
      if (!c.isCompleted) c.complete();
    } else {
      _running--;
    }
  }
}

// Generates a unified HTML E2E test dashboard.
// Pure Dart — no npm / Node.js required.
//
// One self-contained page combining:
//   - Pass/fail summary cards + pass rate bar
//   - Search + status filter
//   - Suite-grouped test list with collapsible details
//   - Full screenshot gallery per test (each step with lightbox + thumbnails)
//   - Failure error message + stack trace
//
// Sources merged on every run:
//   - build/e2e_report.jsonl                   (Flutter --reporter json)
//   - build/e2e_report/manifest.json           (E2ETester step-by-step screenshots)
//   - build/e2e_dashboard/state.json           (persisted history across runs)
//
// Output:
//   cb_file_manager/build/e2e_dashboard/
//     index.html          ← unified dashboard (open in any browser)
//     screenshots/        ← copied screenshot images
//     state.json          ← persisted test history (don't edit by hand)
//
// Usage (from cb_file_manager):
//   dart run tool/e2e_dashboard.dart
//   dart run tool/e2e_dashboard.dart --build-dir build

import 'dart:convert';
import 'dart:io';

const _kDefaultBuildDir = 'build';
const _kReportFile = 'e2e_report.jsonl';
const _kDashboardDir = 'e2e_dashboard';
const _kStateFile = 'state.json';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A single screenshot captured during a test step.
class Shot {
  /// Filename only (no directory). Lives in
  /// `build/e2e_report/screenshots/<filename>`.
  final String filename;

  /// Human-readable step label, e.g. `"00_initial"`, `"result"`,
  /// `"tap_002_save"`.
  final String step;

  /// When the screenshot was captured.
  final DateTime ts;

  Shot({required this.filename, required this.step, required this.ts});

  Map<String, dynamic> toJson() => {
        'filename': filename,
        'step': step,
        'ts': ts.toIso8601String(),
      };

  static Shot fromJson(Map<String, dynamic> j) => Shot(
        filename: j['filename'] as String,
        step: j['step'] as String? ?? '',
        ts: DateTime.tryParse(j['ts'] as String? ?? '') ?? DateTime.now(),
      );
}

class TestResult {
  final String name;
  final String status; // passed | failed | blocked | skipped | error
  final String? error;
  final String? stackTrace;
  final List<Shot> shots;
  final DateTime updatedAt;

  TestResult({
    required this.name,
    required this.status,
    this.error,
    this.stackTrace,
    this.shots = const [],
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  bool get isPassed => status == 'passed' || status == 'success';
  bool get isFailed => status == 'failed' || status == 'error';
  bool get isBlocked => status == 'blocked';

  Map<String, dynamic> toJson() => {
        'name': name,
        'status': status,
        if (error != null) 'error': error,
        if (stackTrace != null) 'stackTrace': stackTrace,
        'shots': shots.map((s) => s.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static TestResult fromJson(Map<String, dynamic> j) {
    // Back-compat with old `screenshots: [filename, ...]` format.
    final List<Shot> shots;
    final shotsRaw = j['shots'];
    if (shotsRaw is List) {
      shots = shotsRaw
          .whereType<Map>()
          .map((m) => Shot.fromJson(m.cast<String, dynamic>()))
          .toList();
    } else {
      final legacy = j['screenshots'];
      if (legacy is List) {
        shots = legacy
            .whereType<String>()
            .map((f) => Shot(filename: f, step: '', ts: DateTime.now()))
            .toList();
      } else {
        shots = const [];
      }
    }
    return TestResult(
      name: j['name'] as String,
      status: j['status'] as String? ?? 'passed',
      error: j['error'] as String?,
      stackTrace: j['stackTrace'] as String?,
      shots: shots,
      updatedAt:
          DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class TestReport {
  final List<TestResult> tests;
  final DateTime generatedAt;
  final String? suiteError;
  final String? suiteStackTrace;

  TestReport({
    required this.tests,
    required this.generatedAt,
    this.suiteError,
    this.suiteStackTrace,
  });

  int get total => tests.length;
  int get passed => tests.where((t) => t.isPassed).length;
  int get failed => tests.where((t) => t.isFailed).length;
  int get blocked => tests.where((t) => t.isBlocked).length;
  int get skipped => tests.where((t) => t.status == 'skipped').length;

  double get passRate => total > 0 ? (passed / total * 100) : 0;
}

// ---------------------------------------------------------------------------
// JSON parser
// ---------------------------------------------------------------------------

TestReport parseJsonLog(
  String content,
  String buildDir,
  Map<String, List<Shot>> manifestShots,
) {
  final idToName = <int, String>{};
  final idToError = <int, _ErrorInfo>{};
  final idToStatus = <int, String>{}; // raw `result` from testDone
  final idToPrints = <int, List<String>>{};
  final hiddenIds = <int>{};
  final hiddenErrors = <_ErrorInfo>[];

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
        if (id != null && name != null) {
          idToName[id] = name;
        }
      }
    } else if (type == 'print') {
      final testID = decoded['testID'] as int?;
      final message = decoded['message'] as String?;
      if (testID != null && message != null) {
        idToPrints.putIfAbsent(testID, () => <String>[]).add(message);
      }
    } else if (type == 'error') {
      // Standalone error event — emitted by the JSON reporter when a suite
      // fails to load (e.g. a global key-state assertion bubbles out before
      // any individual test runs). The testID points at a hidden loader
      // pseudo-test, so attach it for promotion later.
      final testID = decoded['testID'] as int?;
      final message = decoded['error'] as String? ?? '';
      final trace = decoded['stackTrace'] as String? ?? '';
      final errorInfo = _errorInfoFromJsonError(
        testID: testID,
        message: message,
        trace: trace,
        printsByTest: idToPrints,
      );
      if (testID != null) {
        idToError[testID] = errorInfo;
      } else {
        hiddenErrors.add(errorInfo);
      }
    } else if (type == 'testDone') {
      final testID = decoded['testID'] as int?;
      if (testID == null) continue;

      final result = decoded['result'] as String?;
      if (result != null) idToStatus[testID] = result;

      if (decoded['hidden'] == true) {
        hiddenIds.add(testID);
        // Capture the failure so we can surface it as a suite-level banner
        // even when the offending test is a hidden loader.
        if (result != null && result != 'success') {
          final existing = idToError[testID];
          if (existing != null) {
            hiddenErrors.add(existing);
          } else {
            final err = decoded['error'] as String?;
            if (err != null && err.isNotEmpty) {
              hiddenErrors.add(_ErrorInfo(message: err, trace: ''));
            }
          }
        }
        continue;
      }

      if (result != null && result != 'success') {
        final err = decoded['error'] as String?;
        if (err != null && err.isNotEmpty) {
          idToError[testID] = _errorInfoFromJsonError(
            testID: testID,
            message: err,
            trace: decoded['stackTrace'] as String? ?? '',
            printsByTest: idToPrints,
          );
        }
      }
    }
  }

  // Determine if the suite as a whole crashed — i.e. the loader pseudo-test
  // failed, or the JSON reporter emitted a standalone error event without a
  // matching testDone failure. When that happens, every visible test marked
  // "error" with no individual error message is really "blocked" by the
  // suite failure.
  _ErrorInfo? suiteError;
  for (final id in hiddenIds) {
    final e = idToError[id];
    if (e != null) {
      suiteError = e;
      break;
    }
  }
  suiteError ??= hiddenErrors.isNotEmpty ? hiddenErrors.first : null;

  final results = <TestResult>[];
  for (final entry in idToName.entries) {
    final testID = entry.key;
    if (hiddenIds.contains(testID)) continue;

    final name = entry.value;

    // Skip Flutter test framework's "loading <file>.dart" entries — these are
    // not real test cases, they're build/load steps. They show up as "failed"
    // when the Windows build pipeline races with another worker (MSBuild lock
    // contention or CMakeCache.txt generation conflict). The actual tests in
    // those workers will get rerun in single-process mode anyway.
    if (name.startsWith('loading ') && name.endsWith('.dart')) continue;

    // Skip group lifecycle pseudo-tests like "(setUpAll)" / "(tearDownAll)".
    // They cascade to "did not complete" whenever the suite crashes and only
    // add noise to the dashboard.
    if (name.startsWith('(') && name.endsWith(')')) continue;

    final errorInfo = idToError[testID];
    final rawResult = idToStatus[testID] ?? 'success';
    final shots = _shotsForTest(name, manifestShots, buildDir);

    String status;
    String? errMessage;
    String? errTrace;

    if (errorInfo != null) {
      status = 'failed';
      errMessage = errorInfo.message;
      errTrace = errorInfo.trace;
    } else if (rawResult != 'success') {
      // Test was reported as error/failure but has no individual error —
      // this happens when the suite loader crashed and every subsequent
      // case is auto-marked "did not complete". Treat them as blocked and
      // attribute the cause to the suite-level failure.
      if (suiteError != null) {
        status = 'blocked';
        errMessage = 'Blocked by suite failure: ${suiteError.message}';
        errTrace = suiteError.trace;
      } else {
        status = 'failed';
        errMessage = 'Test reported "$rawResult" without an error message.';
        errTrace = null;
      }
    } else {
      status = 'passed';
    }

    results.add(TestResult(
      name: name,
      status: status,
      error: errMessage,
      stackTrace: errTrace,
      shots: shots,
    ));
  }

  return TestReport(
    tests: results,
    generatedAt: DateTime.now(),
    suiteError: suiteError?.message,
    suiteStackTrace: suiteError?.trace,
  );
}

class _ErrorInfo {
  final String message;
  final String trace;
  const _ErrorInfo({required this.message, required this.trace});
}

_ErrorInfo _errorInfoFromJsonError({
  required int? testID,
  required String message,
  required String trace,
  required Map<int, List<String>> printsByTest,
}) {
  if (testID == null || !_isGenericFlutterTestError(message)) {
    return _ErrorInfo(message: message, trace: trace);
  }

  final extracted = _extractFailureFromPrints(printsByTest[testID] ?? const []);
  if (extracted == null) {
    return _ErrorInfo(message: message, trace: trace);
  }

  return extracted;
}

bool _isGenericFlutterTestError(String message) {
  final lower = message.toLowerCase();
  return lower.contains('see exception logs above') ||
      lower.startsWith('test failed.');
}

_ErrorInfo? _extractFailureFromPrints(List<String> rawMessages) {
  if (rawMessages.isEmpty) return null;

  final lines = rawMessages
      .map(_cleanLogLine)
      .where((line) => line.trim().isNotEmpty || line.isEmpty)
      .toList();
  if (lines.isEmpty) return null;

  var start = -1;
  for (var i = lines.length - 1; i >= 0; i--) {
    final line = lines[i];
    if (line.contains('EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK') ||
        line.contains('The following TestFailure was thrown') ||
        line.startsWith('Flutter Error in ')) {
      start = i;
      break;
    }
  }
  if (start < 0) return null;

  for (var i = start - 1; i >= 0 && i >= start - 5; i--) {
    if (lines[i].startsWith('Flutter Error in ')) {
      start = i;
      break;
    }
  }

  final traceLines = lines.sublist(start);
  final message = _extractFailureSummary(traceLines);
  if (message == null || message.trim().isEmpty) return null;

  return _ErrorInfo(
    message: message,
    trace: traceLines.join('\n').trimRight(),
  );
}

String _cleanLogLine(String line) {
  return line
      .replaceAll(RegExp('\x1B\\[[0-?]*[ -/]*[@-~]'), '')
      .replaceAll(RegExp(r'\s+$'), '');
}

String? _extractFailureSummary(List<String> lines) {
  for (final line in lines) {
    if (!line.startsWith('Flutter Error in ')) continue;
    final marker = line.indexOf(': ');
    if (marker >= 0 && marker + 2 < line.length) {
      return line.substring(marker + 2).trim();
    }
  }

  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].contains('The following TestFailure was thrown')) continue;
    for (var j = i + 1; j < lines.length; j++) {
      final candidate = lines[j].trim();
      if (_isFailureSummaryCandidate(candidate)) return candidate;
    }
  }

  for (final line in lines) {
    final candidate = line.trim();
    if (_isFailureSummaryCandidate(candidate)) return candidate;
  }

  return null;
}

bool _isFailureSummaryCandidate(String line) {
  if (line.isEmpty) return false;
  if (line.startsWith('══') || line.startsWith('╞') || line.startsWith('═')) {
    return false;
  }
  if (line.startsWith('#') ||
      line.startsWith('<asynchronous suspension>') ||
      line.startsWith('(elided ')) {
    return false;
  }
  final lower = line.toLowerCase();
  if (lower.startsWith('the following testfailure was thrown') ||
      lower.startsWith('when the exception was thrown') ||
      lower.startsWith('the test description was')) {
    return false;
  }
  return true;
}

/// Renders a stack trace into HTML, highlighting frames that point at user
/// code. Each user frame gets wrapped in `<span class="trace-user">` so the
/// CSS can pull it out of the wall of grey Flutter frames.
String _renderTrace(String trace) {
  final lines = trace.split('\n');
  final out = StringBuffer();
  final userPathPattern = RegExp(
    r'(integration_test/|package:cb_file_manager/|test/|[A-Za-z]:[/\\])',
    caseSensitive: false,
  );
  for (final line in lines) {
    final escaped = _escapeHtml(line);
    final lower = line.toLowerCase();
    final isFlutter = lower.contains('package:flutter') ||
        lower.contains('/flutter/') ||
        lower.contains(r'\flutter\') ||
        lower.startsWith('dart:') ||
        lower.contains(' dart:') ||
        lower.contains('package:flutter_test');
    final hasUserPath = userPathPattern.hasMatch(line);
    if (hasUserPath && !isFlutter) {
      out.writeln('<span class="trace-user">$escaped</span>');
    } else {
      out.writeln(escaped);
    }
  }
  return out.toString();
}

/// Returns the first stack-trace frame that points at user code (the test
/// suite or app package), e.g. `integration_test/app_e2e_test.dart 123:5`
/// or `package:cb_file_manager/foo.dart 42:10`. Returns `null` when no
/// such frame is found (pure Flutter/Dart SDK trace).
///
/// When no frame with a line number can be found we fall back to a bare
/// file path mention (e.g. `Failed to load "/.../app_e2e_test.dart"`) so
/// the user still sees *which file* is implicated.
///
/// Accepts mixed text — error messages may bundle the trace into the
/// message itself, so we scan everything we get.
String? _firstUserFrame(String text) {
  if (text.isEmpty) return null;

  bool isFlutterPath(String p) {
    final lower = p.toLowerCase();
    return lower.contains('/flutter/') ||
        lower.contains(r'\flutter\') ||
        lower.contains('package:flutter') ||
        lower.contains('dart:') ||
        lower.contains('sdk/lib/');
  }

  // Stack frames look like one of these (whitespace varies):
  //   package:cb_file_manager/foo.dart 42:10                Class.method
  //   integration_test/app_e2e_test.dart 123:5              main.<fn>
  //   file:///.../app_e2e_test.dart:123:5
  //   #4      main.<fn> (file:///.../app_e2e_test.dart:42:5)
  final patterns = <RegExp>[
    RegExp(r'(integration_test/[^\s:"]+\.dart)[: ](\d+)(?::(\d+))?'),
    RegExp(r'(package:cb_file_manager/[^\s:"]+\.dart)[: ](\d+)(?::(\d+))?'),
    RegExp(r'(test/[^\s:"]+\.dart)[: ](\d+)(?::(\d+))?'),
    RegExp(r'(?:file:///)?([A-Za-z]:[/\\][^\s:"]*?\.dart):(\d+)(?::(\d+))?'),
  ];

  for (final p in patterns) {
    for (final m in p.allMatches(text)) {
      final path = m.group(1) ?? '';
      if (isFlutterPath(path)) continue;
      final line = m.group(2);
      final col = m.group(3);
      if (line == null) continue;
      return col != null ? '$path:$line:$col' : '$path:$line';
    }
  }

  // Fallback: bare-path mentions, no line number. Still useful — at least
  // tells the user which file is involved (e.g. "Failed to load X.dart").
  final pathOnlyPatterns = <RegExp>[
    RegExp(r'(integration_test/[^\s:"]+\.dart)'),
    RegExp(r'(package:cb_file_manager/[^\s:"]+\.dart)'),
    RegExp(
        r'(?:file:///)?([A-Za-z]:[/\\][^\s:"]*?integration_test[/\\][^\s:"]*?\.dart)'),
    RegExp(
        r'(?:file:///)?([A-Za-z]:[/\\][^\s:"]*?cb_file_manager[/\\][^\s:"]*?\.dart)'),
  ];
  for (final p in pathOnlyPatterns) {
    for (final m in p.allMatches(text)) {
      final path = m.group(1) ?? '';
      if (isFlutterPath(path)) continue;
      return path;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Manifest loader — reads build/e2e_report/manifest.json (written by
// integration_test/e2e_report.dart) so we get exact step labels per shot.
// ---------------------------------------------------------------------------

Future<Map<String, List<Shot>>> _loadManifestShots(String buildDir) async {
  final out = <String, List<Shot>>{};
  final manifestFile = File('$buildDir/e2e_report/manifest.json');
  if (!await manifestFile.exists()) return out;
  try {
    final decoded = jsonDecode(await manifestFile.readAsString());
    if (decoded is! Map) return out;
    final entries = decoded['entries'];
    if (entries is! List) return out;
    for (final raw in entries) {
      if (raw is! Map) continue;
      final tn = raw['testName'] as String?;
      final step = raw['step'] as String? ?? '';
      final filename = raw['filename'] as String?;
      final tsStr = raw['ts'] as String?;
      if (tn == null || filename == null) continue;
      out.putIfAbsent(tn, () => []).add(Shot(
            filename: filename,
            step: step,
            ts: DateTime.tryParse(tsStr ?? '') ?? DateTime.now(),
          ));
    }
    // Sort each test's shots by capture timestamp.
    for (final list in out.values) {
      list.sort((a, b) => a.ts.compareTo(b.ts));
    }
  } catch (_) {}
  return out;
}

/// Looks up shots for [testName]: prefers the manifest (exact mapping),
/// falls back to filename-slug scanning so old runs without a manifest still
/// show something.
List<Shot> _shotsForTest(
  String testName,
  Map<String, List<Shot>> manifestShots,
  String buildDir,
) {
  final fromManifest = manifestShots[testName];
  if (fromManifest != null && fromManifest.isNotEmpty) return fromManifest;

  // Fallback: scan disk for files whose name contains the slug.
  // E2ETester writes filenames like:
  //   001_<slug>_00_initial.png
  //   002_<slug>_result.png
  // where <slug> is built from the label passed to et.init() — which is the
  // test name WITHOUT the group() prefix. We try the full name first, then
  // fall back to the name with the suite prefix stripped.
  final slugFull = _slugify(testName);
  final suite = _inferSuite(testName);
  final stripped = testName.startsWith('$suite ')
      ? testName.substring(suite.length + 1)
      : testName;
  final slugStripped = _slugify(stripped);
  final slugs = <String>{
    if (slugStripped.isNotEmpty) slugStripped,
    if (slugFull.isNotEmpty) slugFull,
  };
  if (slugs.isEmpty) return const [];

  final candidates = <String>[];
  final dirs = <Directory>[
    Directory('$buildDir/e2e_report/screenshots'),
    Directory(buildDir),
  ];
  for (final d in dirs) {
    if (!d.existsSync()) continue;
    try {
      for (final entity in d.listSync()) {
        if (entity is! File) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        final lower = name.toLowerCase();
        if (!lower.endsWith('.png')) continue;
        if (slugs.any(lower.contains)) candidates.add(name);
      }
      if (candidates.isNotEmpty) break;
    } catch (_) {}
  }

  candidates.sort((a, b) {
    final ai = int.tryParse(a.split('_').first) ?? 0;
    final bi = int.tryParse(b.split('_').first) ?? 0;
    return ai.compareTo(bi);
  });

  // Use the longest matching slug for stripping the human-readable step label.
  final bestSlug = slugs.reduce((a, b) => a.length >= b.length ? a : b);
  return candidates
      .map((f) => Shot(
            filename: f,
            step: _stepFromFilename(f, bestSlug),
            ts: DateTime.now(),
          ))
      .toList();
}

/// Tries to recover a human-readable step label from a fallback filename.
/// E.g. `"002_my_test_result.png"` with slug `"my_test"` -> `"result"`.
String _stepFromFilename(String filename, String slug) {
  var name = filename;
  if (name.toLowerCase().endsWith('.png')) {
    name = name.substring(0, name.length - 4);
  }
  // Strip leading "NNN_"
  final firstUnderscore = name.indexOf('_');
  if (firstUnderscore > 0 &&
      int.tryParse(name.substring(0, firstUnderscore)) != null) {
    name = name.substring(firstUnderscore + 1);
  }
  // Strip slug prefix
  if (name.toLowerCase().startsWith(slug)) {
    name = name.substring(slug.length);
    if (name.startsWith('_')) name = name.substring(1);
  }
  return name.isEmpty ? 'screenshot' : name;
}

String _slugify(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

// ---------------------------------------------------------------------------
// Persisted state — keeps full test history across partial reruns so the
// dashboard doesn't lose passed cases when only a few are rerun.
// ---------------------------------------------------------------------------

Future<Map<String, TestResult>> _loadPersistedState(String dashboardDir) async {
  final stateFile = File('$dashboardDir/$_kStateFile');
  if (!await stateFile.exists()) return {};
  try {
    final content = await stateFile.readAsString();
    if (content.trim().isEmpty) return {};
    final decoded = jsonDecode(content);
    if (decoded is! Map) return {};
    final tests = decoded['tests'];
    if (tests is! List) return {};
    final out = <String, TestResult>{};
    for (final t in tests) {
      if (t is! Map) continue;
      final tr = TestResult.fromJson(t.cast<String, dynamic>());
      out[tr.name] = tr;
    }
    return out;
  } catch (_) {
    return {};
  }
}

Future<void> _savePersistedState(
    String dashboardDir, Map<String, TestResult> tests) async {
  final stateFile = File('$dashboardDir/$_kStateFile');
  await stateFile.parent.create(recursive: true);
  final body = {
    'tests': tests.values.map((t) => t.toJson()).toList(),
    'updatedAt': DateTime.now().toIso8601String(),
  };
  await stateFile.writeAsString(jsonEncode(body));
}

/// Merges fresh test results from this run into the persisted state.
/// New results overwrite the previous entry for the same test name; tests
/// that didn't run this time keep their previous status.
///
/// Drops legacy framework pseudo-tests like `"(tearDownAll)"` /
/// `"(setUpAll)"` and `"loading <file>.dart"` that older runs may have
/// persisted before we started filtering them at parse time.
Map<String, TestResult> _mergeResults(
  Map<String, TestResult> persisted,
  List<TestResult> fresh,
) {
  bool isPseudo(String name) {
    if (name.startsWith('(') && name.endsWith(')')) return true;
    if (name.startsWith('loading ') && name.endsWith('.dart')) return true;
    return false;
  }

  final out = <String, TestResult>{};
  persisted.forEach((name, t) {
    if (!isPseudo(name)) out[name] = t;
  });
  for (final t in fresh) {
    if (isPseudo(t.name)) continue;
    out[t.name] = t;
  }
  return out;
}

String generateHtml(TestReport report) {
  final passed = report.passed;
  final failed = report.failed;
  final blocked = report.blocked;
  final total = report.total;
  final passRate = report.passRate;
  final passColor = (failed == 0 && blocked == 0) ? '#22c55e' : '#eab308';

  // Group tests by suite
  final Map<String, List<TestResult>> suiteGroups = {};
  for (final t in report.tests) {
    final suite = _inferSuite(t.name);
    suiteGroups.putIfAbsent(suite, () => []).add(t);
  }

  // Build all-shots index for the lightbox: each entry = {test, step, src}.
  // We render this as JSON so the lightbox can navigate across all shots
  // without re-querying the DOM on every keypress.
  final allShots = <Map<String, String>>[];

  // Suite-level failure banner. Surfaces the loader/setup error that caused
  // a wave of "did not complete" tests so the user doesn't have to dig
  // through individual test rows to find the real cause.
  final suiteBanner = StringBuffer();
  if (report.suiteError != null && report.suiteError!.isNotEmpty) {
    final suiteCombined =
        '${report.suiteError ?? ''}\n${report.suiteStackTrace ?? ''}';
    final suiteFrame = _firstUserFrame(suiteCombined);

    suiteBanner.writeln('<div class="suite-error-banner">');
    suiteBanner.writeln('<div class="suite-error-title">');
    suiteBanner.writeln('<span class="suite-error-icon">!</span>');
    suiteBanner.writeln(
        'Suite failed to load — every blocked test below shares this root cause');
    suiteBanner.writeln('</div>');
    if (suiteFrame != null) {
      suiteBanner.writeln('<div class="reason-where">'
          '<span class="reason-where-label">at</span> '
          '<code>${_escapeHtml(suiteFrame)}</code>'
          '</div>');
    }
    suiteBanner.writeln(
        '<div class="suite-error-msg">${_escapeHtml(report.suiteError!)}</div>');
    if (report.suiteStackTrace != null &&
        report.suiteStackTrace!.trim().isNotEmpty &&
        report.suiteStackTrace != report.suiteError) {
      suiteBanner.writeln('<div class="reason-trace-label">Stack trace</div>');
      suiteBanner.writeln(
          '<pre class="reason-trace-pre">${_renderTrace(report.suiteStackTrace!)}</pre>');
    }
    suiteBanner.writeln('</div>');
  }

  String statusKey(TestResult t) {
    if (t.isPassed) return 'passed';
    if (t.isBlocked) return 'blocked';
    return 'failed';
  }

  String statusBadge(TestResult t) {
    if (t.isPassed) return '<span class="badge pass">PASSED</span>';
    if (t.isBlocked) return '<span class="badge blocked">BLOCKED</span>';
    return '<span class="badge fail">FAILED</span>';
  }

  // Build suite sections
  final suiteSections = StringBuffer();
  for (final entry in suiteGroups.entries) {
    final suiteName = entry.key;
    final tests = entry.value;
    final suitePassed = tests.where((t) => t.isPassed).length;
    final suiteFailedCount = tests.where((t) => t.isFailed).length;
    final suiteBlockedCount = tests.where((t) => t.isBlocked).length;
    final suiteTotal = tests.length;
    final allPassed = suiteFailedCount == 0 && suiteBlockedCount == 0;

    final statusClass = allPassed ? 'all-pass' : 'has-fail';
    final statsText = '$suitePassed/$suiteTotal';
    final rateText =
        suiteTotal > 0 ? '${(suitePassed / suiteTotal * 100).round()}%' : '-';

    suiteSections.writeln('<details class="suite-group" open>');
    suiteSections.writeln('<summary class="suite-header $statusClass">');
    suiteSections.writeln('<span class="suite-chevron">▶</span>');
    suiteSections
        .writeln('<span class="suite-name">${_escapeHtml(suiteName)}</span>');
    suiteSections.writeln(
        '<span class="suite-stats">$statsText &middot; $rateText</span>');
    suiteSections.writeln('</summary>');
    suiteSections.writeln('<div class="suite-tests">');

    for (final t in tests) {
      // Strip group prefix from display name for cleaner look.
      var displayName = t.name;
      if (displayName.startsWith('$suiteName ')) {
        displayName = displayName.substring(suiteName.length + 1);
      }

      final badge = statusBadge(t);
      final stateClass = statusKey(t);
      final shotCountBadge = t.shots.isNotEmpty
          ? '<span class="shot-count">${t.shots.length} shot${t.shots.length == 1 ? '' : 's'}</span>'
          : '';

      final hasErrorMessage =
          (t.isFailed || t.isBlocked) && t.error != null && t.error!.isNotEmpty;
      final hasContent = t.shots.isNotEmpty || hasErrorMessage;

      // Inline gallery
      final galleryBuf = StringBuffer();
      if (t.shots.isNotEmpty) {
        galleryBuf.writeln('<div class="gallery">');
        for (final shot in t.shots) {
          final globalIdx = allShots.length;
          allShots.add({
            'test': t.name,
            'step': shot.step,
            'src': 'screenshots/${shot.filename}',
          });
          galleryBuf.writeln('<figure class="thumb" '
              'onclick="lbOpen($globalIdx)" '
              'title="${_escapeHtml(shot.step)}">');
          galleryBuf
              .writeln('<img src="screenshots/${_escapeHtml(shot.filename)}" '
                  'alt="${_escapeHtml(shot.step)}" loading="lazy">');
          galleryBuf.writeln(
              '<figcaption>${_escapeHtml(shot.step.isEmpty ? 'screenshot' : shot.step)}</figcaption>');
          galleryBuf.writeln('</figure>');
        }
        galleryBuf.writeln('</div>');
      }

      // Reason block — explains why a test failed or was blocked. For
      // blocked tests we colour the block differently so the user can
      // immediately tell "this didn't run because of an upstream crash"
      // apart from "this ran and asserted incorrectly".
      final reasonBuf = StringBuffer();
      if (hasErrorMessage) {
        final cls = t.isBlocked ? 'reason-msg blocked' : 'reason-msg';
        final label = t.isBlocked ? 'BLOCKED — REASON' : 'FAILED — REASON';

        // Find the first user-code frame across both message + trace so
        // even tests whose error embeds the trace get a "failed at"
        // pointer at the top of the card.
        final combined = '${t.error ?? ''}\n${t.stackTrace ?? ''}';
        final userFrame = _firstUserFrame(combined);

        reasonBuf.writeln('<div class="$cls">');
        reasonBuf.writeln('<div class="reason-label">$label</div>');
        if (userFrame != null) {
          reasonBuf.writeln('<div class="reason-where">'
              '<span class="reason-where-label">at</span> '
              '<code>${_escapeHtml(userFrame)}</code>'
              '</div>');
        }
        reasonBuf
            .writeln('<div class="reason-text">${_escapeHtml(t.error!)}</div>');
        if (t.stackTrace != null &&
            t.stackTrace!.trim().isNotEmpty &&
            t.stackTrace != t.error) {
          reasonBuf
              .writeln('<div class="reason-trace-label">Stack trace</div>');
          reasonBuf.writeln(
              '<pre class="reason-trace-pre">${_renderTrace(t.stackTrace!)}</pre>');
        }
        reasonBuf.writeln('</div>');
      }

      final detailsAttr = hasContent ? 'open' : '';

      if (hasContent) {
        suiteSections.writeln('''
    <details class="test-item $stateClass" data-status="$stateClass" data-search="${_escapeHtml(t.name.toLowerCase())}" $detailsAttr>
      <summary class="test-header">
        <span class="test-chevron">▶</span>
        <span class="test-name">${_escapeHtml(displayName)}</span>
        $shotCountBadge
        $badge
      </summary>
      <div class="test-body">
        ${reasonBuf.toString()}
        ${galleryBuf.toString()}
      </div>
    </details>''');
      } else {
        // No shots and no error — render as a non-collapsible row.
        suiteSections.writeln('''
    <div class="test-item $stateClass no-detail" data-status="$stateClass" data-search="${_escapeHtml(t.name.toLowerCase())}">
      <div class="test-header">
        <span class="test-chevron empty"></span>
        <span class="test-name">${_escapeHtml(displayName)}</span>
        $badge
      </div>
    </div>''');
      }
    }

    suiteSections.writeln('</div>'); // .suite-tests
    suiteSections.writeln('</details>'); // .suite-group
  }

  final timestamp =
      report.generatedAt.toLocal().toString().replaceAll('.000', '');
  final shotsJson = jsonEncode(allShots);

  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>E2E Test Dashboard</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, sans-serif;
    background: #0f172a; color: #e2e8f0; min-height: 100vh; padding: 2rem;
  }
  .container { max-width: 1200px; margin: 0 auto; }

  h1 { font-size: 1.6rem; font-weight: 700; color: #f8fafc; }
  .subtitle { font-size: 0.8rem; color: #64748b; margin-bottom: 1.5rem; margin-top: 0.25rem; }

  /* Summary cards */
  .summary-row { display: flex; gap: 1rem; margin-bottom: 1.5rem; flex-wrap: wrap; }
  .card {
    background: #1e293b; border-radius: 12px; padding: 1.25rem 1.5rem;
    flex: 1; min-width: 140px; border: 1px solid #334155;
  }
  .card-label { font-size: 0.75rem; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.4rem; }
  .card-value { font-size: 2rem; font-weight: 700; }
  .card-value.green  { color: #22c55e; }
  .card-value.red    { color: #ef4444; }
  .card-value.yellow { color: #eab308; }

  .bar-wrap {
    background: #1e293b; border-radius: 12px; padding: 1.25rem 1.5rem;
    flex: 2; border: 1px solid #334155;
  }
  .bar-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.6rem; }
  .bar-label { font-size: 0.75rem; color: #94a3b8; text-transform: uppercase; }
  .bar-pct { font-size: 1.5rem; font-weight: 700; color: $passColor; }
  .bar-track { background: #334155; border-radius: 99px; height: 10px; overflow: hidden; display: flex; }
  .bar-fill-pass    { background: #22c55e; height: 100%; transition: width 0.6s ease; }
  .bar-fill-fail    { background: #ef4444; height: 100%; transition: width 0.6s ease; }
  .bar-fill-blocked { background: #eab308; height: 100%; transition: width 0.6s ease; }

  /* Controls */
  .controls-row {
    display: flex; gap: 0.5rem; margin-bottom: 1rem; flex-wrap: wrap; align-items: center;
  }
  .search-box {
    flex: 1; min-width: 200px; padding: 0.45rem 0.8rem;
    background: #1e293b; border: 1px solid #334155; color: #e2e8f0;
    border-radius: 8px; font-size: 0.85rem; outline: none;
    transition: border-color 0.15s;
  }
  .search-box::placeholder { color: #475569; }
  .search-box:focus { border-color: #3b82f6; }

  .filters { display: flex; gap: 0.4rem; flex-wrap: wrap; }
  .filter-btn {
    padding: 0.4rem 0.9rem; border-radius: 99px;
    border: 1px solid #334155; background: #1e293b; color: #94a3b8;
    font-size: 0.8rem; cursor: pointer; transition: all 0.15s;
  }
  .filter-btn:hover { border-color: #475569; color: #e2e8f0; }
  .filter-btn.active { background: #3b82f6; border-color: #3b82f6; color: #fff; }

  .collapse-controls { display: flex; gap: 0.4rem; }
  .collapse-btn {
    padding: 0.35rem 0.75rem; border-radius: 6px;
    border: 1px solid #334155; background: #1e293b; color: #64748b;
    font-size: 0.75rem; cursor: pointer; transition: all 0.15s;
  }
  .collapse-btn:hover { border-color: #475569; color: #e2e8f0; }

  /* Suite groups */
  .suite-group {
    margin-bottom: 0.75rem; border: 1px solid #334155;
    border-radius: 12px; overflow: hidden;
  }
  .suite-header {
    display: flex; align-items: center; gap: 0.75rem;
    padding: 0.75rem 1.25rem; background: #1e293b;
    cursor: pointer; user-select: none; list-style: none;
  }
  .suite-header::-webkit-details-marker { display: none; }
  .suite-chevron {
    font-size: 0.65rem; color: #64748b; transition: transform 0.2s;
    flex-shrink: 0; width: 12px; text-align: center;
  }
  details.suite-group[open] > .suite-header .suite-chevron { transform: rotate(90deg); }
  .suite-name { flex: 1; font-size: 0.9rem; font-weight: 600; color: #e2e8f0; }
  .suite-stats {
    font-size: 0.75rem; padding: 0.15rem 0.6rem; border-radius: 99px; flex-shrink: 0;
  }
  .suite-header.all-pass .suite-stats { background: #14532d; color: #22c55e; }
  .suite-header.has-fail .suite-stats { background: #451a03; color: #eab308; }
  .suite-tests { padding: 0.25rem 0; }

  /* Test item */
  .test-item {
    border-bottom: 1px solid #1e293b; transition: background-color 0.15s;
  }
  .test-item:last-child { border-bottom: none; }
  .test-item.passed  { border-left: 3px solid #22c55e; }
  .test-item.failed  { border-left: 3px solid #ef4444; }
  .test-item.blocked { border-left: 3px solid #eab308; }
  .test-item summary::-webkit-details-marker { display: none; }
  .test-item summary { list-style: none; }

  .test-header {
    display: flex; align-items: center; gap: 0.75rem;
    padding: 0.6rem 1rem 0.6rem 1.25rem; cursor: pointer;
    user-select: none;
  }
  .test-item.no-detail .test-header { cursor: default; }
  .test-item:not(.no-detail) .test-header:hover { background: #263344; }

  .test-chevron {
    font-size: 0.6rem; color: #64748b;
    transition: transform 0.2s; flex-shrink: 0; width: 10px;
  }
  .test-chevron.empty { visibility: hidden; }
  details.test-item[open] > .test-header .test-chevron { transform: rotate(90deg); }

  .test-name {
    flex: 1; font-size: 0.85rem; color: #e2e8f0;
    font-family: 'Cascadia Code', 'Fira Code', monospace;
  }

  .badge {
    font-size: 0.65rem; padding: 0.15rem 0.5rem; border-radius: 99px;
    font-weight: 600; white-space: nowrap; flex-shrink: 0; letter-spacing: 0.03em;
  }
  .badge.pass    { background: #14532d; color: #22c55e; }
  .badge.fail    { background: #450a0a; color: #ef4444; }
  .badge.blocked { background: #422006; color: #fbbf24; }

  .shot-count {
    font-size: 0.65rem; padding: 0.15rem 0.5rem; border-radius: 99px;
    background: #1e3a5f; color: #93c5fd; flex-shrink: 0;
  }

  .test-body {
    padding: 0.5rem 1.25rem 1rem 1.5rem;
    border-top: 1px solid #1e293b; background: #0d1626;
  }

  /* Failure / blocked reason block (per-test) */
  .reason-msg {
    background: #2d0a0a; border: 1px solid #450a0a; border-radius: 8px;
    padding: 0.65rem 0.8rem; margin-bottom: 0.75rem;
  }
  .reason-msg.blocked {
    background: #1f1402; border-color: #422006;
  }
  .reason-label {
    font-size: 0.65rem; font-weight: 700; letter-spacing: 0.06em;
    color: #fca5a5; margin-bottom: 0.35rem;
  }
  .reason-msg.blocked .reason-label { color: #fbbf24; }

  /* "at <file>:<line>" pointer — the single most actionable thing on the card */
  .reason-where {
    display: flex; align-items: center; gap: 0.4rem;
    font-size: 0.78rem; margin-bottom: 0.45rem;
  }
  .reason-where-label {
    font-size: 0.62rem; font-weight: 700; letter-spacing: 0.08em;
    color: #94a3b8; text-transform: uppercase;
  }
  .reason-where code {
    font-family: 'Cascadia Code', 'Fira Code', monospace;
    font-size: 0.78rem; color: #fde68a;
    background: rgba(0, 0, 0, 0.35);
    padding: 0.12rem 0.45rem; border-radius: 4px;
    word-break: break-all;
  }
  .reason-msg:not(.blocked) .reason-where code { color: #fecaca; }

  .reason-text {
    font-family: 'Cascadia Code', 'Fira Code', monospace;
    font-size: 0.78rem; color: #fecaca; white-space: pre-wrap;
    word-break: break-word;
    max-height: 260px; overflow-y: auto;
  }
  .reason-msg.blocked .reason-text { color: #fde68a; }

  .reason-trace-label {
    margin-top: 0.65rem; margin-bottom: 0.3rem;
    font-size: 0.62rem; font-weight: 700; letter-spacing: 0.08em;
    color: #94a3b8; text-transform: uppercase;
  }
  .reason-trace-pre {
    padding: 0.55rem 0.7rem;
    background: #0f172a; border: 1px solid #1e293b; border-radius: 6px;
    font-family: 'Cascadia Code', 'Fira Code', monospace;
    font-size: 0.72rem; color: #94a3b8;
    white-space: pre-wrap; word-break: break-word;
    max-height: 260px; overflow-y: auto;
  }
  /* User-code frames inside the trace pop out from grey Flutter frames */
  .trace-user { color: #fde68a; font-weight: 600; }
  .reason-msg:not(.blocked) .trace-user { color: #fecaca; }

  /* Suite-level error banner — explains a wave of "did not complete" tests */
  .suite-error-banner {
    background: linear-gradient(180deg, #2d0a0a 0%, #1f0606 100%);
    border: 1px solid #7f1d1d; border-radius: 12px;
    padding: 1rem 1.25rem; margin-bottom: 1rem;
  }
  .suite-error-title {
    display: flex; align-items: center; gap: 0.6rem;
    font-size: 0.85rem; font-weight: 600; color: #fecaca;
    margin-bottom: 0.5rem;
  }
  .suite-error-icon {
    display: inline-flex; align-items: center; justify-content: center;
    width: 1.4rem; height: 1.4rem; flex-shrink: 0;
    background: #b91c1c; color: #fff; border-radius: 99px;
    font-weight: 700; font-size: 0.85rem;
  }
  .suite-error-msg {
    font-family: 'Cascadia Code', 'Fira Code', monospace;
    font-size: 0.78rem; color: #fda4af; white-space: pre-wrap;
    word-break: break-word;
    max-height: 280px; overflow-y: auto;
  }
  .suite-error-banner .reason-where { margin-top: 0.1rem; }
  .suite-error-banner .reason-where code { color: #fde68a; }
  .suite-error-banner .reason-trace-pre { color: #cbd5e1; max-height: 320px; }

  /* Gallery */
  .gallery {
    display: grid; gap: 0.6rem;
    grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
    margin-top: 0.5rem;
  }
  .thumb {
    background: #1e293b; border: 1px solid #334155; border-radius: 8px;
    overflow: hidden; cursor: zoom-in; transition: border-color 0.15s, transform 0.15s;
  }
  .thumb:hover { border-color: #3b82f6; transform: translateY(-2px); }
  .thumb img {
    width: 100%; aspect-ratio: 16 / 10; object-fit: cover; display: block;
    border-bottom: 1px solid #334155;
  }
  .thumb figcaption {
    padding: 0.4rem 0.6rem; font-size: 0.72rem; color: #94a3b8;
    font-family: 'Cascadia Code', 'Fira Code', monospace;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }

  .hidden { display: none !important; }

  /* Lightbox */
  #lb-overlay {
    display: none; position: fixed; inset: 0;
    background: rgba(0, 0, 0, 0.94); z-index: 9999;
    flex-direction: column; align-items: center; justify-content: center;
  }
  #lb-overlay.on { display: flex; }
  #lb-topbar {
    position: fixed; top: 0; left: 0; right: 0;
    display: flex; align-items: center; gap: 0.75rem;
    padding: 0.6rem 1.1rem;
    background: rgba(0, 0, 0, 0.7); backdrop-filter: blur(6px);
    z-index: 10001;
  }
  #lb-info {
    flex: 1; font-size: 0.82rem; color: #cbd5e1;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  #lb-info .lb-test  { color: #93c5fd; font-weight: 600; }
  #lb-info .lb-sep   { color: #475569; margin: 0 0.4rem; }
  #lb-info .lb-step  { color: #e2e8f0; }
  #lb-counter { font-size: 0.75rem; color: #64748b; flex-shrink: 0; }
  #lb-close {
    font-size: 1.4rem; color: #94a3b8; cursor: pointer;
    line-height: 1; user-select: none; flex-shrink: 0;
    padding: 0.1rem 0.4rem; border-radius: 4px; transition: color 0.15s;
  }
  #lb-close:hover { color: #fff; }

  #lb-body {
    display: flex; align-items: center; justify-content: center;
    width: 100%; height: 100%; padding: 3.2rem 0 3rem; overflow: hidden;
  }
  #lb-img {
    max-width: calc(100vw - 8rem); max-height: calc(100vh - 8rem);
    border-radius: 4px; box-shadow: 0 0.5rem 3rem #000;
    object-fit: contain; transition: opacity 0.12s;
  }
  .lb-nav-btn {
    width: 3.5rem; height: 100%; flex-shrink: 0;
    display: flex; align-items: center; justify-content: center;
    background: none; border: none; cursor: pointer;
    color: #475569; font-size: 1.8rem;
    transition: color 0.15s, background 0.15s; user-select: none;
  }
  .lb-nav-btn:hover:not(:disabled) {
    color: #fff; background: rgba(255, 255, 255, 0.06);
  }
  .lb-nav-btn:disabled { color: #1e293b; cursor: default; }

  #lb-strip-wrap {
    position: fixed; bottom: 0; left: 0; right: 0;
    background: rgba(0, 0, 0, 0.72); backdrop-filter: blur(4px);
    padding: 0.3rem 0.8rem;
  }
  #lb-strip {
    display: flex; gap: 0.3rem; overflow-x: auto;
    scrollbar-width: none; -ms-overflow-style: none;
  }
  #lb-strip::-webkit-scrollbar { display: none; }
  .lb-thumb {
    width: 3rem; height: 2.2rem; flex-shrink: 0;
    border-radius: 3px; object-fit: cover;
    opacity: 0.4; cursor: pointer; border: 2px solid transparent;
    transition: opacity 0.15s, border-color 0.15s;
  }
  .lb-thumb:hover { opacity: 0.8; }
  .lb-thumb.active { opacity: 1; border-color: #3b82f6; }
</style>
</head>
<body>
<div class="container">

  <h1>E2E Test Dashboard</h1>
  <p class="subtitle">Generated: $timestamp &nbsp;|&nbsp; cb_file_manager</p>

  <div class="summary-row">
    <div class="card">
      <div class="card-label">Total</div>
      <div class="card-value">$total</div>
    </div>
    <div class="card">
      <div class="card-label">Passed</div>
      <div class="card-value green">$passed</div>
    </div>
    <div class="card">
      <div class="card-label">Failed</div>
      <div class="card-value red">$failed</div>
    </div>
    ${blocked > 0 ? '''<div class="card">
      <div class="card-label">Blocked</div>
      <div class="card-value yellow">$blocked</div>
    </div>''' : ''}
    <div class="bar-wrap">
      <div class="bar-header">
        <span class="bar-label">Pass Rate</span>
        <span class="bar-pct">${passRate.toStringAsFixed(1)}%</span>
      </div>
      <div class="bar-track">
        <div class="bar-fill-pass" style="width: ${(passed / (total == 0 ? 1 : total) * 100).toStringAsFixed(2)}%"></div>
        ${failed > 0 ? '<div class="bar-fill-fail" style="width: ${(failed / total * 100).toStringAsFixed(2)}%"></div>' : ''}
        ${blocked > 0 ? '<div class="bar-fill-blocked" style="width: ${(blocked / total * 100).toStringAsFixed(2)}%"></div>' : ''}
      </div>
    </div>
  </div>

  ${suiteBanner.toString()}

  <div class="controls-row">
    <input type="text" id="searchInput" class="search-box"
           placeholder="Search test cases..." oninput="applyFilters()">
    <div class="filters">
      <button class="filter-btn active" data-filter="all" onclick="setFilter('all')">All ($total)</button>
      <button class="filter-btn" data-filter="passed" onclick="setFilter('passed')">Passed ($passed)</button>
      <button class="filter-btn" data-filter="failed" onclick="setFilter('failed')">Failed ($failed)</button>
      ${blocked > 0 ? '<button class="filter-btn" data-filter="blocked" onclick="setFilter(\'blocked\')">Blocked ($blocked)</button>' : ''}
    </div>
    <div class="collapse-controls">
      <button class="collapse-btn" onclick="expandAll()">Expand All</button>
      <button class="collapse-btn" onclick="collapseAll()">Collapse All</button>
    </div>
  </div>

  <div id="suiteList">
$suiteSections
  </div>
</div>

<!-- Lightbox -->
<div id="lb-overlay" onclick="lbClose()">
  <div id="lb-topbar" onclick="event.stopPropagation()">
    <div id="lb-info">
      <span class="lb-test"></span>
      <span class="lb-sep">›</span>
      <span class="lb-step"></span>
    </div>
    <span id="lb-counter"></span>
    <span id="lb-close" onclick="lbClose()">&#x2715;</span>
  </div>
  <div id="lb-body" onclick="event.stopPropagation()">
    <button class="lb-nav-btn" id="lb-prev" onclick="lbPrev()">&#x276E;</button>
    <img id="lb-img" src="" alt="">
    <button class="lb-nav-btn" id="lb-next" onclick="lbNext()">&#x276F;</button>
  </div>
  <div id="lb-strip-wrap" onclick="event.stopPropagation()">
    <div id="lb-strip"></div>
  </div>
</div>

<script>
  const _shots = $shotsJson;
  let _idx = 0;
  let _stripBuilt = false;

  function _buildStrip() {
    if (_stripBuilt) return;
    const strip = document.getElementById('lb-strip');
    strip.innerHTML = '';
    _shots.forEach((s, i) => {
      const t = document.createElement('img');
      t.src = s.src;
      t.className = 'lb-thumb';
      t.onclick = () => lbGoto(i);
      strip.appendChild(t);
    });
    _stripBuilt = true;
  }

  function lbOpen(i) {
    _buildStrip();
    lbGoto(i);
  }

  function lbGoto(i) {
    if (!_shots.length) return;
    _idx = Math.max(0, Math.min(i, _shots.length - 1));
    const s = _shots[_idx];
    const img = document.getElementById('lb-img');
    img.style.opacity = '0';
    img.src = s.src;
    img.onload = () => { img.style.opacity = '1'; };
    document.querySelector('#lb-info .lb-test').textContent = s.test;
    document.querySelector('#lb-info .lb-step').textContent = s.step;
    document.getElementById('lb-counter').textContent = (_idx + 1) + ' / ' + _shots.length;
    document.getElementById('lb-prev').disabled = _idx === 0;
    document.getElementById('lb-next').disabled = _idx === _shots.length - 1;
    const thumbs = document.querySelectorAll('.lb-thumb');
    thumbs.forEach((t, j) => t.classList.toggle('active', j === _idx));
    if (thumbs[_idx]) {
      thumbs[_idx].scrollIntoView({ behavior: 'smooth', inline: 'nearest', block: 'nearest' });
    }
    document.getElementById('lb-overlay').classList.add('on');
  }

  function lbClose() { document.getElementById('lb-overlay').classList.remove('on'); }
  function lbPrev() { lbGoto(_idx - 1); }
  function lbNext() { lbGoto(_idx + 1); }

  document.addEventListener('keydown', e => {
    const on = document.getElementById('lb-overlay').classList.contains('on');
    if (!on) return;
    if (e.key === 'Escape')     lbClose();
    if (e.key === 'ArrowLeft')  lbPrev();
    if (e.key === 'ArrowRight') lbNext();
  });

  // Filters + search
  let _currentFilter = 'all';
  function setFilter(f) {
    _currentFilter = f;
    document.querySelectorAll('.filter-btn').forEach(b => {
      b.classList.toggle('active', b.dataset.filter === f);
    });
    applyFilters();
  }
  function applyFilters() {
    const q = (document.getElementById('searchInput').value || '').toLowerCase().trim();
    document.querySelectorAll('.test-item').forEach(item => {
      const status = item.dataset.status || '';
      const search = item.dataset.search || '';
      const matchFilter =
        _currentFilter === 'all' ||
        (_currentFilter === 'passed'  && status === 'passed') ||
        (_currentFilter === 'failed'  && status === 'failed') ||
        (_currentFilter === 'blocked' && status === 'blocked');
      const matchSearch = q === '' || search.indexOf(q) !== -1;
      item.classList.toggle('hidden', !(matchFilter && matchSearch));
    });
    document.querySelectorAll('.suite-group').forEach(group => {
      const visible = group.querySelectorAll('.test-item:not(.hidden)').length;
      group.classList.toggle('hidden', visible === 0);
    });
  }
  function expandAll() {
    document.querySelectorAll('details').forEach(d => d.open = true);
  }
  function collapseAll() {
    document.querySelectorAll('details').forEach(d => d.open = false);
  }
</script>
</body>
</html>''';
}

String _escapeHtml(String s) {
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

String _inferSuite(String name) {
  // 1. Explicit group() prefix (present in JSON reporter output).
  // New numbered prefixes are listed first; legacy names follow for
  // backward-compat with persisted dashboard state.
  const groupPrefixes = [
    '01 Navigation',
    '02 File Operations',
    '03 Cut & Move',
    '04 Folder Operations',
    '05 Multi-Select',
    '06 Keyboard Shortcuts',
    '07 Search & Filter',
    '08 View Mode',
    '09 Tab Management',
    '10 Edge Cases & Error Handling',
    '11 Extended File Operations',
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
  for (final prefix in groupPrefixes) {
    if (name.startsWith('$prefix ')) return prefix;
  }

  // 2. Keyword-based inference (backward compatibility with old logs)
  final lower = name.toLowerCase();
  if (lower.contains('cut') && lower.contains('move')) return 'Cut & Move';
  if (lower.contains('folder') &&
      (lower.contains('copy') ||
          lower.contains('delete') ||
          lower.contains('rename'))) {
    return 'Folder Operations';
  }
  if (lower.contains('f5') ||
      (lower.contains('refresh') && !lower.contains('folder')) ||
      lower.contains('escape') ||
      lower.contains('enter key') ||
      lower.contains('cancel rename')) {
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
      lower.contains('delete')) {
    return 'File Operations';
  }
  if (lower.contains('search') || lower.contains('filter')) {
    return 'Search & Filter';
  }
  if (lower.contains('grid view') ||
      lower.contains('list view') ||
      lower.contains('toggle') ||
      lower.contains('view mode')) {
    return 'View Mode';
  }
  if (lower.contains('tab') ||
      lower.contains('ctrl+t') ||
      lower.contains('ctrl+w')) {
    return 'Tab Management';
  }
  if (lower.contains('edge') ||
      lower.contains('error') ||
      lower.contains('cancel') ||
      lower.contains('empty name') ||
      lower.contains('no file') ||
      lower.contains('no folder') ||
      lower.contains('no longer exists')) {
    return 'Edge Cases & Error Handling';
  }
  if (lower.contains('extended') ||
      lower.contains('batch move') ||
      lower.contains('deep copy') ||
      lower.contains('nested')) {
    return 'Extended File Operations';
  }
  if (lower.contains('video') ||
      lower.contains('thumbnail') ||
      lower.contains('play_circle') ||
      lower.contains('mp4') ||
      lower.contains('thumbnail')) {
    return 'Video Thumbnails';
  }
  return 'E2E';
}

// ---------------------------------------------------------------------------
// File copier
// ---------------------------------------------------------------------------

Future<void> copyScreenshots(
    List<String> screenshots, String buildDir, String dashboardDir) async {
  final ssDir = Directory('$dashboardDir/screenshots');
  if (!await ssDir.exists()) {
    await ssDir.create(recursive: true);
  }

  // Possible source roots, in priority order. E2ETester writes to
  // build/e2e_report/screenshots; older tooling drops files in build/.
  final sourceRoots = <String>[
    '$buildDir/e2e_report/screenshots',
    buildDir,
  ];

  for (final ss in screenshots) {
    for (final root in sourceRoots) {
      final src = File('$root/$ss');
      if (await src.exists()) {
        await src.copy('${ssDir.path}/$ss');
        break;
      }
    }
  }
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  String? buildDir;

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--build-dir' && i + 1 < args.length) {
      buildDir = args[++i];
    }
  }

  buildDir ??= _kDefaultBuildDir;
  final reportFile = File('$buildDir/$_kReportFile');
  final dashboardDir = '$buildDir/$_kDashboardDir';

  if (!await reportFile.exists()) {
    print('[Dashboard] ERROR: $reportFile not found.');
    print('[Dashboard] Run E2E tests first: make dev-test mode=e2e');
    exit(1);
  }

  print('[Dashboard] Reading $reportFile ...');
  final content = await reportFile.readAsString();

  print('[Dashboard] Loading screenshot manifest ...');
  final manifestShots = await _loadManifestShots(buildDir);

  print('[Dashboard] Parsing test results ...');
  final freshReport = parseJsonLog(content, buildDir, manifestShots);

  // Merge with persisted state so reruns of a subset don't drop other tests.
  final persisted = await _loadPersistedState(dashboardDir);
  final merged = _mergeResults(persisted, freshReport.tests);

  if (merged.isEmpty) {
    print('[Dashboard] WARNING: No test results parsed from log.');
    exit(1);
  }

  // Sort by suite then name for stable output
  final sortedTests = merged.values.toList()
    ..sort((a, b) {
      final sa = _inferSuite(a.name);
      final sb = _inferSuite(b.name);
      final c = sa.compareTo(sb);
      if (c != 0) return c;
      return a.name.compareTo(b.name);
    });

  final report = TestReport(
    tests: sortedTests,
    generatedAt: DateTime.now(),
    suiteError: freshReport.suiteError,
    suiteStackTrace: freshReport.suiteStackTrace,
  );

  // Persist the merged state for the next run.
  await Directory(dashboardDir).create(recursive: true);
  await _savePersistedState(dashboardDir, merged);

  if (freshReport.tests.length < merged.length) {
    print('[Dashboard] Merged ${freshReport.tests.length} fresh result(s) '
        'with ${persisted.length} persisted — total ${merged.length}.');
  }

  // Collect all screenshots referenced by any test
  final allScreenshots = <String>{};
  for (final t in report.tests) {
    for (final s in t.shots) {
      allScreenshots.add(s.filename);
    }
  }

  // Copy screenshots into dashboard dir
  if (allScreenshots.isNotEmpty) {
    print('[Dashboard] Copying ${allScreenshots.length} screenshot(s) ...');
    await copyScreenshots(allScreenshots.toList(), buildDir, dashboardDir);
  }

  // Write HTML
  final htmlPath = '$dashboardDir/index.html';
  final html = generateHtml(report);
  await File(htmlPath).writeAsString(html);

  print('');
  print('[Dashboard] ✓ Report generated: $htmlPath');
  print('[Dashboard] Open in browser:');
  print('  file://${Directory.current.path}/$htmlPath');
  print('');
  final blockedSummary =
      report.blocked > 0 ? ', ${report.blocked} blocked' : '';
  print('  Summary: ${report.passed} passed, ${report.failed} failed'
      '$blockedSummary, ${report.total} total');
  print('  Pass rate: ${report.passRate.toStringAsFixed(1)}%');
  if (report.suiteError != null && report.suiteError!.isNotEmpty) {
    print('');
    print('[Dashboard] Suite-level failure:');
    print('  ${report.suiteError}');
  }
}

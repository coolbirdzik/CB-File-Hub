// Generates a self-contained HTML E2E test dashboard from flutter --reporter json output.
// Pure Dart — no npm / Node.js required.
//
// Flow (called by e2e_allure.dart after test run):
//   1. Read build/e2e_report.jsonl
//   2. Parse test results (name, status, error, duration)
//   3. Copy screenshots into build/e2e_dashboard/screenshots/
//   4. Write build/e2e_dashboard/index.html
//
// Usage (from cb_file_manager):
//   dart run tool/e2e_dashboard.dart
//   dart run tool/e2e_dashboard.dart --build-dir build
//
// Output:
//   cb_file_manager/build/e2e_dashboard/
//     index.html          ← self-contained dashboard (open in any browser)
//     screenshots/       ← copied failure screenshots

import 'dart:convert';
import 'dart:io';

const _kDefaultBuildDir = 'build';
const _kReportFile = 'e2e_report.jsonl';
const _kDashboardDir = 'e2e_dashboard';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class TestResult {
  final String name;
  final String status; // passed | failed | skipped | error
  final String? error;
  final String? stackTrace;
  final List<String> screenshots;

  TestResult({
    required this.name,
    required this.status,
    this.error,
    this.stackTrace,
    this.screenshots = const [],
  });

  bool get isPassed => status == 'passed' || status == 'success';
  bool get isFailed => status == 'failed' || status == 'error';
}

class TestReport {
  final List<TestResult> tests;
  final DateTime generatedAt;

  TestReport({required this.tests, required this.generatedAt});

  int get total => tests.length;
  int get passed => tests.where((t) => t.isPassed).length;
  int get failed => tests.where((t) => t.isFailed).length;
  int get skipped => tests.where((t) => t.status == 'skipped').length;

  double get passRate => total > 0 ? (passed / total * 100) : 0;
}

// ---------------------------------------------------------------------------
// JSON parser
// ---------------------------------------------------------------------------

TestReport parseJsonLog(String content, String buildDir) {
  final idToName = <int, String>{};
  final idToError = <int, _ErrorInfo>{};
  final hiddenIds = <int>{};

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
    } else if (type == 'testDone') {
      final testID = decoded['testID'] as int?;
      if (testID == null) continue;

      if (decoded['hidden'] == true) {
        hiddenIds.add(testID);
        continue;
      }

      final result = decoded['result'] as String?;
      if (result != null && result != 'success') {
        final error = decoded['error'] as String?;
        idToError[testID] = _ErrorInfo(
          message: _firstLine(error ?? ''),
          trace: error ?? '',
        );
      }
    }
  }

  final results = <TestResult>[];
  for (final entry in idToName.entries) {
    final testID = entry.key;
    if (hiddenIds.contains(testID)) continue;

    final name = entry.value;
    final errorInfo = idToError[testID];
    final status = errorInfo != null ? 'failed' : 'passed';
    final screenshots = _findScreenshots(name, buildDir);

    results.add(TestResult(
      name: name,
      status: status,
      error: errorInfo?.message,
      stackTrace: errorInfo?.trace,
      screenshots: screenshots,
    ));
  }

  return TestReport(tests: results, generatedAt: DateTime.now());
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

List<String> _findScreenshots(String testName, String buildDir) {
  // Scan actual screenshots in build dir — don't guess filenames
  final buildPath = Directory(buildDir);
  if (!buildPath.existsSync()) return [];

  final screenshots = <String>[];
  try {
    for (final entity in buildPath.listSync()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
        screenshots.add(entity.path.split(Platform.pathSeparator).last);
      }
    }
  } catch (_) {}

  if (screenshots.isEmpty) return [];

  // Match screenshot to test by checking if test name keywords appear in filename
  final keywords = testName
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 3 && !_stopWords.contains(w))
      .toList();

  // Try each screenshot and score by keyword matches
  final candidates = <_SsCandidate>[];

  for (final ss in screenshots) {
    final ssLower = ss.toLowerCase();
    // Prioritize _failure screenshots for failed tests
    if (!ssLower.contains('failure') && !ssLower.contains('error')) continue;

    int score = 0;
    for (final kw in keywords) {
      if (ssLower.contains(kw)) score++;
    }
    if (score > 0) candidates.add(_SsCandidate(ss, score));
  }

  // Sort by score descending
  candidates.sort((a, b) => b.score - a.score);

  return candidates.map((c) => c.name).toList();
}

class _SsCandidate {
  final String name;
  final int score;
  _SsCandidate(this.name, this.score);
}

const _stopWords = {
  'the',
  'and',
  'for',
  'via',
  'with',
  'from',
  'that',
  'this',
  'into',
  'file',
  'right'
};

// ---------------------------------------------------------------------------
// HTML generator
// ---------------------------------------------------------------------------

String generateHtml(TestReport report, String screenshotsDir) {
  final passed = report.passed;
  final failed = report.failed;
  final total = report.total;
  final passRate = report.passRate;

  final passColor = passed == total ? '#22c55e' : '#eab308';

  // Group tests by suite
  final Map<String, List<TestResult>> suiteGroups = {};
  for (final t in report.tests) {
    final suite = _inferSuite(t.name);
    suiteGroups.putIfAbsent(suite, () => []).add(t);
  }

  // Build suite sections with collapsible <details>
  final suiteSections = StringBuffer();
  for (final entry in suiteGroups.entries) {
    final suiteName = entry.key;
    final tests = entry.value;
    final suitePassed = tests.where((t) => t.isPassed).length;
    final suiteTotal = tests.length;
    final suiteFailed = suiteTotal - suitePassed;
    final allPassed = suitePassed == suiteTotal;

    final statusClass = allPassed ? 'all-pass' : 'has-fail';
    final statsText = suiteFailed > 0
        ? '$suitePassed/$suiteTotal passed'
        : '$suiteTotal/$suiteTotal passed';

    suiteSections.writeln('<details class="suite-group" open>');
    suiteSections.writeln('<summary class="suite-header $statusClass">');
    suiteSections.writeln('<span class="suite-chevron">▶</span>');
    suiteSections
        .writeln('<span class="suite-name">${_escapeHtml(suiteName)}</span>');
    suiteSections.writeln('<span class="suite-stats">$statsText</span>');
    suiteSections.writeln('</summary>');
    suiteSections.writeln('<div class="suite-tests">');

    for (final t in tests) {
      final badge = t.isPassed
          ? '<span class="badge pass">PASSED</span>'
          : '<span class="badge fail">FAILED</span>';

      // Strip group prefix from display name for cleaner look
      var displayName = t.name;
      if (displayName.startsWith('$suiteName ')) {
        displayName = displayName.substring(suiteName.length + 1);
      }

      final expandBtn = t.isFailed
          ? '<button class="expand-btn" onclick="toggleDetail(this)">Details</button>'
          : '';

      final errorSection = t.isFailed && t.error != null
          ? '''
      <div class="error-section">
        <div class="error-msg">${_escapeHtml(t.error ?? '')}</div>
        ${t.screenshots.isNotEmpty ? t.screenshots.map((s) => '<div class="screenshot-wrap"><img src="$screenshotsDir/$s" alt="failure screenshot" onclick="window.open(this.src)" title="Click to enlarge"/></div>').join('\n') : ''}
      </div>'''
          : '';

      suiteSections.writeln('''
    <div class="test-item ${t.isPassed ? 'passed' : 'failed'}">
      <div class="test-header" ${t.isFailed ? 'onclick="toggleDetail(this.querySelector(\'.expand-btn\') || this)"' : ''}>
        <span class="test-name">${_escapeHtml(displayName)}</span>
        $badge
        $expandBtn
      </div>
      $errorSection
    </div>''');
    }

    suiteSections.writeln('</div>'); // .suite-tests
    suiteSections.writeln('</details>'); // .suite-group
  }

  final timestamp =
      report.generatedAt.toLocal().toString().replaceAll('.000', '');

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
    background: #0f172a;
    color: #e2e8f0;
    min-height: 100vh;
    padding: 2rem;
  }

  .container { max-width: 1100px; margin: 0 auto; }

  .title-row {
    display: flex; align-items: baseline; gap: 1rem;
    margin-bottom: 0.25rem; flex-wrap: wrap;
  }
  h1 {
    font-size: 1.6rem;
    font-weight: 700;
    color: #f8fafc;
  }
  .detail-link {
    font-size: 0.8rem; font-weight: 500;
    color: #3b82f6; text-decoration: none;
    padding: 0.2rem 0.65rem; border-radius: 99px;
    border: 1px solid #1d4ed8;
    white-space: nowrap;
    transition: background 0.15s, color 0.15s;
  }
  .detail-link:hover { background: #1d4ed8; color: #fff; }
  .subtitle {
    font-size: 0.8rem;
    color: #64748b;
    margin-bottom: 1.5rem;
  }

  /* ---- Summary cards ---- */
  .summary-row {
    display: flex;
    gap: 1rem;
    margin-bottom: 1.5rem;
    flex-wrap: wrap;
  }

  .card {
    background: #1e293b;
    border-radius: 12px;
    padding: 1.25rem 1.5rem;
    flex: 1;
    min-width: 140px;
    border: 1px solid #334155;
  }

  .card-label { font-size: 0.75rem; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.4rem; }
  .card-value { font-size: 2rem; font-weight: 700; }
  .card-value.green { color: #22c55e; }
  .card-value.red   { color: #ef4444; }
  .card-value.gray  { color: #94a3b8; }

  /* ---- Pass rate bar ---- */
  .bar-wrap {
    background: #1e293b;
    border-radius: 12px;
    padding: 1.25rem 1.5rem;
    flex: 2;
    border: 1px solid #334155;
  }
  .bar-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.6rem; }
  .bar-label { font-size: 0.75rem; color: #94a3b8; text-transform: uppercase; }
  .bar-pct { font-size: 1.5rem; font-weight: 700; color: $passColor; }
  .bar-track {
    background: #334155;
    border-radius: 99px;
    height: 10px;
    overflow: hidden;
    display: flex;
  }
  .bar-fill-pass { background: #22c55e; height: 100%; transition: width 0.6s ease; border-radius: 99px 0 0 99px; }
  .bar-fill-fail { background: #ef4444; height: 100%; transition: width 0.6s ease; }
  .bar-sep { width: 2px; background: #0f172a; }

  /* ---- Controls ---- */
  .controls-row {
    display: flex; gap: 0.5rem; margin-bottom: 1rem; flex-wrap: wrap;
    align-items: center;
  }
  .filters { display: flex; gap: 0.5rem; flex: 1; flex-wrap: wrap; }
  .filter-btn {
    padding: 0.4rem 0.9rem;
    border-radius: 99px;
    border: 1px solid #334155;
    background: #1e293b;
    color: #94a3b8;
    font-size: 0.8rem;
    cursor: pointer;
    transition: all 0.15s;
  }
  .filter-btn:hover { border-color: #475569; color: #e2e8f0; }
  .filter-btn.active { background: #3b82f6; border-color: #3b82f6; color: #fff; }

  .collapse-controls { display: flex; gap: 0.4rem; }
  .collapse-btn {
    padding: 0.35rem 0.75rem; border-radius: 6px;
    border: 1px solid #334155; background: #1e293b;
    color: #64748b; font-size: 0.75rem; cursor: pointer;
    transition: all 0.15s;
  }
  .collapse-btn:hover { border-color: #475569; color: #e2e8f0; }

  /* ---- Suite groups (collapsible) ---- */
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
  details.suite-group[open] > .suite-header .suite-chevron {
    transform: rotate(90deg);
  }

  .suite-name {
    flex: 1; font-size: 0.9rem; font-weight: 600; color: #e2e8f0;
  }
  .suite-stats {
    font-size: 0.75rem; padding: 0.15rem 0.6rem; border-radius: 99px;
    flex-shrink: 0;
  }
  .suite-header.all-pass .suite-stats {
    background: #14532d; color: #22c55e;
  }
  .suite-header.has-fail .suite-stats {
    background: #451a03; color: #eab308;
  }

  .suite-tests { padding: 0.25rem 0; }

  /* ---- Test list ---- */
  .test-item {
    border-bottom: 1px solid #1e293b;
    transition: background-color 0.15s;
  }
  .test-item:last-child { border-bottom: none; }
  .test-item.passed { border-left: 3px solid #22c55e; }
  .test-item.failed  { border-left: 3px solid #ef4444; }

  .test-header {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.6rem 1rem 0.6rem 1.25rem;
    cursor: default;
  }
  .test-item.failed .test-header { cursor: pointer; }
  .test-item.failed .test-header:hover { background: #263344; }

  .test-name {
    flex: 1;
    font-size: 0.85rem;
    color: #e2e8f0;
    font-family: 'Cascadia Code', 'Fira Code', monospace;
  }

  .badge {
    font-size: 0.65rem;
    padding: 0.15rem 0.5rem;
    border-radius: 99px;
    font-weight: 600;
    white-space: nowrap;
    flex-shrink: 0;
    letter-spacing: 0.03em;
  }
  .badge.pass { background: #14532d; color: #22c55e; }
  .badge.fail { background: #450a0a; color: #ef4444; }

  .expand-btn {
    background: none;
    border: 1px solid #334155;
    color: #64748b;
    font-size: 0.7rem;
    padding: 0.15rem 0.5rem;
    border-radius: 6px;
    cursor: pointer;
    flex-shrink: 0;
  }
  .expand-btn:hover { border-color: #ef4444; color: #ef4444; }

  .error-section {
    display: none;
    padding: 0.75rem 1rem 1rem 1.5rem;
    border-top: 1px solid #334155;
    animation: slideDown 0.2s ease;
  }
  .error-section.open { display: block; }

  @keyframes slideDown {
    from { opacity: 0; transform: translateY(-4px); }
    to   { opacity: 1; transform: translateY(0); }
  }

  .error-msg {
    background: #2d0a0a;
    border: 1px solid #450a0a;
    border-radius: 8px;
    padding: 0.75rem;
    font-family: 'Cascadia Code', 'Fira Code', monospace;
    font-size: 0.78rem;
    color: #fca5a5;
    white-space: pre-wrap;
    word-break: break-all;
    margin-bottom: 0.75rem;
    max-height: 200px;
    overflow-y: auto;
  }

  .screenshot-wrap {
    border-radius: 8px;
    overflow: hidden;
    border: 1px solid #334155;
    cursor: zoom-in;
    max-width: 500px;
  }
  .screenshot-wrap img {
    width: 100%;
    display: block;
    transition: transform 0.2s;
  }
  .screenshot-wrap img:hover { transform: scale(1.02); }

  .hidden { display: none !important; }
</style>
</head>
<body>
<div class="container">

  <div class="title-row">
    <h1>E2E Test Dashboard</h1>
    <a href="../e2e_report/report.html" class="detail-link">📸 Screenshot Report →</a>
  </div>
  <p class="subtitle">Generated: $timestamp &nbsp;|&nbsp; cb_file_manager</p>

  <!-- Summary cards -->
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
    <div class="bar-wrap">
      <div class="bar-header">
        <span class="bar-label">Pass Rate</span>
        <span class="bar-pct">${passRate.toStringAsFixed(1)}%</span>
      </div>
      <div class="bar-track">
        <div class="bar-fill-pass" style="width: ${passRate}%"></div>
        ${failed > 0 ? '<div class="bar-fill-fail" style="width: ${100 - passRate}%"></div>' : ''}
      </div>
    </div>
  </div>

  <!-- Controls: filters + expand/collapse -->
  <div class="controls-row">
    <div class="filters" id="filters">
      <button class="filter-btn active" data-filter="all" onclick="setFilter('all')">All ($total)</button>
      <button class="filter-btn" data-filter="passed" onclick="setFilter('passed')">Passed ($passed)</button>
      <button class="filter-btn" data-filter="failed" onclick="setFilter('failed')">Failed ($failed)</button>
    </div>
    <div class="collapse-controls">
      <button class="collapse-btn" onclick="expandAll()">Expand All</button>
      <button class="collapse-btn" onclick="collapseAll()">Collapse All</button>
    </div>
  </div>

  <!-- Suite groups -->
  <div id="suiteList">
$suiteSections
  </div>

</div>

<script>
  let currentFilter = 'all';

  function setFilter(filter) {
    currentFilter = filter;
    document.querySelectorAll('.filter-btn').forEach(b => {
      b.classList.toggle('active', b.dataset.filter === filter);
    });
    document.querySelectorAll('.test-item').forEach(item => {
      const isPass = item.classList.contains('passed');
      if (filter === 'all') {
        item.classList.remove('hidden');
      } else if (filter === 'passed') {
        item.classList.toggle('hidden', !isPass);
      } else {
        item.classList.toggle('hidden', isPass);
      }
    });
    // Hide suite groups with no visible tests
    document.querySelectorAll('.suite-group').forEach(group => {
      const visibleTests = group.querySelectorAll('.test-item:not(.hidden)').length;
      group.classList.toggle('hidden', visibleTests === 0);
    });
  }

  function toggleDetail(btn) {
    const item = btn.closest('.test-item');
    const section = item.querySelector('.error-section');
    if (!section) return;
    section.classList.toggle('open');
  }

  function expandAll() {
    document.querySelectorAll('.suite-group').forEach(d => d.open = true);
  }

  function collapseAll() {
    document.querySelectorAll('.suite-group').forEach(d => d.open = false);
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
  // 1. Explicit group() prefix (present in JSON reporter output)
  const groupPrefixes = [
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

  for (final ss in screenshots) {
    final src = File('$buildDir/$ss');
    if (await src.exists()) {
      await src.copy('$ssDir/$ss');
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

  print('[Dashboard] Parsing test results ...');
  final report = parseJsonLog(content, buildDir);

  if (report.tests.isEmpty) {
    print('[Dashboard] WARNING: No test results parsed from log.');
    exit(1);
  }

  // Collect all screenshots from failed tests
  final allScreenshots = <String>{};
  for (final t in report.tests) {
    allScreenshots.addAll(t.screenshots);
  }

  // Copy screenshots into dashboard dir
  if (allScreenshots.isNotEmpty) {
    print('[Dashboard] Copying ${allScreenshots.length} screenshot(s) ...');
    await copyScreenshots(allScreenshots.toList(), buildDir, dashboardDir);
  }

  // Write HTML
  await Directory(dashboardDir).create(recursive: true);
  final htmlPath = '$dashboardDir/index.html';
  final html = generateHtml(report, 'screenshots');
  await File(htmlPath).writeAsString(html);

  print('');
  print('[Dashboard] ✓ Report generated: $htmlPath');
  print('[Dashboard] Open in browser:');
  print('  file://${Directory.current.path}/$htmlPath');
  print('');
  print(
      '  Summary: ${report.passed} passed, ${report.failed} failed, ${report.total} total');
  print('  Pass rate: ${report.passRate.toStringAsFixed(1)}%');
}

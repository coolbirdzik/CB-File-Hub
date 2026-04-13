// E2E screenshot capture and self-updating HTML report.
//
// Usage inside a testWidgets() call:
//   await captureE2EScreenshot(tester, 'test name', 'initial state');
//   await captureE2EScreenshot(tester, 'test name', 'result');
//   await recordTestResult('test name', passed);   // call at end of test
//
// Output is written to:
//   build/e2e_report/report.html         ← open this in a browser
//   build/e2e_report/screenshots/*.png   ← referenced by the HTML (relative paths)
//
// The HTML file is rewritten after every captured screenshot so a partial
// report is available even if later tests crash.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cb_file_manager/e2e/cb_e2e_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'e2e_keys.dart' as keys;

// ---------------------------------------------------------------------------
// Internal state
// ---------------------------------------------------------------------------

class _Entry {
  final String testName;
  final String step;
  final String filename;
  final DateTime ts;
  _Entry(
      {required this.testName,
      required this.step,
      required this.filename,
      required this.ts});
}

final List<_Entry> _log = [];
Directory? _reportDir;
Directory? _screenshotsDir;
int _counter = 0;

/// Stores test results so the HTML report can show pass/fail badges.
/// Key = test name, Value = true (passed) / false (failed).
final Map<String, bool> _testResults = {};

/// Records the result of a test for the HTML report.
///
/// Call this at the end of each `testWidgets()` test:
///   await recordTestResult('my test', true);   // passed
///   await recordTestResult('my test', false);  // failed
///
/// If not called, the test shows with no badge (unknown status).
void recordTestResult(String testName, bool passed) {
  _testResults[testName] = passed;
  _writeResultsJson(); // persist so e2e_parallel can read it after merge
}

/// Exports _testResults to build/e2e_report/results.json so e2e_parallel
/// can read it after merging and inject pass/fail into the HTML.
/// Loads results.json (written by e2e_parallel) and report.jsonl (Flutter JSONL)
/// into _testResults so pass/fail badges are shown in the HTML.
Future<void> _loadResultsJson() async {
  if (_reportDir == null) return;
  try {
    final file = File(p.join(_reportDir!.path, 'results.json'));
    if (!await file.exists()) return;
    final content = await file.readAsString();
    if (content.trim().isEmpty || content.trim() == '{}') return;
    final decoded = jsonDecode(content);
    if (decoded is! Map) return;
    for (final entry in decoded.entries) {
      final key = entry.key as String;
      final val = entry.value;
      if (val is bool) _testResults[key] = val;
    }
  } catch (_) {}
  // Also load from report.jsonl if results.json is missing/incomplete
  await _loadResultsFromJsonl();
}

Future<void> _writeResultsJson() async {
  if (_reportDir == null) return;
  try {
    final file = File(p.join(_reportDir!.path, 'results.json'));
    final entries = _testResults.entries
        .map((e) => '  "${_esc(e.key)}": ${e.value}')
        .join(',\n');
    await file.writeAsString('{\n$entries\n}');
  } catch (_) {}
}

/// Reads build/e2e_report.jsonl (written by run_e2e_with_log.dart --json-report)
/// and merges test results into _testResults. Does NOT write results.json —
/// used only during HTML generation so pass/fail data is available even
/// without e2e_parallel.
Future<void> _loadResultsFromJsonl() async {
  if (_reportDir == null) return;
  // run_e2e_with_log.dart writes to build/e2e_report.jsonl (not report.jsonl)
  final file = File(p.join(_reportDir!.path, 'e2e_report.jsonl'));
  if (!await file.exists()) return;
  try {
    final content = await file.readAsString();
    if (content.trim().isEmpty) return;
    final idToName = <int, String>{};
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || !line.startsWith('{')) continue;
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
          if (name != null) _testResults[name] = result == 'success';
        }
      }
    }
  } catch (_) {}
}

/// Merges test results from a JSONL file (produced by flutter --reporter json)
/// into the _testResults map and writes results.json.
///
/// This is called by e2e_parallel.dart after merging all worker JSONLs so the
/// screenshot HTML gets accurate pass/fail badges.
Future<void> mergeTestResultsFromJsonl(String jsonlContent) async {
  final idToName = <int, String>{};
  for (final rawLine in jsonlContent.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || !line.startsWith('{')) continue;
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
        if (name != null) {
          _testResults[name] = result == 'success';
        }
      }
    }
  }
  await _ensureReportDir();
  await _writeResultsJson();
}

int get totalTestCount => _testResults.length;
int get passedTestCount => _testResults.values.where((v) => v).length;
int get failedTestCount => _testResults.values.where((v) => !v).length;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Captures a screenshot, saves it as a PNG, and updates the HTML report.
///
/// [testName] must match the string passed to [testWidgets].
/// [step] is a human-readable label, e.g. `'initial state'` or `'result'`.
///
/// Non-fatal: all errors are caught so a failing screenshot never causes a
/// test to fail.
Future<void> captureE2EScreenshot(
  WidgetTester tester,
  String testName,
  String step,
) async {
  try {
    await _ensureReportDir();

    // Let the UI fully settle before grabbing a frame.
    // The action that triggered this screenshot already called pumpAndSettle,
    // so this is mostly free (returns immediately when already settled).
    try {
      await tester.pumpAndSettle(
        kCbE2EFast
            ? const Duration(milliseconds: 100)
            : const Duration(seconds: 1),
      );
    } catch (_) {
      await tester.pump(
        kCbE2EFast
            ? const Duration(milliseconds: 50)
            : const Duration(milliseconds: 200),
      );
    }
    await tester.pump(
      kCbE2EFast
          ? const Duration(milliseconds: 16)
          : const Duration(milliseconds: 50),
    );

    final index = ++_counter;
    final slug =
        '${index.toString().padLeft(3, '0')}_${_slugify(testName)}_${_slugify(step)}';

    final Uint8List? bytes = await _capturePngBytes(tester, slug);

    if (bytes != null && bytes.isNotEmpty) {
      final filename = '$slug.png';
      final file = File(p.join(_screenshotsDir!.path, filename));
      await file.writeAsBytes(bytes);

      _log.add(_Entry(
        testName: testName,
        step: step,
        filename: filename,
        ts: DateTime.now(),
      ));

      // Write the HTML report every 5 screenshots (crash recovery still works
      // within 5 shots) rather than after every single capture to avoid
      // rebuilding the full HTML string 100+ times per run.
      if (_counter % 5 == 0) await _writeHtmlReport();

      if (kDebugMode) {
        debugPrint(
            '[E2E Report] Screenshot saved: $filename  →  ${_reportDir!.path}${Platform.pathSeparator}report.html');
      }
    } else {
      if (kDebugMode) {
        debugPrint(
            '[E2E Report] No bytes captured for "$slug" — screenshot skipped');
      }
    }
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint(
          '[E2E Report] captureE2EScreenshot failed (non-fatal): $e\n$st');
    }
  }
}

// ---------------------------------------------------------------------------
// E2ETester — WidgetTester wrapper that auto-screenshots every interaction
// ---------------------------------------------------------------------------

/// WidgetTester wrapper with optional action-by-action screenshots.
///
/// Usage:
/// ```dart
/// testWidgets('my test', (WidgetTester tester) async {
///   final et = E2ETester(tester);
///   await et.init('my test');
///
///   // Interactions settle the UI; full screenshot mode also captures each one.
///   await et.enterText(finder, 'hello');
///   await et.tap(finder);
///   await et.longPress(finder);
///   await et.drag(finder, const Offset(0, -100));
///   await et.scrollUntilVisible(finder, scrollable, 100);
///   await et.pumpAndSettle();
///   await et.screenshot('custom label');       // manual snapshot any time
/// });
/// ```
///
/// Methods return `Future<void>` to match [WidgetTester] signatures.
/// Finder errors (zero elements) are logged and skip without failing the test.
class E2ETester {
  /// The wrapped tester. Exposed for helpers that still need the raw
  /// [WidgetTester] (e.g. some `page.go()` extensions).
  final WidgetTester tester;

  /// Base label prepended to every auto-generated screenshot step name.
  /// Set via [init].
  String _label = '';

  E2ETester(this.tester);

  /// Initialise the test label and capture the first "initial state" screenshot.
  /// Call once at the top of each test, before any interactions:
  ///   await et.init('my test');
  Future<void> init(String label) async {
    _label = label;
    await captureE2EScreenshot(tester, _label, '00_initial');
  }

  // -------------------------------------------------------------------------
  // Generic / manual screenshot helpers
  // -------------------------------------------------------------------------

  /// Manually capture a screenshot with a custom [step] label.
  /// Always flushes the HTML report to disk (useful at test end).
  Future<void> screenshot(String step) async {
    await captureE2EScreenshot(tester, _label, step);
    await _writeHtmlReport(); // always flush at explicit checkpoints
  }

  /// Wait for animations to settle, then capture a screenshot.
  Future<void> screenshotSettled(String step) async {
    try {
      await tester.pumpAndSettle(const Duration(seconds: 2));
    } catch (_) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await captureE2EScreenshot(tester, _label, step);
  }

  /// Capture a screenshot, then run [expectation], then capture again.
  /// Useful for documenting assertion states without duplicating the assertion.
  Future<void> screenshotBeforeExpect(
    String step,
    Future<void> Function() expectation,
  ) async {
    await captureE2EScreenshot(tester, _label, step);
    await expectation();
  }

  /// Run [expectation], then capture a screenshot.
  /// Useful for documenting the result of a series of steps.
  Future<void> screenshotAfterExpect(
    String step,
    Future<void> Function() expectation,
  ) async {
    await expectation();
    await captureE2EScreenshot(tester, _label, step);
  }

  /// Record that this test passed. Call at the end of the test.
  /// Flushes the HTML report immediately.
  Future<void> pass() async {
    recordTestResult(_label, true);
    await _writeHtmlReport();
  }

  /// Record that this test failed. Call at the end of the test.
  /// Flushes the HTML report immediately.
  Future<void> fail() async {
    recordTestResult(_label, false);
    await _writeHtmlReport();
  }

  // -------------------------------------------------------------------------
  // Internal sequencing
  // -------------------------------------------------------------------------

  int _actionCounter = 0;

  String _seq(String action, [String? detail]) {
    final c = (++_actionCounter).toString().padLeft(3, '0');
    return detail != null ? '${action}_${c}_$detail' : '${action}_$c';
  }

  /// Runs [fn] then captures a screenshot.  Never throws.
  Future<void> _act(String action, Future<void> Function() fn,
      [String? detail]) async {
    await fn();
    if (kCbE2EFullScreenshots) {
      await captureE2EScreenshot(tester, _label, _seq(action, detail));
    } else {
      await _settleAfterAction();
    }
  }

  Future<void> _settleAfterAction() async {
    try {
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    } catch (_) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // -------------------------------------------------------------------------
  // Widget interaction forwards (each auto-screenshots after running)
  // -------------------------------------------------------------------------

  /// See [WidgetTester.tap].
  Future<void> tap(Finder finder, {String? detail}) => _act(
        'tap',
        () async => await tester.tap(finder),
        detail,
      );

  /// See [WidgetTester.longPress].
  Future<void> longPress(Finder finder, {String? detail}) => _act(
        'long_press',
        () async => await tester.longPress(finder),
        detail,
      );

  /// See [WidgetTester.enterText].
  Future<void> enterText(Finder finder, String text, {String? detail}) => _act(
        'enter_text',
        () async => await tester.enterText(finder, text),
        detail ?? text,
      );

  /// See [WidgetTester.drag].
  Future<void> drag(Finder finder, Offset offset, {String? detail}) => _act(
        'drag',
        () async => await tester.drag(finder, offset),
        detail,
      );

  /// See [WidgetTester.fling].
  Future<void> fling(Finder finder, Offset offset, {String? detail}) => _act(
        'fling',
        () async => await tester.fling(finder, offset, 3000),
        detail,
      );

  /// Scrolls [scrollable] by [distance] until [target] is visible.
  /// Signature matches Flutter SDK 2.x: scrollUntilVisible(scrollable, distance).
  /// If [target] is provided the method first calls ensureVisible on it.
  Future<void> scrollUntilVisible(
    Finder target,
    Finder scrollable,
    double distance, {
    String? detail,
  }) =>
      _act(
        'scroll',
        () async {
          await tester.ensureVisible(target);
          await tester.scrollUntilVisible(scrollable, distance);
        },
        detail,
      );

  /// See [WidgetTester.ensureVisible].
  Future<void> ensureVisible(Finder finder) async {
    await tester.ensureVisible(finder);
  }

  /// See [WidgetTester.pump].
  Future<void> pump([Duration? duration]) async {
    await tester.pump(duration);
  }

  /// Pump until animations are done.
  /// [pumpAndSettle] does NOT auto-screenshot — it is a timing wait, not a
  /// user-visible action. Use [screenshotSettled] when you also need a frame.
  Future<void> pumpAndSettle([Duration? duration]) async {
    await tester.pumpAndSettle(duration ?? const Duration(days: 1));
  }

  // -------------------------------------------------------------------------
  // Keyboard helpers — sendKeyDownEvent / sendKeyUpEvent / sendKeyEvent
  // These don't use _act because WidgetTester key methods don't take a callback.
  // -------------------------------------------------------------------------

  /// Press [key] down.
  Future<void> keyDown(LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    if (kCbE2EFullScreenshots) {
      await captureE2EScreenshot(tester, _label, 'key_down_${key.keyLabel}');
    } else {
      await _settleAfterAction();
    }
  }

  /// Release [key].
  Future<void> keyUp(LogicalKeyboardKey key) async {
    await tester.sendKeyUpEvent(key);
    if (kCbE2EFullScreenshots) {
      await captureE2EScreenshot(tester, _label, 'key_up_${key.keyLabel}');
    } else {
      await _settleAfterAction();
    }
  }

  /// Full key press: down → up → screenshot.
  Future<void> keyPress(LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    if (kCbE2EFullScreenshots) {
      await captureE2EScreenshot(tester, _label, 'key_press_${key.keyLabel}');
    } else {
      await _settleAfterAction();
    }
  }

  // -------------------------------------------------------------------------
  // Shortcut helpers — common Finder + action combos
  // -------------------------------------------------------------------------

  /// Finder.byIcon + tap.
  Future<void> tapIcon(IconData icon, {String? detail}) =>
      tap(find.byIcon(icon), detail: detail ?? 'icon_${icon.codePoint}');

  /// Finder.byType + tap.
  Future<void> tapByType(Type type, {String? detail}) =>
      tap(find.byType(type), detail: detail ?? type.toString());

  /// Finder.byKey + tap.
  Future<void> tapByKey(ValueKey key, {String? detail}) =>
      tap(find.byKey(key), detail: detail ?? key.toString());

  /// Finder.byIcon + longPress.
  Future<void> longPressIcon(IconData icon, {String? detail}) =>
      longPress(find.byIcon(icon), detail: detail ?? 'icon_${icon.codePoint}');

  /// Finder.byType + longPress.
  Future<void> longPressByType(Type type, {String? detail}) =>
      longPress(find.byType(type), detail: detail ?? type.toString());

  /// Finder.byType + enterText.
  Future<void> enterTextByType(Type type, String text, {String? detail}) =>
      enterText(find.byType(type), text, detail: detail ?? type.toString());

  // -------------------------------------------------------------------------
  // Project-specific helper wrappers (auto-screenshot after each action)
  // -------------------------------------------------------------------------

  /// Single-tap a file row (grid or list). Auto-screenshots after.
  Future<void> tapFileRow(String path, {String? detail}) => _act(
        'tap_file',
        () => keys.tapFileRow(tester, path),
        detail ?? _lastName(path),
      );

  /// Double-tap a folder row to navigate into it. Auto-screenshots after.
  Future<void> tapFolderRow(String path, {String? detail}) => _act(
        'tap_folder',
        () => keys.tapFolderRow(tester, path),
        detail ?? _lastName(path),
      );

  /// Single-tap a folder row to select it (no navigation). Auto-screenshots after.
  Future<void> selectFolderRow(String path, {String? detail}) => _act(
        'select_folder',
        () => keys.selectFolderRow(tester, path),
        detail ?? _lastName(path),
      );

  /// Ctrl+click to add a file to the multi-selection. Auto-screenshots after.
  Future<void> selectFileWithCtrl(String path, {String? detail}) => _act(
        'ctrl_select',
        () => keys.selectFileWithCtrl(tester, path),
        detail ?? _lastName(path),
      );

  /// Right-click a file row to open its context menu. Auto-screenshots after.
  Future<void> rightClickFileRow(String path, {String? detail}) => _act(
        'right_click_file',
        () => keys.rightClickFileRow(tester, path),
        detail ?? _lastName(path),
      );

  /// Right-click a folder row to open its context menu. Auto-screenshots after.
  Future<void> rightClickFolderRow(String path, {String? detail}) => _act(
        'right_click_folder',
        () => keys.rightClickFolderRow(tester, path),
        detail ?? _lastName(path),
      );

  /// Tap a context menu item by its action id. Auto-screenshots after.
  Future<void> tapContextMenuItem(String actionId, {String? detail}) => _act(
        'menu',
        () => keys.tapContextMenuItem(tester, actionId),
        detail ?? actionId,
      );

  /// Right-click on the background (empty area) to open the background context menu.
  /// Auto-screenshots after.
  Future<void> openBackgroundContextMenu(
          {Offset? tapPosition, String? detail}) =>
      _act(
        'bg_menu',
        () => keys.openBackgroundContextMenu(tester, tapPosition: tapPosition),
        detail,
      );

  /// Send a keyboard shortcut (modifiers + key). Auto-screenshots after.
  Future<void> sendKeyboardShortcut({
    LogicalKeyboardKey key = LogicalKeyboardKey.keyC,
    bool ctrl = false,
    bool shift = false,
    bool alt = false,
    String? detail,
  }) =>
      _act(
        'shortcut',
        () => keys.sendKeyboardShortcut(
          tester,
          key: key,
          ctrl: ctrl,
          shift: shift,
          alt: alt,
        ),
        detail,
      );

  /// Type text into the currently focused TextField. Auto-screenshots after.
  Future<void> typeIntoFocusedField(String text, {String? detail}) => _act(
        'type',
        () => keys.typeIntoFocusedField(tester, text),
        detail ?? text,
      );

  /// Tap the dialog confirm button. Auto-screenshots after.
  Future<void> tapDialogConfirm({String? buttonText, String? detail}) => _act(
        'confirm',
        () => keys.tapDialogConfirm(tester, buttonText: buttonText),
        detail ?? buttonText ?? 'confirm',
      );

  /// Returns the last path segment — used as a concise screenshot label.
  static String _lastName(String path) {
    final sep = path.contains('/') ? '/' : r'\';
    return path.split(sep).lastWhere((s) => s.isNotEmpty, orElse: () => path);
  }
}

// ---------------------------------------------------------------------------
// Screenshot capture with two-layer fallback
// ---------------------------------------------------------------------------

/// Returns raw PNG bytes or null if all capture methods fail.
///
/// Layer 1 — [IntegrationTestWidgetsFlutterBinding.takeScreenshot]:
///   Uses the native `captureScreenshot` method channel. Works when running
///   with `flutter test` on devices that support it (Android, iOS, some
///   desktop configurations). May throw [MissingPluginException] on Windows
///   desktop when no driver is connected.
///
/// Layer 2 — [WidgetTester.captureImage] via [RenderRepaintBoundary.toImage]:
///   Pure-Dart fallback that walks the render tree. Works on all platforms
///   including Windows desktop `flutter test`.
Future<Uint8List?> _capturePngBytes(WidgetTester tester, String slug) async {
  // --- Layer 1: integration_test channel ---
  try {
    final binding = IntegrationTestWidgetsFlutterBinding.instance;
    final List<int> bytes = await binding.takeScreenshot(slug);
    if (bytes.isNotEmpty) {
      return Uint8List.fromList(bytes);
    }
  } catch (_) {
    // MissingPluginException or StateError on desktop — fall through.
  }

  // --- Layer 2: direct render-tree capture via flutter_test's captureImage ---
  // captureImage(Element) is a top-level function exported by flutter_test.
  // It walks up to the nearest RenderRepaintBoundary and calls toImage().
  final finders = <Finder>[
    find.byType(MaterialApp),
    find.byType(WidgetsApp),
  ];

  for (final finder in finders) {
    if (finder.evaluate().isEmpty) continue;
    try {
      final Element element = finder.evaluate().first;
      final ui.Image image = await captureImage(element);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData != null && byteData.lengthInBytes > 0) {
        return byteData.buffer.asUint8List();
      }
    } catch (_) {
      continue;
    }
  }

  return null;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

Future<void> _ensureReportDir() async {
  if (_reportDir != null) return;
  _reportDir = Directory(p.join(Directory.current.path, 'build', 'e2e_report'));
  _screenshotsDir = Directory(p.join(_reportDir!.path, 'screenshots'));
  await _screenshotsDir!.create(recursive: true);
  if (kDebugMode) {
    debugPrint('[E2E Report] Output directory: ${_reportDir!.path}');
  }
}

String _slugify(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _encodeJson(Map<String, bool> map) {
  final entries =
      map.entries.map((e) => '"${_esc(e.key)}": ${e.value}').join(', ');
  return '{$entries}';
}

/// Infers a suite name from a test name (without group() prefix).
/// Used for grouping screenshots in the HTML report.
String _inferSuiteFromTestName(String name) {
  final lower = name.toLowerCase();
  // Check specific patterns first (higher priority)
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
      lower.contains('mp4') ||
      lower.contains('play_circle')) {
    return 'Video Thumbnails';
  }
  return 'E2E';
}

Future<void> _writeHtmlReport() async {
  if (_reportDir == null) return;

  // Load results.json + report.jsonl so pass/fail data is available even without e2e_parallel
  await _loadResultsJson();

  // Group entries: suite → test name → entries (preserving insertion order).
  final Map<String, Map<String, List<_Entry>>> suiteGrouped = {};
  for (final e in _log) {
    final suite = _inferSuiteFromTestName(e.testName);
    suiteGrouped.putIfAbsent(suite, () => {});
    suiteGrouped[suite]!.putIfAbsent(e.testName, () => []).add(e);
  }

  final totalTests = _testResults.length;
  final totalPassed = passedTestCount;
  final totalFailed = failedTestCount;

  final sb = StringBuffer()
    ..writeln('<!DOCTYPE html>')
    ..writeln('<html lang="en">')
    ..writeln('<head>')
    ..writeln('<meta charset="UTF-8">')
    ..writeln(
        '<meta name="viewport" content="width=device-width,initial-scale=1.0">')
    ..writeln('<title>CB File Manager — E2E Report</title>')
    ..writeln('<style>')
    ..writeln(_kCss)
    ..writeln('</style>')
    ..writeln('</head>')
    ..writeln('<body>')
    ..writeln('<h1>CB File Manager &mdash; E2E Test Report</h1>')
    ..writeln('<p class="meta">'
        'Last updated: ${DateTime.now()}'
        ' &nbsp;&middot;&nbsp; ${_log.length} screenshot(s)'
        ' &nbsp;&middot;&nbsp; $totalTests test(s)'
        ' &nbsp;&middot;&nbsp; ${suiteGrouped.length} suite(s)'
        '</p>')
    // Summary cards
    ..writeln('<div class="summary-row">')
    ..writeln('<div class="stat-card">'
        '<div class="stat-label">Total</div>'
        '<div class="stat-value">$totalTests</div>'
        '</div>')
    ..writeln('<div class="stat-card stat-pass">'
        '<div class="stat-label">Passed</div>'
        '<div class="stat-value">$totalPassed</div>'
        '</div>')
    ..writeln('<div class="stat-card stat-fail">'
        '<div class="stat-label">Failed</div>'
        '<div class="stat-value">$totalFailed</div>'
        '</div>')
    ..writeln('</div>')
    // Search + filters
    ..writeln('<div class="controls-row">')
    ..writeln('<input type="text" id="searchInput" class="search-box" '
        'placeholder="Search test cases..." oninput="applyFilters()">')
    ..writeln('<div class="filter-btns">')
    ..writeln(
        '<button class="filter-btn active" data-filter="all" onclick="setFilter(\'all\')">All ($totalTests)</button>')
    ..writeln(
        '<button class="filter-btn" data-filter="passed" onclick="setFilter(\'passed\')">Passed ($totalPassed)</button>')
    ..writeln(
        '<button class="filter-btn" data-filter="failed" onclick="setFilter(\'failed\')">Failed ($totalFailed)</button>')
    ..writeln('</div>')
    // Per-page selector + pagination
    ..writeln('<div class="pager-row">')
    ..writeln('<div class="pager-btns">'
        '<button class="ctrl-btn" onclick="prevPage()">&#x276E; Prev</button>'
        '<span class="page-info" id="pageInfo">Page 1</span>'
        '<button class="ctrl-btn" onclick="nextPage()">Next &#x276F;</button>'
        '</div>')
    ..writeln('<div class="per-page">'
        '<label for="perPage">Show</label>'
        '<select id="perPage" onchange="setPerPage(this.value)">'
        '<option value="5">5</option>'
        '<option value="10" selected>10</option>'
        '<option value="20">20</option>'
        '<option value="50">50</option>'
        '<option value="999">All</option>'
        '</select>'
        '<label>per page</label>'
        '</div>')
    ..writeln('</div>')
    ..writeln(
        '<button class="ctrl-btn" onclick="document.querySelectorAll(\'details\').forEach(d=>d.open=true)">Expand All</button>')
    ..writeln(
        '<button class="ctrl-btn" onclick="document.querySelectorAll(\'details\').forEach(d=>d.open=false)">Collapse All</button>')
    ..writeln('</div>')
    // Hidden data for JS — must come before the JS that uses it
    ..writeln(
        '<script>const _testResults = ${_encodeJson(_testResults)};</script>');

  for (final suiteName in suiteGrouped.keys) {
    final testMap = suiteGrouped[suiteName]!;
    final testCount = testMap.keys.length;

    // Count passed/failed in this suite
    int suitePassed = 0, suiteFailed = 0;
    for (final tn in testMap.keys) {
      final result = _testResults[tn];
      if (result == true) {
        suitePassed++;
      } else if (result == false) {
        suiteFailed++;
      }
    }

    // Build a unique ID for this suite so we can show/hide it
    final suiteId = 'suite-${_slugify(suiteName)}';
    final suiteStatusClass =
        suiteFailed > 0 ? 'has-fail' : (suitePassed > 0 ? 'all-pass' : '');
    final suitePassRate = testCount > 0
        ? '${(suitePassed / testCount * 100).toStringAsFixed(0)}%'
        : '-';

    sb
      ..writeln(
          '<div class="suite-section $suiteStatusClass" id="$suiteId" data-suite="$suiteName">')
      ..writeln('<details class="suite-inner" open>')
      ..writeln('<summary class="suite-title">')
      ..writeln('<span class="suite-name">${_esc(suiteName)}</span>')
      ..writeln('<span class="suite-stats">'
          '$suitePassed/$testCount &nbsp; <span class="suite-rate">$suitePassRate</span></span>')
      ..writeln('</summary>')
      ..writeln('<div class="suite-content">');

    for (final testName in testMap.keys) {
      final entries = testMap[testName]!;
      final result = _testResults[testName];
      // Build test data for JS
      final testPassed = result == true;
      final testFailed = result == false;
      final testStatus =
          result == null ? 'unknown' : (testPassed ? 'passed' : 'failed');
      final testSearchable =
          '${_esc(testName)} ${suiteName.toLowerCase()}'.toLowerCase();

      final badgeClass = testFailed
          ? 'badge-fail'
          : (testPassed ? 'badge-pass' : 'badge-unknown');
      final badgeLabel = testFailed ? 'FAILED' : (testPassed ? 'PASSED' : '?');

      sb
        ..writeln('<div class="test-group" '
            'data-test-name="${_esc(testName)}" '
            'data-searchable="${_esc(testSearchable)}" '
            'data-status="$testStatus" '
            'data-suite="${_esc(suiteName)}">')
        ..writeln('<details class="test-inner" open>')
        ..writeln('<summary class="test-title">'
            '<span class="test-name-text">${_esc(testName)}</span>'
            '<span class="$badgeClass">$badgeLabel</span>'
            '</summary>')
        ..writeln('<div class="screenshots">');

      for (final entry in entries) {
        sb
          ..writeln('<div class="card">')
          ..writeln(
              '<img src="screenshots/${_esc(entry.filename)}" alt="${_esc(entry.step)}" onclick="lb(this)" loading="lazy">')
          ..writeln('<div class="card-info">')
          ..writeln('<div class="step">${_esc(entry.step)}</div>')
          ..writeln('<div class="ts">${entry.ts}</div>')
          ..writeln('</div>')
          ..writeln('</div>');
      }

      sb
        ..writeln('</div>') // .screenshots
        ..writeln('</details>')
        ..writeln('</div>'); // .test-group
    }

    sb
      ..writeln('</div>') // .suite-content
      ..writeln('</details>')
      ..writeln('</div>'); // .suite-section
  }

  sb
    ..writeln(_kLightboxHtml)
    ..writeln('</body>')
    ..writeln('</html>');

  final reportFile = File(p.join(_reportDir!.path, 'report.html'));
  await reportFile.writeAsString(sb.toString());
}

// ---------------------------------------------------------------------------
// Embedded CSS
// ---------------------------------------------------------------------------

const _kCss = r'''
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #0f0f0f; color: #d8d8d8; padding: 28px 36px; line-height: 1.5;
  }

  h1 { font-size: 22px; font-weight: 600; color: #f2f2f2; margin-bottom: 6px; }
  .meta { font-size: 13px; color: #555; margin-bottom: 16px; }

  /* Summary cards */
  .summary-row {
    display: flex; gap: 12px; margin-bottom: 20px; flex-wrap: wrap;
  }
  .stat-card {
    background: #161616; border: 1px solid #222; border-radius: 8px;
    padding: 12px 20px; min-width: 100px;
  }
  .stat-label { font-size: 11px; color: #666; text-transform: uppercase; letter-spacing: .05em; margin-bottom: 4px; }
  .stat-value { font-size: 24px; font-weight: 700; }
  .stat-pass .stat-value { color: #4ade80; }
  .stat-fail .stat-value { color: #f87171; }

  /* Controls row */
  .controls-row {
    display: flex; gap: 8px; margin-bottom: 24px; flex-wrap: wrap;
    align-items: center;
  }
  .search-box {
    flex: 1; min-width: 200px; padding: 7px 12px; font-size: 13px;
    background: #1a1a1a; border: 1px solid #2a2a2a; color: #d8d8d8;
    border-radius: 6px; outline: none; transition: border-color .15s;
  }
  .search-box::placeholder { color: #444; }
  .search-box:focus { border-color: #3a7eff; }

  .filter-btns { display: flex; gap: 6px; }
  .filter-btn {
    padding: 6px 14px; font-size: 12px; border-radius: 6px;
    border: 1px solid #333; background: #1a1a1a; color: #999;
    cursor: pointer; transition: all .15s;
  }
  .filter-btn:hover { border-color: #3a7eff; color: #cce3ff; }
  .filter-btn.active { background: #3a7eff; border-color: #3a7eff; color: #fff; }

  .pager-row {
    display: flex; gap: 8px; align-items: center; flex-wrap: wrap;
    margin-bottom: 8px;
  }
  .pager-btns { display: flex; gap: 6px; align-items: center; }
  .page-info { font-size: 12px; color: #555; padding: 0 8px; white-space: nowrap; }

  .per-page { display: flex; gap: 6px; align-items: center; font-size: 12px; color: #666; }
  .per-page select {
    background: #1a1a1a; border: 1px solid #2a2a2a; color: #d8d8d8;
    border-radius: 5px; padding: 3px 8px; font-size: 12px; cursor: pointer;
    outline: none;
  }
  .per-page select:focus { border-color: #3a7eff; }
  .per-page label { color: #666; }

  /* Suite controls */
  .suite-controls { display: flex; gap: 8px; margin-bottom: 24px; }
  .ctrl-btn {
    padding: 5px 14px; font-size: 12px; border-radius: 6px;
    border: 1px solid #333; background: #1a1a1a; color: #999;
    cursor: pointer; transition: all .15s;
  }
  .ctrl-btn:hover { border-color: #3a7eff; color: #cce3ff; }

  /* Suite section (outer collapsible) */
  .suite-section {
    margin-bottom: 28px; border: 1px solid #222; border-radius: 10px;
    overflow: hidden; background: #131313;
  }
  .suite-section.has-fail { border-color: #5c2020; }
  .suite-section.all-pass { border-color: #1a4a2a; }

  .suite-title {
    display: flex; align-items: center; justify-content: space-between;
    padding: 12px 18px; background: #181818; cursor: pointer;
    user-select: none; list-style: none; border-bottom: 1px solid #222;
  }
  .suite-title::-webkit-details-marker { display: none; }
  .suite-title::before {
    content: '▶'; margin-right: 12px; font-size: 10px; color: #555;
    transition: transform .2s; flex-shrink: 0;
  }
  details[open] > .suite-title::before { transform: rotate(90deg); }

  .suite-name {
    font-size: 14px; font-weight: 600; color: #aecfff; flex: 1;
  }
  .suite-stats {
    font-size: 12px; color: #666; flex-shrink: 0; display: flex; gap: 6px; align-items: center;
  }
  .suite-rate { font-size: 11px; color: #4ade80; }

  .suite-content { padding: 8px 12px 12px; }

  /* Test group (inner collapsible) */
  .test-group {
    margin-bottom: 14px; border: 1px solid #1e1e1e; border-radius: 8px;
    overflow: hidden; background: #151515;
  }

  .test-title {
    display: flex; align-items: center; gap: 10px;
    font-size: 13px; font-weight: 500; color: #cce3ff;
    padding: 9px 14px; cursor: pointer; user-select: none;
    list-style: none; border-left: 3px solid #3a7eff;
    background: #181818;
  }
  .test-title::-webkit-details-marker { display: none; }
  .test-title::before {
    content: '▶'; margin-right: 10px; font-size: 9px; color: #555;
    transition: transform .2s; display: inline-block; flex-shrink: 0;
  }
  details[open] > .test-title::before { transform: rotate(90deg); }

  .test-name-text { flex: 1; }

  /* Pass/fail badges */
  .badge-pass { background: #1a4a2a; color: #4ade80; font-size: 10px; padding: 2px 8px; border-radius: 99px; font-weight: 700; }
  .badge-fail { background: #5c2020; color: #f87171; font-size: 10px; padding: 2px 8px; border-radius: 99px; font-weight: 700; }
  .badge-unknown { background: #333; color: #666; font-size: 10px; padding: 2px 8px; border-radius: 99px; font-weight: 700; }

  .screenshots { display: flex; flex-wrap: wrap; gap: 16px; padding: 12px 14px; }

  .card {
    background: #161616; border: 1px solid #252525; border-radius: 8px;
    overflow: hidden; width: 440px; transition: border-color .15s;
  }
  .card:hover { border-color: #3a7eff; }

  .card img {
    width: 100%; display: block; cursor: zoom-in;
    border-bottom: 1px solid #252525;
  }

  .card-info { padding: 10px 13px; }
  .step { font-size: 13px; font-weight: 500; color: #cce3ff; }
  .ts   { font-size: 11px; color: #484848; margin-top: 3px; }

  /* Hidden / filtered */
  .hidden { display: none !important; }

  /* Lightbox overlay */
  #lb-overlay {
    display: none; position: fixed; inset: 0;
    background: rgba(0,0,0,.92); z-index: 9999;
    flex-direction: column; align-items: center; justify-content: center;
  }
  #lb-overlay.on { display: flex; }

  /* Top bar: test name + step label on left, counter + close on right */
  #lb-topbar {
    position: fixed; top: 0; left: 0; right: 0;
    display: flex; align-items: center; gap: 12px;
    padding: 10px 18px;
    background: rgba(0,0,0,.75); backdrop-filter: blur(6px);
    z-index: 10001;
  }
  #lb-info {
    flex: 1; font-size: 13px; color: #cce3ff;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  #lb-info .lb-test  { color: #7db4ff; font-weight: 600; }
  #lb-info .lb-sep   { color: #555; margin: 0 6px; }
  #lb-info .lb-step  { color: #cce3ff; }
  #lb-counter {
    font-size: 12px; color: #666; white-space: nowrap; flex-shrink: 0;
  }
  #lb-close {
    font-size: 22px; color: #888; cursor: pointer;
    line-height: 1; user-select: none; flex-shrink: 0;
    padding: 2px 6px; border-radius: 4px; transition: color .15s;
  }
  #lb-close:hover { color: #fff; }

  /* Image container with side nav buttons */
  #lb-body {
    display: flex; align-items: center; justify-content: center;
    width: 100%; height: 100%; padding: 52px 0 48px;
    overflow: hidden;
  }
  #lb-img {
    max-width: calc(100vw - 130px); max-height: calc(100vh - 110px);
    border-radius: 4px; box-shadow: 0 8px 48px #000;
    display: block; object-fit: contain;
    transition: opacity .12s;
  }
  .lb-nav-btn {
    width: 58px; height: 100%; flex-shrink: 0;
    display: flex; align-items: center; justify-content: center;
    background: none; border: none; cursor: pointer;
    color: #444; font-size: 30px;
    transition: color .15s, background .15s;
    user-select: none;
  }
  .lb-nav-btn:hover:not(:disabled) { color: #fff; background: rgba(255,255,255,.06); }
  .lb-nav-btn:disabled { color: #222; cursor: default; }

  /* Bottom thumbnail strip */
  #lb-strip-wrap {
    position: fixed; bottom: 0; left: 0; right: 0;
    background: rgba(0,0,0,.72); backdrop-filter: blur(4px);
    padding: 5px 12px;
  }
  #lb-strip {
    display: flex; gap: 5px; overflow-x: auto; max-width: 100%;
    scrollbar-width: none; -ms-overflow-style: none;
    align-items: center; justify-content: flex-start;
  }
  #lb-strip::-webkit-scrollbar { display: none; }
  .lb-thumb {
    width: 46px; height: 34px; flex-shrink: 0;
    border-radius: 3px; object-fit: cover;
    opacity: .35; cursor: pointer;
    border: 2px solid transparent;
    transition: opacity .15s, border-color .15s;
  }
  .lb-thumb:hover { opacity: .72; }
  .lb-thumb.active { opacity: 1; border-color: #3a7eff; }
''';

// ---------------------------------------------------------------------------
// Lightbox HTML + JS
// ---------------------------------------------------------------------------

const _kLightboxHtml = r'''
  <div id="lb-overlay" onclick="lbClose()">
    <!-- Top bar -->
    <div id="lb-topbar" onclick="event.stopPropagation()">
      <div id="lb-info">
        <span class="lb-test"></span>
        <span class="lb-sep">›</span>
        <span class="lb-step"></span>
      </div>
      <span id="lb-counter"></span>
      <span id="lb-close" onclick="lbClose()">&#x2715;</span>
    </div>
    <!-- Main image + side nav -->
    <div id="lb-body" onclick="event.stopPropagation()">
      <button class="lb-nav-btn" id="lb-prev" onclick="lbPrev()">&#x276E;</button>
      <img id="lb-img" src="" alt="">
      <button class="lb-nav-btn" id="lb-next" onclick="lbNext()">&#x276F;</button>
    </div>
    <!-- Thumbnail strip -->
    <div id="lb-strip-wrap" onclick="event.stopPropagation()">
      <div id="lb-strip"></div>
    </div>
  </div>

  <script>
    /* ---- Pagination state ---- */
    let _currentPage = 0;
    let _currentFilter = 'all';
    let _currentSearch = '';
    let _allVisibleTests = [];  // .test-group elements that are currently visible

    /* ---- Lightbox ---- */
    let _shots = null;   // lazy-built: [{src, test, step}]
    let _idx   = 0;

    function _buildShots() {
      if (_shots) return;
      _shots = [];
      document.querySelectorAll('.screenshots .card').forEach(card => {
        const img  = card.querySelector('img');
        if (!img) return;
        const testEl = card.closest('.test-group') && card.closest('.test-group').querySelector('.test-title');
        const stepEl = card.querySelector('.step');
        _shots.push({
          src:  img.src,
          test: testEl ? testEl.textContent.trim() : '',
          step: stepEl ? stepEl.textContent.trim() : '',
        });
      });
      const strip = document.getElementById('lb-strip');
      strip.innerHTML = '';
      _shots.forEach(function(s, i) {
        var t = document.createElement('img');
        t.src = s.src; t.alt = '';
        t.className = 'lb-thumb';
        t.onclick = function() { lbGoto(i); };
        strip.appendChild(t);
      });
    }

    function lb(img) {
      _buildShots();
      var src = img.src;
      var i = 0;
      for (var j = 0; j < _shots.length; j++) {
        if (_shots[j].src === src) { i = j; break; }
      }
      lbGoto(i);
    }

    function lbGoto(i) {
      _buildShots();
      if (!_shots.length) return;
      _idx = Math.max(0, Math.min(i, _shots.length - 1));
      var s = _shots[_idx];

      var lbImg = document.getElementById('lb-img');
      lbImg.style.opacity = '0';
      lbImg.src = s.src;
      lbImg.onload = function() { lbImg.style.opacity = '1'; };

      document.querySelector('#lb-info .lb-test').textContent = s.test;
      document.querySelector('#lb-info .lb-step').textContent = s.step;
      document.getElementById('lb-counter').textContent = (_idx + 1) + ' / ' + _shots.length;

      document.getElementById('lb-prev').disabled = _idx === 0;
      document.getElementById('lb-next').disabled = _idx === _shots.length - 1;

      var thumbs = document.querySelectorAll('.lb-thumb');
      for (var j = 0; j < thumbs.length; j++) {
        thumbs[j].classList.toggle('active', j === _idx);
      }
      if (thumbs[_idx]) {
        thumbs[_idx].scrollIntoView({ behavior: 'smooth', inline: 'nearest', block: 'nearest' });
      }

      document.getElementById('lb-overlay').classList.add('on');
    }

    function lbClose() {
      document.getElementById('lb-overlay').classList.remove('on');
    }
    function lbPrev() { lbGoto(_idx - 1); }
    function lbNext() { lbGoto(_idx + 1); }

    document.addEventListener('keydown', function(e) {
      var on = document.getElementById('lb-overlay').classList.contains('on');
      if (!on) return;
      if (e.key === 'Escape')     lbClose();
      if (e.key === 'ArrowLeft')  lbPrev();
      if (e.key === 'ArrowRight') lbNext();
    });

    /* ---- Filtering + Search + Pagination ---- */
    function setFilter(filter) {
      _currentFilter = filter;
      document.querySelectorAll('.filter-btn').forEach(function(b) {
        b.classList.toggle('active', b.dataset.filter === filter);
      });
      _currentPage = 0;
      applyFilters();
    }

    function applyFilters() {
      var searchEl = document.getElementById('searchInput');
      _currentSearch = (searchEl ? searchEl.value : '').toLowerCase().trim();

      var allTests = document.querySelectorAll('.test-group');
      _allVisibleTests = [];

      allTests.forEach(function(tg) {
        var searchable = tg.dataset.searchable || '';
        var status = tg.dataset.status || 'unknown';

        var matchFilter = (_currentFilter === 'all') ||
                          (_currentFilter === 'passed' && status === 'passed') ||
                          (_currentFilter === 'failed' && status === 'failed');

        var matchSearch = _currentSearch === '' ||
                           searchable.indexOf(_currentSearch) !== -1 ||
                           (tg.dataset.testName || '').toLowerCase().indexOf(_currentSearch) !== -1;

        tg.classList.toggle('hidden', !(matchFilter && matchSearch));
      });

      // Collect suite sections that have visible test groups
      document.querySelectorAll('.suite-section').forEach(function(s) {
        var visibleTests = s.querySelectorAll('.test-group:not(.hidden)');
        s.classList.toggle('hidden', visibleTests.length === 0);
      });

      // Rebuild visible list for pagination
      _allVisibleTests = Array.from(document.querySelectorAll('.test-group:not(.hidden)'));
      applyPagination();
    }

    function setPerPage(val) {
      var parsed = parseInt(val, 10);
      _perPage = isNaN(parsed) || parsed <= 0 ? 10 : parsed;
      _currentPage = 0;
      applyPagination();
    }

    function applyPagination() {
      var perPage = _perPage || 10;
      var total = _allVisibleTests.length;
      var totalPages = Math.max(1, Math.ceil(total / perPage));
      _currentPage = Math.min(_currentPage, totalPages - 1);

      _allVisibleTests.forEach(function(tg, i) {
        var start = _currentPage * perPage;
        tg.classList.toggle('hidden', i < start || i >= start + perPage);
      });

      // Update page info
      var pageInfo = document.getElementById('pageInfo');
      if (pageInfo) {
        pageInfo.textContent = total > 0
          ? 'Page ' + (_currentPage + 1) + ' / ' + totalPages + '  (' + total + ' test' + (total !== 1 ? 's' : '') + ')'
          : 'No results';
      }
    }

    function nextPage() {
      var perPage = _perPage || 10;
      var totalPages = Math.ceil(_allVisibleTests.length / perPage);
      if (_currentPage < totalPages - 1) {
        _currentPage++;
        applyPagination();
      }
    }

    function prevPage() {
      if (_currentPage > 0) {
        _currentPage--;
        applyPagination();
      }
    }
  </script>
  <script>
    /* ---- Per-page setting ---- */
    var _perPage = 10;

    /* ---- Test result badges + stats update ---- */
    function updateTestResults(data) {
      if (!data || Object.keys(data).length === 0) { applyFilters(); return; }
      var total = Object.keys(data).length;
      var passed = 0, failed = 0;
      for (var k in data) { if (data[k] === true) passed++; else failed++; }
      var cards = document.querySelectorAll('.stat-card');
      if (cards[0]) cards[0].querySelector('.stat-value').textContent = total;
      if (cards[1]) cards[1].querySelector('.stat-value').textContent = passed;
      if (cards[2]) cards[2].querySelector('.stat-value').textContent = failed;
      document.querySelectorAll('.filter-btn').forEach(function(b) {
        var f = b.dataset.filter;
        if (f === 'all')    b.textContent = 'All (' + total + ')';
        else if (f === 'passed') b.textContent = 'Passed (' + passed + ')';
        else if (f === 'failed')  b.textContent = 'Failed (' + failed + ')';
      });
      document.querySelectorAll('.test-group').forEach(function(tg) {
        var suite = tg.dataset.suite || '';
        var name  = tg.dataset.testName || '';
        var fullName = suite + ' ' + name;
        var result = data[fullName];
        if (result === undefined) result = data[name];
        var badge = tg.querySelector('[class*=badge-]');
        if (badge) {
          if (result === true) {
            badge.className = 'badge-pass';
            badge.textContent = 'PASSED';
            tg.dataset.status = 'passed';
          } else if (result === false) {
            badge.className = 'badge-fail';
            badge.textContent = 'FAILED';
            tg.dataset.status = 'failed';
          }
        }
      });
      document.querySelectorAll('.suite-section').forEach(function(s) {
        var tests = s.querySelectorAll('.test-group');
        var p = 0, f = 0;
        tests.forEach(function(t) {
          if (t.dataset.status === 'passed') p++;
          else if (t.dataset.status === 'failed') f++;
        });
        var stotal = tests.length;
        var rate = stotal > 0 ? Math.round(p / stotal * 100) : 0;
        var stats = s.querySelector('.suite-stats');
        if (stats) stats.innerHTML = p + '/' + stotal + ' &nbsp; <span class="suite-rate">' + rate + '%</span>';
        s.className = 'suite-section ' + (f > 0 ? 'has-fail' : (p > 0 ? 'all-pass' : ''));
      });
      applyFilters();
    }
    // Wait for DOM to be fully loaded before updating test results
    document.addEventListener('DOMContentLoaded', function() {
      if (typeof _testResults !== 'undefined' && _testResults !== null && Object.keys(_testResults).length > 0) {
        updateTestResults(_testResults);
      } else {
        fetch('results.json').then(function(r) { return r.ok ? r.json() : null; }).then(function(data) {
          if (data) { _testResults = data; updateTestResults(data); }
          else { applyFilters(); }
        }).catch(function() { applyFilters(); });
      }
    });
  </script>
''';

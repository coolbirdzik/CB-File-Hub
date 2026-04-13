import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Desktop often uses [ViewMode.grid] (saved in preferences). Grid rows use
/// `file-grid-item-*` / `folder-grid-item-*`; list/details use `file-item-*` / `folder-item-*`.
bool _hasKey(Finder finder) => finder.evaluate().isNotEmpty;

/// Asserts a file row is visible in either grid or list layout.
void expectFileRowVisible(String absolutePath) {
  final grid = find.byKey(ValueKey('file-grid-item-$absolutePath'));
  final list = find.byKey(ValueKey('file-item-$absolutePath'));
  expect(
    _hasKey(grid) || _hasKey(list),
    isTrue,
    reason: 'Expected file row for path (grid or list). path=$absolutePath '
        'gridCount=${grid.evaluate().length} listCount=${list.evaluate().length}',
  );
}

/// Asserts no file row widget exists for [absolutePath] (grid or list).
void expectFileRowAbsent(String absolutePath) {
  expect(
    find.byKey(ValueKey('file-grid-item-$absolutePath')),
    findsNothing,
    reason: 'Expected no grid file row for $absolutePath',
  );
  expect(
    find.byKey(ValueKey('file-item-$absolutePath')),
    findsNothing,
    reason: 'Expected no list file row for $absolutePath',
  );
}

/// Asserts a folder row is visible in either grid or list layout.
/// Use this BEFORE [tapFolderRow] to fail fast at the right step.
void expectFolderRowVisible(String absolutePath) {
  final grid = find.byKey(ValueKey('folder-grid-item-$absolutePath'));
  final list = find.byKey(ValueKey('folder-item-$absolutePath'));
  expect(
    _hasKey(grid) || _hasKey(list),
    isTrue,
    reason: 'Expected folder row for path (grid or list). path=$absolutePath '
        'gridCount=${grid.evaluate().length} listCount=${list.evaluate().length}',
  );
}

/// Verifies a folder row exists (grid or list). Fails immediately if not found.
void assertFolderRowExists(String absolutePath) {
  final grid = find.byKey(ValueKey('folder-grid-item-$absolutePath'));
  final list = find.byKey(ValueKey('folder-item-$absolutePath'));
  if (!_hasKey(grid) && !_hasKey(list)) {
    fail(
      'assertFolderRowExists FAILED: folder row not found. path=$absolutePath '
      'gridCount=${grid.evaluate().length} listCount=${list.evaluate().length}',
    );
  }
  if (kDebugMode) {
    debugPrint('[E2E] assertFolderRowExists OK: $absolutePath');
  }
}

/// Verifies a file row exists (grid or list). Fails immediately if not found.
void assertFileRowExists(String absolutePath) {
  final grid = find.byKey(ValueKey('file-grid-item-$absolutePath'));
  final list = find.byKey(ValueKey('file-item-$absolutePath'));
  if (!_hasKey(grid) && !_hasKey(list)) {
    fail(
      'assertFileRowExists FAILED: file row not found. path=$absolutePath '
      'gridCount=${grid.evaluate().length} listCount=${list.evaluate().length}',
    );
  }
  if (kDebugMode) {
    debugPrint('[E2E] assertFileRowExists OK: $absolutePath');
  }
}

/// Opens a folder row (grid or list).
///
/// On **desktop**, a single tap only toggles selection; navigation uses **double-tap**
/// (see folder grid/list items in `folder_list/components`).
Future<void> tapFolderRow(WidgetTester tester, String absolutePath) async {
  final finder = _resolveFileOrFolderFinder(
    absolutePath,
    gridKeyPrefix: 'folder-grid-item',
    listKeyPrefix: 'folder-item',
  );
  if (finder == null) {
    fail('No folder row found for $absolutePath');
  }
  if (kDebugMode) {
    debugPrint('[E2E] tapFolderRow: double-tapping $absolutePath');
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder, warnIfMissed: false);
}

/// Returns the center [Offset] of a file or folder row (grid or list).
/// Throws if the row is not found.
Offset getFileOrFolderCenter(WidgetTester tester, String absolutePath,
    {bool isFolder = false}) {
  final gridPrefix = isFolder ? 'folder-grid-item' : 'file-grid-item';
  final listPrefix = isFolder ? 'folder-item' : 'file-item';
  final finder = _resolveFileOrFolderFinder(
    absolutePath,
    gridKeyPrefix: gridPrefix,
    listKeyPrefix: listPrefix,
  );
  if (finder == null) {
    fail('getCenter FAILED: no row found for $absolutePath');
  }
  return tester.getCenter(finder);
}

/// Resolves a Finder for a file or folder row in either grid or list layout.
/// Returns null if neither is found.
Finder? _resolveFileOrFolderFinder(
  String absolutePath, {
  required String gridKeyPrefix,
  required String listKeyPrefix,
}) {
  final grid = find.byKey(ValueKey('$gridKeyPrefix-$absolutePath'));
  final list = find.byKey(ValueKey('$listKeyPrefix-$absolutePath'));
  if (_hasKey(grid)) return grid;
  if (_hasKey(list)) return list;
  return null;
}

/// Taps a file row in either grid or list layout.
/// Does NOT double-tap — use this for single actions (e.g., right-click to open context menu).
Future<void> tapFileRow(WidgetTester tester, String absolutePath) async {
  final finder = _resolveFileOrFolderFinder(
    absolutePath,
    gridKeyPrefix: 'file-grid-item',
    listKeyPrefix: 'file-item',
  );
  if (finder == null) {
    fail('tapFileRow FAILED: no file row found for $absolutePath');
  }
  if (kDebugMode) {
    debugPrint('[E2E] tapFileRow: tapping $absolutePath');
  }
  await tester.tap(finder);
}

/// Performs Ctrl+click to add [absolutePath] to the current multi-selection.
/// Works in both grid and list view modes.
Future<void> selectFileWithCtrl(
    WidgetTester tester, String absolutePath) async {
  final finder = _resolveFileOrFolderFinder(
    absolutePath,
    gridKeyPrefix: 'file-grid-item',
    listKeyPrefix: 'file-item',
  );
  if (finder == null) {
    fail('selectFileWithCtrl FAILED: no file row found for $absolutePath');
  }
  final center = tester.getCenter(finder);
  if (kDebugMode) {
    debugPrint('[E2E] selectFileWithCtrl: Ctrl+clicking $absolutePath');
  }
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.tapAt(center);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
}

/// Opens the context menu for a file by right-clicking it.
/// Works in both grid and list view modes.
Future<void> rightClickFileRow(WidgetTester tester, String absolutePath) async {
  final finder = _resolveFileOrFolderFinder(
    absolutePath,
    gridKeyPrefix: 'file-grid-item',
    listKeyPrefix: 'file-item',
  );
  if (finder == null) {
    fail('rightClickFileRow FAILED: no file row found for $absolutePath');
  }
  final center = tester.getCenter(finder);
  if (kDebugMode) {
    debugPrint('[E2E] rightClickFileRow: right-clicking $absolutePath');
  }
  await tester.tapAt(center, buttons: kSecondaryMouseButton);
  // Wait for the context menu to render. pumpAndSettle handles animations,
  // but the menu may need extra frames to build the PopupMenuItem widgets.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

/// Taps a context menu item by its action id.
///
/// The app uses `showMenu<String>()` → `List<PopupMenuEntry<String>>` which
/// renders as `PopupMenuItem<String>` widgets inside an Overlay.
///
/// IMPORTANT CAVEATS:
/// 1. `find.byWidgetPredicate.evaluate()` does NOT find widgets in the Overlay.
///    We use `tester.widgetList` which traverses the full element tree including
///    Overlay entries (via `_TheaterElement.debugVisitOnstageChildren`).
/// 2. `pumpAndSettle` may return BEFORE `showMenu` finishes rendering its items.
///    We pump extra frames to ensure the PopupMenuItem widgets are in the tree.
/// 3. On Windows desktop, some items (e.g. 'new_folder') are nested inside a
///    submenu. Submenu triggers are `PopupMenuItem` with `enabled: false` and no
///    `value`; their children are `InkWell` widgets in an `OverlayEntry` — NOT
///    `PopupMenuItem<String>`. This function handles that automatically by tapping
///    each disabled `PopupMenuItem` in turn until the target label appears.
///
/// Example usage:
///   await tapContextMenuItem(tester, 'copy');      // Copy file
///   await tapContextMenuItem(tester, 'new_folder'); // Works on Windows & non-Windows
Future<void> tapContextMenuItem(
  WidgetTester tester,
  String actionId,
) async {
  if (kDebugMode) {
    debugPrint('[E2E] tapContextMenuItem: tapping id="$actionId"');
  }

  // Give the overlay time to render the menu items.
  // `pumpAndSettle` from the caller may return before `showMenu`'s internal
  // layout is complete. Extra pumps ensure PopupMenuItem widgets exist in the tree.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));

  final actionIds = _actionIdAliases(actionId);
  final labels = _actionIdLabels(actionId);

  // Step 1: direct PopupMenuItem<String> value match (top-level non-submenu items).
  var foundCount = 0;
  final allMenuItems = tester
      .widgetList<PopupMenuItem<String>>(
        find.byType(PopupMenuItem<String>),
      )
      .toList();
  for (final item in allMenuItems) {
    if (actionIds.contains(item.value)) {
      foundCount++;
    }
  }
  if (kDebugMode) {
    debugPrint(
        '[E2E] tapContextMenuItem: direct value match found $foundCount item(s)');
  }
  if (foundCount > 0) {
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is PopupMenuItem<String> && actionIds.contains(w.value),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));
    return;
  }

  // Step 2: label text match — handles items that are already visible as Text
  // (e.g. submenu OverlayEntry InkWell rows that are already open).
  final textFinder = _findFirstVisibleText(labels);
  final textCount = textFinder?.evaluate().length ?? 0;
  if (kDebugMode) {
    debugPrint(
        '[E2E] tapContextMenuItem: label candidates ${labels.join(" | ")} found $textCount time(s)');
  }
  if (textFinder != null && textCount > 0) {
    await tester.tap(textFinder.first, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    return;
  }

  // Step 3: submenu exploration.
  // On Windows desktop, items like 'new_folder' live inside a submenu.
  // Submenu triggers are `PopupMenuItem<String>` with `enabled: false` and no value —
  // tapping them inserts an OverlayEntry with InkWell rows for each child action.
  // Try each disabled PopupMenuItem in turn; once the target label becomes visible
  // (as Text inside the OverlayEntry), tap it.
  if (kDebugMode) {
    debugPrint('[E2E] tapContextMenuItem: trying submenu exploration');
  }
  final submenuTriggerFinder = find.byWidgetPredicate(
    (w) => w is PopupMenuItem<String> && w.enabled == false,
  );
  final triggerCount = submenuTriggerFinder.evaluate().length;
  if (kDebugMode) {
    debugPrint(
        '[E2E] tapContextMenuItem: found $triggerCount submenu trigger(s)');
  }
  for (var i = 0; i < triggerCount; i++) {
    final trigger = submenuTriggerFinder.at(i);
    await tester.ensureVisible(trigger);
    await tester.tap(trigger, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final retryFinder = _findFirstVisibleText(labels);
    if (retryFinder != null && retryFinder.evaluate().isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
            '[E2E] tapContextMenuItem: found ${labels.join(" | ")} via submenu #$i');
      }
      await tester.tap(retryFinder.first, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      return;
    }
  }

  // All strategies exhausted.
  if (kDebugMode) debugPrint('[E2E] tapContextMenuItem: all strategies failed');
  fail('Context menu item not found: "$actionId"');
}

Set<String> _actionIdAliases(String actionId) {
  switch (actionId) {
    case 'new_file':
      return {'new_file', 'new_file_more'};
    default:
      return {actionId};
  }
}

/// Maps action IDs to English display label candidates used for text fallback.
List<String> _actionIdLabels(String actionId) {
  switch (actionId) {
    case 'copy':
      return const ['Copy'];
    case 'cut':
      return const ['Cut'];
    case 'paste':
      // English l10n.pasteHere — must match UI, not the word "Paste" alone.
      return const ['Paste Here', 'Paste'];
    case 'delete':
      return const ['Delete'];
    case 'rename':
      return const ['Rename'];
    case 'new_folder':
      return const ['New Folder'];
    case 'new_file':
      return const [
        'Create New File...',
        'Create New File',
        'New File...',
        'New File',
        'New file',
      ];
    case 'refresh':
      return const ['Refresh'];
    case 'properties':
      return const ['Properties'];
    default:
      return [actionId];
  }
}

Finder? _findFirstVisibleText(List<String> labels) {
  for (final label in labels) {
    final finder = find.text(label);
    if (finder.evaluate().isNotEmpty) {
      return finder;
    }
  }
  return null;
}

/// Sends a keyboard shortcut via [WidgetTester] (modifiers + main key, symmetric up).
Future<void> sendKeyboardShortcut(
  WidgetTester tester, {
  LogicalKeyboardKey key = LogicalKeyboardKey.keyC,
  bool ctrl = false,
  bool shift = false,
  bool alt = false,
}) async {
  if (kDebugMode) {
    final modifiers = [
      if (ctrl) 'Ctrl',
      if (shift) 'Shift',
      if (alt) 'Alt',
    ].join('+');
    debugPrint('[E2E] sendKeyboardShortcut: $modifiers+${key.keyLabel}');
  }

  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// Opens the background context menu (right-click on empty folder list area).
///
/// Strategy: tap directly on [ListView] inside the file list — ListView always has
/// a visible size even when empty, and its parent GestureDetector handles
/// onSecondaryTapUp (not Scaffold).
///
/// Fallback chain: ListView → SizedBox inside file list → Scaffold.
Future<void> openBackgroundContextMenu(
  WidgetTester tester, {
  Offset? tapPosition,
}) async {
  if (kDebugMode) {
    debugPrint('[E2E] openBackgroundContextMenu: right-clicking');
  }
  late final Offset position;
  if (tapPosition != null) {
    position = tapPosition;
  } else {
    // Try ListView first (list/details mode), then GridView (grid mode),
    // finally Scaffold as last resort.
    var target = find.byType(ListView);
    if (target.evaluate().isEmpty) {
      target = find.byType(GridView);
    }
    if (target.evaluate().isEmpty) {
      // Fallback: Scaffold (top-level, always present but won't open file context menu)
      target = find.byType(Scaffold);
    }
    expect(target, findsAtLeastNWidgets(1),
        reason: 'ListView/GridView/Scaffold not found — app did not render');
    final r = tester.getRect(target.first);
    // Tap center of the widget (safe for empty list — no file rows there)
    position = Offset(r.center.dx, r.center.dy);
  }
  await tester.tapAt(position, buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

/// Dismisses any open dialog or popup by pressing Escape.
Future<void> dismissDialog(WidgetTester tester) async {
  if (kDebugMode) {
    debugPrint('[E2E] dismissDialog: pressing Escape');
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// Dismisses any open dialog or popup by tapping the Cancel button.
Future<void> tapDialogCancel(WidgetTester tester) async {
  if (kDebugMode) {
    debugPrint('[E2E] tapDialogCancel: tapping Cancel button');
  }
  // Find and tap Cancel (case-insensitive match via text contains)
  final cancelFinder = find.widgetWithText(TextButton, 'Cancel');
  expect(cancelFinder, findsOneWidget,
      reason: 'Cancel button not found in dialog');
  await tester.tap(cancelFinder);
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// Confirms a dialog by tapping the primary action button (Create, Delete, etc.).
/// Pass the button text to disambiguate when multiple TextButtons are present.
Future<void> tapDialogConfirm(WidgetTester tester, {String? buttonText}) async {
  if (kDebugMode) {
    debugPrint('[E2E] tapDialogConfirm: tapping confirm button');
  }
  final Finder confirmFinder;
  if (buttonText != null) {
    // The Delete confirmation dialog uses ElevatedButton for confirm,
    // TextButton for cancel. Use byType to find the right widget.
    if (buttonText.toLowerCase() == 'delete') {
      confirmFinder = find.widgetWithText(ElevatedButton, buttonText);
    } else {
      confirmFinder = find.widgetWithText(TextButton, buttonText);
    }
  } else {
    // Fall back to last TextButton in the dialog (usually Cancel)
    confirmFinder = find.byType(TextButton);
  }
  expect(confirmFinder, findsWidgets, reason: 'No button found in dialog');
  // Tap the last matching button (primary action is conventionally last)
  await tester.tap(confirmFinder.last);
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

/// Types text into the currently focused TextField (e.g., rename field, create dialog).
Future<void> typeIntoFocusedField(WidgetTester tester, String text) async {
  if (kDebugMode) {
    debugPrint('[E2E] typeIntoFocusedField: typing "$text"');
  }
  await tester.pump();
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
}

/// Single-tap a folder row to select it (NOT navigate into it).
/// On desktop, single tap selects; double-tap navigates.
Future<void> selectFolderRow(WidgetTester tester, String absolutePath) async {
  final finder = _resolveFileOrFolderFinder(
    absolutePath,
    gridKeyPrefix: 'folder-grid-item',
    listKeyPrefix: 'folder-item',
  );
  if (finder == null) {
    fail('selectFolderRow FAILED: no folder row found for $absolutePath');
  }
  if (kDebugMode) {
    debugPrint('[E2E] selectFolderRow: single-tapping $absolutePath');
  }
  await tester.tap(finder, warnIfMissed: false);
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
}

/// Right-click a folder row to open its context menu.
/// Works in both grid and list view modes.
Future<void> rightClickFolderRow(
    WidgetTester tester, String absolutePath) async {
  final finder = _resolveFileOrFolderFinder(
    absolutePath,
    gridKeyPrefix: 'folder-grid-item',
    listKeyPrefix: 'folder-item',
  );
  if (finder == null) {
    fail('rightClickFolderRow FAILED: no folder row found for $absolutePath');
  }
  final center = tester.getCenter(finder);
  if (kDebugMode) {
    debugPrint('[E2E] rightClickFolderRow: right-clicking $absolutePath');
  }
  await tester.tapAt(center, buttons: kSecondaryMouseButton);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

/// Asserts no folder row widget exists for [absolutePath] (grid or list).
void expectFolderRowAbsent(String absolutePath) {
  expect(
    find.byKey(ValueKey('folder-grid-item-$absolutePath')),
    findsNothing,
    reason: 'Expected no grid folder row for $absolutePath',
  );
  expect(
    find.byKey(ValueKey('folder-item-$absolutePath')),
    findsNothing,
    reason: 'Expected no list folder row for $absolutePath',
  );
}

/// Opens background context menu and taps "New folder" action.
/// This creates a folder via the folder-context-menu create dialog.
Future<void> createFolderViaContextMenu(
  WidgetTester tester,
  String folderName,
) async {
  if (kDebugMode) {
    debugPrint(
        '[E2E] createFolderViaContextMenu: opening background menu, new folder');
  }
  await openBackgroundContextMenu(tester);
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // Tap "New folder" in the context menu
  await tapContextMenuItem(tester, 'new_folder');
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // Type folder name in the dialog
  await typeIntoFocusedField(tester, folderName);
  await tester.pumpAndSettle(const Duration(milliseconds: 500));

  // Confirm
  await tapDialogConfirm(tester, buttonText: 'Create');
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

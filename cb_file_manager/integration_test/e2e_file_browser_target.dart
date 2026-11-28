import 'package:cb_file_manager/ui/widgets/file_drag_drop_item.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'e2e_wait.dart';

/// The file browser paints text below a separate pointer interaction layer.
/// Target the actual row by filesystem identity, not the decorative label.
Finder fileBrowserItemForE2EPath(String path) => find.byWidgetPredicate(
  (widget) => widget is FileDragDropItem && widget.path == path,
  description: 'interactive file browser item for $path',
);

/// Click a real, visible row and verify the browser accepted the selection.
/// Preserve the viewport identity for later scroll gestures after recycling.
Future<Finder> selectE2EFileBrowserItem(
  WidgetTester tester,
  String path,
) async {
  final row = fileBrowserItemForE2EPath(path);
  expect(row, findsOneWidget, reason: 'the sandbox file must have one row');
  final viewport = scrollableForE2EItem(row);

  // Center the row rather than aligning it under a pinned details header.
  await Scrollable.ensureVisible(tester.element(row), alignment: .5);
  await settleE2EUi(tester);
  expect(
    row.hitTestable(),
    findsOneWidget,
    reason: 'the file row must accept pointer input',
  );
  await tester.tap(row.hitTestable());

  expect(
    await waitForE2ECondition(tester, () {
      final matches = row.evaluate().toList();
      return matches.length == 1 &&
          (matches.single.widget as FileDragDropItem).selectedPaths.contains(
            path,
          );
    }),
    isTrue,
    reason: 'clicking the row must actually select the sandbox file',
  );
  await settleE2EUi(tester);
  return viewport;
}

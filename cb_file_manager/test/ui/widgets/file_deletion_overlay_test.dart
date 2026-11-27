import 'dart:async';

import 'package:cb_file_manager/services/pending_file_deletions.dart';
import 'package:cb_file_manager/ui/widgets/selection_geometry_item.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final grid in [false, true]) {
    for (final failure in [false, true]) {
      testWidgets(
        'pending overlay in ${grid ? 'grid' : 'list'}, failure=$failure',
        (tester) async {
          var taps = 0;
          Widget item(String path) => SelectionGeometryItem(
            path: path,
            controller: null,
            child: SizedBox(
              height: 48,
              child: TextButton(onPressed: () => taps++, child: Text(path)),
            ),
          );
          final children = [item('pending.tmp'), item('other.tmp')];
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: grid
                    ? GridView.count(crossAxisCount: 2, children: children)
                    : ListView(children: children),
              ),
            ),
          );
          final work = Completer<void>();
          final task = PendingFileDeletions.instance.track([
            'pending.tmp',
          ], () => work.future);
          final result = failure ? expectLater(task, throwsStateError) : task;
          await tester.pump();
          expect(
            find.byKey(const ValueKey('deleting-pending.tmp')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('deleting-other.tmp')),
            findsNothing,
          );
          final sweep = find.byKey(const ValueKey('delete-sweep-paint'));
          expect(sweep, findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          final painter = tester.widget<CustomPaint>(sweep).painter;
          await tester.pump(const Duration(milliseconds: 200));
          // Animation repaints directly without rebuilding item/thumbnail UI.
          expect(tester.widget<CustomPaint>(sweep).painter, same(painter));
          await tester.tap(find.text('pending.tmp'), warnIfMissed: false);
          expect(taps, 0);
          await tester.tap(find.text('other.tmp'));
          expect(taps, 1);
          if (failure) {
            work.completeError(StateError('delete failed'));
          } else {
            work.complete();
          }
          await result;
          await tester.pump();
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(sweep, findsNothing);
          expect(find.text('pending.tmp'), findsOneWidget);
          await tester.tap(find.text('pending.tmp'));
          expect(taps, 2);
        },
      );
    }
  }

  test('overlapping batches keep a path pending until both finish', () async {
    final pending = PendingFileDeletions();
    final first = Completer<void>();
    final second = Completer<void>();
    final a = pending.track(['file', 'file'], () => first.future);
    final b = pending.track(['file'], () => second.future);
    expect(pending.contains('file'), isTrue);
    first.complete();
    await a;
    expect(pending.contains('file'), isTrue);
    second.complete();
    await b;
    expect(pending.contains('file'), isFalse);
    pending.dispose();
  });
}

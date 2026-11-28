import 'dart:async';

import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'pull-to-refresh keeps the gesture, showing text instead of a spinner',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CbRefreshIndicator(
              onRefresh: () {
                calls++;
                return pending.future;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [Text('Files')],
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(calls, 1);
      expect(find.byType(CbLoadingText), findsOneWidget);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CbLoadingText), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('places a toast action below the message row', (tester) async {
    const message = 'Access denied while deleting the selected folder.';
    const actionLabel = 'Retry with administrator access';

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                AppToast.show(
                  context,
                  message,
                  actionLabel: actionLabel,
                  onAction: () {},
                  duration: const Duration(minutes: 1),
                );
              },
              child: const Text('Show toast'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show toast'));
    await tester.pumpAndSettle();

    final messageRect = tester.getRect(find.text(message));
    final actionRect = tester.getRect(find.text(actionLabel));

    expect(actionRect.top, greaterThan(messageRect.bottom));

    await tester.tap(find.text(actionLabel));
    await tester.pump();
  });
}

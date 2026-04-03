import 'package:cb_file_manager/ui/widgets/chips_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('submits pending text when the field is submitted',
      (tester) async {
    String? submittedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {},
                  behavior: HitTestBehavior.opaque,
                ),
              ),
              const Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: Colors.white),
                ),
              ),
              Center(
                child: SizedBox(
                  width: 320,
                  child: ChipsInput<String>(
                    values: const <String>[],
                    onChanged: (_) {},
                    onSubmitted: (value) => submittedValue = value,
                    chipBuilder: (context, value) => Chip(
                      label: Text(value),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'urgent');
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(submittedValue, equals('urgent'));
  });
}

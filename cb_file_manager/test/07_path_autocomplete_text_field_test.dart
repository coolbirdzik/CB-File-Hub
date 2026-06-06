import 'package:cb_file_manager/ui/tab_manager/components/path_autocomplete_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('07.01 shows recent paths on focus and filters on typing',
      (tester) async {
    final controller = TextEditingController();
    String? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: PathAutocompleteTextField(
              controller: controller,
              onSubmitted: (v) => submitted = v,
              recentPathsLoader: () async => <String>[
                '/recent/one',
                '/recent/two',
              ],
              decoration: const InputDecoration(hintText: 'Path'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.text('/recent/one'), findsOneWidget);
    expect(find.text('/recent/two'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'two');
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('/recent/one'), findsNothing);
    expect(find.text('/recent/two'), findsOneWidget);

    await tester.tap(find.text('/recent/two'));
    await tester.pumpAndSettle();

    expect(controller.text, equals('/recent/two'));
    expect(submitted, isNull);

    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(submitted, equals('/recent/two'));
  });
}

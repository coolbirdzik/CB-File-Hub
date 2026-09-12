import 'package:cb_file_manager/ui/components/common/search_text_field.dart';
import 'package:cb_file_manager/helpers/core/search_request_guard.dart';
import 'package:cb_file_manager/helpers/core/search_query.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'tag parsing preserves spaces and deduplicates desktop/mobile queries',
    () {
      expect(SearchQuery.tags(' #summer trip #family #summer trip '), [
        'summer trip',
        'family',
      ]);
      expect(SearchQuery.tags(' # '), isEmpty);
    },
  );

  test(
    'removed folders exclude descendants but retain similarly named folders',
    () {
      expect(
        SearchQuery.isRemovedPath('C:/media/trip/a.mp4', ['C:/media/trip']),
        isTrue,
      );
      expect(
        SearchQuery.isRemovedPath('C:/media/trip-2/a.mp4', ['C:/media/trip']),
        isFalse,
      );
    },
  );

  test('query listeners ignore selection and wait for IME commit', () {
    final controller = SearchTextController(text: 'video');
    addTearDown(controller.dispose);
    final queries = <String>[];
    controller.addQueryListener(() => queries.add(controller.text));
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    expect(queries, isEmpty);
    controller.value = const TextEditingValue(
      text: 'phim',
      composing: TextRange(start: 0, end: 4),
    );
    expect(queries, isEmpty);
    controller.value = controller.value.copyWith(composing: TextRange.empty);
    expect(queries, ['phim']);
    controller.clear();
    controller.clear();
    expect(queries, ['phim', '']);
  });

  testWidgets(
    'double click selects text without searching; Enter submits once',
    (tester) async {
      final controller = SearchTextController(text: 'alpha beta');
      addTearDown(controller.dispose);
      final queries = <String>[];
      final submissions = <String>[];
      controller.addQueryListener(() => queries.add(controller.text));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchTextField(
              controller: controller,
              onSubmitted: submissions.add,
            ),
          ),
        ),
      );
      await tester.tapAt(
        tester.getTopLeft(find.byType(TextField)) + const Offset(20, 20),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(
        tester.getTopLeft(find.byType(TextField)) + const Offset(20, 20),
      );
      await tester.pump();
      expect(controller.selection.isCollapsed, isFalse);
      expect(queries, isEmpty);
      expect(submissions, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(submissions, ['alpha beta']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('edits, refresh and disposal invalidate outstanding search results', () {
    final requests = SearchRequestGuard();
    final first = requests.begin();
    requests.invalidate();
    expect(requests.isCurrent(first), isFalse);
    final second = requests.begin();
    final third = requests.begin();
    expect(requests.isCurrent(second), isFalse);
    expect(requests.isCurrent(third), isTrue);
    requests.dispose();
    expect(requests.isCurrent(third), isFalse);
  });
}

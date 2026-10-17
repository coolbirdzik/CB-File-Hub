import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/widgets/tag_management_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('recent tags block renders and selects a recent tag', (
    tester,
  ) async {
    String? selectedTag;
    var recentTags = ['urgent', 'work'];
    var loads = 0;
    var refreshVersion = 0;
    late StateSetter update;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('vi')],
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return RecentTagsWidget(
                refreshVersion: refreshVersion,
                loadRecentTags: (_) async {
                  loads++;
                  return List.of(recentTags);
                },
                onTagSelected: (tag) {
                  selectedTag = tag;
                  setState(() => recentTags = [tag, 'urgent']);
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent Tags'), findsOneWidget);
    expect(find.text('urgent'), findsOneWidget);
    expect(find.text('work'), findsOneWidget);

    final workPosition = tester.getTopLeft(find.text('work'));
    await tester.tap(find.text('work'));
    await tester.pumpAndSettle();
    expect(selectedTag, 'work');
    expect(loads, 1);
    expect(tester.widget<AnimatedTagList>(find.byType(AnimatedTagList)).tags, [
      'urgent',
      'work',
    ]);
    expect(tester.getTopLeft(find.text('work')), workPosition);

    update(() => refreshVersion++);
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(tester.widget<AnimatedTagList>(find.byType(AnimatedTagList)).tags, [
      'work',
      'urgent',
    ]);
  });
}

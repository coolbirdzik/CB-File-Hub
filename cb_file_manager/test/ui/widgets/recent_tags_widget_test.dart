import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/widgets/tag_management_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('recent tags block renders and selects a recent tag',
      (tester) async {
    String? selectedTag;

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
          body: RecentTagsWidget(
            loadRecentTags: (_) async => const ['urgent', 'work'],
            onTagSelected: (tag) => selectedTag = tag,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent Tags'), findsOneWidget);
    expect(find.text('urgent'), findsOneWidget);
    expect(find.text('work'), findsOneWidget);

    await tester.tap(find.text('urgent'));
    expect(selectedTag, 'urgent');
  });
}

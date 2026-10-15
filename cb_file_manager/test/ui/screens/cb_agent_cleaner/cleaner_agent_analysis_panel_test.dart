import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_agent_review.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_agent_analysis_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'analysis remains readable in a narrow ${dark ? 'dark' : 'light'} pane with Vietnamese labels',
      (tester) async {
        final node = DiskTreeNode(
          name: 'very-long-file-name-cache.bin',
          fullPath:
              r'C:\Users\Tester\AppData\Local\Google\Chrome\User Data\Default\Cache\very-long-file-name-cache.bin',
        );
        const analysis = CleanerItemAnalysis(
          decision: CleanerItemDecision.review,
          reason:
              'Cần đóng ứng dụng và kiểm tra dữ liệu đang dùng trước khi quyết định xóa mục này. Không chọn chỉ vì file chiếm nhiều dung lượng.',
        );
        DiskTreeNode? revealed;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            locale: const Locale('vi'),
            supportedLocales: const [Locale('en'), Locale('vi')],
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 260,
                  height: 260,
                  child: CleanerAgentAnalysisPanel(
                    inspectingNode: null,
                    focusedPath: node.fullPath,
                    items: [
                      CleanerReviewedItem(node: node, analysis: analysis),
                    ],
                    onReveal: (value) => revealed = value,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Phân tích của CB Agent'), findsOneWidget);
        expect(find.text('Cần xem lại'), findsOneWidget);
        expect(find.text(analysis.reason), findsOneWidget);
        await tester.tap(
          find.byKey(ValueKey('cleaner-agent-analysis-${node.fullPath}')),
        );
        expect(revealed, same(node));
        expect(node.isSelectedForDeletion, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

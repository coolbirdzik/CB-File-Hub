import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_agent_review.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_agent_analysis_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'completed review shows actionable summary and reveals its target',
    (tester) async {
      final node = DiskTreeNode(
        name: 'cache.tmp',
        fullPath: r'C:\Temp\cache.tmp',
        isFile: true,
        sizeBytes: 50 * 1024 * 1024,
        junkCategoryId: 'windows_temp',
      );
      final review = CleanerFullReview(
        DiskTreeNode(name: 'C:', fullPath: r'C:\', children: [node]),
      );
      await review.prepareGroups(checkActive: () {});
      final group = review.groups.single;
      review.markGroupReviewed(
        group,
        const CleanerItemAnalysis(
          decision: CleanerItemDecision.clean,
          reason: 'File tạm; kiểm tra trước khi dọn.',
          fromScan: true,
        ),
      );
      DiskTreeNode? revealed;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi')],
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
                height: 450,
                child: CleanerAgentAnalysisPanel(
                  inspectingNode: null,
                  focusedPath: null,
                  review: review,
                  items: [
                    CleanerReviewedItem(node: node, analysis: group.analysis!),
                  ],
                  onReveal: (value) => revealed = value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tóm tắt những phần cần chú ý'), findsOneWidget);
      expect(
        find.text('Có thể cân nhắc dọn: 1 nhóm · 50.0 MB'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ValueKey('cleaner-summary-${group.id}')));
      expect(revealed, same(node));
      expect(node.isSelectedForDeletion, isFalse);
      revealed = null;
      final detail = find.byKey(
        ValueKey('cleaner-agent-analysis-${node.fullPath}'),
      );
      await tester.scrollUntilVisible(detail, 200);
      await tester.tap(detail);
      expect(revealed, same(node));
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'analysis remains readable in a narrow ${dark ? 'dark' : 'light'} pane with Vietnamese labels',
      (tester) async {
        final node = DiskTreeNode(
          name: 'very-long-file-name-cache.bin',
          fullPath:
              r'C:\Users\Tester\AppData\Local\Google\Chrome\User Data\Default\Cache\very-long-file-name-cache.bin',
        );
        final analysis = CleanerItemAnalysis(
          decision: CleanerItemDecision.review,
          reason:
              'Cần đóng ứng dụng và kiểm tra dữ liệu đang dùng trước khi quyết định xóa mục này. Không chọn chỉ vì file chiếm nhiều dung lượng.',
          fromScan: dark,
        );
        DiskTreeNode? revealed;
        final review = CleanerFullReview(
          DiskTreeNode(
            name: 'C:',
            fullPath: r'C:\',
            children: [
              node,
              DiskTreeNode(name: 'next', fullPath: r'C:\next'),
            ],
          ),
        )..markReviewed(node);
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
                    review: review,
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
        expect(find.text('1 / 2'), findsOneWidget);
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          0.5,
        );
        expect(find.text('Cần xem lại'), findsOneWidget);
        expect(
          find.text(dark ? 'Theo dữ liệu quét' : 'Gợi ý từ AI'),
          findsOneWidget,
        );
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

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_theme_builder.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_agent_review.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_review_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<CleanerFullReview> fixture() async {
  const gb = 1024 * 1024 * 1024;
  final nodes = [
    DiskTreeNode(
      name: 'session.tmp',
      fullPath: r'C:\Users\Linh\AppData\Local\Temp\session.tmp',
      isFile: true,
      sizeBytes: 2 * gb,
      junkCategoryId: 'windows_temp',
    ),
    DiskTreeNode(
      name: 'cache.bin',
      fullPath: r'C:\Users\Linh\AppData\Local\Browser\Cache\cache.bin',
      isFile: true,
      sizeBytes: gb,
      junkCategoryId: 'browser_cache',
    ),
    DiskTreeNode(
      name: 'Holiday.mp4',
      fullPath: r'C:\Users\Linh\Videos\Holiday.mp4',
      isFile: true,
      sizeBytes: 12 * gb,
    ),
    DiskTreeNode(
      name: 'Archive.zip',
      fullPath: r'C:\Users\Linh\Downloads\Archive.zip',
      isFile: true,
      sizeBytes: 6 * gb,
    ),
    DiskTreeNode(
      name: 'pagefile.sys',
      fullPath: r'C:\pagefile.sys',
      isFile: true,
      sizeBytes: 4 * gb,
    ),
  ];
  final root = DiskTreeNode(
    name: 'C:',
    fullPath: r'C:\',
    sizeBytes: 27 * gb,
    children: [
      ...nodes,
      DiskTreeNode(
        name: 'Projects',
        fullPath: r'C:\Projects',
        sizeBytes: 2 * gb,
        children: [
          DiskTreeNode(
            name: 'Small files',
            fullPath: '',
            isFile: true,
            sizeBytes: 2 * gb,
            aggregatedItemCount: 23500,
          ),
        ],
      ),
    ],
  );
  final review = CleanerFullReview(root);
  await review.prepareGroups(checkActive: () {});
  for (final group in review.groups) {
    final decision = group.canClean
        ? CleanerItemDecision.clean
        : group.cause?.verdict == 'KEEP'
        ? CleanerItemDecision.keep
        : CleanerItemDecision.review;
    review.markGroupReviewed(
      group,
      CleanerItemAnalysis(
        decision: decision,
        reason: switch (decision) {
          CleanerItemDecision.clean =>
            'Bộ nhớ đệm và file tạm. Đóng ứng dụng, kiểm tra trước khi dọn.',
          CleanerItemDecision.review =>
            'Dữ liệu cá nhân hoặc dự án. Chỉ dọn khi bạn xác nhận không còn cần.',
          CleanerItemDecision.keep =>
            'Bộ nhớ ảo của Windows. Nên giữ để hệ thống hoạt động ổn định.',
        },
        fromScan: true,
      ),
    );
  }
  return review;
}

void main() {
  for (final scenario in [
    (width: 900.0, height: 120.0, scale: 1.0),
    (width: 900.0, height: 210.0, scale: 1.5),
    (width: 1200.0, height: 310.0, scale: 2.0),
    (width: 260.0, height: 450.0, scale: 2.0),
  ]) {
    testWidgets('app theme fits short overview and scaled text: $scenario', (
      tester,
    ) async {
      final review = await fixture();
      tester.view.physicalSize = Size(scenario.width, scenario.height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      DiskTreeNode? revealed;
      await tester.pumpWidget(
        MaterialApp(
          theme: CbThemeBuilder.build(
            brightness: Brightness.light,
            accent: Colors.blue,
          ),
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scenario.scale)),
            child: child!,
          ),
          home: Scaffold(
            body: CleanerReviewOverview(
              review: review,
              onReveal: (node) => revealed = node,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('cleaner-overview-category-0')))
            .height,
        greaterThan(32),
      );
      final safe = review.groups.firstWhere(
        (g) => g.categoryId == 'windows_temp',
      );
      final revealSafe = find.byKey(ValueKey('cleaner-summary-${safe.id}'));
      await tester.ensureVisible(revealSafe);
      await tester.pumpAndSettle();
      await tester.tap(revealSafe);
      expect(revealed, same(safe.representative));
      final reviewTab = find.byKey(
        const ValueKey('cleaner-overview-category-1'),
      );
      await tester.ensureVisible(reviewTab);
      await tester.pumpAndSettle();
      await tester.tap(reviewTab);
      await tester.pumpAndSettle();
      final personal = review.groups.firstWhere((g) => g.type == 'video');
      final revealPersonal = find.byKey(
        ValueKey('cleaner-summary-${personal.id}'),
      );
      await tester.ensureVisible(revealPersonal);
      await tester.pumpAndSettle();
      await tester.tap(revealPersonal);
      expect(revealed, same(personal.representative));
      expect(
        review.groups
            .expand((g) => g.nodes)
            .any((n) => n.isSelectedForDeletion),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  }
  for (final dark in [false, true]) {
    for (final width in [260.0, 1200.0]) {
      testWidgets(
        'visual overview switches priorities and reveals exact rows at $width, dark=$dark',
        (tester) async {
          final review = await fixture();
          final preview =
              Platform.environment['CB_CLEANER_OVERVIEW_PREVIEW'] == 'true';
          if (preview) {
            await tester.runAsync(() async {
              final font = FontLoader('CleanerPreview')
                ..addFont(
                  File(
                    r'C:\Windows\Fonts\segoeui.ttf',
                  ).readAsBytes().then(ByteData.sublistView),
                );
              await font.load();
              final icons =
                  FontLoader(
                    'packages/phosphor_flutter/PhosphorLight',
                  )..addFont(
                    rootBundle.load(
                      'packages/phosphor_flutter/lib/fonts/Phosphor-Light.ttf',
                    ),
                  );
              await icons.load();
            });
          }
          tester.view.physicalSize = Size(width, width == 260 ? 450 : 310);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          DiskTreeNode? revealed;
          final theme = CbThemeBuilder.build(
            brightness: dark ? Brightness.dark : Brightness.light,
            accent: Colors.blue,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.copyWith(
                textTheme: theme.textTheme.apply(
                  fontFamily: preview ? 'CleanerPreview' : null,
                ),
              ),
              locale: const Locale('vi'),
              supportedLocales: const [Locale('vi')],
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Scaffold(
                body: RepaintBoundary(
                  key: const ValueKey('preview'),
                  child: CleanerReviewOverview(
                    review: review,
                    coverageIssueCount: 4,
                    onReveal: (node) => revealed = node,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('3.0 GB'), findsOneWidget);
          expect(find.text('18.0 GB'), findsOneWidget);
          expect(find.text('4.0 GB'), findsOneWidget);
          for (var i = 0; i < 3; i++) {
            expect(
              tester
                  .getSize(find.byKey(ValueKey('cleaner-overview-share-$i')))
                  .height,
              5,
            );
          }
          final safe = review.groups.firstWhere(
            (g) => g.categoryId == 'windows_temp',
          );
          expect(
            tester
                .widget<LinearProgressIndicator>(
                  find.byKey(
                    ValueKey('cleaner-overview-group-share-${safe.id}'),
                  ),
                )
                .value,
            closeTo(2 / 3, 0.0001),
          );
          await tester.tap(find.byKey(ValueKey('cleaner-summary-${safe.id}')));
          expect(revealed, same(safe.representative));
          expect(
            review.groups
                .expand((g) => g.nodes)
                .any((n) => n.isSelectedForDeletion),
            isFalse,
          );
          expect(tester.takeException(), isNull);

          if (preview) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('preview')),
            );
            await tester.runAsync(() async {
              final screenshot = await boundary.toImage();
              final data = await screenshot.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                'build/cleaner_overview_${width.toInt()}_${dark ? 'dark' : 'light'}.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              screenshot.dispose();
            });
          }

          await tester.tap(
            find.byKey(const ValueKey('cleaner-overview-category-1')),
          );
          await tester.pumpAndSettle();
          final personal = review.groups.firstWhere((g) => g.type == 'video');
          await tester.tap(
            find.byKey(ValueKey('cleaner-summary-${personal.id}')),
          );
          expect(revealed, same(personal.representative));
          await tester.tap(
            find.byKey(const ValueKey('cleaner-overview-category-2')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Nên giữ · Các nhóm lớn nhất'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('cleaner-overview-folders')),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('Thư mục lớn cần chú ý · Tổng thư mục'),
            findsOneWidget,
          );
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

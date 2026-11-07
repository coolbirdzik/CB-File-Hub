import 'package:cb_file_manager/bloc/cleaner_app_insights/cleaner_app_insights.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/app_storage/app_space_insights.dart';
import 'package:cb_file_manager/services/disk_cleaner/app_storage/app_space_models.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_apps_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const int _mb = 1024 * 1024;

/// The Apps page as macOS and Linux show it: fed by App storage, with the
/// platform's own manage action and no Windows wording.
void main() {
  final now = DateTime(2026, 11, 7, 12);

  AppStorageReport report() => AppSpaceInsights.toAppStorageReport(
    AppSpaceReport(
      generatedAt: now,
      entries: const [
        AppSpaceEntry(
          app: InstalledAppInfo(
            id: 'chatter',
            displayName: 'Chatter',
            source: InstalledAppSource.macApp,
            installLocation: '/Applications/Chatter.app',
          ),
          isRunning: false,
          items: [
            AppSpaceItem(
              path: '/Applications/Chatter.app',
              kind: AppSpaceKind.install,
              tier: AppSpaceTier.review,
              bytes: 300 * _mb,
            ),
            AppSpaceItem(
              path: '/Users/me/Library/Application Support/Chatter/Cache',
              kind: AppSpaceKind.cache,
              tier: AppSpaceTier.safe,
              bytes: 120 * _mb,
            ),
          ],
        ),
      ],
    ),
    usageByAppId: {
      'chatter': AppUsageEvidence(
        lastOpenedAt: now.subtract(const Duration(days: 3)),
        source: AppUsageSource.spotlight,
      ),
    },
  );

  Future<(List<InstalledAppInfo>, List<AppStorageProfile>)> pump(
    WidgetTester tester, {
    required bool canUninstall,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cubit = CleanerAppInsightsCubit(nowProvider: () => now)
      ..setReport(report());
    addTearDown(cubit.close);
    final managed = <InstalledAppInfo>[];
    final reviewed = <AppStorageProfile>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: CleanerAppsView(
            cubit: cubit,
            onManageApp: managed.add,
            manageLabel: 'Show in Finder',
            scanHint: 'Sizes come from App storage.',
            onUninstallApp: canUninstall ? (_) {} : null,
            onReviewCleanable: reviewed.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (managed, reviewed);
  }

  testWidgets('shows the platform action and App storage sizes', (
    tester,
  ) async {
    final (managed, reviewed) = await pump(tester, canUninstall: true);
    expect(find.text('Sizes come from App storage.'), findsOneWidget);
    expect(find.textContaining('Windows'), findsNothing);
    expect(find.text('Chatter'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('cleaner-app-manage-chatter')));
    expect(managed.single.id, 'chatter');
    await tester.tap(find.byKey(const ValueKey('cleaner-app-review-chatter')));
    expect(reviewed.single.app.id, 'chatter');
    expect(
      find.byKey(const ValueKey('cleaner-app-uninstall-chatter')),
      findsOneWidget,
    );
  });

  testWidgets('Linux offers no uninstall', (tester) async {
    await pump(tester, canUninstall: false);
    expect(
      find.byKey(const ValueKey('cleaner-app-uninstall-chatter')),
      findsNothing,
    );
  });
}

import 'package:cb_file_manager/bloc/cleaner_app_insights/cleaner_app_insights.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_apps_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const int _mb = 1024 * 1024;
const int _gb = 1024 * _mb;

void main() {
  final now = DateTime(2026, 8, 1, 12);

  AppStorageReport fixtureReport() {
    return AppStorageReport(
      drivePath: 'C:\\',
      generatedAt: now,
      isPartial: true,
      apps: <AppStorageProfile>[
        AppStorageProfile(
          app: const InstalledAppInfo(
            id: 'alpha',
            displayName: 'Alpha Editor',
            publisher: 'Acme',
            version: '4.2',
            source: InstalledAppSource.win32,
            canManage: true,
          ),
          usage: AppUsageEvidence(
            lastOpenedAt: now.subtract(const Duration(days: 220)),
            source: AppUsageSource.userAssist,
            confidence: UsageEvidenceConfidence.medium,
          ),
          entries: const <AppStorageEntry>[
            AppStorageEntry(
              path: 'C:\\Program Files\\Alpha',
              kind: AppStorageKind.install,
              sizeBytes: 2 * _gb,
              measurementQuality: MeasurementQuality.measured,
              attributionConfidence: AttributionConfidence.confirmed,
            ),
            AppStorageEntry(
              path: 'C:\\Users\\Test\\AppData\\Local\\Alpha\\Cache',
              kind: AppStorageKind.cache,
              sizeBytes: 120 * _mb,
              measurementQuality: MeasurementQuality.measured,
              attributionConfidence: AttributionConfidence.confirmed,
              categoryId: 'app_cache',
              isCleanable: true,
            ),
          ],
        ),
        const AppStorageProfile(
          app: InstalledAppInfo(
            id: 'beta',
            displayName: 'Beta Player',
            publisher: 'Media Corp',
            source: InstalledAppSource.msix,
            estimatedSizeBytes: 600 * _mb,
          ),
        ),
      ],
      sharedOrUnattributed: const <AppStorageEntry>[
        AppStorageEntry(
          path: 'C:\\ProgramData\\Shared Tools',
          kind: AppStorageKind.shared,
          sizeBytes: 900 * _mb,
          measurementQuality: MeasurementQuality.measured,
          attributionConfidence: AttributionConfidence.shared,
        ),
      ],
    );
  }

  Future<void> pumpView(
    WidgetTester tester, {
    required CleanerAppInsightsCubit cubit,
    Locale locale = const Locale('en'),
    void Function(AppStorageEntry)? onOpenFolder,
    void Function(InstalledAppInfo)? onManageApp,
    void Function(AppStorageProfile)? onReviewCleanable,
    void Function(AppStorageProfile)? onAskAgent,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: CleanerAppsView(
            cubit: cubit,
            onOpenFolder: onOpenFolder,
            onManageApp: onManageApp,
            onReviewCleanable: onReviewCleanable,
            onAskAgent: onAskAgent,
          ),
        ),
      ),
    );
    if (cubit.state.status == CleanerAppInsightsStatus.loading) {
      await tester.pump();
    } else {
      await tester.pumpAndSettle();
    }
  }

  testWidgets('renders summary, filters, details, and safe callbacks',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = CleanerAppInsightsCubit(nowProvider: () => now)
      ..setReport(fixtureReport());
    addTearDown(cubit.close);
    AppStorageProfile? reviewed;
    InstalledAppInfo? managed;
    AppStorageProfile? asked;
    AppStorageEntry? opened;

    await pumpView(
      tester,
      cubit: cubit,
      onOpenFolder: (entry) => opened = entry,
      onManageApp: (app) => managed = app,
      onReviewCleanable: (profile) => reviewed = profile,
      onAskAgent: (profile) => asked = profile,
    );

    expect(
      find.byKey(const ValueKey<String>('cleaner-apps-summary-footprint')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cleaner-apps-summary-attention')),
      findsOneWidget,
    );
    expect(find.text('Review'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('cleaner-app-row-alpha')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cleaner-app-detail-alpha')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cleaner-apps-partial-banner')),
      findsOneWidget,
    );
    expect(find.byType(Checkbox), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('cleaner-app-manage-alpha')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('cleaner-app-review-alpha')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('cleaner-app-ask-agent-alpha')),
    );
    await tester.ensureVisible(
      find.byKey(
        const ValueKey<String>(
          'cleaner-app-open-folder-C:\\Program Files\\Alpha',
        ),
      ),
    );
    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'cleaner-app-open-folder-C:\\Program Files\\Alpha',
        ),
      ),
    );

    expect(managed?.id, 'alpha');
    expect(reviewed?.app.id, 'alpha');
    expect(asked?.app.id, 'alpha');
    expect(opened?.path, 'C:\\Program Files\\Alpha');
  });

  testWidgets('search and filters keep the visible detail selection aligned',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = CleanerAppInsightsCubit(nowProvider: () => now)
      ..setReport(fixtureReport());
    addTearDown(cubit.close);
    await pumpView(tester, cubit: cubit);

    await tester.enterText(
      find.byKey(const ValueKey<String>('cleaner-apps-search')),
      'Beta',
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey<String>('cleaner-app-row-alpha')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('cleaner-app-detail-beta')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('cleaner-apps-search')),
      '',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('cleaner-apps-filter-cleanable')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey<String>('cleaner-app-row-alpha')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cleaner-app-row-beta')),
      findsNothing,
    );
    expect(cubit.state.selectedAppId, 'alpha');
  });

  testWidgets('compact Vietnamese layout localizes visible labels',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = CleanerAppInsightsCubit(nowProvider: () => now)
      ..setReport(fixtureReport());
    addTearDown(cubit.close);
    await pumpView(
      tester,
      cubit: cubit,
      locale: const Locale('vi'),
    );

    expect(find.text('Nên xem lại'), findsOneWidget);
    expect(find.text('Nên xem'), findsWidgets);
    expect(find.text('220 ngày chưa mở'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('cleaner-apps-compact-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cleaner-app-detail-alpha')),
      findsOneWidget,
    );
  });

  testWidgets('shows localized loading and error states', (tester) async {
    final cubit = CleanerAppInsightsCubit(nowProvider: () => now)..setLoading();
    addTearDown(cubit.close);
    await pumpView(tester, cubit: cubit);

    expect(
      find.byKey(const ValueKey<String>('cleaner-apps-loading')),
      findsOneWidget,
    );

    cubit.setError('inventory unavailable');
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('cleaner-apps-error')),
      findsOneWidget,
    );
    expect(find.textContaining('inventory unavailable'), findsOneWidget);
  });
}

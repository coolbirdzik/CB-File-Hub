import 'package:cb_file_manager/bloc/cleaner_app_insights/cleaner_app_insights.dart';
import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:flutter_test/flutter_test.dart';

const int _mb = 1024 * 1024;
const int _gb = 1024 * _mb;

void main() {
  final now = DateTime(2026, 8, 1, 12);

  AppStorageProfile profile({
    required String id,
    required String name,
    required int sizeBytes,
    DateTime? lastOpenedAt,
    bool cleanable = false,
    String? publisher,
    String? installLocation,
  }) {
    return AppStorageProfile(
      app: InstalledAppInfo(
        id: id,
        displayName: name,
        publisher: publisher,
        source: InstalledAppSource.win32,
        installLocation: installLocation,
      ),
      usage: AppUsageEvidence(
        lastOpenedAt: lastOpenedAt,
        source: lastOpenedAt == null ? null : AppUsageSource.userAssist,
        confidence: lastOpenedAt == null
            ? null
            : UsageEvidenceConfidence.medium,
      ),
      entries: <AppStorageEntry>[
        AppStorageEntry(
          path: installLocation ?? 'C:\\Apps\\$name',
          kind: cleanable ? AppStorageKind.cache : AppStorageKind.install,
          sizeBytes: sizeBytes,
          measurementQuality: MeasurementQuality.measured,
          attributionConfidence: AttributionConfidence.confirmed,
          isCleanable: cleanable,
        ),
      ],
    );
  }

  AppStorageReport report() => AppStorageReport(
    drivePath: 'C:\\',
    generatedAt: now,
    apps: <AppStorageProfile>[
      profile(
        id: 'alpha',
        name: 'Alpha Editor',
        publisher: 'Acme',
        sizeBytes: 2 * _gb,
        lastOpenedAt: now.subtract(const Duration(days: 240)),
      ),
      profile(
        id: 'beta',
        name: 'Beta Player',
        publisher: 'Media Corp',
        installLocation: 'C:\\Special\\Beta',
        sizeBytes: 600 * _mb,
      ),
      profile(
        id: 'gamma',
        name: 'Gamma Browser',
        sizeBytes: 800 * _mb,
        cleanable: true,
        lastOpenedAt: now.subtract(const Duration(days: 10)),
      ),
    ],
  );

  test('defaults to review-first with 1 GB and 180 day thresholds', () {
    final cubit = CleanerAppInsightsCubit(nowProvider: () => now);
    addTearDown(cubit.close);

    cubit.setReport(report());

    expect(cubit.state.largeThresholdBytes, _gb);
    expect(cubit.state.staleThresholdDays, 180);
    expect(cubit.state.sort, CleanerAppSort.attentionDescending);
    expect(cubit.state.visibleApps.map((profile) => profile.app.id), <String>[
      'alpha',
      'gamma',
      'beta',
    ]);
    expect(cubit.state.selectedAppId, 'alpha');
    expect(cubit.state.largeAppCount, 1);
    expect(cubit.state.staleAppCount, 1);
    expect(cubit.state.attentionAppCount, 1);
    expect(cubit.state.attentionBytes, 2 * _gb);
  });

  test(
    'filters large, stale, and cleanable without treating unknown as stale',
    () {
      final cubit = CleanerAppInsightsCubit(nowProvider: () => now);
      addTearDown(cubit.close);
      cubit.setReport(report());

      cubit.setFilter(CleanerAppFilter.large);
      expect(cubit.state.visibleApps.map((profile) => profile.app.id), <String>[
        'alpha',
      ]);

      cubit.setFilter(CleanerAppFilter.stale);
      expect(cubit.state.visibleApps.map((profile) => profile.app.id), <String>[
        'alpha',
      ]);
      expect(
        cubit.state.visibleApps.any((profile) => profile.app.id == 'beta'),
        isFalse,
      );

      cubit.setFilter(CleanerAppFilter.attention);
      expect(cubit.state.visibleApps.map((profile) => profile.app.id), <String>[
        'alpha',
      ]);

      cubit.setFilter(CleanerAppFilter.cleanable);
      expect(cubit.state.visibleApps.map((profile) => profile.app.id), <String>[
        'gamma',
      ]);
    },
  );

  test('searches metadata and paths and keeps selection visible', () {
    final cubit = CleanerAppInsightsCubit(nowProvider: () => now);
    addTearDown(cubit.close);
    cubit.setReport(report());
    cubit.selectApp('gamma');

    cubit.setSearchQuery('special\\beta');

    expect(cubit.state.visibleApps.map((profile) => profile.app.id), <String>[
      'beta',
    ]);
    expect(cubit.state.selectedAppId, 'beta');

    cubit.setSearchQuery('missing');
    expect(cubit.state.visibleApps, isEmpty);
    expect(cubit.state.selectedAppId, isNull);
  });

  test('threshold presets update summary and filtered results', () {
    final cubit = CleanerAppInsightsCubit(nowProvider: () => now);
    addTearDown(cubit.close);
    cubit.setReport(report());
    cubit.setLargeThresholdBytes(500 * _mb);
    cubit.setStaleThresholdDays(365);

    expect(cubit.state.largeAppCount, 3);
    expect(cubit.state.staleAppCount, 0);

    cubit.setSort(CleanerAppSort.lastOpenedOldest);
    expect(cubit.state.visibleApps.map((profile) => profile.app.id), <String>[
      'alpha',
      'gamma',
      'beta',
    ]);
  });

  test('exposes loading and failure states for screen-owned lifecycle', () {
    final cubit = CleanerAppInsightsCubit(nowProvider: () => now);
    addTearDown(cubit.close);

    cubit.setLoading();
    expect(cubit.state.status, CleanerAppInsightsStatus.loading);

    cubit.setError('inventory unavailable');
    expect(cubit.state.status, CleanerAppInsightsStatus.failure);
    expect(cubit.state.errorMessage, 'inventory unavailable');

    cubit.clear();
    expect(cubit.state.status, CleanerAppInsightsStatus.idle);
    expect(cubit.state.report, isNull);
  });
}

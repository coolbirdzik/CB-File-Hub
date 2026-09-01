import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tabId = 'app-insights-test-tab';
  final service = DiskCleanerService.instance;

  tearDown(() {
    service.clearCleanerScanContext(tabId);
  });

  AppStorageReport buildReport() {
    return AppStorageReport(
      drivePath: r'C:\',
      generatedAt: DateTime.utc(2026, 8, 1),
      apps: [
        AppStorageProfile(
          app: const InstalledAppInfo(
            id: 'win32:large-app',
            displayName: 'Large App',
            publisher: 'Example Publisher',
            version: '9.8.7',
            source: InstalledAppSource.win32,
          ),
          usage: AppUsageEvidence(
            lastOpenedAt: DateTime.utc(2025, 1, 1),
            source: AppUsageSource.userAssist,
            confidence: UsageEvidenceConfidence.high,
          ),
          entries: const [
            AppStorageEntry(
              path: r'C:\Program Files\Large App',
              kind: AppStorageKind.install,
              sizeBytes: 2 * 1024 * 1024 * 1024,
              measurementQuality: MeasurementQuality.measured,
              attributionConfidence: AttributionConfidence.confirmed,
            ),
          ],
        ),
      ],
    );
  }

  test('App Insights tool requires explicit sharing from the Apps view',
      () async {
    service.publishCleanerScanContext(
      ownerTabId: tabId,
      root: DiskTreeNode(name: r'C:\', fullPath: r'C:\'),
      appStorageReport: buildReport(),
    );

    final result = await ToolExecutor(ownerTabId: tabId).execute(
      const ToolCall(name: 'get_current_app_storage', arguments: {}),
    );

    expect(result.success, isTrue);
    expect(result.output, contains('has not been shared'));
    expect(result.output, isNot(contains('Large App')));
  });

  test('App Insights tool redacts paths unless the selected app is requested',
      () async {
    service.publishCleanerScanContext(
      ownerTabId: tabId,
      root: DiskTreeNode(name: r'C:\', fullPath: r'C:\'),
      appStorageReport: buildReport(),
      selectedAppId: 'win32:large-app',
      appInsightsSharedWithAgent: true,
    );
    final executor = ToolExecutor(ownerTabId: tabId);

    final summary = await executor.execute(
      const ToolCall(
        name: 'get_current_app_storage',
        arguments: {'filter': 'large', 'include_paths': true},
      ),
    );
    expect(summary.output, contains('Large App'));
    expect(summary.output, isNot(contains(r'C:\Program Files\Large App')));
    expect(summary.output, contains('days ago'));
    expect(summary.output, isNot(contains('2025-01-01')));
    expect(summary.output, isNot(contains('Example Publisher')));
    expect(summary.output, isNot(contains('9.8.7')));

    final detail = await executor.execute(
      const ToolCall(
        name: 'get_current_app_storage',
        arguments: {
          'app_id': 'win32:large-app',
          'include_paths': true,
        },
      ),
    );
    expect(detail.output, contains(r'C:\Program Files\Large App'));
  });
}

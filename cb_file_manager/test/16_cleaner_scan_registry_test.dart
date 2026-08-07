import 'package:cb_file_manager/services/ai/cleaner_scan_registry.dart';
import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ScanReport report() => ScanReport(
        drivesScanned: const ['C:\\'],
        itemsByCategory: const {},
        warnings: const [],
        scannedAt: DateTime(2026),
      );

  group('CleanerScanRegistry', () {
    test('recognizes model-generated scan ID placeholders', () {
      expect(
        CleanerScanRegistry.isPlaceholder('SCANNED_ID_PLACEHOLDER'),
        isTrue,
      );
      expect(CleanerScanRegistry.isPlaceholder('sc_xxx'), isTrue);
      expect(CleanerScanRegistry.isPlaceholder(''), isTrue);
      expect(CleanerScanRegistry.isPlaceholder('sc_mdk92'), isFalse);
    });

    test('resolves a placeholder to the latest scan in the same tab', () {
      final registry = CleanerScanRegistry();
      registry.store('sc_tab_a_old', report(), ownerTabId: 'tab-a');
      registry.store('sc_tab_b', report(), ownerTabId: 'tab-b');
      registry.store('sc_tab_a_latest', report(), ownerTabId: 'tab-a');

      expect(
        registry.resolveId(
          'SCANNED_ID_PLACEHOLDER',
          ownerTabId: 'tab-a',
        ),
        'sc_tab_a_latest',
      );
      expect(
        registry.resolveId('sc_tab_b', ownerTabId: 'tab-a'),
        isNull,
      );
      expect(
        registry.resolveId('sc_expired', ownerTabId: 'tab-a'),
        isNull,
      );
    });

    test('evicts the oldest scan when capacity is reached', () {
      final registry = CleanerScanRegistry(maxEntries: 2);
      registry.store('sc_one', report(), ownerTabId: 'tab-a');
      registry.store('sc_two', report(), ownerTabId: 'tab-a');
      registry.store('sc_three', report(), ownerTabId: 'tab-a');

      expect(registry['sc_one'], isNull);
      expect(registry['sc_two'], isNotNull);
      expect(registry['sc_three'], isNotNull);
    });
  });

  test('cleaner call expands the generic cache category alias', () {
    final executor = ToolExecutor(ownerTabId: 'tab-a');

    final normalized = executor.normalizeCall(const ToolCall(
      name: 'clean_disk_junk',
      arguments: {
        'categories': ['dev_cache', 'cache'],
      },
    ));

    expect(normalized.arguments['categories'], [
      'dev_cache',
      'browser_cache',
      'thumbnail_cache',
      'app_cache',
    ]);
  });
}

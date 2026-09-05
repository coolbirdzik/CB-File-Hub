import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cb_agent_cleaner_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'setup uses the cached result without scanning and refresh scans explicitly',
    () async {
      final root = DiskTreeNode(name: r'C:\', fullPath: r'C:\');
      final cached = FullDiskScanResult(root: root, duration: Duration.zero);
      var scanCalls = 0;
      final coordinator = CleanerScanCoordinator(
        cachedResultFor: (_) => cached,
        startFullDiskScan: (drivePath) async {
          scanCalls++;
          return FullDiskScanHandle.completed(
            drivePath: drivePath,
            result: cached,
          );
        },
      );

      expect(coordinator.cachedSetupResult(r'C:\'), same(cached));
      expect(scanCalls, 0);

      final refreshHandle = await coordinator.forceRefresh(r'C:\');
      expect(scanCalls, 1);
      expect(await refreshHandle.future, same(cached));
    },
  );

  test('setup does not reuse a cached result for a distinct drive', () async {
    final cachedRoot = DiskTreeNode(name: r'C:\', fullPath: r'C:\');
    final cached = FullDiskScanResult(
      root: cachedRoot,
      duration: Duration.zero,
    );
    final refreshedRoot = DiskTreeNode(name: r'D:\', fullPath: r'D:\');
    final refreshed = FullDiskScanResult(
      root: refreshedRoot,
      duration: Duration.zero,
    );
    var scanCalls = 0;
    final coordinator = CleanerScanCoordinator(
      cachedResultFor: (drivePath) => drivePath == r'C:\' ? cached : null,
      startFullDiskScan: (drivePath) async {
        scanCalls++;
        return FullDiskScanHandle.completed(
          drivePath: drivePath,
          result: refreshed,
        );
      },
    );

    expect(coordinator.cachedSetupResult(r'D:\'), isNull);
    expect(scanCalls, 0);

    final refreshHandle = await coordinator.forceRefresh(r'D:\');
    expect(scanCalls, 1);
    expect(await refreshHandle.future, same(refreshed));
  });

  test(
    'old-large evidence presentation keeps folders and files in sections',
    () {
      final sections = splitOldLargeEvidence([
        const FullDiskScanInsight(
          name: 'small-file.bin',
          path: r'C:\small-file.bin',
          isFile: true,
          sizeBytes: 200,
        ),
        const FullDiskScanInsight(
          name: 'large-folder',
          path: r'C:\large-folder',
          isFile: false,
          sizeBytes: 900,
        ),
        const FullDiskScanInsight(
          name: 'large-file.bin',
          path: r'C:\large-file.bin',
          isFile: true,
          sizeBytes: 800,
        ),
        const FullDiskScanInsight(
          name: 'small-folder',
          path: r'C:\small-folder',
          isFile: false,
          sizeBytes: 300,
        ),
      ]);

      expect(sections.totalCount, 4);
      expect(sections.folders.map((item) => item.name), <String>[
        'large-folder',
        'small-folder',
      ]);
      expect(sections.files.map((item) => item.name), <String>[
        'large-file.bin',
        'small-file.bin',
      ]);
      expect(sections.folders.every((item) => !item.isFile), isTrue);
      expect(sections.files.every((item) => item.isFile), isTrue);
    },
  );
}

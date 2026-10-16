import 'package:cb_file_manager/services/ai/agent_tool_catalog.dart';
import 'package:cb_file_manager/services/ai/disk_cleaner_skill.dart';
import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_space_insights.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:flutter_test/flutter_test.dart';

const _gb = 1024 * 1024 * 1024;

DiskTreeNode _file(String path, int bytes) => DiskTreeNode(
  name: path.substring(path.lastIndexOf(r'\') + 1),
  fullPath: path,
  isFile: true,
  sizeBytes: bytes,
  fileCount: 1,
);

DiskTreeNode _folder(String path, List<DiskTreeNode> children) {
  final node = DiskTreeNode(
    name: path.substring(path.lastIndexOf(r'\') + 1),
    fullPath: path,
    sizeBytes: children.fold(0, (sum, child) => sum + child.sizeBytes),
    fileCount: children.fold(0, (sum, child) => sum + child.fileCount),
    children: children,
  );
  node.sortBySize();
  return node;
}

/// A drive where most space is a WSL disk, a game and old ISOs.
DiskTreeNode _sampleDrive() {
  final wsl = _file(
    r'C:\Users\Tester\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu_79rhkp1fndgsc\LocalState\ext4.vhdx',
    60 * _gb,
  );
  final packages = _folder(r'C:\Users\Tester\AppData\Local\Packages', [
    _folder(
      r'C:\Users\Tester\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu_79rhkp1fndgsc',
      [
        _folder(
          r'C:\Users\Tester\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu_79rhkp1fndgsc\LocalState',
          [wsl],
        ),
      ],
    ),
  ]);
  final downloads = _folder(r'C:\Users\Tester\Downloads', [
    _file(r'C:\Users\Tester\Downloads\win11.iso', 6 * _gb),
    _file(r'C:\Users\Tester\Downloads\ubuntu.iso', 5 * _gb),
    _file(r'C:\Users\Tester\Downloads\movie.mkv', 4 * _gb),
  ]);
  final user = _folder(r'C:\Users\Tester', [
    _folder(r'C:\Users\Tester\AppData', [
      _folder(r'C:\Users\Tester\AppData\Local', [packages]),
    ]),
    downloads,
  ]);
  final steam = _folder(r'C:\Program Files (x86)\Steam\steamapps\common', [
    _folder(r'C:\Program Files (x86)\Steam\steamapps\common\BigGame', [
      _file(
        r'C:\Program Files (x86)\Steam\steamapps\common\BigGame\data.pak',
        40 * _gb,
      ),
    ]),
  ]);
  return _folder(r'C:', [
    _folder(r'C:\Users', [user]),
    _folder(r'C:\Program Files (x86)', [
      _folder(r'C:\Program Files (x86)\Steam', [
        _folder(r'C:\Program Files (x86)\Steam\steamapps', [steam]),
      ]),
    ]),
    _file(r'C:\hiberfil.sys', 12 * _gb),
  ]);
}

void main() {
  const tabId = 'cleaner-space-insights-test-tab';
  final service = DiskCleanerService.instance;

  tearDown(() => service.clearCleanerScanContext(tabId));

  test('known causes match Windows space hogs and their descendants', () {
    expect(
      CleanerSpaceInsights.causeWithin(r'C:\hiberfil.sys', isFile: true)?.id,
      'hibernation_file',
    );
    expect(
      CleanerSpaceInsights.causeWithin(r'C:\Windows\WinSxS')?.id,
      'component_store',
    );
    expect(
      CleanerSpaceInsights.causeWithin(
        r'C:\Program Files (x86)\Steam\steamapps\common\BigGame\data.pak',
        isFile: true,
      )?.id,
      'game_library',
    );
    expect(
      CleanerSpaceInsights.causeWithin(r'D:\work\app\node_modules\react')?.id,
      'node_modules',
    );
    expect(
      CleanerSpaceInsights.causeWithin(
        r'C:\Users\Tester\OneDrive - Contoso',
      )?.verdict,
      'KEEP',
    );
    // A folder named like a file type is not a disk image.
    expect(
      CleanerSpaceInsights.causeWithin(r'C:\Projects\backup.vhdx'),
      isNull,
    );
    expect(CleanerSpaceInsights.causeWithin(r'C:\Projects\src'), isNull);
  });

  test('hotspots point at the specific owner instead of its ancestors', () {
    final hotspots = CleanerSpaceInsights.findHotspots(
      _sampleDrive(),
      threshold: 3 * _gb,
    );
    final paths = hotspots.map((h) => h.node.fullPath).toList();

    expect(paths.first, endsWith(r'LocalState\ext4.vhdx'));
    expect(paths, contains(r'C:\hiberfil.sys'));
    expect(paths, contains(r'C:\Users\Tester\Downloads\win11.iso'));
    expect(paths, isNot(contains(r'C:\Users')));
    expect(paths, isNot(contains(r'C:\Users\Tester')));
  });

  test('cause matches are attributed once, outermost first', () {
    final causes = CleanerSpaceInsights.findCauses(_sampleDrive());
    final byId = {for (final match in causes) match.cause.id: match};

    expect(causes.first.cause.id, 'wsl_disk');
    expect(byId['game_library']!.totalBytes, 40 * _gb);
    // Downloads is matched as a folder, so its ISOs are not counted again as
    // separate disk-image causes.
    expect(byId['downloads']!.totalBytes, 15 * _gb);
    expect(byId.containsKey('virtual_machine_disk'), isFalse);
  });

  test('search filters by type and size without double counting', () {
    final root = _sampleDrive();
    final images = CleanerSpaceInsights.search(root, typeGroup: 'disk_image');
    expect(images.count, 3); // two ISOs and the WSL VHDX
    expect(images.totalBytes, 71 * _gb);

    final big = CleanerSpaceInsights.search(
      root,
      extensions: {'ISO'},
      minBytes: 6 * _gb,
    );
    expect(big.matches.single.fullPath, endsWith('win11.iso'));

    final named = CleanerSpaceInsights.search(root, query: 'steam');
    expect(named.count, 1, reason: 'nested matches stay inside the parent');
  });

  test('current scan explains causes and offers investigation tools', () async {
    service.publishCleanerScanContext(
      ownerTabId: tabId,
      root: _sampleDrive(),
      coverageIssues: const [
        FullDiskScanCoverageIssue(
          path: r'C:\System Volume Information',
          reason: FullDiskScanCoverageIssueReason.inaccessible,
        ),
      ],
    );

    final output = (await ToolExecutor(ownerTabId: tabId).execute(
      const ToolCall(name: 'get_current_cleaner_scan', arguments: {}),
    )).output;

    expect(output, contains('Space hotspots'));
    expect(output, contains('WSL Linux distribution disk'));
    expect(output, contains('powercfg /h off'));
    expect(output, contains('Installed games'));
    expect(output, contains('explore_cleaner_scan'));
    expect(output, contains('search_cleaner_scan'));
    expect(output, contains(r'C:\System Volume Information'));
    expect(output, contains('Top level:'));
    expect(output.length, lessThanOrEqualTo(8100));
  });

  test('explore and search read the scan tree without touching it', () async {
    final root = _sampleDrive();
    service.publishCleanerScanContext(ownerTabId: tabId, root: root);
    final executor = ToolExecutor(ownerTabId: tabId);

    final explore = await executor.execute(
      const ToolCall(
        name: 'explore_cleaner_scan',
        arguments: {'path': r'C:\Users\Tester', 'depth': 2},
      ),
    );
    expect(explore.success, isTrue);
    expect(explore.output, contains(r'C:\Users\Tester\Downloads'));
    expect(explore.output, contains('of parent'));
    // depth 2 includes grandchildren.
    expect(explore.output, contains(r'- C:\Users\Tester\AppData\Local ['));
    expect(explore.output, contains('Largest files inside'));
    expect(explore.output, contains('ext4.vhdx'));

    final missing = await executor.execute(
      const ToolCall(
        name: 'explore_cleaner_scan',
        arguments: {'path': r'C:\Nope'},
      ),
    );
    expect(missing.success, isFalse);

    final search = await executor.execute(
      const ToolCall(name: 'search_cleaner_scan', arguments: {'type': 'video'}),
    );
    expect(search.success, isTrue);
    expect(search.output, contains('movie.mkv'));
    expect(search.output, contains('matches: 1'));

    final noFilter = await executor.execute(
      const ToolCall(name: 'search_cleaner_scan', arguments: {}),
    );
    expect(noFilter.success, isFalse);

    expect(root.hasSelectionInSubtree, isFalse);
  });

  test('cleaner screen prompt carries the cleaner skill up front', () {
    final cleaner = AgentToolCatalog.cleanerScreenContext('#cb-agent-cleaner');
    final other = AgentToolCatalog.cleanerScreenContext(r'C:\Users');
    expect(other, isEmpty);
    if (DiskCleanerSkill.isAvailable) {
      expect(cleaner, contains('get_current_cleaner_scan first'));
      expect(cleaner, contains('explore_cleaner_scan'));
    }
  });
}

import 'package:cb_file_manager/services/disk_cleaner/cleaner_space_insights.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/services/disk_cleaner/scan_target_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Agents copy long scan paths by hand; a local model dropped one "0" from
/// a 40-character PikPak cache name and could not inspect or select it.
void main() {
  const cacheName = '049AD5AE4C9996E008D7877DB31F2C665227DE8B.pptd';
  const cacheDir = r'C:\Users\me\AppData\Roaming\PikPak\Profiles\player-cache';

  DiskTreeNode dir(String path, List<DiskTreeNode> children) => DiskTreeNode(
    name: path.split(r'\').last,
    fullPath: path,
    children: children,
  );
  DiskTreeNode file(String dirPath, String name, int size) => DiskTreeNode(
    name: name,
    fullPath: '$dirPath\\$name',
    isFile: true,
    sizeBytes: size,
  );

  late DiskTreeNode root;
  setUp(() {
    root = DiskTreeNode(
      name: r'C:\',
      fullPath: r'C:\',
      children: [
        dir(r'C:\Users', [
          dir(r'C:\Users\me', [
            dir(r'C:\Users\me\AppData', [
              dir(r'C:\Users\me\AppData\Roaming', [
                dir(r'C:\Users\me\AppData\Roaming\PikPak', [
                  dir(r'C:\Users\me\AppData\Roaming\PikPak\Profiles', [
                    dir(cacheDir, [
                      file(cacheDir, cacheName, 21034004480),
                      file(cacheDir, '$cacheName.cfg', 212992),
                    ]),
                  ]),
                ]),
              ]),
            ]),
            dir(r'C:\Users\me\logs', [
              file(r'C:\Users\me\logs', 'app1.log', 10),
              file(r'C:\Users\me\logs', 'app2.log', 10),
            ]),
          ]),
        ]),
      ],
    );
  });

  test('exact paths resolve without a correction', () {
    final match = resolveScanTarget(root, '$cacheDir\\$cacheName');
    expect(match.node?.name, cacheName);
    expect(match.correctedFrom, isNull);
    expect(
      resolveScanTarget(root, r'c:/users/ME/appdata/').node?.fullPath,
      r'C:\Users\me\AppData',
    );
  });

  test('a unique near miss in a long name is corrected', () {
    const typo = '049AD5AE4C9996E08D7877DB31F2C665227DE8B.pptd';
    final match = resolveScanTarget(root, '$cacheDir\\$typo');
    expect(match.node?.fullPath, '$cacheDir\\$cacheName');
    expect(match.correctedFrom, '$cacheDir\\$typo');
    // A typo in a folder segment too.
    expect(
      resolveScanTarget(
        root,
        r'C:\Users\me\AppData\Roaming\PikPak\Profile\player-cache\' + cacheName,
      ).node?.name,
      cacheName,
    );
  });

  test('ambiguous or short names are not guessed', () {
    final ambiguous = resolveScanTarget(root, r'C:\Users\me\logs\app3.log');
    expect(ambiguous.node, isNull);
    expect(ambiguous.suggestions, [
      r'C:\Users\me\logs\app1.log',
      r'C:\Users\me\logs\app2.log',
    ]);
    expect(resolveScanTarget(root, r'C:\').node, isNull);
    expect(resolveScanTarget(root, r'D:\Users').node, isNull);
    expect(resolveScanTarget(root, r'C:\Nothing\here').suggestions, isEmpty);
  });

  test('search query also matches folders in the path', () {
    final result = CleanerSpaceInsights.search(
      root,
      query: 'PikPak',
      extensions: {'PPTD'},
    );
    expect(result.matches.map((node) => node.name), [cacheName]);
    expect(
      CleanerSpaceInsights.search(
        root,
        query: 'player-cache',
        kind: 'file',
      ).matches.length,
      2,
    );
  });
}

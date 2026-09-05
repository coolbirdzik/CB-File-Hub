import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cb_agent_cleaner_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filters evidence with folders first in the All view', () {
    const folder = FullDiskScanInsight(
      name: 'Archive',
      path: r'C:\Archive',
      isFile: false,
      sizeBytes: 500,
    );
    const file = FullDiskScanInsight(
      name: 'archive.iso',
      path: r'C:\Archive\archive.iso',
      isFile: true,
      sizeBytes: 1000,
    );

    expect(
      filterOldLargeEvidence(<FullDiskScanInsight>[
        file,
        folder,
      ], OldLargeEvidenceFilter.all),
      <FullDiskScanInsight>[folder, file],
    );
    expect(
      filterOldLargeEvidence(<FullDiskScanInsight>[
        file,
        folder,
      ], OldLargeEvidenceFilter.folders),
      <FullDiskScanInsight>[folder],
    );
    expect(
      filterOldLargeEvidence(<FullDiskScanInsight>[
        file,
        folder,
      ], OldLargeEvidenceFilter.files),
      <FullDiskScanInsight>[file],
    );
  });

  test('falls back to the deepest displayed ancestor for a compacted file', () {
    final archive = DiskTreeNode(
      name: 'Archive',
      fullPath: r'C:\Archive',
      children: [DiskTreeNode(name: 'Images', fullPath: r'C:\Archive\Images')],
    );
    final root = DiskTreeNode(
      name: r'C:\',
      fullPath: r'C:\',
      children: [archive],
    );

    final revealed = findNearestDisplayedTreeNodeForPath(
      root,
      r'c:/archive/images/compacted.iso',
    );

    expect(revealed, same(archive.children.single));
  });
}

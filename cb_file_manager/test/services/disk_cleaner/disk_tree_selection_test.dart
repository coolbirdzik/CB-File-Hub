import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Check all cleanable never selects the drive or safe ancestors', () {
    final junkFile = DiskTreeNode(
      name: 'cache.tmp',
      fullPath: r'C:\Users\me\AppData\Local\cache.tmp',
      isFile: true,
      sizeBytes: 100,
      fileCount: 1,
      junkCategoryId: 'windows_temp',
    );
    final safeFile = DiskTreeNode(
      name: 'document.txt',
      fullPath: r'C:\Users\me\document.txt',
      isFile: true,
      sizeBytes: 900,
      fileCount: 1,
      isSelectedForDeletion: true,
    );
    final users = DiskTreeNode(
      name: 'Users',
      fullPath: r'C:\Users',
      sizeBytes: 1000,
      fileCount: 2,
      children: [junkFile, safeFile],
      isSelectedForDeletion: true,
    );
    final root = DiskTreeNode(
      name: r'C:\',
      fullPath: r'C:\',
      sizeBytes: 1000,
      fileCount: 2,
      children: [users],
      isSelectedForDeletion: true,
    );

    final selected = DiskTreeSelection.setAllCleanableChecked(root, true);

    expect(DiskTreeSelection.countCleanableNodes(root), 1);
    expect(selected, {junkFile.fullPath});
    expect(root.isSelectedForDeletion, isFalse);
    expect(users.isSelectedForDeletion, isFalse);
    expect(safeFile.isSelectedForDeletion, isFalse);
    expect(junkFile.isSelectedForDeletion, isTrue);
  });

  test('Uncheck all clears junk and manually selected safe nodes', () {
    final junk = DiskTreeNode(
      name: 'cache',
      fullPath: r'C:\cache',
      junkCategoryId: 'dev_cache',
      isSelectedForDeletion: true,
    );
    final manuallySelected = DiskTreeNode(
      name: 'manual',
      fullPath: r'C:\manual',
      isSelectedForDeletion: true,
    );
    final root = DiskTreeNode(
      name: r'C:\',
      fullPath: r'C:\',
      children: [junk, manuallySelected],
    );

    final selected = DiskTreeSelection.setAllCleanableChecked(root, false);

    expect(selected, isEmpty);
    expect(junk.isSelectedForDeletion, isFalse);
    expect(manuallySelected.isSelectedForDeletion, isFalse);
  });

  test('Check all stores only top-level junk targets', () {
    final child = DiskTreeNode(
      name: 'child.tmp',
      fullPath: r'C:\cache\child.tmp',
      isFile: true,
      junkCategoryId: 'dev_cache',
    );
    final parent = DiskTreeNode(
      name: 'cache',
      fullPath: r'C:\cache',
      junkCategoryId: 'dev_cache',
      children: [child],
    );
    final root = DiskTreeNode(
      name: r'C:\',
      fullPath: r'C:\',
      children: [parent],
    );

    final selected = DiskTreeSelection.setAllCleanableChecked(root, true);

    expect(selected, {parent.fullPath});
    expect(parent.isSelectedForDeletion, isTrue);
    expect(child.isSelectedForDeletion, isFalse);
  });

  test('Exact target toggle replaces overlapping targets without tree walk',
      () {
    final child = DiskTreeNode(
      name: 'child.tmp',
      fullPath: r'C:\cache\child.tmp',
      isFile: true,
      isSelectedForDeletion: true,
    );
    final sibling = DiskTreeNode(
      name: 'other.tmp',
      fullPath: r'C:\other.tmp',
      isFile: true,
      isSelectedForDeletion: true,
    );
    final parent = DiskTreeNode(
      name: 'cache',
      fullPath: r'C:\cache',
      children: [child],
    );

    final selected = DiskTreeSelection.setExactTargetChecked(
      {child, sibling},
      parent,
      true,
    );

    expect(selected, {parent, sibling});
    expect(parent.isSelectedForDeletion, isTrue);
    expect(child.isSelectedForDeletion, isFalse);
    expect(sibling.isSelectedForDeletion, isTrue);
  });

  test('Junk aggregate cache refreshes after tree metadata changes', () {
    final child = DiskTreeNode(
      name: 'cache.tmp',
      fullPath: r'C:\cache.tmp',
      isFile: true,
      sizeBytes: 128,
      junkCategoryId: 'dev_cache',
    );
    final root = DiskTreeNode(
      name: r'C:\',
      fullPath: r'C:\',
      children: [child],
    );

    expect(root.hasJunkChildren, isTrue);
    expect(root.junkBytes, 128);

    child.junkCategoryId = null;
    root.invalidateJunkCache();

    expect(root.hasJunkChildren, isFalse);
    expect(root.junkBytes, 0);
  });

  test('Preview targets contain selected parents without duplicate children',
      () {
    final child = DiskTreeNode(
      name: 'child.tmp',
      fullPath: r'C:\cache\child.tmp',
      isFile: true,
      sizeBytes: 100,
      fileCount: 1,
      junkCategoryId: 'dev_cache',
      isSelectedForDeletion: true,
    );
    final cache = DiskTreeNode(
      name: 'cache',
      fullPath: r'C:\cache',
      sizeBytes: 100,
      fileCount: 1,
      children: [child],
      junkCategoryId: 'dev_cache',
      isSelectedForDeletion: true,
    );
    final root = DiskTreeNode(
      name: r'C:\',
      fullPath: r'C:\',
      children: [cache],
    );

    final targets = DiskTreeSelection.collectDeletionTargets(root);

    expect(targets, [cache]);
  });

  test('Preview expands safe ancestors to reveal selected targets', () {
    final selected = DiskTreeNode(
      name: 'cache.tmp',
      fullPath: r'C:\Users\me\cache.tmp',
      isFile: true,
      isSelectedForDeletion: true,
    );
    final profile = DiskTreeNode(
      name: 'me',
      fullPath: r'C:\Users\me',
      children: [selected],
    );
    final users = DiskTreeNode(
      name: 'Users',
      fullPath: r'C:\Users',
      children: [profile],
    );
    final root = DiskTreeNode(
      name: r'C:\',
      fullPath: r'C:\',
      children: [users],
    );

    DiskTreeSelection.expandAncestorsOfSelection(root);

    expect(root.isExpanded, isTrue);
    expect(users.isExpanded, isTrue);
    expect(profile.isExpanded, isTrue);
    expect(selected.isExpanded, isFalse);
  });
}

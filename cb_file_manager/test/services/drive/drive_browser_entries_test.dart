import 'package:cb_file_manager/services/drive/drive_browser_entries.dart';
import 'package:cb_file_manager/services/drive/drive_info.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final drives = [
    DriveInfo(
      path: 'D:/',
      displayName: 'Ảnh 10',
      label: 'Sao lưu',
      kind: DriveKind.fixed,
      space: DriveSpaceInfo.fromTotalFree(2000, 1000),
    ),
    DriveInfo(
      path: 'C:/',
      displayName: 'Ảnh 2',
      kind: DriveKind.fixed,
      space: DriveSpaceInfo.fromTotalFree(1000, 200),
    ),
    const DriveInfo(path: 'E:/', displayName: 'USB', kind: DriveKind.removable),
  ];
  List<String> paths({
    String query = '',
    SortOption sort = SortOption.nameAsc,
  }) => DriveBrowserEntries.filterAndSort(
    drives,
    query: query,
    sortOption: sort,
  ).map((drive) => drive.path).toList();

  test('search folds accents and case and matches labels and drive roots', () {
    expect(paths(query: 'ANH'), ['C:/', 'D:/']);
    expect(paths(query: 'luu sao'), ['D:/']);
    expect(paths(query: 'd:'), ['D:/']);
    expect(paths(query: 'missing'), isEmpty);
    expect(paths(query: ''), hasLength(3));
  });

  test(
    'natural name sorting supports both directions without changing source',
    () {
      expect(paths(), ['C:/', 'D:/', 'E:/']);
      expect(paths(sort: SortOption.nameDesc), ['E:/', 'D:/', 'C:/']);
      expect(drives.first.path, 'D:/');
    },
  );

  test(
    'capacity sorting leaves unavailable capacity last in both directions',
    () {
      expect(paths(sort: SortOption.sizeAsc), ['C:/', 'D:/', 'E:/']);
      expect(paths(sort: SortOption.sizeDesc), ['D:/', 'C:/', 'E:/']);
    },
  );

  test('path and type sorting work on filtered entries too', () {
    expect(paths(sort: SortOption.pathDesc), ['E:/', 'D:/', 'C:/']);
    expect(paths(sort: SortOption.typeAsc), ['C:/', 'D:/', 'E:/']);
    expect(paths(sort: SortOption.typeDesc), ['E:/', 'C:/', 'D:/']);
    expect(paths(query: 'anh', sort: SortOption.pathDesc), ['D:/', 'C:/']);
  });

  test('folder-only sort preferences fall back to drive name ordering', () {
    expect(paths(sort: SortOption.dateDesc), ['C:/', 'D:/', 'E:/']);
    expect(DriveBrowserEntries.effectiveSort(null), SortOption.nameAsc);
    expect(
      DriveBrowserEntries.sortOptions,
      isNot(contains(SortOption.dateDesc)),
    );
  });

  test(
    'grouped keyboard order follows cards while retaining sort within a group',
    () {
      const wsl = DriveInfo(
        path: '\\\\wsl.localhost\\Debian\\',
        displayName: 'Debian',
        kind: DriveKind.wsl,
      );
      final grouped = DriveBrowserEntries.groupForDisplay([wsl, ...drives]);
      expect(grouped.map((d) => d.path), ['D:/', 'C:/', 'E:/', wsl.path]);
      expect(
        DriveBrowserEntries.groupForDisplay([
          wsl,
          ...drives,
        ], descending: true).first,
        wsl,
      );
    },
  );
}

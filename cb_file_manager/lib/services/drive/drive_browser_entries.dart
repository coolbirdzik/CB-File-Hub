import 'package:cb_file_manager/helpers/core/text_utils.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';

import 'drive_info.dart';

/// Search and ordering for the storage locations shown by Home's Browse action.
abstract final class DriveBrowserEntries {
  static const sortOptions = {
    SortOption.nameAsc,
    SortOption.nameDesc,
    SortOption.sizeAsc,
    SortOption.sizeDesc,
    SortOption.typeAsc,
    SortOption.typeDesc,
    SortOption.pathAsc,
    SortOption.pathDesc,
  };

  static SortOption effectiveSort(SortOption? option) =>
      sortOptions.contains(option) ? option! : SortOption.nameAsc;

  /// Grouped card/list order is also used by keyboard navigation.
  static List<DriveInfo> groupForDisplay(
    Iterable<DriveInfo> drives, {
    bool descending = false,
  }) {
    final groups = <DriveGroup, List<DriveInfo>>{};
    for (final drive in drives) {
      groups.putIfAbsent(drive.group, () => []).add(drive);
    }
    final order = groups.keys.toList()
      ..sort((a, b) {
        final compared = DriveInfo.groupSortOrder(
          a,
        ).compareTo(DriveInfo.groupSortOrder(b));
        return descending ? -compared : compared;
      });
    return [for (final group in order) ...groups[group]!];
  }

  static List<DriveInfo> filterAndSort(
    Iterable<DriveInfo> drives, {
    String query = '',
    SortOption sortOption = SortOption.nameAsc,
  }) {
    final result = drives.where((drive) {
      return TextUtils.matchesSearch(
        '${drive.displayName} ${drive.label} ${drive.path}',
        query,
      );
    }).toList();
    final option = effectiveSort(sortOption);
    result.sort((a, b) {
      // Unknown capacities stay last in either direction.
      if (option == SortOption.sizeAsc || option == SortOption.sizeDesc) {
        final known = (a.space.hasDetails ? 0 : 1).compareTo(
          b.space.hasDetails ? 0 : 1,
        );
        if (known != 0) return known;
      }
      final compared = switch (option) {
        SortOption.sizeAsc ||
        SortOption.sizeDesc => a.space.totalBytes.compareTo(b.space.totalBytes),
        SortOption.typeAsc ||
        SortOption.typeDesc => a.kind.index.compareTo(b.kind.index),
        SortOption.pathAsc ||
        SortOption.pathDesc => TextUtils.compareNatural(a.path, b.path),
        _ => TextUtils.compareNatural(a.displayName, b.displayName),
      };
      if (compared != 0) return option.ascending ? compared : -compared;
      return TextUtils.compareNatural(a.path, b.path);
    });
    return result;
  }
}

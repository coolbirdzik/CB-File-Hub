import 'dart:io';
import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:path/path.dart' as pathlib;
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';

/// Centralized utility class for sorting file system entities.
///
/// This class provides static methods to sort files, folders, and mixed
/// lists of file system entities according to various sort options.
class FileSystemSorter {
  // Private constructor to prevent instantiation
  FileSystemSorter._();

  /// Sorts a list of file system entities based on the given sort option.
  ///
  /// This method handles both files and directories, sorting them according
  /// to the specified [sortOption]. File stats are cached for performance.
  ///
  /// Parameters:
  /// - [entities]: The list of file system entities to sort
  /// - [sortOption]: The sort option to apply
  /// - [fileStatsCache]: Optional cache of file stats to improve performance
  ///
  /// Returns a new sorted list without modifying the original.
  static Future<List<FileSystemEntity>> sortEntities(
    List<FileSystemEntity> entities,
    SortOption sortOption, {
    Map<String, FileStat>? fileStatsCache,
  }) async {
    if (entities.isEmpty) return [];

    final stopwatch = Stopwatch()..start();

    // Create a copy to avoid modifying the original list
    final sortedEntities = List<FileSystemEntity>.from(entities);

    // Build or use provided file stats cache
    final statsCache = fileStatsCache ?? await _buildStatsCache(entities);
    AppLogger.perf(
        '⏱️ [PERF] FileSystemSorter._buildStatsCache for ${entities.length} items took: ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.reset();
    stopwatch.start();

    // Get the comparator function for the sort option
    final comparator = getComparator(sortOption, statsCache);

    // Sort the entities
    sortedEntities.sort(comparator);
    AppLogger.perf(
        '⏱️ [PERF] FileSystemSorter.sort() for ${entities.length} items took: ${stopwatch.elapsedMilliseconds}ms');

    return sortedEntities;
  }

  /// Sorts a list of files based on the given sort option.
  ///
  /// This is a convenience method specifically for File objects.
  static Future<List<File>> sortFiles(
    List<File> files,
    SortOption sortOption, {
    Map<String, FileStat>? fileStatsCache,
  }) async {
    final sorted =
        await sortEntities(files, sortOption, fileStatsCache: fileStatsCache);
    return sorted.cast<File>();
  }

  /// Sorts a list of directories based on the given sort option.
  ///
  /// This is a convenience method specifically for Directory objects.
  static Future<List<Directory>> sortDirectories(
    List<Directory> directories,
    SortOption sortOption, {
    Map<String, FileStat>? fileStatsCache,
  }) async {
    final sorted = await sortEntities(directories, sortOption,
        fileStatsCache: fileStatsCache);
    return sorted.cast<Directory>();
  }

  /// Returns a comparator function for the given sort option.
  ///
  /// The comparator can be used with List.sort() to sort file system entities.
  ///
  /// Parameters:
  /// - [sortOption]: The sort option to create a comparator for
  /// - [fileStatsCache]: Cache of file stats for performance
  static int Function(FileSystemEntity, FileSystemEntity) getComparator(
    SortOption sortOption,
    Map<String, FileStat> fileStatsCache,
  ) {
    switch (sortOption) {
      case SortOption.nameAsc:
        return (a, b) => _compareByName(a, b, ascending: true);

      case SortOption.nameDesc:
        return (a, b) => _compareByName(a, b, ascending: false);

      case SortOption.dateAsc:
        return (a, b) => _compareByDate(a, b, fileStatsCache, ascending: true);

      case SortOption.dateDesc:
        return (a, b) => _compareByDate(a, b, fileStatsCache, ascending: false);

      case SortOption.sizeAsc:
        return (a, b) => _compareBySize(a, b, fileStatsCache, ascending: true);

      case SortOption.sizeDesc:
        return (a, b) => _compareBySize(a, b, fileStatsCache, ascending: false);

      case SortOption.typeAsc:
        return (a, b) => _compareByType(a, b, ascending: true);

      case SortOption.typeDesc:
        return (a, b) => _compareByType(a, b, ascending: false);

      case SortOption.dateCreatedAsc:
        return (a, b) =>
            _compareByDateCreated(a, b, fileStatsCache, ascending: true);

      case SortOption.dateCreatedDesc:
        return (a, b) =>
            _compareByDateCreated(a, b, fileStatsCache, ascending: false);

      case SortOption.extensionAsc:
        return (a, b) => _compareByExtension(a, b, ascending: true);

      case SortOption.extensionDesc:
        return (a, b) => _compareByExtension(a, b, ascending: false);

      case SortOption.attributesAsc:
        return (a, b) =>
            _compareByAttributes(a, b, fileStatsCache, ascending: true);

      case SortOption.attributesDesc:
        return (a, b) =>
            _compareByAttributes(a, b, fileStatsCache, ascending: false);

      default:
        return (a, b) => _compareByName(a, b, ascending: true);
    }
  }

  // Private helper methods for comparison

  static int _compareByName(FileSystemEntity a, FileSystemEntity b,
      {required bool ascending}) {
    final aName = pathlib.basename(a.path).toLowerCase();
    final bName = pathlib.basename(b.path).toLowerCase();
    return ascending ? aName.compareTo(bName) : bName.compareTo(aName);
  }

  static int _compareByDate(
      FileSystemEntity a, FileSystemEntity b, Map<String, FileStat> statsCache,
      {required bool ascending}) {
    final aStat = statsCache[a.path];
    final bStat = statsCache[b.path];

    if (aStat == null || bStat == null) {
      return _compareByName(a, b, ascending: true);
    }

    final comparison = aStat.modified.compareTo(bStat.modified);
    return ascending ? comparison : -comparison;
  }

  static int _compareBySize(
      FileSystemEntity a, FileSystemEntity b, Map<String, FileStat> statsCache,
      {required bool ascending}) {
    final aStat = statsCache[a.path];
    final bStat = statsCache[b.path];

    if (aStat == null || bStat == null) {
      return _compareByName(a, b, ascending: true);
    }

    final comparison = aStat.size.compareTo(bStat.size);
    return ascending ? comparison : -comparison;
  }

  static int _compareByType(FileSystemEntity a, FileSystemEntity b,
      {required bool ascending}) {
    final aExt = pathlib.extension(a.path).toLowerCase();
    final bExt = pathlib.extension(b.path).toLowerCase();
    return ascending ? aExt.compareTo(bExt) : bExt.compareTo(aExt);
  }

  static int _compareByDateCreated(
      FileSystemEntity a, FileSystemEntity b, Map<String, FileStat> statsCache,
      {required bool ascending}) {
    final aStat = statsCache[a.path];
    final bStat = statsCache[b.path];

    if (aStat == null || bStat == null) {
      return _compareByName(a, b, ascending: true);
    }

    // On Windows, use changed time as creation time
    // On other platforms, fall back to modified time
    final aTime = Platform.isWindows ? aStat.changed : aStat.modified;
    final bTime = Platform.isWindows ? bStat.changed : bStat.modified;

    final comparison = aTime.compareTo(bTime);
    return ascending ? comparison : -comparison;
  }

  static int _compareByExtension(FileSystemEntity a, FileSystemEntity b,
      {required bool ascending}) {
    final aExt = pathlib.extension(a.path).toLowerCase();
    final bExt = pathlib.extension(b.path).toLowerCase();
    return ascending ? aExt.compareTo(bExt) : bExt.compareTo(aExt);
  }

  static int _compareByAttributes(
      FileSystemEntity a, FileSystemEntity b, Map<String, FileStat> statsCache,
      {required bool ascending}) {
    final aStat = statsCache[a.path];
    final bStat = statsCache[b.path];

    if (aStat == null || bStat == null) {
      return _compareByName(a, b, ascending: true);
    }

    // Create a string representation of attributes for comparison
    final aAttrs = '${aStat.mode},${aStat.type}';
    final bAttrs = '${bStat.mode},${bStat.type}';

    return ascending ? aAttrs.compareTo(bAttrs) : bAttrs.compareTo(aAttrs);
  }

  /// Builds a cache of file stats for the given entities.
  ///
  /// This improves performance when sorting by date, size, or attributes.
  /// Uses parallel stat() calls (batches of 50) to avoid blocking the isolate.
  static Future<Map<String, FileStat>> _buildStatsCache(
    List<FileSystemEntity> entities,
  ) async {
    if (entities.isEmpty) return {};

    final cache = <String, FileStat>{};
    const batchSize = 50;

    for (int i = 0; i < entities.length; i += batchSize) {
      final batch = entities.skip(i).take(batchSize);
      final results = await Future.wait(
        batch.map((entity) async {
          try {
            return MapEntry(entity.path, await entity.stat());
          } catch (_) {
            return null;
          }
        }),
      );
      for (final entry in results) {
        if (entry != null) {
          cache[entry.key] = entry.value;
        }
      }
    }

    return cache;
  }
}

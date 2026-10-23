import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/service_locator.dart';
import '../../helpers/tags/tag_manager.dart';
import '../../services/file_metadata_service.dart';
import '../../services/windows_shell_properties.dart';
import '../../ui/screens/folder_list/folder_list_state.dart';

/// Loads only the selected property, with bounded concurrency. Comparisons do
/// no I/O and keep unknown values last in both directions.
class FilePropertySorter {
  static final _fallbackMetadata = FileMetadataService();

  static Future<int Function(FileSystemEntity, FileSystemEntity)> prepare(
    Iterable<FileSystemEntity> entities,
    SortOption sort, {
    bool Function()? isCancelled,
    Future<Object?> Function(FileSystemEntity, DetailsColumn)? readValue,
  }) async {
    final column = sort.metadataColumn!;
    final unique = {for (final entity in entities) entity.path: entity};
    final values = <String, Object?>{};
    if (column == DetailsColumn.tags && readValue == null) {
      final tags = await TagManager.getTagsForFiles(unique.keys.toList());
      for (final entry in tags.entries) {
        final names = entry.value.map((s) => s.toLowerCase()).toList()..sort();
        values[entry.key] = names.isEmpty ? null : names.join(', ');
      }
    } else {
      final list = unique.values.toList();
      for (var i = 0; i < list.length; i += 8) {
        if (isCancelled?.call() ?? false) break;
        await Future.wait(
          list.skip(i).take(8).map((entity) async {
            try {
              values[entity.path] = await (readValue ?? _read)(entity, column);
            } catch (_) {
              values[entity.path] = null;
            }
          }),
        );
      }
    }
    return (FileSystemEntity a, FileSystemEntity b) {
      if (a is Directory && b is! Directory) return -1;
      if (b is Directory && a is! Directory) return 1;
      final av = values[a.path], bv = values[b.path];
      if (av == null && bv != null) return 1;
      if (bv == null && av != null) return -1;
      final result = _compare(av, bv);
      if (result != 0) return sort.ascending ? result : -result;
      final name = p
          .basename(a.path)
          .toLowerCase()
          .compareTo(p.basename(b.path).toLowerCase());
      return name != 0 ? name : a.path.compareTo(b.path);
    };
  }

  static int _compare(Object? a, Object? b) {
    if (a == null || b == null) return 0;
    if (a is num && b is num) return a.compareTo(b);
    if (a is List<num> && b is List<num>) {
      for (var i = 0; i < a.length || i < b.length; i++) {
        final result = (i < a.length ? a[i] : 0).compareTo(
          i < b.length ? b[i] : 0,
        );
        if (result != 0) return result;
      }
      return 0;
    }
    return a.toString().toLowerCase().compareTo(b.toString().toLowerCase());
  }

  static Object? decodeShellKey(String property, String key) {
    if (key.isEmpty) return null;
    if (property == 'dimensions') {
      final dimensions = key.split(',').map(num.tryParse).toList();
      if (dimensions.length != 2 || dimensions.any((v) => v == null)) {
        return null;
      }
      final width = dimensions[0]!, height = dimensions[1]!;
      return <num>[width * height, width, height];
    }
    if (const {
      'duration',
      'dateTaken',
      'pageCount',
      'rating',
      'frameRate',
      'bitRate',
      'year',
    }.contains(property)) {
      return num.tryParse(key);
    }
    if (property == 'fileVersion') {
      final parts = RegExp(
        r'\d+',
      ).allMatches(key).map((m) => num.parse(m[0]!)).toList();
      if (parts.isNotEmpty) return parts;
    }
    return key.toLowerCase();
  }

  static Future<Object?> _read(
    FileSystemEntity entity,
    DetailsColumn column,
  ) async {
    if (column == DetailsColumn.permissions) {
      return (await entity.stat()).modeString();
    }
    final metadata = locator.isRegistered<FileMetadataService>()
        ? locator<FileMetadataService>()
        : _fallbackMetadata;
    if (column == DetailsColumn.itemCount) {
      return entity is Directory
          ? metadata.getFolderItemCount(entity.path)
          : null;
    }
    if (entity is Directory && column != DetailsColumn.owner) return null;
    if (WindowsShellProperties.isSupported) {
      return decodeShellKey(
        column.name,
        await WindowsShellProperties.instance.getSortKey(
          entity.path,
          column.name,
        ),
      );
    }
    if (column == DetailsColumn.dimensions) {
      final dimensions = await metadata.getImageDimensions(entity.path);
      return dimensions == null
          ? null
          : <num>[
              dimensions.width * dimensions.height,
              dimensions.width,
              dimensions.height,
            ];
    }
    if (column == DetailsColumn.duration) {
      return (await metadata.getMediaDuration(entity.path))?.inMicroseconds;
    }
    return null;
  }
}

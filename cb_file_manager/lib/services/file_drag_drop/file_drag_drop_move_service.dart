import 'dart:io';

import 'package:cb_file_manager/helpers/files/windows_file_operations.dart';
import 'package:path/path.dart' as p;

enum FileDragDropMoveRejection {
  none,
  empty,
  nonLocalPath,
  destinationMissing,
  selfDrop,
  descendantDrop,
  sameParent,
  moveFailed,
}

class FileDragDropMovePlan {
  final List<String> sources;
  final String destination;
  final FileDragDropMoveRejection rejection;

  const FileDragDropMovePlan({
    required this.sources,
    required this.destination,
    required this.rejection,
  });

  bool get isValid => rejection == FileDragDropMoveRejection.none;
}

class FileDragDropMoveService {
  static FileDragDropMovePlan createMovePlan({
    required List<String> sources,
    required String destination,
  }) {
    final cleanedSources = sources
        .map((source) => source.trim())
        .where((source) => source.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final cleanedDestination = destination.trim();

    if (cleanedSources.isEmpty) {
      return FileDragDropMovePlan(
        sources: cleanedSources,
        destination: cleanedDestination,
        rejection: FileDragDropMoveRejection.empty,
      );
    }

    if (!_isLocalPath(cleanedDestination) ||
        cleanedSources.any((source) => !_isLocalPath(source))) {
      return FileDragDropMovePlan(
        sources: cleanedSources,
        destination: cleanedDestination,
        rejection: FileDragDropMoveRejection.nonLocalPath,
      );
    }

    final normalizedDestination = _normalize(cleanedDestination);
    if (!Directory(cleanedDestination).existsSync()) {
      return FileDragDropMovePlan(
        sources: cleanedSources,
        destination: cleanedDestination,
        rejection: FileDragDropMoveRejection.destinationMissing,
      );
    }

    var movedSourceCount = 0;
    for (final source in cleanedSources) {
      final normalizedSource = _normalize(source);
      if (normalizedSource == normalizedDestination) {
        return FileDragDropMovePlan(
          sources: cleanedSources,
          destination: cleanedDestination,
          rejection: FileDragDropMoveRejection.selfDrop,
        );
      }

      if (Directory(source).existsSync() &&
          _isWithin(normalizedSource, normalizedDestination)) {
        return FileDragDropMovePlan(
          sources: cleanedSources,
          destination: cleanedDestination,
          rejection: FileDragDropMoveRejection.descendantDrop,
        );
      }

      if (_normalize(p.dirname(source)) != normalizedDestination) {
        movedSourceCount++;
      }
    }

    if (movedSourceCount == 0) {
      return FileDragDropMovePlan(
        sources: cleanedSources,
        destination: cleanedDestination,
        rejection: FileDragDropMoveRejection.sameParent,
      );
    }

    return FileDragDropMovePlan(
      sources: cleanedSources,
      destination: cleanedDestination,
      rejection: FileDragDropMoveRejection.none,
    );
  }

  static Future<FileDragDropMoveRejection> move({
    required List<String> sources,
    required String destination,
  }) async {
    final plan = createMovePlan(sources: sources, destination: destination);
    if (!plan.isValid) return plan.rejection;

    final moved = WindowsFileOperations.isAvailable
        ? await WindowsFileOperations.moveItems(
            sources: plan.sources,
            destination: plan.destination,
          )
        : await _moveWithDart(plan.sources, plan.destination);

    return moved
        ? FileDragDropMoveRejection.none
        : FileDragDropMoveRejection.moveFailed;
  }

  static bool _isLocalPath(String value) {
    if (value.startsWith('#')) return false;
    if (value.startsWith(r'\\')) return false;
    if (value.startsWith('//')) return false;
    if (Platform.isWindows) {
      return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value);
    }
    return p.isAbsolute(value);
  }

  static String _normalize(String value) {
    var normalized = p.normalize(value);
    final root = p.rootPrefix(normalized);
    if (normalized.length > root.length &&
        (normalized.endsWith(r'\') || normalized.endsWith('/'))) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static bool _isWithin(String parent, String child) {
    if (parent == child) return true;
    return p.isWithin(parent, child);
  }

  static Future<bool> _moveWithDart(
    List<String> sources,
    String destination,
  ) async {
    try {
      for (final source in sources) {
        final target = p.join(destination, p.basename(source));
        if (FileSystemEntity.typeSync(source) ==
            FileSystemEntityType.directory) {
          await Directory(source).rename(target);
        } else {
          await File(source).rename(target);
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

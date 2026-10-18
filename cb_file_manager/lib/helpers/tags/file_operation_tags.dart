import 'dart:io';

import 'package:path/path.dart' as p;

import 'tag_manager.dart';

/// Tags captured before a transfer, keyed by their original paths.
class FileOperationTags {
  final Map<String, List<String>> _tags;

  FileOperationTags._(this._tags);

  static Future<FileOperationTags> capture(List<String> sources) async {
    return FileOperationTags._(await TagManager.getTagsForPathTrees(sources));
  }

  /// Apply only confirmed transfers, using the actual destination name.
  /// A directory renamed as a whole also transfers its descendants.
  Future<void> apply({
    required String source,
    required String destination,
    required bool isMove,
    bool recursive = false,
  }) async {
    if (p.equals(p.normalize(source), p.normalize(destination))) return;
    for (final entry in _tags.entries) {
      final original = entry.key;
      final exact = p.equals(p.normalize(source), p.normalize(original));
      if (!exact && !(recursive && p.isWithin(source, original))) continue;
      final target = exact
          ? destination
          : p.join(destination, p.relative(original, from: source));
      await _applyTags(original, target, entry.value, isMove);
    }
  }

  /// Resolve the most specific shell result for each tagged path. This handles
  /// both whole-directory moves and individual children renamed during merges.
  Future<void> applyCompleted(
    Map<String, String> transfers, {
    required bool isMove,
  }) async {
    String key(String path) => Platform.isWindows
        ? p.normalize(path).toLowerCase()
        : p.normalize(path);
    final bySource = {
      for (final entry in transfers.entries) key(entry.key): entry,
    };
    final canExpand = <String, bool>{};
    for (final entry in _tags.entries) {
      var ancestor = p.normalize(entry.key);
      while (true) {
        final transfer = bySource[key(ancestor)];
        if (transfer != null) {
          final exact = p.equals(ancestor, p.normalize(entry.key));
          final expand =
              exact ||
              (canExpand[ancestor] ??=
                  isMove &&
                  await FileSystemEntity.type(
                        transfer.key,
                        followLinks: false,
                      ) ==
                      FileSystemEntityType.notFound);
          if (expand) {
            final target = exact
                ? transfer.value
                : p.join(
                    transfer.value,
                    p.relative(entry.key, from: transfer.key),
                  );
            await _applyTags(entry.key, target, entry.value, isMove);
          }
          break;
        }
        final parent = p.dirname(ancestor);
        if (parent == ancestor) break;
        ancestor = parent;
      }
    }
  }

  Future<void> _applyTags(
    String original,
    String target,
    List<String> sourceTags,
    bool isMove,
  ) async {
    if (p.equals(p.normalize(original), p.normalize(target))) return;
    if (await FileSystemEntity.type(target, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }

    final tags = {...await TagManager.getTags(target), ...sourceTags};
    if (!await TagManager.setTags(target, tags.toList())) {
      throw FileSystemException('Could not transfer tags', target);
    }
    // Keep source metadata if a copy succeeded but source deletion failed.
    if (isMove &&
        await FileSystemEntity.type(original, followLinks: false) ==
            FileSystemEntityType.notFound) {
      if (!await TagManager.setTags(original, [])) {
        throw FileSystemException('Could not remove moved tags', original);
      }
    }
  }
}

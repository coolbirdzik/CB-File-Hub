import 'dart:async';
import 'dart:io';

import 'package:cb_native/cb_native.dart';

/// Size of one root passed to an [EditorRootSizer].
class EditorRootSize {
  final int bytes;

  /// Folders below the root that could not be read.
  final int unreadable;
  final bool exists;

  const EditorRootSize({
    required this.bytes,
    this.unreadable = 0,
    this.exists = true,
  });

  static const missing = EditorRootSize(bytes: 0, exists: false);
}

/// Sizes each of `roots` on its own: a file counts as itself, a link as
/// nothing, and links inside folders are never followed. Roots are disjoint.
typedef EditorRootSizer =
    Future<List<EditorRootSize>> Function(List<String> roots);

/// One Rust walk over every root ([NativeFs.rootSizes]); the Dart walk when
/// the native library is missing or fails.
Future<List<EditorRootSize>> editorRootSizes(List<String> roots) async {
  final native = await NativeFs.rootSizes(roots);
  if (native != null) {
    return [
      for (final size in native)
        EditorRootSize(
          bytes: size.bytes,
          unreadable: size.unreadable,
          exists: size.exists,
        ),
    ];
  }
  return dartEditorRootSizes(roots);
}

/// The Dart walk behind [editorRootSizes], a few roots at a time.
Future<List<EditorRootSize>> dartEditorRootSizes(
  List<String> roots, {
  int concurrency = 8,
}) async {
  final out = List<EditorRootSize>.filled(roots.length, EditorRootSize.missing);
  var next = 0;
  Future<void> worker() async {
    while (next < roots.length) {
      final index = next++;
      out[index] = await _dartRootSize(roots[index]);
    }
  }

  await Future.wait([
    for (var i = 0; i < concurrency && i < roots.length; i++) worker(),
  ]);
  return out;
}

Future<EditorRootSize> _dartRootSize(String root) async {
  final type = FileSystemEntity.typeSync(root, followLinks: false);
  switch (type) {
    case FileSystemEntityType.notFound:
      return EditorRootSize.missing;
    case FileSystemEntityType.file:
      try {
        return EditorRootSize(bytes: File(root).lengthSync());
      } on FileSystemException {
        return const EditorRootSize(bytes: 0, unreadable: 1);
      }
    case FileSystemEntityType.directory:
      break;
    default:
      return const EditorRootSize(bytes: 0);
  }
  var bytes = 0;
  var unreadable = 0;
  final pending = <String>[root];
  while (pending.isNotEmpty) {
    final directory = pending.removeLast();
    try {
      await for (final entity in Directory(
        directory,
      ).list(followLinks: false)) {
        if (entity is Directory) {
          pending.add(entity.path);
        } else if (entity is File) {
          try {
            bytes += entity.lengthSync();
          } on FileSystemException {
            // Removed or locked meanwhile: counted like the native walk,
            // which skips entries whose metadata cannot be read.
          }
        }
      }
    } on FileSystemException {
      unreadable++;
    }
  }
  return EditorRootSize(bytes: bytes, unreadable: unreadable);
}

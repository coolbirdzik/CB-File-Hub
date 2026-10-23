import 'dart:io';
import 'package:cb_native/cb_native.dart';

/// Preserve request order and duplicate paths. Dart filesystem I/O is the
/// bounded asynchronous fallback; network entity subclasses retain their API.
Future<List<bool>> probeFiles(
  List<String> paths, {
  bool useNative = true,
}) async {
  if (useNative) {
    final native = await NativeFs.filesExist(paths);
    if (native != null) return native;
  }
  final result = <bool>[];
  for (var i = 0; i < paths.length; i += 50) {
    result.addAll(
      await Future.wait(paths.skip(i).take(50).map((s) => File(s).exists())),
    );
  }
  return result;
}

Future<List<File>> existingTaggedFiles(
  Iterable<FileSystemEntity> entities,
) async {
  final files = entities.whereType<File>().toList();
  // Plain local File paths can be batched. FTP/network File adapters can
  // override exists(); never send their virtual paths to the local Rust FS.
  final localType = File('').runtimeType;
  final local = [
    for (var i = 0; i < files.length; i++)
      if (files[i].runtimeType == localType) i,
  ];
  final flags = await probeFiles([for (final i in local) files[i].path]);
  final valid = <int>{
    for (var i = 0; i < local.length; i++)
      if (flags[i]) local[i],
  };
  for (var i = 0; i < files.length; i++) {
    if (files[i].runtimeType != localType && await files[i].exists()) {
      valid.add(i);
    }
  }
  return [
    for (var i = 0; i < files.length; i++)
      if (valid.contains(i)) files[i],
  ];
}

import 'dart:typed_data';

import 'package:cb_file_manager/services/ssh/sftp_transfer.dart';
import 'package:path/path.dart' as p;

/// An in-memory [TransferFileSystem], standing in for an SFTP server.
class MemoryTransferFileSystem implements TransferFileSystem {
  MemoryTransferFileSystem({
    p.Context? paths,
    String? root,
    String? homePath,
    this.chunkSize = 4,
  }) : paths = paths ?? p.posix,
       root = root ?? (paths ?? p.posix).rootPrefix('/') {
    dirs.add(this.root);
    this.homePath = homePath ?? this.root;
  }

  @override
  final p.Context paths;
  final String root;
  late final String homePath;
  final int chunkSize;
  final dirs = <String>{};
  final files = <String, List<int>>{};

  /// Directories reported as links.
  final links = <String>{};

  void addFile(String path, String content) {
    mkdirs(paths.dirname(path));
    files[path] = content.codeUnits;
  }

  void mkdirs(String path) {
    for (var d = path; !dirs.contains(d); d = paths.dirname(d)) {
      dirs.add(d);
    }
  }

  String? text(String path) =>
      files[path] == null ? null : String.fromCharCodes(files[path]!);

  @override
  Future<String> home() async => homePath;

  @override
  String? parent(String path) {
    final parent = paths.dirname(path);
    return parent == path ? null : parent;
  }

  @override
  Future<List<TransferEntry>> list(String directory) async {
    if (!dirs.contains(directory)) throw StateError('No such folder');
    return [
      for (final d in dirs)
        if (d != directory && paths.dirname(d) == directory)
          TransferEntry(
            name: paths.basename(d),
            path: d,
            isDirectory: true,
            isLink: links.contains(d),
          ),
      for (final f in files.entries)
        if (paths.dirname(f.key) == directory)
          TransferEntry(
            name: paths.basename(f.key),
            path: f.key,
            isDirectory: false,
            size: f.value.length,
          ),
    ];
  }

  @override
  Future<bool?> kind(String path) async => dirs.contains(path)
      ? true
      : files.containsKey(path)
      ? false
      : null;

  @override
  Future<void> createDirectory(String path) async {
    if (!dirs.contains(paths.dirname(path))) throw StateError('No parent');
    dirs.add(path);
  }

  @override
  Stream<Uint8List> read(String path) async* {
    final bytes = files[path] ?? (throw StateError('No such file'));
    for (var i = 0; i < bytes.length; i += chunkSize) {
      await Future<void>.delayed(Duration.zero);
      yield Uint8List.fromList(
        bytes.sublist(
          i,
          i + chunkSize > bytes.length ? bytes.length : i + chunkSize,
        ),
      );
    }
  }

  @override
  Future<void> write(
    String path,
    Stream<Uint8List> data,
    void Function(int written) onProgress,
  ) async {
    if (!dirs.contains(paths.dirname(path))) throw StateError('No parent');
    final out = files[path] = <int>[];
    await for (final chunk in data) {
      out.addAll(chunk);
      onProgress(out.length);
    }
  }

  @override
  Future<void> deleteFile(String path) async => files.remove(path);
}

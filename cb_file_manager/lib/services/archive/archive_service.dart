import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart' as archive_io;
import 'package:path/path.dart' as p;

import 'archive_entry_info.dart';
import 'archive_format.dart';

/// Virtual folder/file listing for archive browser mode.
class ArchiveDirectoryListing {
  final List<Directory> folders;
  final List<File> files;

  const ArchiveDirectoryListing({required this.folders, required this.files});
}

typedef ArchiveProgressCallback = void Function(int completed, int total);

/// Lists and extracts common archive formats (zip, tar, 7z, rar, …).
class ArchiveService {
  static const _sevenZipCandidates = [
    r'C:\Program Files\7-Zip\7z.exe',
    r'C:\Program Files (x86)\7-Zip\7z.exe',
  ];

  final Map<String, String> _materializedEntryCache = {};

  /// Returns whether [filePath] points to a supported archive.
  bool isSupportedArchive(String filePath) {
    return detectArchiveFormat(filePath) != ArchiveFormat.unknown;
  }

  /// Lists entries inside [archivePath] without extracting to disk.
  Future<List<ArchiveEntryInfo>> listEntries(String archivePath) async {
    final format = detectArchiveFormat(archivePath);
    if (format == ArchiveFormat.unknown) {
      throw UnsupportedError('Unsupported archive: $archivePath');
    }

    if (isDartArchiveFormat(format)) {
      return _listWithDart(archivePath, format);
    }

    return _listWithSevenZip(archivePath);
  }

  /// Extracts the full archive into [destinationDir].
  Future<void> extractAll({
    required String archivePath,
    required String destinationDir,
    ArchiveProgressCallback? onProgress,
  }) async {
    final format = detectArchiveFormat(archivePath);
    if (format == ArchiveFormat.unknown) {
      throw UnsupportedError('Unsupported archive: $archivePath');
    }

    if (isDartArchiveFormat(format)) {
      await _extractWithDart(
        archivePath: archivePath,
        destinationDir: destinationDir,
        onProgress: onProgress,
      );
      return;
    }

    await _extractWithSevenZip(
      archivePath: archivePath,
      destinationDir: destinationDir,
      onProgress: onProgress,
    );
  }

  /// Extracts a single [entryName] from [archivePath] into [destinationDir].
  Future<void> extractEntry({
    required String archivePath,
    required String entryName,
    required String destinationDir,
  }) async {
    final format = detectArchiveFormat(archivePath);
    if (format == ArchiveFormat.unknown) {
      throw UnsupportedError('Unsupported archive: $archivePath');
    }

    if (isDartArchiveFormat(format)) {
      await _extractSingleWithDart(
        archivePath: archivePath,
        entryName: entryName,
        destinationDir: destinationDir,
        format: format,
      );
      return;
    }

    await _extractSingleWithSevenZip(
      archivePath: archivePath,
      entryName: entryName,
      destinationDir: destinationDir,
    );
  }

  String? findSevenZipExecutable() {
    for (final candidate in _sevenZipCandidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  Future<List<ArchiveEntryInfo>> _listWithDart(
    String archivePath,
    ArchiveFormat format,
  ) async {
    final archive = await _decodeDartArchive(archivePath, format);
    try {
      return archive.files
          .where((file) => file.name.isNotEmpty)
          .map(
            (file) => ArchiveEntryInfo(
              name: _normalizeEntryName(file.name),
              size: file.size,
              compressedSize: 0,
              isDirectory: file.isDirectory,
              modified: DateTime.fromMillisecondsSinceEpoch(
                file.lastModTime * 1000,
                isUtc: true,
              ).toLocal(),
            ),
          )
          .toList();
    } finally {
      await archive.clear();
    }
  }

  Future<void> _extractWithDart({
    required String archivePath,
    required String destinationDir,
    ArchiveProgressCallback? onProgress,
  }) async {
    final format = detectArchiveFormat(archivePath);
    onProgress?.call(0, 1);

    if (format == ArchiveFormat.gzip || format == ArchiveFormat.bzip2) {
      await _extractSingleCompressedMember(
        archivePath: archivePath,
        destinationDir: destinationDir,
        format: format,
      );
      onProgress?.call(1, 1);
      return;
    }

    await archive_io.extractFileToDisk(archivePath, destinationDir);
    onProgress?.call(1, 1);
  }

  Future<void> _extractSingleWithDart({
    required String archivePath,
    required String entryName,
    required String destinationDir,
    required ArchiveFormat format,
  }) async {
    final archive = await _decodeDartArchive(archivePath, format);
    try {
      final normalizedTarget = _normalizeEntryName(entryName);
      ArchiveFile? match;
      for (final file in archive.files) {
        if (_normalizeEntryName(file.name) == normalizedTarget) {
          match = file;
          break;
        }
      }
      if (match == null) {
        throw StateError('Entry not found: $entryName');
      }

      Directory(destinationDir).createSync(recursive: true);
      final outPath = p.join(destinationDir, p.basename(normalizedTarget));
      if (match.isDirectory) {
        Directory(outPath).createSync(recursive: true);
        return;
      }

      final output = archive_io.OutputFileStream(outPath);
      try {
        match.writeContent(output);
      } finally {
        await output.close();
      }
    } finally {
      await archive.clear();
    }
  }

  Future<void> _extractSingleCompressedMember({
    required String archivePath,
    required String destinationDir,
    required ArchiveFormat format,
  }) async {
    Directory(destinationDir).createSync(recursive: true);
    final baseName = p.basenameWithoutExtension(archivePath);
    final outPath = p.join(
      destinationDir,
      baseName.isEmpty ? 'extracted' : baseName,
    );

    final input = archive_io.InputFileStream(archivePath);
    final output = archive_io.OutputFileStream(outPath);
    try {
      if (format == ArchiveFormat.gzip) {
        const GZipDecoder().decodeStream(input, output);
      } else {
        BZip2Decoder().decodeStream(input, output);
      }
    } finally {
      await input.close();
      await output.close();
    }
  }

  Future<Archive> _decodeDartArchive(
    String archivePath,
    ArchiveFormat format,
  ) async {
    Directory? tempDir;
    var workingPath = archivePath;
    var workingFormat = format;

    try {
      if (workingFormat == ArchiveFormat.tarGz) {
        tempDir = Directory.systemTemp.createTempSync('cb_archive_');
        workingPath = p.join(tempDir.path, 'temp.tar');
        await _decompressToFile(
          archivePath,
          workingPath,
          (input, output) => const GZipDecoder().decodeStream(input, output),
        );
        workingFormat = ArchiveFormat.tar;
      } else if (workingFormat == ArchiveFormat.tarBz2) {
        tempDir = Directory.systemTemp.createTempSync('cb_archive_');
        workingPath = p.join(tempDir.path, 'temp.tar');
        await _decompressToFile(
          archivePath,
          workingPath,
          (input, output) => BZip2Decoder().decodeStream(input, output),
        );
        workingFormat = ArchiveFormat.tar;
      } else if (workingFormat == ArchiveFormat.tarXz) {
        tempDir = Directory.systemTemp.createTempSync('cb_archive_');
        workingPath = p.join(tempDir.path, 'temp.tar');
        await _decompressToFile(
          archivePath,
          workingPath,
          (input, output) => XZDecoder().decodeStream(input, output),
        );
        workingFormat = ArchiveFormat.tar;
      }

      if (workingFormat == ArchiveFormat.gzip ||
          workingFormat == ArchiveFormat.bzip2) {
        final baseName = p.basenameWithoutExtension(archivePath);
        return Archive()..add(
          ArchiveFile(
            baseName.isEmpty ? p.basename(archivePath) : baseName,
            File(archivePath).lengthSync(),
            Uint8List(0),
          ),
        );
      }

      final input = archive_io.InputFileStream(workingPath);
      try {
        if (workingFormat == ArchiveFormat.tar) {
          return TarDecoder().decodeStream(input, storeData: false);
        }
        if (workingFormat == ArchiveFormat.zip) {
          return ZipDecoder().decodeStream(input);
        }
      } finally {
        await input.close();
      }
    } finally {
      if (tempDir != null) {
        await tempDir.delete(recursive: true);
      }
    }

    throw UnsupportedError('Cannot decode archive format: $format');
  }

  Future<void> _decompressToFile(
    String inputPath,
    String outputPath,
    void Function(InputStream input, OutputStream output) decode,
  ) async {
    final input = archive_io.InputFileStream(inputPath);
    final output = archive_io.OutputFileStream(outputPath);
    try {
      decode(input, output);
    } finally {
      await input.close();
      await output.close();
    }
  }

  Future<List<ArchiveEntryInfo>> _listWithSevenZip(String archivePath) async {
    final executable = findSevenZipExecutable();
    if (executable == null) {
      throw StateError(
        '7-Zip is required to read this archive format. Install 7-Zip on Windows.',
      );
    }

    final result = await Process.run(executable, [
      'l',
      '-ba',
      archivePath,
    ], runInShell: false);
    if (result.exitCode != 0) {
      throw StateError(
        'Failed to list archive (${result.exitCode}): ${result.stderr}',
      );
    }

    final stdout = result.stdout?.toString() ?? '';
    final entries = <ArchiveEntryInfo>[];
    for (final line in stdout.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parsed = _parseSevenZipListLine(trimmed);
      if (parsed != null) {
        entries.add(parsed);
      }
    }
    return entries;
  }

  ArchiveEntryInfo? _parseSevenZipListLine(String line) {
    // Example: 2024-01-01 12:00:00 ....A         1234         5678  folder/file.txt
    final match = RegExp(
      r'^(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s+(\S+)\s+(\d+)\s+(\d+)\s+(.+)$',
    ).firstMatch(line);
    if (match == null) return null;

    final datePart = match.group(1)!;
    final timePart = match.group(2)!;
    final attributes = match.group(3)!;
    final size = int.tryParse(match.group(4)!) ?? 0;
    final compressed = int.tryParse(match.group(5)!) ?? 0;
    final name = match.group(6)!.trim();
    if (name.isEmpty) return null;

    DateTime? modified;
    try {
      modified = DateTime.parse('$datePart $timePart');
    } catch (_) {}

    return ArchiveEntryInfo(
      name: _normalizeEntryName(name),
      size: size,
      compressedSize: compressed,
      isDirectory: attributes.contains('D'),
      modified: modified,
    );
  }

  Future<void> _extractWithSevenZip({
    required String archivePath,
    required String destinationDir,
    ArchiveProgressCallback? onProgress,
  }) async {
    final executable = findSevenZipExecutable();
    if (executable == null) {
      throw StateError(
        '7-Zip is required to extract this archive format. Install 7-Zip on Windows.',
      );
    }

    Directory(destinationDir).createSync(recursive: true);
    onProgress?.call(0, 1);

    final result = await Process.run(executable, [
      'x',
      archivePath,
      '-o$destinationDir',
      '-y',
    ], runInShell: false);
    if (result.exitCode != 0) {
      throw StateError(
        'Failed to extract archive (${result.exitCode}): ${result.stderr}',
      );
    }

    onProgress?.call(1, 1);
  }

  Future<void> _extractSingleWithSevenZip({
    required String archivePath,
    required String entryName,
    required String destinationDir,
  }) async {
    final executable = findSevenZipExecutable();
    if (executable == null) {
      throw StateError(
        '7-Zip is required to extract this archive format. Install 7-Zip on Windows.',
      );
    }

    Directory(destinationDir).createSync(recursive: true);
    final result = await Process.run(executable, [
      'e',
      archivePath,
      entryName,
      '-o$destinationDir',
      '-y',
    ], runInShell: false);
    if (result.exitCode != 0) {
      throw StateError(
        'Failed to extract entry (${result.exitCode}): ${result.stderr}',
      );
    }
  }

  String _normalizeEntryName(String name) {
    return name.replaceAll('\\', '/');
  }

  /// Lists direct children at [innerPath] inside [archiveFilePath].
  Future<ArchiveDirectoryListing> listDirectory({
    required String archiveFilePath,
    String innerPath = '',
    required String Function({
      required String archiveFile,
      required String innerPath,
      required String entryName,
      required bool isDirectory,
    })
    buildVirtualPath,
  }) async {
    final normalizedInner = _normalizeInnerPrefix(innerPath);
    final entries = await listEntries(archiveFilePath);
    final folderNames = <String>{};
    final fileNames = <String>{};

    for (final entry in entries) {
      final entryPath = _normalizeEntryName(entry.name);
      if (normalizedInner.isNotEmpty &&
          !entryPath.startsWith(normalizedInner)) {
        continue;
      }

      var relative = normalizedInner.isEmpty
          ? entryPath
          : entryPath.substring(normalizedInner.length);
      relative = relative.replaceAll(RegExp(r'^/+'), '');
      if (relative.isEmpty) continue;

      final parts = relative
          .split('/')
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.isEmpty) continue;

      if (parts.length == 1) {
        if (entry.isDirectory || entryPath.endsWith('/')) {
          folderNames.add(parts.first);
        } else {
          fileNames.add(parts.first);
        }
      } else {
        folderNames.add(parts.first);
      }
    }

    final sortedFolderNames = folderNames.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final sortedFileNames = fileNames.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // [normalizedInner] carries a trailing slash for prefix matching; strip it
    // so joined child paths do not end up with a doubled separator.
    final parentInner = normalizedInner.isEmpty
        ? ''
        : normalizedInner.substring(0, normalizedInner.length - 1);
    String childInnerFor(String name) =>
        parentInner.isEmpty ? name : '$parentInner/$name';

    final folders = sortedFolderNames.map((name) {
      return Directory(
        buildVirtualPath(
          archiveFile: archiveFilePath,
          innerPath: childInnerFor(name),
          entryName: name,
          isDirectory: true,
        ),
      );
    }).toList();

    final files = sortedFileNames.map((name) {
      return File(
        buildVirtualPath(
          archiveFile: archiveFilePath,
          innerPath: childInnerFor(name),
          entryName: name,
          isDirectory: false,
        ),
      );
    }).toList();

    return ArchiveDirectoryListing(folders: folders, files: files);
  }

  /// Extracts one archive member to a temp file for preview/open.
  Future<File> materializeEntryFile({
    required String archiveFilePath,
    required String entryInnerPath,
    String? cacheKey,
  }) async {
    final key = cacheKey ?? '$archiveFilePath::$entryInnerPath';
    final cachedPath = _materializedEntryCache[key];
    if (cachedPath != null) {
      final cachedFile = File(cachedPath);
      if (cachedFile.existsSync()) {
        return cachedFile;
      }
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'cb_archive_entry_preview_',
    );
    await extractEntry(
      archivePath: archiveFilePath,
      entryName: entryInnerPath,
      destinationDir: tempDir.path,
    );

    final outputPath = p.join(tempDir.path, p.basename(entryInnerPath));
    final outputFile = File(outputPath);
    if (!outputFile.existsSync()) {
      throw StateError('Failed to materialize archive entry: $entryInnerPath');
    }

    _materializedEntryCache[key] = outputFile.path;
    return outputFile;
  }

  String _normalizeInnerPrefix(String innerPath) {
    final normalized = innerPath
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty)
        .join('/');
    if (normalized.isEmpty) return '';
    return normalized.endsWith('/') ? normalized : '$normalized/';
  }
}

import 'dart:typed_data';

import 'bindings.dart' as b;
import 'buffers.dart';
import 'native_job.dart';

/// Totals from [NativeFs.directorySize].
class NativeSizeResult {
  const NativeSizeResult({
    required this.bytes,
    required this.files,
    required this.directories,
    required this.unreadable,
  });

  final int bytes;
  final int files;
  final int directories;

  /// Paths or folders that could not be read; their size is missing.
  final int unreadable;
}

class NativeRecycleEntry {
  const NativeRecycleEntry(
    this.path,
    this.originalPath,
    this.size,
    this.deletedMs,
    this.isDirectory,
  );
  final String path, originalPath;
  final int size, deletedMs;
  final bool isDirectory;
}

/// One entry of [NativeFs.listDirectory].
class NativeListEntry {
  const NativeListEntry({
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modifiedMs,
    required this.changedMs,
  });

  final String path;
  final bool isDirectory;
  final int size;
  final int modifiedMs;

  /// `FileStat.changed`: creation time on Windows.
  final int changedMs;
}

class NativeListing {
  const NativeListing(this.folders, this.files);

  final List<NativeListEntry> folders;
  final List<NativeListEntry> files;
}

/// Sort orders of [NativeFs.listDirectory], named like the app's
/// `SortOption` values they implement. The index is the wire value
/// (`Sort::from_index` in listing.rs), so only append.
enum NativeListSort {
  nameAsc,
  nameDesc,
  dateAsc,
  dateDesc,
  dateCreatedAsc,
  dateCreatedDesc,
  sizeAsc,
  sizeDesc,
  extensionAsc,
  extensionDesc,

  /// package:path extension of the name.
  typeAsc,
  typeDesc,
  dateAccessedAsc,
  dateAccessedDesc,

  /// Full path, Dart-lower-cased.
  pathAsc,
  pathDesc,

  /// The Attributes column's letters (R, H, S, A, ...).
  attributesAsc,
  attributesDesc,
}

/// How [NativeFs.walk] reads a name's extension.
enum NativeExtensionMode {
  /// No extension filter.
  none,

  /// From the last dot, like `FileTypeUtils.getFileExtension`.
  lastDot,

  /// package:path `extension`: a leading dot does not count.
  path,
}

class NativeWalkEntry {
  const NativeWalkEntry({
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modifiedMs,
  });

  final String path;
  final bool isDirectory;

  /// 0 unless stats were requested.
  final int size;
  final int modifiedMs;
}

/// A file one or more junk rules matched; [ruleIndices] index the rules
/// given to [NativeFs.junkScan], in order.
class NativeJunkHit {
  const NativeJunkHit({
    required this.path,
    required this.size,
    required this.modifiedMs,
    required this.ruleIndices,
  });

  final String path;
  final int size;
  final int modifiedMs;
  final List<int> ruleIndices;
}

/// `_CompiledRule` of the Disk Cleaner's junk scan. [baseKey] is already the
/// Dart `_pathKey` of the rule's base path.
class NativeJunkRule {
  const NativeJunkRule({
    required this.index,
    required this.baseKey,
    required this.recursive,
    this.includeGlobs,
    this.excludeGlobs,
    this.cutoffMs,
  });

  final int index;
  final String baseKey;
  final bool recursive;
  final List<String>? includeGlobs;
  final List<String>? excludeGlobs;

  /// Files modified after this are skipped.
  final int? cutoffMs;
}

class NativeJunkResult {
  const NativeJunkResult(this.hits, this.error);

  final List<NativeJunkHit> hits;

  /// The first unreadable directory's message, if any.
  final String? error;
}

/// Filesystem walks on Rust threads. Every method returns null when the
/// native library is unavailable (or the call was cancelled), so callers
/// keep their Dart code as the fallback.
abstract final class NativeFs {
  /// File.exists for a batch, preserving input order, with bounded workers.
  static Future<List<bool>?> filesExist(List<String> paths) async {
    final config = WireWriter()..strs(paths);
    final job = NativeJob.start(b.jobExistsBatch, config.takeBytes());
    if (job == null) return null;
    final Uint8List? out;
    try {
      out = await job.result();
    } on NativeJobException {
      return null;
    }
    if (out == null) return null;
    return out.map((v) => v != 0).toList(growable: false);
  }

  /// Stream $I metadata beneath explicitly supplied Recycle Bin roots.
  static Future<bool> recycleBin({
    required List<String> roots,
    required void Function(List<NativeRecycleEntry>) onEntries,
  }) async {
    final config = WireWriter()..strs(roots);
    final job = NativeJob.start(b.jobRecycleBin, config.takeBytes());
    if (job == null) return false;
    final out = await job.result(
      onOutput: (chunk) {
        final r = WireReader(chunk);
        final entries = <NativeRecycleEntry>[];
        while (!r.isDone) {
          entries.add(
            NativeRecycleEntry(r.str(), r.str(), r.i64(), r.i64(), r.boolean()),
          );
        }
        onEntries(entries);
      },
    );
    return out != null;
  }

  /// Sizes of [files] (links followed) plus everything below [directories]
  /// (links not followed), like `LazyPathSizeCalculator`.
  static Future<NativeSizeResult?> directorySize({
    Iterable<String> files = const [],
    Iterable<String> directories = const [],
    bool Function()? shouldContinue,
  }) async {
    final config = WireWriter()
      ..strs(files)
      ..strs(directories);
    final job = NativeJob.start(b.jobDirSize, config.takeBytes());
    if (job == null) return null;
    final out = await job.result(shouldContinue: shouldContinue);
    if (out == null) return null;
    final r = WireReader(out);
    return NativeSizeResult(
      bytes: r.i64(),
      files: r.i64(),
      directories: r.i64(),
      unreadable: r.i64(),
    );
  }

  /// One directory, folders and files each sorted by [sort] exactly like the
  /// folder browser's Dart comparator. Links are left out, and files ending
  /// in one of [skipSuffixes] or named one of [skipNames] are skipped.
  /// Returns null when the directory cannot be listed, so the caller's Dart
  /// path can raise the precise error.
  static Future<NativeListing?> listDirectory(
    String path, {
    NativeListSort sort = NativeListSort.nameAsc,
    bool stats = false,
    List<String> skipSuffixes = const [],
    List<String> skipNames = const [],
  }) async {
    final config = WireWriter()
      ..str(path)
      ..u8(sort.index)
      ..boolean(stats)
      ..strs(skipSuffixes)
      ..strs(skipNames);
    final job = NativeJob.start(b.jobListDir, config.takeBytes());
    if (job == null) return null;
    final Uint8List? out;
    try {
      out = await job.result();
    } on NativeJobException {
      return null;
    }
    if (out == null) return null;
    final r = WireReader(out);
    final folderCount = r.u32();
    final fileCount = r.u32();
    NativeListEntry entry() {
      final kind = r.u8();
      final size = r.i64();
      final modified = r.i64();
      final changed = r.i64();
      return NativeListEntry(
        path: r.str(),
        isDirectory: kind == b.kindDirectory,
        size: size,
        modifiedMs: modified,
        changedMs: changed,
      );
    }

    final folders = List.generate(folderCount, (_) => entry());
    final files = List.generate(fileCount, (_) => entry());
    return NativeListing(folders, files);
  }

  /// The order of [paths] (from any folders) under [sort], as indices into
  /// [paths], using the folder listing's comparators. Stats a date, size or
  /// attributes order needs are read per parent folder on worker threads;
  /// a path that is gone sorts as empty. Null when the library is missing.
  static Future<List<int>?> sortPaths(
    List<String> paths, {
    required NativeListSort sort,
  }) async {
    final config = WireWriter()
      ..u8(sort.index)
      ..strs(paths);
    final job = NativeJob.start(b.jobSortPaths, config.takeBytes());
    if (job == null) return null;
    final Uint8List? out;
    try {
      out = await job.result();
    } on NativeJobException {
      return null;
    }
    if (out == null) return null;
    final r = WireReader(out);
    return List.generate(r.u32(), (_) => r.u32());
  }

  /// Entries below [roots]. Returns null when unavailable, cancelled, or a
  /// pattern in [excludeNameRegexes] (case-insensitive, Rust syntax) does not
  /// compile, so the caller can run its Dart walker instead.
  ///
  /// [maxDepth] 0 reads every level; 1 reads the roots and their direct
  /// subfolders. [skipDotNames] drops entries whose name starts with `.` but
  /// still lists inside dot folders, like `getFoldersAndFiles`. Entries
  /// smaller than [minSize] or modified after [maxModifiedMs] are dropped
  /// (both need stats, which are then read). The walk stops after about
  /// [maxResults] hits when it is above 0 (a few more can arrive from
  /// folders read in parallel). Traversal order is unspecified.
  static Future<List<NativeWalkEntry>?> walk({
    required List<String> roots,
    bool recursive = true,
    int maxDepth = 0,
    bool files = true,
    bool directories = false,
    bool skipDotNames = false,
    bool stats = false,
    bool followLinks = false,
    NativeExtensionMode extensionMode = NativeExtensionMode.none,
    Iterable<String> extensions = const [],
    List<String> excludeNameRegexes = const [],
    int maxResults = 0,
    int minSize = 0,
    int? maxModifiedMs,
    bool Function()? shouldContinue,
  }) async {
    final out = await _walk(
      roots: roots,
      recursive: recursive,
      maxDepth: maxDepth,
      flags:
          (files ? 1 : 0) |
          (directories ? 2 : 0) |
          (skipDotNames ? 4 : 0) |
          (stats ? 8 : 0) |
          (followLinks ? 16 : 0),
      extensionMode: extensionMode,
      extensions: extensions,
      excludeNameRegexes: excludeNameRegexes,
      maxResults: maxResults,
      minSize: minSize,
      maxModifiedMs: maxModifiedMs,
      shouldContinue: shouldContinue,
    );
    if (out == null) return null;
    final entries = <NativeWalkEntry>[];
    final r = WireReader(out);
    while (!r.isDone) {
      final kind = r.u8();
      final size = r.i64();
      final modified = r.i64();
      entries.add(
        NativeWalkEntry(
          path: r.str(),
          isDirectory: kind == b.kindDirectory,
          size: size,
          modifiedMs: modified,
        ),
      );
    }
    return entries;
  }

  /// How many files [walk] would return with the same filters, without
  /// sending their paths to Dart.
  static Future<int?> countFiles({
    required List<String> roots,
    bool recursive = true,
    bool skipDotNames = false,
    NativeExtensionMode extensionMode = NativeExtensionMode.none,
    Iterable<String> extensions = const [],
    List<String> excludeNameRegexes = const [],
    bool Function()? shouldContinue,
  }) async {
    final out = await _walk(
      roots: roots,
      recursive: recursive,
      maxDepth: 0,
      flags: 1 | (skipDotNames ? 4 : 0) | 32,
      extensionMode: extensionMode,
      extensions: extensions,
      excludeNameRegexes: excludeNameRegexes,
      maxResults: 0,
      minSize: 0,
      maxModifiedMs: null,
      shouldContinue: shouldContinue,
    );
    if (out == null || out.length < 8) return null;
    return WireReader(out).i64();
  }

  static Future<Uint8List?> _walk({
    required List<String> roots,
    required bool recursive,
    required int maxDepth,
    required int flags,
    required NativeExtensionMode extensionMode,
    required Iterable<String> extensions,
    required List<String> excludeNameRegexes,
    required int maxResults,
    required int minSize,
    required int? maxModifiedMs,
    required bool Function()? shouldContinue,
  }) {
    final config = WireWriter()
      ..strs(roots)
      ..boolean(recursive)
      ..u32(maxDepth)
      ..u8(flags)
      ..u8(extensionMode.index)
      ..strs(extensions)
      ..strs(excludeNameRegexes)
      ..i64(maxResults)
      ..i64(minSize)
      // i64::MAX: no limit.
      ..i64(maxModifiedMs ?? 0x7FFFFFFFFFFFFFFF);
    final job = NativeJob.start(b.jobWalk, config.takeBytes());
    if (job == null) return Future.value();
    return job.result(shouldContinue: shouldContinue);
  }

  /// Walks one junk-scan group root and returns every file the [rules]
  /// match. [onProgress] gets (files matched, bytes, directories read, last
  /// matching rule index + 1) and the folder being read.
  static Future<NativeJunkResult?> junkScan({
    required String scanPath,
    required bool recursive,
    required bool lowerCaseKeys,
    required List<NativeJunkRule> rules,
    void Function(NativeJobProgress progress)? onProgress,
    bool Function()? shouldContinue,
    Duration tick = const Duration(milliseconds: 100),
  }) async {
    final config = WireWriter()
      ..str(scanPath)
      ..boolean(recursive)
      ..boolean(lowerCaseKeys)
      ..u32(rules.length);
    void globs(List<String>? globs) {
      config.boolean(globs != null);
      if (globs != null) config.strs(globs);
    }

    for (final rule in rules) {
      config
        ..i32(rule.index)
        ..str(rule.baseKey)
        ..boolean(rule.recursive);
      globs(rule.includeGlobs);
      globs(rule.excludeGlobs);
      config
        ..boolean(rule.cutoffMs != null)
        ..i64(rule.cutoffMs ?? 0);
    }
    final job = NativeJob.start(b.jobJunkScan, config.takeBytes());
    if (job == null) return null;
    final out = await job.result(
      shouldContinue: shouldContinue,
      onProgress: onProgress,
      tick: tick,
    );
    if (out == null) return null;
    final hits = <NativeJunkHit>[];
    String? error;
    final r = WireReader(out);
    while (!r.isDone) {
      if (r.u8() == 2) {
        error ??= r.str();
        continue;
      }
      final size = r.i64();
      final modified = r.i64();
      final path = r.str();
      final indices = List.generate(r.u32(), (_) => r.i32());
      hits.add(
        NativeJunkHit(
          path: path,
          size: size,
          modifiedMs: modified,
          ruleIndices: indices,
        ),
      );
    }
    return NativeJunkResult(hits, error);
  }
}

import 'dart:typed_data';
import 'bindings.dart' as b;
import 'buffers.dart';
import 'native_job.dart';

class NativeCacheEntry {
  const NativeCacheEntry(this.path, this.size, this.modifiedMs);
  final String path;
  final int size, modifiedMs;
}

class NativeSyntaxToken {
  const NativeSyntaxToken(this.start, this.length, this.className);
  final int start, length;
  final String className;
}

/// Small background jobs for interactive views. Null requests Dart fallback.
abstract final class NativeUiJobs {
  static Future<Uint8List?> _run(int kind, WireWriter config) async {
    final job = NativeJob.start(kind, config.takeBytes());
    if (job == null) return null;
    try {
      return await job.result();
    } on NativeJobException {
      return null;
    }
  }

  static Future<List<String>?> suggestDirectories(
    String root,
    String prefix, {
    required int limit,
    required bool caseInsensitive,
  }) async {
    final out = await _run(
      b.jobPathSuggestions,
      WireWriter()
        ..str(root)
        ..str(prefix)
        ..boolean(caseInsensitive)
        ..u32(limit),
    );
    if (out == null) return null;
    final r = WireReader(out);
    final paths = <String>[];
    while (!r.isDone) {
      paths.add(r.str());
    }
    return paths;
  }

  static Future<List<int?>?> countChildren(List<String> roots) async {
    final out = await _run(b.jobChildCounts, WireWriter()..strs(roots));
    if (out == null) return null;
    final r = WireReader(out);
    return List.generate(roots.length, (_) {
      final count = r.i64();
      return count < 0 ? null : count;
    });
  }

  static Future<List<NativeCacheEntry>?> cachePlan(
    String root, {
    required int cutoffMs,
    required int maxCount,
    required int maxBytes,
  }) async {
    final out = await _run(
      b.jobCachePlan,
      WireWriter()
        ..str(root)
        ..i64(cutoffMs)
        ..u32(maxCount)
        ..i64(maxBytes),
    );
    if (out == null) return null;
    final r = WireReader(out);
    final entries = <NativeCacheEntry>[];
    while (!r.isDone) {
      entries.add(NativeCacheEntry(r.str(), r.i64(), r.i64()));
    }
    return entries;
  }

  static Future<List<NativeSyntaxToken>?> tokenize(
    String language,
    String source,
  ) async {
    final out = await _run(
      b.jobSyntax,
      WireWriter()
        ..str(language)
        ..str(source),
    );
    if (out == null) return null;
    final r = WireReader(out);
    final tokens = <NativeSyntaxToken>[];
    while (!r.isDone) {
      tokens.add(NativeSyntaxToken(r.u32(), r.u32(), r.str()));
    }
    return tokens;
  }

  /// Rule kinds equal AlbumAutoRule.condition.index. Regex rules request Dart
  /// fallback before any output to preserve ECMAScript matching semantics.
  static Future<bool?> scanSmartAlbum({
    required List<String> roots,
    required List<String> extensions,
    required List<(int, String)> rules,
    required void Function(List<String>) onBatch,
    required bool Function() shouldContinue,
    void Function(int processed, int matched)? onProgress,
  }) async {
    final config = WireWriter()
      ..strs(roots)
      ..strs(extensions)
      ..u32(rules.length);
    for (final (kind, pattern) in rules) {
      config
        ..u8(kind)
        ..str(pattern);
    }
    final job = NativeJob.start(b.jobSmartAlbum, config.takeBytes());
    if (job == null) return null;
    try {
      final result = await job.result(
        shouldContinue: shouldContinue,
        onOutput: (chunk) {
          if (!shouldContinue()) return;
          final r = WireReader(chunk);
          final paths = <String>[];
          while (!r.isDone) {
            paths.add(r.str());
          }
          onBatch(paths);
        },
        onProgress: (p) => onProgress?.call(p.counters[1], p.counters[0]),
      );
      return result != null;
    } on NativeJobException {
      return null;
    }
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cb_native/cb_native.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win32;

import '../../helpers/core/text_utils.dart';
import 'document_text.dart';

class ContentSearchRequest {
  final String root;
  final String query;
  final String extension;
  final bool caseSensitive;
  final bool matchAll;
  final bool recursive;

  const ContentSearchRequest({
    required this.root,
    required this.query,
    this.extension = '',
    this.caseSensitive = false,
    this.matchAll = true,
    this.recursive = true,
  });
}

class ContentSearchOutcome {
  final List<Map<String, dynamic>> items;
  final bool complete;
  final List<String> warnings;
  final int filesSearched;

  const ContentSearchOutcome(
    this.items,
    this.complete,
    this.warnings,
    this.filesSearched,
  );
}

/// Finds files by the words they contain, including Office and other
/// documents, and ranks them by how many query terms match. The walk and
/// matching run in Rust or on a background isolate, never on the UI isolate.
class ContentSearch {
  static const maxEntries = 50000;
  static const maxResults = 2000;
  static const maxReadBytes = 192 * 1024 * 1024;
  static const timeLimit = Duration(seconds: 30);

  /// The Rust search reads files on every core, so it covers a whole drive.
  static const nativeMaxEntries = 400000;
  static const nativeMaxReadBytes = 2 * 1024 * 1024 * 1024;
  static const nativeTimeLimit = Duration(seconds: 45);
  static const _snippetsPerFile = 3;
  static const _snippetChars = 200;

  /// Tool and VCS folders that drown real documents in noise.
  static const _skippedDirectories = {
    '.git',
    '.svn',
    '.hg',
    'node_modules',
    '.dart_tool',
    '__pycache__',
    r'$recycle.bin',
    'system volume information',
  };

  /// Windows and installed programs, skipped right below a drive root
  /// (content.rs `SYSTEM_DIRECTORIES`).
  static const _systemDirectories = {
    'windows',
    'program files',
    'program files (x86)',
    'programdata',
    r'$winreagent',
    'recovery',
    'msocache',
    'proc',
    'sys',
    'dev',
    'usr',
    'bin',
    'sbin',
    'lib',
    'lib64',
    'boot',
    'snap',
    'system',
    'library',
    'private',
  };

  /// App caches and settings, skipped anywhere below the root.
  static const _appDataDirectories = {'appdata'};

  /// Quoted phrases stay whole; other words match independently. Unless
  /// [caseSensitive], terms ignore case and diacritics ("hoa don" finds
  /// "Hóa đơn"), as every other search in the app does.
  static List<String> terms(String query, {required bool caseSensitive}) {
    final terms = <String>[];
    for (final match in RegExp(r'"([^"]+)"|(\S+)').allMatches(query)) {
      final raw = match.group(1) ?? match.group(2)!;
      final term = caseSensitive ? raw.trim() : TextUtils.searchKey(raw);
      if (term.isNotEmpty && !terms.contains(term)) terms.add(term);
    }
    return terms;
  }

  static final _runeKeys = <int, String>{};

  /// Exactly [TextUtils.searchKey], computed per character with a cache so
  /// whole documents fold without regex passes over every line.
  static String searchKey(String text) {
    final out = StringBuffer();
    var gap = false;
    void emit(int unit) {
      if (_isSeparator(unit)) {
        gap = out.isNotEmpty;
        return;
      }
      if (gap) out.writeCharCode(0x20);
      gap = false;
      out.writeCharCode(unit);
    }

    for (final rune in text.runes) {
      if (rune < 0x80) {
        emit(rune >= 0x41 && rune <= 0x5A ? rune + 0x20 : rune);
        continue;
      }
      final key = _runeKeys.putIfAbsent(
        rune,
        () => TextUtils.normalizeForSearch(String.fromCharCode(rune)),
      );
      for (final unit in key.codeUnits) {
        emit(unit);
      }
    }
    return out.toString();
  }

  /// Whitespace as RegExp \s defines it, plus the punctuation searchKey
  /// treats as word breaks.
  static bool _isSeparator(int c) =>
      c == 0x20 ||
      (c >= 0x09 && c <= 0x0D) ||
      c == 0x5F ||
      c == 0x2D ||
      c == 0x2E ||
      c == 0x28 ||
      c == 0x29 ||
      c == 0x5B ||
      c == 0x5D ||
      c == 0x7B ||
      c == 0x7D ||
      (c > 0x7F &&
          (c == 0xA0 ||
              c == 0x1680 ||
              (c >= 0x2000 && c <= 0x200A) ||
              c == 0x2028 ||
              c == 0x2029 ||
              c == 0x202F ||
              c == 0x205F ||
              c == 0x3000 ||
              c == 0xFEFF));

  /// Searches with the Rust content search (parallel, reads PDF) when
  /// package:cb_native is built, else on a background Dart isolate.
  /// [useNative] false forces the Dart search; tests compare the two.
  static Future<ContentSearchOutcome> run(
    ContentSearchRequest request, {
    required bool Function() isCancelled,
    bool useNative = true,
  }) async {
    final queryTerms = terms(
      request.query,
      caseSensitive: request.caseSensitive,
    );
    if (queryTerms.isEmpty) {
      throw ArgumentError('query has no searchable words.');
    }
    if (useNative && CbNative.isAvailable) {
      final outcome = await _runNative(request, queryTerms, isCancelled);
      if (outcome != null) return outcome;
    }
    return _runIsolate(request, isCancelled);
  }

  static Future<ContentSearchOutcome?> _runNative(
    ContentSearchRequest request,
    List<String> queryTerms,
    bool Function() isCancelled,
  ) async {
    // Rust stops itself at the time limit; the grace only covers a file
    // whose extraction never returns.
    final deadline = DateTime.now().add(
      nativeTimeLimit + const Duration(seconds: 10),
    );
    var stoppedByUser = false;
    final result = await NativeContent.search(
      root: request.root,
      terms: queryTerms,
      recursive: request.recursive,
      caseSensitive: request.caseSensitive,
      matchAll: request.matchAll,
      extension: _wantedExtension(request.extension),
      maxEntries: nativeMaxEntries,
      maxResults: maxResults,
      maxReadBytes: nativeMaxReadBytes,
      timeLimit: nativeTimeLimit,
      shouldContinue: () {
        if (isCancelled()) stoppedByUser = true;
        return !stoppedByUser && DateTime.now().isBefore(deadline);
      },
    );
    if (result == null) return null;
    // A search faster than one poll tick still honours a Stop pressed during it.
    if (stoppedByUser || isCancelled()) {
      throw StateError('Operation stopped by user.');
    }
    final items = [
      for (final match in result.matches)
        _item(
          path: match.path,
          format: match.format,
          size: match.size,
          modified: DateTime.fromMillisecondsSinceEpoch(match.modifiedMs),
          queryTerms: queryTerms,
          matched: [for (final index in match.matchedTerms) queryTerms[index]],
          hits: match.hits,
          snippets: [
            for (final (line, text) in match.snippets)
              {'line': line, 'text': text},
          ],
        ),
    ];
    return _finish(
      items: items,
      problems: result.warnings,
      stopReason: result.finished
          ? switch (result.stop) {
              NativeContentStop.none => null,
              NativeContentStop.entries => 'Scan bounds reached',
              NativeContentStop.time => 'Search time limit reached',
              NativeContentStop.readBudget => 'Read budget reached',
              NativeContentStop.results => 'Result limit reached',
            }
          : 'Search time limit reached',
      tooLarge: result.tooLarge,
      noText: result.noText,
      cloudOnly: result.cloudOnly,
      skippedSystem: result.skippedSystem,
      unsupported: result.unsupported,
      searched: result.filesSearched,
    );
  }

  static Future<ContentSearchOutcome> _runIsolate(
    ContentSearchRequest request,
    bool Function() isCancelled,
  ) async {
    final port = ReceivePort();
    final reply = Completer<Object?>();
    final subscription = port.listen((message) {
      if (!reply.isCompleted) reply.complete(message);
    });
    final cancelled = Object();
    final poll = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (isCancelled() && !reply.isCompleted) reply.complete(cancelled);
    });
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _worker,
        (port.sendPort, request),
        onError: port.sendPort,
        onExit: port.sendPort,
        debugName: 'agent-content-search',
      );
      if (isCancelled() && !reply.isCompleted) reply.complete(cancelled);
      final message = await reply.future;
      if (identical(message, cancelled)) {
        throw StateError('Operation stopped by user.');
      }
      if (message is ContentSearchOutcome) return message;
      if (message is List && message.isNotEmpty) {
        throw StateError('Content search failed: ${message.first}');
      }
      throw StateError('Content search stopped unexpectedly.');
    } finally {
      poll.cancel();
      await subscription.cancel();
      port.close();
      isolate?.kill(priority: Isolate.immediate);
    }
  }

  static void _worker((SendPort, ContentSearchRequest) message) {
    final (port, request) = message;
    port.send(search(request));
  }

  static String _wantedExtension(String extension) {
    final ext = extension.toLowerCase();
    return ext.isEmpty || ext.startsWith('.') ? ext : '.$ext';
  }

  /// The Dart search the worker isolate runs. It has no PDF reader.
  static ContentSearchOutcome search(ContentSearchRequest request) {
    final queryTerms = terms(
      request.query,
      caseSensitive: request.caseSensitive,
    );
    final wantedExt = _wantedExtension(request.extension);
    final clock = Stopwatch()..start();
    final items = <Map<String, dynamic>>[];
    final problems = <String>[];
    final unsupported = <String, int>{};
    var visited = 0;
    var searched = 0;
    var tooLarge = 0;
    var noText = 0;
    var cloudOnly = 0;
    final skippedSystem = <String>[];
    final rootIsDrive = RegExp(r'^([A-Za-z]:[\\/]?|/)$').hasMatch(request.root);
    var readBytes = 0;
    String? stopReason;

    final pending = [request.root];
    while (pending.isNotEmpty && stopReason == null) {
      final directory = pending.removeLast();
      List<FileSystemEntity> children;
      try {
        children = Directory(directory).listSync(followLinks: false)
          ..sort((a, b) => b.path.compareTo(a.path));
      } on FileSystemException catch (error) {
        problems.add(
          'Could not list ${error.path ?? directory}: ${error.message}',
        );
        continue;
      }
      for (final entity in children) {
        if (++visited > maxEntries) {
          stopReason = 'Scan bounds reached';
          break;
        }
        if (clock.elapsed > timeLimit) {
          stopReason = 'Search time limit reached';
          break;
        }
        if (_cloudOnly(entity.path)) {
          cloudOnly++;
          continue;
        }
        if (entity is Directory) {
          final name = p.basename(entity.path).toLowerCase();
          if (!request.recursive || _skippedDirectories.contains(name)) {
            continue;
          }
          if (_appDataDirectories.contains(name) ||
              _isToolCache(name, directory) ||
              (rootIsDrive &&
                  directory == request.root &&
                  _systemDirectories.contains(name))) {
            if (skippedSystem.length < 50) skippedSystem.add(entity.path);
            continue;
          }
          pending.add(entity.path);
          continue;
        }
        if (entity is! File) continue;
        final path = entity.path;
        final fileExt = p.extension(path).toLowerCase();
        if (wantedExt.isNotEmpty && fileExt != wantedExt) continue;
        final format = DocumentText.formatOf(path);
        if (format == 'binary') continue;
        if (format == 'unsupported' || format == 'pdf') {
          unsupported[fileExt] = (unsupported[fileExt] ?? 0) + 1;
          continue;
        }
        try {
          final stat = entity.statSync();
          if (stat.size > DocumentText.maxBytesFor(format)) {
            tooLarge++;
            continue;
          }
          if ((readBytes += stat.size) > maxReadBytes) {
            stopReason = 'Read budget reached';
            break;
          }
          final bytes = _readCandidate(entity, format);
          if (bytes == null) continue;
          String? text;
          try {
            text = DocumentText.extract(format, bytes);
          } catch (_) {
            // A corrupt document is skipped like one without text.
          }
          if (text == null) {
            if (format != 'text') noText++;
            continue;
          }
          searched++;
          final match = _match(text, queryTerms, request);
          if (match == null) continue;
          items.add(
            _item(
              path: path,
              format: format,
              size: stat.size,
              modified: stat.modified,
              queryTerms: queryTerms,
              matched: match.matched,
              hits: match.hits,
              snippets: match.snippets,
            ),
          );
          if (items.length >= maxResults) {
            stopReason = 'Result limit reached';
            break;
          }
        } on FileSystemException catch (error) {
          problems.add('Could not read $path: ${error.message}');
        }
      }
    }
    return _finish(
      items: items,
      problems: problems,
      stopReason: stopReason,
      tooLarge: tooLarge,
      noText: noText,
      cloudOnly: cloudOnly,
      skippedSystem: skippedSystem,
      unsupported: unsupported,
      searched: searched,
    );
  }

  /// The file's bytes, or null for a plain-text candidate whose first 8 KiB
  /// hold a NUL: then only that much is read (content.rs does the same).
  static Uint8List? _readCandidate(File file, String format) {
    if (format != 'text') return file.readAsBytesSync();
    final handle = file.openSync();
    try {
      final head = handle.readSync(8192);
      final utf16 =
          head.length >= 2 &&
          ((head[0] == 0xFF && head[1] == 0xFE) ||
              (head[0] == 0xFE && head[1] == 0xFF));
      if (!utf16 && head.contains(0)) return null;
      final rest = <int>[...head];
      while (true) {
        final chunk = handle.readSync(1 << 20);
        if (chunk.isEmpty) break;
        rest.addAll(chunk);
      }
      return Uint8List.fromList(rest);
    } finally {
      handle.closeSync();
    }
  }

  /// A cloud placeholder (OneDrive, iCloud...): reading it would download
  /// it. Same attributes as content.rs checks.
  static bool _cloudOnly(String path) {
    if (!Platform.isWindows) return false;
    final pathPtr = path.toNativeUtf16();
    try {
      final attributes = win32.GetFileAttributes(win32.PCWSTR(pathPtr)).value;
      return attributes != 0xFFFFFFFF &&
          attributes & (0x1000 | 0x40000 | 0x400000) != 0;
    } catch (_) {
      return false;
    } finally {
      malloc.free(pathPtr);
    }
  }

  static Map<String, dynamic> _item({
    required String path,
    required String format,
    required int size,
    required DateTime modified,
    required List<String> queryTerms,
    required List<String> matched,
    required int hits,
    required List<Map<String, dynamic>> snippets,
  }) => {
    'path': path,
    'name': p.basename(path),
    'format': format,
    'size_bytes': size,
    'modified': modified.toIso8601String(),
    'matched_terms': matched,
    if (matched.length < queryTerms.length)
      'missing_terms': [
        for (final term in queryTerms)
          if (!matched.contains(term)) term,
      ],
    'hits': hits,
    'snippets': snippets,
  };

  /// Ranks [items] and turns what was skipped into warnings; any of it
  /// makes the scope incomplete.
  static ContentSearchOutcome _finish({
    required List<Map<String, dynamic>> items,
    required List<String> problems,
    required String? stopReason,
    required int tooLarge,
    required int noText,
    required int cloudOnly,
    required List<String> skippedSystem,
    required Map<String, int> unsupported,
    required int searched,
  }) {
    final warnings = <String>[];
    void warn(String text) {
      if (!warnings.contains(text)) warnings.add(text);
    }

    if (stopReason != null) {
      warn('$stopReason. Narrow the folder, extension or query.');
    }
    if (tooLarge > 0) {
      warn(
        '$tooLarge file(s) were too large to search '
        '(text over 2 MiB, documents over 64 MiB).',
      );
    }
    if (noText > 0) {
      warn(
        '$noText document(s) have no text to search, such as scanned PDFs '
        '(OCR is not supported) or damaged files.',
      );
    }
    if (cloudOnly > 0) {
      warn(
        '$cloudOnly cloud-only item(s) (OneDrive, iCloud and similar) were '
        'skipped so searching does not download them.',
      );
    }
    if (skippedSystem.isNotEmpty) {
      final shown = (skippedSystem.toList()..sort()).take(5).join(', ');
      warn(
        'Skipped system and app-data folders ($shown'
        '${skippedSystem.length > 5 ? ', ...' : ''}); search inside one '
        'directly if it is needed.',
      );
    }
    if (unsupported.isNotEmpty) {
      final kinds = (unsupported.keys.toList()..sort())
          .map((ext) => '${unsupported[ext]} $ext')
          .join(', ');
      warn('Not searched, no text reader for these formats yet: $kinds.');
    }
    // Unreadable paths last and condensed: a drive has many, and they must
    // not crowd out why the scope is incomplete.
    if (problems.isNotEmpty) {
      warn(
        problems.length == 1
            ? problems.single
            : '${problems.length} folders or files could not be read, e.g. '
                  '${problems.take(2).join('; ')}',
      );
    }
    int score(Map<String, dynamic> item) {
      final hits = item['hits'] as int;
      return (item['matched_terms'] as List).length * 100000 +
          (hits > 99999 ? 99999 : hits);
    }

    items.sort((a, b) {
      final byScore = score(b).compareTo(score(a));
      return byScore != 0
          ? byScore
          : (a['path'] as String).compareTo(b['path'] as String);
    });
    final complete =
        problems.isEmpty &&
        stopReason == null &&
        tooLarge == 0 &&
        noText == 0 &&
        cloudOnly == 0 &&
        skippedSystem.isEmpty &&
        unsupported.isEmpty;
    return ContentSearchOutcome(items, complete, warnings, searched);
  }

  /// Hits per term over the whole text, plus the first lines that show them.
  static ({
    List<String> matched,
    int hits,
    List<Map<String, dynamic>> snippets,
  })?
  _match(String text, List<String> queryTerms, ContentSearchRequest request) {
    final hits = List.filled(queryTerms.length, 0);
    final snippets = <Map<String, dynamic>>[];
    var lineNumber = 0;
    for (final line in text.split('\n')) {
      lineNumber++;
      if (line.isEmpty) continue;
      final haystack = request.caseSensitive ? line : searchKey(line);
      int? firstAt;
      for (var i = 0; i < queryTerms.length; i++) {
        final term = queryTerms[i];
        // Non-overlapping occurrences, kept where a word starts (content.rs
        // `find` walks them the same way).
        var count = 0;
        for (
          var at = haystack.indexOf(term);
          at >= 0;
          at = haystack.indexOf(term, at + term.length)
        ) {
          if (!_startsWord(haystack, at, term)) continue;
          firstAt ??= at;
          count++;
        }
        hits[i] += count;
      }
      if (firstAt != null && snippets.length < _snippetsPerFile) {
        snippets.add({
          'line': lineNumber,
          'text': _snippet(line, firstAt, haystack.length),
        });
      }
    }
    final matched = [
      for (var i = 0; i < queryTerms.length; i++)
        if (hits[i] > 0) queryTerms[i],
    ];
    if (matched.isEmpty ||
        (request.matchAll && matched.length < queryTerms.length)) {
      return null;
    }
    return (
      matched: matched,
      hits: hits.fold<int>(0, (sum, value) => sum + value),
      snippets: snippets,
    );
  }

  static bool _isAsciiAlphanumeric(int c) =>
      (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || _isAsciiLower(c);
  static bool _isAsciiLower(int c) => c >= 0x61 && c <= 0x7A;
  static bool _isAsciiLetter(int c) =>
      _isAsciiLower(c) || (c >= 0x41 && c <= 0x5A);

  /// A term matches where a word starts, like Windows Search: "f95" finds
  /// "F95" and "f95zone" but not the hex in "0x1f95f". A number may follow
  /// letters ("2048" in "INV2048"); text without spaces (CJK) matches
  /// anywhere. Same rule as content.rs `starts_word`.
  static bool _startsWord(String haystack, int at, String term) {
    if (term.isEmpty || !_isAsciiAlphanumeric(term.codeUnitAt(0))) return true;
    if (at == 0) return true;
    final previous = haystack.codeUnitAt(at - 1);
    if (!_isAsciiAlphanumeric(previous)) return true;
    final first = term.codeUnitAt(0);
    return _isAsciiLetter(previous) && first >= 0x30 && first <= 0x39;
  }

  /// Hidden tool folders (`.cargo`, `.gradle`...) and Go's module cache
  /// (`pkg/mod`). Same rule as content.rs `is_tool_cache`.
  static bool _isToolCache(String lowerName, String parent) =>
      lowerName.startsWith('.') ||
      (lowerName == 'mod' && p.basename(parent).toLowerCase() == 'pkg');

  /// A window of the original line around a match found in its search key,
  /// whose offsets differ slightly from the original after folding.
  static String _snippet(String line, int keyOffset, int keyLength) {
    final clean = line.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length <= _snippetChars) return clean;
    final center = keyLength == 0
        ? 0
        : (keyOffset * clean.length / keyLength).round();
    var start = center - _snippetChars ~/ 3;
    if (start < 0) start = 0;
    var end = start + _snippetChars;
    if (end > clean.length) {
      end = clean.length;
      start = end - _snippetChars;
    }
    return '${start > 0 ? '…' : ''}${clean.substring(start, end)}'
        '${end < clean.length ? '…' : ''}';
  }
}

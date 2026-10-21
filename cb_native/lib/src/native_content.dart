import 'dart:typed_data';

import 'bindings.dart' as b;
import 'buffers.dart';
import 'native_job.dart';

/// One file whose text contains the query (content.rs `RECORD_MATCH`).
class NativeContentMatch {
  const NativeContentMatch({
    required this.path,
    required this.format,
    required this.size,
    required this.modifiedMs,
    required this.hits,
    required this.matchedTerms,
    required this.snippets,
  });

  final String path;

  /// `DocumentText` format name: text, docx, xlsx, pptx, opendocument,
  /// epub, rtf or pdf.
  final String format;
  final int size;
  final int modifiedMs;
  final int hits;

  /// Indices into the terms passed to [NativeContent.search].
  final List<int> matchedTerms;

  /// 1-based line and its text, around the first match on that line.
  final List<(int, String)> snippets;
}

/// Why a content search stopped before covering everything.
enum NativeContentStop { none, entries, time, readBudget, results }

class NativeContentResult {
  const NativeContentResult({
    required this.matches,
    required this.warnings,
    required this.finished,
    this.tooLarge = 0,
    this.stop = NativeContentStop.none,
    this.filesSearched = 0,
    this.noText = 0,
    this.cloudOnly = 0,
    this.skippedSystem = const [],
    this.unsupported = const {},
  });

  final List<NativeContentMatch> matches;

  /// Unreadable folders and files, as messages.
  final List<String> warnings;

  /// False when [NativeContent.search]'s `shouldContinue` stopped it; the
  /// fields below are then zero and [matches] holds what arrived until then.
  final bool finished;
  final int tooLarge;
  final NativeContentStop stop;
  final int filesSearched;

  /// Documents with no text to search, such as scanned PDFs.
  final int noText;

  /// Cloud placeholders (OneDrive, iCloud...) skipped so they are not
  /// downloaded.
  final int cloudOnly;

  /// System folders below a drive root and AppData folders, not entered.
  final List<String> skippedSystem;

  /// Files with no text reader, by lower-cased extension.
  final Map<String, int> unsupported;
}

/// The text of a document; [text] is null when the file has none (a scanned
/// PDF, a corrupt document).
class NativeDocumentText {
  const NativeDocumentText(this.text);

  final String? text;
}

/// The agent's content search and document text on Rust threads (content.rs,
/// doctext.rs), including PDF text.
abstract final class NativeContent {
  /// Searches the text of files below [root] for [terms]: `TextUtils`
  /// search keys, or raw strings with [caseSensitive]. Returns null when the
  /// library is unavailable.
  static Future<NativeContentResult?> search({
    required String root,
    required List<String> terms,
    bool recursive = true,
    bool caseSensitive = false,
    bool matchAll = true,
    String extension = '',
    int maxEntries = 400000,
    int maxResults = 2000,
    int maxReadBytes = 2 * 1024 * 1024 * 1024,
    Duration timeLimit = const Duration(seconds: 45),
    bool Function()? shouldContinue,
  }) async {
    final config = WireWriter()
      ..str(root)
      ..boolean(recursive)
      ..boolean(caseSensitive)
      ..boolean(matchAll)
      ..strs(terms)
      ..str(extension)
      ..i64(maxEntries)
      ..i64(maxResults)
      ..i64(maxReadBytes)
      ..i64(timeLimit.inMilliseconds);
    final job = NativeJob.start(b.jobContentSearch, config.takeBytes());
    if (job == null) return null;

    final matches = <NativeContentMatch>[];
    final warnings = <String>[];
    NativeContentResult? summary;
    // Each poll returns whole records: Rust appends one record per call.
    void decode(Uint8List chunk) {
      final r = WireReader(chunk);
      while (!r.isDone) {
        switch (r.u8()) {
          case 1:
            final path = r.str();
            final format = r.str();
            final size = r.i64();
            final modified = r.i64();
            final hits = r.i64();
            final matched = [for (var i = r.u32(); i > 0; i--) r.u32()];
            final snippets = [
              for (var i = r.u32(); i > 0; i--) (r.u32(), r.str()),
            ];
            matches.add(
              NativeContentMatch(
                path: path,
                format: format,
                size: size,
                modifiedMs: modified,
                hits: hits,
                matchedTerms: matched,
                snippets: snippets,
              ),
            );
          case 2:
            warnings.add(r.str());
          case 3:
            final tooLarge = r.i64();
            final stop = r.u8();
            final searched = r.i64();
            final noText = r.i64();
            final cloudOnly = r.i64();
            final skippedSystem = [for (var i = r.u32(); i > 0; i--) r.str()];
            final unsupported = <String, int>{
              for (var i = r.u32(); i > 0; i--) r.str(): r.i64(),
            };
            summary = NativeContentResult(
              matches: matches,
              warnings: warnings,
              finished: true,
              tooLarge: tooLarge,
              stop: stop < NativeContentStop.values.length
                  ? NativeContentStop.values[stop]
                  : NativeContentStop.none,
              filesSearched: searched,
              noText: noText,
              cloudOnly: cloudOnly,
              skippedSystem: skippedSystem,
              unsupported: unsupported,
            );
          default:
            throw const NativeJobException('Unknown content search record.');
        }
      }
    }

    await job.result(shouldContinue: shouldContinue, onOutput: decode);
    return summary ??
        NativeContentResult(
          matches: matches,
          warnings: warnings,
          finished: false,
        );
  }

  /// The text of the document at [path] in [format] (a `DocumentText`
  /// format name). Returns null when the library is unavailable. Throws
  /// [NativeJobException] when the file cannot be read.
  static Future<NativeDocumentText?> documentText(
    String path,
    String format,
  ) async {
    final config = WireWriter()
      ..str(path)
      ..str(format);
    final job = NativeJob.start(b.jobDocumentText, config.takeBytes());
    if (job == null) return null;
    final out = await job.result();
    if (out == null || out.isEmpty) return null;
    final r = WireReader(out);
    return NativeDocumentText(r.boolean() ? r.str() : null);
  }
}

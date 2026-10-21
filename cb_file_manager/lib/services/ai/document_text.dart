import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Searchable text inside plain-text, Office Open XML, OpenDocument, EPUB and
/// RTF files. Pure and synchronous: callers run it off the UI isolate.
class DocumentText {
  static const documentFormats = {
    '.docx': 'docx',
    '.docm': 'docx',
    '.dotx': 'docx',
    '.xlsx': 'xlsx',
    '.xlsm': 'xlsx',
    '.pptx': 'pptx',
    '.pptm': 'pptx',
    '.odt': 'opendocument',
    '.ods': 'opendocument',
    '.odp': 'opendocument',
    '.epub': 'epub',
    '.rtf': 'rtf',
    // Read by package:cb_native only; the Dart search reports it skipped.
    '.pdf': 'pdf',
  };

  /// Documents whose text needs a reader the app does not have yet.
  static const unsupportedExtensions = {'.doc', '.xls', '.ppt'};

  /// Never text; skipped without reading.
  static const binaryExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp',
    '.heic',
    '.tif',
    '.tiff',
    '.ico',
    '.psd',
    '.raw',
    '.cr2',
    '.nef',
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.wmv',
    '.webm',
    '.flv',
    '.m4v',
    '.mp3',
    '.wav',
    '.flac',
    '.aac',
    '.ogg',
    '.m4a',
    '.wma',
    '.zip',
    '.rar',
    '.7z',
    '.gz',
    '.tgz',
    '.bz2',
    '.xz',
    '.tar',
    '.iso',
    '.img',
    '.vhd',
    '.vhdx',
    '.exe',
    '.dll',
    '.sys',
    '.msi',
    '.bin',
    '.dat',
    '.db',
    '.sqlite',
    '.class',
    '.jar',
    '.so',
    '.dylib',
    '.o',
    '.obj',
    '.lib',
    '.pdb',
    '.woff',
    '.woff2',
    '.ttf',
    '.otf',
    '.gguf',
    '.safetensors',
    '.pt',
    '.onnx',
  };

  static const maxPlainTextBytes = 2 * 1024 * 1024;
  static const maxDocumentBytes = 64 * 1024 * 1024;
  static const maxExtractedChars = 4 * 1024 * 1024;

  /// 'text', a [documentFormats] value, 'unsupported' or 'binary'.
  static String formatOf(String path) {
    final ext = p.extension(path).toLowerCase();
    if (documentFormats.containsKey(ext)) return documentFormats[ext]!;
    if (unsupportedExtensions.contains(ext)) return 'unsupported';
    if (binaryExtensions.contains(ext)) return 'binary';
    return 'text';
  }

  static int maxBytesFor(String format) =>
      format == 'text' ? maxPlainTextBytes : maxDocumentBytes;

  /// Text of a file in [format], or null when it is binary or unreadable.
  static String? extract(String format, Uint8List bytes) {
    final text = switch (format) {
      'text' => _plainText(bytes),
      'rtf' => _rtfText(_plainText(bytes) ?? ''),
      'docx' => _zipText(bytes, (name) {
        return name == 'word/document.xml' ||
            RegExp(
              r'^word/(header|footer)\d*\.xml$|^word/(footnotes|endnotes|comments)\.xml$',
            ).hasMatch(name);
      }),
      'xlsx' => _zipText(
        bytes,
        (name) =>
            name == 'xl/sharedStrings.xml' ||
            RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(name),
        sheetInlineOnly: true,
      ),
      'pptx' => _zipText(
        bytes,
        (name) => RegExp(
          r'^ppt/(slides/slide|notesSlides/notesSlide)\d+\.xml$',
        ).hasMatch(name),
      ),
      'opendocument' => _zipText(bytes, (name) => name == 'content.xml'),
      'epub' => _zipText(
        bytes,
        (name) => RegExp(r'\.(x?html?)$', caseSensitive: false).hasMatch(name),
      ),
      _ => null,
    };
    if (text == null) return null;
    return text.length > maxExtractedChars
        ? text.substring(0, maxExtractedChars)
        : text;
  }

  static String? _plainText(Uint8List bytes) {
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) return _utf16(bytes, 2, true);
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) return _utf16(bytes, 2, false);
    }
    final probe = bytes.length < 8192 ? bytes.length : 8192;
    for (var i = 0; i < probe; i++) {
      if (bytes[i] == 0) return null;
    }
    final start =
        bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF
        ? 3
        : 0;
    // Legacy code pages still match their ASCII words.
    return utf8.decode(bytes.sublist(start), allowMalformed: true);
  }

  static String _utf16(Uint8List bytes, int start, bool littleEndian) {
    final units = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      units.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  static String? _zipText(
    Uint8List bytes,
    bool Function(String name) wanted, {
    bool sheetInlineOnly = false,
  }) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return null;
    }
    final entries =
        archive.files.where((file) => file.isFile && wanted(file.name)).toList()
          ..sort((a, b) => _naturalCompare(a.name, b.name));
    final parts = <String>[];
    var length = 0;
    void add(String text) {
      if (text.isEmpty) return;
      parts.add(text);
      length += text.length + 1;
    }

    for (final entry in entries) {
      final xml = utf8.decode(entry.content, allowMalformed: true);
      if (sheetInlineOnly && entry.name.startsWith('xl/worksheets/')) {
        // Shared strings hold most cell text; sheets add inline strings.
        for (final cell in RegExp(r'<is>([\s\S]*?)</is>').allMatches(xml)) {
          add(xmlText(cell.group(1)!));
        }
      } else {
        add(xmlText(xml));
      }
      if (length > maxExtractedChars) break;
    }
    return parts.join('\n');
  }

  static final _blockEnd = RegExp(
    r'</(?:w:p|a:p|text:p|text:h|p|h[1-6]|li|div|tr|si|title)>|'
    r'<(?:w:br|w:cr|a:br|text:line-break|br)\b[^>]*>',
  );
  static final _cellBreak = RegExp(
    r'<(?:w:tab|text:tab)\b[^>]*>|</(?:td|th|table:table-cell|w:tc)>',
  );
  static final _tag = RegExp(r'<[^>]*>');
  static final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);');

  /// Visible text of an XML/HTML fragment, one paragraph per line.
  static String xmlText(String xml) {
    final text = xml
        .replaceAll(RegExp(r'<(script|style)\b[\s\S]*?</\1>'), '')
        .replaceAll(_blockEnd, '\n')
        .replaceAll(_cellBreak, '\t')
        .replaceAll(_tag, '');
    return text
        .replaceAllMapped(_entity, (match) {
          final value = match.group(1)!;
          return switch (value) {
            'amp' => '&',
            'lt' => '<',
            'gt' => '>',
            'quot' => '"',
            'apos' => "'",
            _ => _codePoint(
              value.startsWith('#x')
                  ? int.tryParse(value.substring(2), radix: 16)
                  : int.tryParse(value.substring(1)),
            ),
          };
        })
        .replaceAll(RegExp(r'[ \t]*\n[ \t\n]*'), '\n')
        .trim();
  }

  static String _rtfText(String rtf) {
    final text = rtf
        // Font tables, styles and pictures are not document text.
        .replaceAll(
          RegExp(
            r'\{\\(?:\*|fonttbl|colortbl|stylesheet|info|pict)[^{}]*(?:\{[^{}]*\}[^{}]*)*\}',
          ),
          '',
        )
        .replaceAllMapped(
          RegExp(r'\\u(-?\d+)\??'),
          (m) => _codePoint((int.tryParse(m.group(1)!) ?? -1) & 0xFFFF),
        )
        .replaceAllMapped(
          RegExp(r"\\'([0-9a-fA-F]{2})"),
          (m) => _codePoint(int.tryParse(m.group(1)!, radix: 16)),
        )
        .replaceAll(RegExp(r'\\(?:par|line|row)\b ?'), '\n')
        .replaceAll(RegExp(r'\\(?:tab|cell)\b ?'), '\t')
        .replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), '')
        .replaceAll(RegExp(r'(?<!\\)[{}]'), '')
        .replaceAllMapped(RegExp(r'\\([\\{}])'), (m) => m.group(1)!);
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  /// [value] as a character, or U+FFFD where it is not a valid scalar value
  /// (doctext.rs does the same).
  static String _codePoint(int? value) =>
      value == null ||
          value < 0 ||
          value > 0x10FFFF ||
          (value >= 0xD800 && value <= 0xDFFF)
      ? String.fromCharCode(0xFFFD)
      : String.fromCharCode(value);

  /// slide2 before slide10.
  static int _naturalCompare(String a, String b) {
    final digits = RegExp(r'\d+');
    final aKey = a.replaceAllMapped(digits, (m) => m[0]!.padLeft(8, '0'));
    final bKey = b.replaceAllMapped(digits, (m) => m[0]!.padLeft(8, '0'));
    return aKey.compareTo(bKey);
  }
}

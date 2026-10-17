import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'bencode_reader.dart';

/// Reads v1/hybrid metainfo without re-encoding `info`: hashes must use the
/// original bytes, including for torrents produced by noncanonical encoders.
class TorrentMetainfo {
  final String hash;
  final String name;
  final int totalBytes;
  final int fileCount;
  final String category;
  final List<String> trackers;
  final String? comment;
  final String? createdBy;
  final int? creationDate;
  final bool? isPrivate;
  final int? pieceLength;
  final int? pieceCount;

  const TorrentMetainfo(
    this.hash,
    this.name,
    this.totalBytes,
    this.fileCount,
    this.category, {
    this.trackers = const [],
    this.comment,
    this.createdBy,
    this.creationDate,
    this.isPrivate,
    this.pieceLength,
    this.pieceCount,
  });

  static TorrentMetainfo parse(Uint8List bytes) {
    if (bytes.length > 16 * 1024 * 1024) {
      throw const FormatException('Torrent exceeds 16 MiB');
    }
    final reader = BencodeReader(bytes);
    final root = reader.read();
    if (reader.offset != bytes.length || root is! Map<String, Object>) {
      throw const FormatException('Invalid torrent dictionary');
    }
    final info = root['info'];
    if (info is! Map<String, Object> || reader.infoStart == null) {
      throw const FormatException('Missing torrent info');
    }
    // aria2 supports v1 and hybrid torrents, but not pure BEP 52/v2 torrents.
    if (info['pieces'] is! Uint8List ||
        info['piece length'] is! int ||
        (info['piece length'] as int) <= 0) {
      throw const FormatException(
        'A BitTorrent v1 or hybrid torrent is required',
      );
    }
    final name = _text(info['name.utf-8'] ?? info['name']);
    _safeComponent(name);
    if (info['name'] != null) _safeComponent(_text(info['name']));
    var total = 0;
    final names = <String>[];
    final files = info['files'];
    final paths = <String>{};
    if (files != null && files is! List<Object>) {
      throw const FormatException('Invalid file list');
    }
    if (files is List<Object>) {
      if (files.isEmpty) throw const FormatException('Empty torrent');
      for (final file in files) {
        if (file is! Map<String, Object>) {
          throw const FormatException('Invalid torrent file');
        }
        final components = file['path.utf-8'] ?? file['path'];
        if (components is! List<Object> || components.isEmpty) {
          throw const FormatException('Missing file path');
        }
        final parts = components.map(_text).toList();
        for (final part in parts) {
          _safeComponent(part);
        }
        if (!paths.add(parts.join('/').toLowerCase())) {
          throw const FormatException('Duplicate file path');
        }
        // Validate both encodings: clients differ in which path they prefer.
        if (file['path'] case final List<Object> fallback) {
          for (final component in fallback) {
            _safeComponent(_text(component));
          }
        }
        names.add(parts.last.toLowerCase());
        final length = _length(file['length']);
        if (total + length < total) {
          throw const FormatException('Torrent size overflow');
        }
        total += length;
      }
    } else {
      total = _length(info['length']);
      names.add(name.toLowerCase());
    }
    final pieces = info['pieces'] as Uint8List;
    final expected = total == 0
        ? 0
        : 1 + (total - 1) ~/ (info['piece length'] as int);
    if (pieces.length != expected * 20) {
      throw const FormatException('Invalid piece hashes');
    }
    final hash = sha1
        .convert(
          Uint8List.sublistView(bytes, reader.infoStart!, reader.infoEnd!),
        )
        .toString();
    final category =
        names.every((n) => RegExp(r'\.(mkv|mp4|avi|mov|webm|wmv)$').hasMatch(n))
        ? 'video'
        : names.every(
            (n) => RegExp(r'\.(mp3|flac|wav|m4a|ogg|aac)$').hasMatch(n),
          )
        ? 'audio'
        : names.every((n) => RegExp(r'\.(pdf|epub|txt|docx?)$').hasMatch(n))
        ? 'documents'
        : 'other';
    final trackers = <String>{};
    void addTracker(Object? value) {
      final text = _optionalText(value, limit: 2048);
      if (text != null && text.isNotEmpty && trackers.length < 128) {
        trackers.add(text);
      }
    }

    if (root['announce-list'] case final List<Object> tiers) {
      for (final tier in tiers) {
        if (tier is List<Object>) {
          for (final tracker in tier) {
            addTracker(tracker);
          }
        }
      }
    }
    addTracker(root['announce']);
    final date = root['creation date'];
    return TorrentMetainfo(
      hash,
      name,
      total,
      names.length,
      category,
      trackers: List.unmodifiable(trackers),
      comment: _optionalText(root['comment.utf-8'] ?? root['comment']),
      createdBy: _optionalText(root['created by']),
      creationDate: date is int && date >= 0 && date <= 8640000000000
          ? date * 1000
          : null,
      isPrivate: info['private'] == 1,
      pieceLength: info['piece length'] as int,
      pieceCount: pieces.length ~/ 20,
    );
  }

  static String? _optionalText(Object? value, {int limit = 4096}) {
    if (value is! Uint8List) return null;
    // Only display metadata is bounded; the original bytes and hash stay intact.
    final text = utf8
        .decode(value.take(limit * 4).toList(), allowMalformed: true)
        .trim();
    return text.length > limit ? text.substring(0, limit) : text;
  }

  static int _length(Object? value) {
    if (value is! int || value < 0) {
      throw const FormatException('Invalid file size');
    }
    return value;
  }

  static String _text(Object? value) {
    if (value is! Uint8List) throw const FormatException('Invalid text');
    return utf8.decode(value, allowMalformed: true);
  }

  static void _safeComponent(String value) {
    if (value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.contains(RegExp(r'[\x00-\x1f/\\:*?"<>|]')) ||
        value.endsWith('.') ||
        value.endsWith(' ') ||
        RegExp(
          r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
          caseSensitive: false,
        ).hasMatch(value)) {
      throw const FormatException('Unsafe torrent file path');
    }
  }
}

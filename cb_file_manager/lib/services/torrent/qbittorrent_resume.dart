import 'dart:convert';
import 'dart:typed_data';

import 'bencode_reader.dart';
import 'magnet_link.dart';
import 'torrent_metainfo.dart';

/// Offline recovery only. qBit's progress/piece flags are not aria2 state.
class QbittorrentResume {
  final MagnetLink magnet;
  final List<String> trackers;
  final String? downloadDirectory;
  final String? group;
  final int? addedAt;
  final Uint8List? metainfo;

  const QbittorrentResume._(
    this.magnet,
    this.trackers,
    this.downloadDirectory,
    this.group,
    this.addedAt,
    this.metainfo,
  );

  static QbittorrentResume parse(Uint8List bytes, String expectedHash) {
    final reader = BencodeReader(bytes);
    final root = reader.read();
    if (reader.offset != bytes.length || root is! Map<String, Object>) {
      throw const FormatException('Invalid qBittorrent resume dictionary');
    }
    if (_text(root['file-format']) != 'libtorrent resume file') {
      throw const FormatException('Invalid qBittorrent resume format');
    }
    final rawHash = root['info-hash'];
    if (rawHash is! Uint8List || rawHash.length != 20) {
      throw const FormatException('Resume has no supported v1 info hash');
    }
    final hash = rawHash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (hash != expectedHash) {
      throw const FormatException('qBittorrent resume hash mismatch');
    }
    final rawName = _text(root['qBt-name']) ?? _text(root['name']) ?? hash;
    final name = rawName.length > 1024 ? rawName.substring(0, 1024) : rawName;
    final trackers = <String>{};
    void collect(Object? value, [int depth = 0]) {
      if (depth > 4 || trackers.length >= 512) return;
      if (value is List && value is! Uint8List) {
        for (final child in value) {
          collect(child, depth + 1);
        }
      } else {
        final text = _text(value);
        final uri = text == null ? null : Uri.tryParse(text);
        if (uri != null &&
            const ['udp', 'http', 'https', 'ws', 'wss'].contains(uri.scheme) &&
            uri.host.isNotEmpty) {
          trackers.add(text!);
        }
      }
    }

    collect(root['trackers']);
    var uri = 'magnet:?xt=urn:btih:$hash&dn=${Uri.encodeComponent(name)}';
    for (final tracker in trackers) {
      final suffix = '&tr=${Uri.encodeComponent(tracker)}';
      if (uri.length + suffix.length <= 32768) uri += suffix;
    }
    // Embedded info is optional. Preserve the exact info byte slice instead of
    // re-encoding it, which would change hashes of noncanonical dictionaries.
    Uint8List? metainfo;
    if (reader.infoStart != null && root['info'] is Map<String, Object>) {
      metainfo = Uint8List.fromList([
        100,
        if (trackers.isNotEmpty) ...[
          ...ascii.encode('13:announce-listl'),
          for (final tracker in trackers) ...[
            108,
            ...ascii.encode('${utf8.encode(tracker).length}:'),
            ...utf8.encode(tracker),
            101,
          ],
          101,
        ],
        ...ascii.encode('4:info'),
        ...bytes.sublist(reader.infoStart!, reader.infoEnd!),
        101,
      ]);
      if (TorrentMetainfo.parse(metainfo).hash != hash) {
        throw const FormatException('Embedded resume metainfo hash mismatch');
      }
    }
    final added = root['added_time'];
    return QbittorrentResume._(
      MagnetLink.parse(uri),
      List.unmodifiable(trackers),
      _text(root['qBt-savePath']) ?? _text(root['save_path']),
      _text(root['qBt-category']),
      added is int && added > 0 && added <= 8640000000000 ? added * 1000 : null,
      metainfo,
    );
  }

  static String? _text(Object? value) {
    if (value is! Uint8List) return null;
    final text = utf8
        .decode(value.take(16384).toList(), allowMalformed: true)
        .replaceAll(RegExp(r'[\x00-\x1f"]'), '')
        .trim();
    return text.isEmpty ? null : text;
  }
}

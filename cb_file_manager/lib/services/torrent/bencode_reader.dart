import 'dart:convert';
import 'dart:typed_data';

/// Bounded-depth decoding, retaining exact root info bytes for identity checks.
class BencodeReader {
  final Uint8List bytes;
  int offset = 0;
  int? infoStart;
  int? infoEnd;
  BencodeReader(this.bytes);

  Object read([int depth = 0]) {
    if (depth > 64 || offset >= bytes.length) {
      throw const FormatException('Truncated or deeply nested bencode');
    }
    final type = bytes[offset++];
    if (type == 105) {
      final start = offset;
      while (offset < bytes.length && bytes[offset] != 101) {
        offset++;
      }
      if (offset == bytes.length) {
        throw const FormatException('Unterminated integer');
      }
      final raw = ascii.decode(bytes.sublist(start, offset++));
      if (!RegExp(r'^(0|-?[1-9][0-9]*)$').hasMatch(raw)) {
        throw const FormatException('Invalid integer');
      }
      return int.parse(raw);
    }
    if (type == 108 || type == 100) {
      final list = <Object>[];
      final map = <String, Object>{};
      while (offset < bytes.length && bytes[offset] != 101) {
        if (type == 108) {
          list.add(read(depth + 1));
        } else {
          final key = read(depth + 1);
          if (key is! Uint8List) {
            throw const FormatException('Invalid dictionary key');
          }
          final name = utf8.decode(key, allowMalformed: true);
          if (map.containsKey(name)) {
            throw const FormatException('Duplicate dictionary key');
          }
          final start = offset;
          map[name] = read(depth + 1);
          if (depth == 0 && name == 'info') {
            infoStart = start;
            infoEnd = offset;
          }
        }
      }
      if (offset == bytes.length) {
        throw const FormatException('Unterminated collection');
      }
      offset++;
      return type == 108 ? list : map;
    }
    if (type < 48 || type > 57) throw const FormatException('Invalid bencode');
    final start = offset - 1;
    while (offset < bytes.length && bytes[offset] != 58) {
      if (bytes[offset] < 48 || bytes[offset] > 57) {
        throw const FormatException('Invalid string length');
      }
      offset++;
    }
    if (offset == bytes.length) throw const FormatException('Truncated string');
    final size = int.parse(ascii.decode(bytes.sublist(start, offset++)));
    if (size < 0 || size > bytes.length - offset) {
      throw const FormatException('Truncated string');
    }
    final result = Uint8List.sublistView(bytes, offset, offset + size);
    offset += size;
    return result;
  }
}

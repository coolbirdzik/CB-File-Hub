import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Read-only, bounded reader for Chromium IndexedDB's LevelDB backing store.
/// Uses CURRENT/MANIFEST and sequence numbers, including tombstones, rather
/// than carving old files (which can resurrect deleted credentials).
/// Formats: google/leveldb doc/{log_format,table_format}.md and Chromium's
/// content/browser/indexed_db/indexed_db_leveldb_coding.* / V8 value-serializer.
class ChromiumIndexedDb {
  static const maxBytes = 128 * 1024 * 1024;
  final String directory;
  final _records = <String, _Record>{};
  final databaseNames = <String>[];
  int get recordCount => _records.length;
  int _bytes = 0;
  ChromiumIndexedDb(this.directory);

  Future<Uint8List> _file(String name) async {
    final file = File(p.join(directory, name));
    final size = await file.length();
    _bytes += size;
    if (size > maxBytes || _bytes > maxBytes) {
      throw const FormatException('limit');
    }
    return file.readAsBytes();
  }

  Future<Map<String, List<Map<String, dynamic>>>> readTables(
    Set<String> wanted,
  ) async {
    final current = (await File(
      p.join(directory, 'CURRENT'),
    ).readAsString()).trim();
    if (!RegExp(r'^MANIFEST-\d+$').hasMatch(current)) {
      throw const FormatException('manifest');
    }
    final active = <int>{};
    var logNumber = 0, previousLog = 0;
    for (final bytes in _logs(await _file(current))) {
      final c = _Cursor(bytes);
      while (c.remaining > 0) {
        switch (c.uint()) {
          case 1:
            c.blob(); // comparator
          case 2:
            logNumber = c.uint();
          case 3:
            c.uint(); // next file number
          case 4:
            c.uint(); // last sequence
          case 5:
            c.uint();
            c.blob(); // compaction pointer
          case 6:
            c.uint();
            active.remove(c.uint());
          case 7:
            c.uint();
            final number = c.uint();
            c.uint();
            c.blob();
            c.blob();
            active.add(number);
          case 9:
            previousLog = c.uint();
          default:
            throw const FormatException('manifest version');
        }
      }
    }
    if (active.length > 512) throw const FormatException('limit');
    for (final number in active) {
      final stem = number.toString().padLeft(6, '0');
      final name = await File(p.join(directory, '$stem.ldb')).exists()
          ? '$stem.ldb'
          : '$stem.sst';
      _table(await _file(name));
    }
    final logs = <String>[];
    await for (final entry in Directory(directory).list(followLinks: false)) {
      final match = RegExp(r'^(\d+)\.log$').firstMatch(p.basename(entry.path));
      if (entry is File && match != null) {
        final number = int.parse(match[1]!);
        if (number >= logNumber || number == previousLog) {
          logs.add(p.basename(entry.path));
        }
      }
    }
    if (logs.length > 32) throw const FormatException('limit');
    for (final file in logs..sort()) {
      for (final batch in _logs(await _file(file))) {
        final c = _Cursor(batch);
        final sequence = c.le(8), count = c.le(4);
        if (count > 100000) throw const FormatException('limit');
        for (var i = 0; i < count; i++) {
          final type = c.byte();
          if (type != 0 && type != 1) throw const FormatException('batch type');
          final key = c.blob();
          _put(key, type == 1 ? c.blob() : null, sequence + i);
        }
        if (c.remaining != 0) throw const FormatException('batch length');
      }
    }
    final names = <int, String>{};
    final stores = <int, int>{};
    for (final r in _records.values.where((r) => r.value != null)) {
      final c = _Cursor(r.key);
      final prefix = c.prefix();
      if (prefix == (0, 0, 0) && c.remaining > 0 && c.byte() == 201) {
        c.take(c.uint() * 2); // origin
        final name = _utf16(c.take(c.uint() * 2), Endian.big);
        names[_Cursor(r.value!).le(r.value!.length)] = name;
      } else if (prefix.$1 > 0 &&
          prefix.$2 == 0 &&
          prefix.$3 == 0 &&
          c.remaining == 1 &&
          c.byte() == 1) {
        names[prefix.$1] = _utf16(r.value!, Endian.big);
      } else if (prefix.$2 > 0 && prefix.$3 == 1) {
        stores.update(
          prefix.$1,
          (s) => s < prefix.$2 ? s : prefix.$2,
          ifAbsent: () => prefix.$2,
        );
      }
    }
    databaseNames
      ..clear()
      ..addAll(names.values);
    final result = <String, List<Map<String, dynamic>>>{};
    for (final r in _records.values.where((r) => r.value != null)) {
      final c = _Cursor(r.key);
      final (db, store, index) = c.prefix();
      final name = names[db];
      if (!wanted.contains(name) || store != stores[db] || index != 1) continue;
      final value = _Cursor(r.value!)..uint(); // IndexedDB value version
      final object = _blink(value.take(value.remaining));
      if (object is! Map<String, dynamic>) {
        throw const FormatException('record type');
      }
      result.putIfAbsent(name!, () => []).add(object);
    }
    return result;
  }

  void _put(Uint8List key, Uint8List? value, int sequence) {
    if (_records.length > 200000) throw const FormatException('limit');
    final id = base64Encode(key);
    final old = _records[id];
    if (old == null || sequence >= old.sequence) {
      _records[id] = _Record(key, value, sequence);
    }
  }

  void _table(Uint8List bytes) {
    if (bytes.length < 48) throw const FormatException('table');
    final footer = _Cursor(Uint8List.sublistView(bytes, bytes.length - 48));
    footer.uint();
    footer.uint(); // metaindex handle
    final indexOffset = footer.uint(), indexLength = footer.uint();
    final magic = Uint8List.sublistView(bytes, bytes.length - 8);
    if (base64Encode(magic) != 'V/uAiyR1R9s=') {
      throw const FormatException('table magic');
    }
    for (final entry in _blockEntries(
      _block(bytes, indexOffset, indexLength),
    )) {
      final handle = _Cursor(entry.$2);
      for (final record in _blockEntries(
        _block(bytes, handle.uint(), handle.uint()),
      )) {
        if (record.$1.length < 8) throw const FormatException('internal key');
        final length = record.$1.length - 8;
        final tag = _Cursor(Uint8List.sublistView(record.$1, length)).le(8);
        final type = tag & 255;
        if (type != 0 && type != 1) throw const FormatException('table type');
        _put(
          Uint8List.sublistView(record.$1, 0, length),
          type == 1 ? record.$2 : null,
          tag >>> 8,
        );
      }
    }
  }

  Uint8List _block(Uint8List bytes, int offset, int length) {
    if (offset < 0 || length < 0 || offset + length + 5 > bytes.length) {
      throw const FormatException('block');
    }
    final compressed = Uint8List.sublistView(bytes, offset, offset + length);
    final type = bytes[offset + length];
    final checksum = _Cursor(
      Uint8List.sublistView(bytes, offset + length + 1, offset + length + 5),
    ).le(4);
    if (maskedCrc32c([...compressed, type]) != checksum) {
      throw const FormatException('checksum');
    }
    return switch (type) {
      0 => compressed,
      1 => decodeSnappy(compressed),
      _ => throw const FormatException('compression'),
    };
  }
}

class _Record {
  final Uint8List key;
  final Uint8List? value;
  final int sequence;
  _Record(this.key, this.value, this.sequence);
}

Iterable<(Uint8List, Uint8List)> _blockEntries(Uint8List bytes) sync* {
  if (bytes.length < 4) throw const FormatException('restarts');
  final count = _Cursor(Uint8List.sublistView(bytes, bytes.length - 4)).le(4);
  final end = bytes.length - 4 - count * 4;
  if (count == 0 || end < 0) throw const FormatException('restarts');
  final c = _Cursor(Uint8List.sublistView(bytes, 0, end));
  var previous = Uint8List(0);
  while (c.remaining > 0) {
    final shared = c.uint(), size = c.uint(), valueSize = c.uint();
    if (shared > previous.length) throw const FormatException('prefix');
    final key = Uint8List.fromList([...previous.take(shared), ...c.take(size)]);
    yield (key, c.take(valueSize));
    previous = key;
  }
}

Iterable<Uint8List> _logs(Uint8List bytes) sync* {
  final fragments = BytesBuilder(copy: false);
  var assembling = false;
  for (var start = 0; start < bytes.length; start += 32768) {
    final end = (start + 32768).clamp(0, bytes.length);
    var offset = start;
    while (offset + 7 <= end) {
      final c = _Cursor(Uint8List.sublistView(bytes, offset, offset + 7));
      final checksum = c.le(4), length = c.le(2), type = c.byte();
      if (checksum == 0 && length == 0 && type == 0) break;
      if (offset + 7 + length > end) {
        if (end == bytes.length) return; // incomplete tail of a live WAL
        throw const FormatException('log length');
      }
      final data = Uint8List.sublistView(
        bytes,
        offset + 7,
        offset + 7 + length,
      );
      if (maskedCrc32c([type, ...data]) != checksum) {
        throw const FormatException('checksum');
      }
      offset += 7 + length;
      switch (type) {
        case 1:
          if (assembling) throw const FormatException('log fragments');
          yield data;
        case 2:
          if (assembling) throw const FormatException('log fragments');
          assembling = true;
          fragments.add(data);
        case 3:
        case 4:
          if (!assembling) throw const FormatException('log fragments');
          fragments.add(data);
          if (fragments.length > 16 * 1024 * 1024) {
            throw const FormatException('limit');
          }
          if (type == 4) {
            assembling = false;
            yield fragments.takeBytes();
          }
        default:
          throw const FormatException('log type');
      }
    }
  }
}

/// Raw Snappy blocks used by LevelDB and Chromium value wrapping.
Uint8List decodeSnappy(Uint8List bytes) {
  final c = _Cursor(bytes);
  final size = c.uint();
  if (size > 16 * 1024 * 1024) throw const FormatException('limit');
  final out = Uint8List(size);
  var at = 0;
  while (c.remaining > 0) {
    final tag = c.byte(), type = tag & 3;
    int length, distance;
    if (type == 0) {
      final n = tag >> 2;
      length = n < 60 ? n + 1 : c.le(n - 59) + 1;
      if (at + length > size) throw const FormatException('snappy literal');
      out.setRange(at, at + length, c.take(length));
      at += length;
      continue;
    }
    if (type == 1) {
      length = 4 + ((tag >> 2) & 7);
      distance = ((tag & 224) << 3) | c.byte();
    } else {
      length = 1 + (tag >> 2);
      distance = c.le(type == 2 ? 2 : 4);
    }
    if (distance <= 0 || distance > at || at + length > size) {
      throw const FormatException('snappy copy');
    }
    for (var i = 0; i < length; i++) {
      out[at] = out[at - distance];
      at++;
    }
  }
  if (at != size) throw const FormatException('snappy size');
  return out;
}

final _crcTable = List<int>.generate(256, (n) {
  var crc = n;
  for (var i = 0; i < 8; i++) {
    crc = (crc >>> 1) ^ ((crc & 1) == 0 ? 0 : 0x82f63b78);
  }
  return crc;
});
int maskedCrc32c(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 255] ^ (crc >>> 8);
  }
  crc = (crc ^ 0xffffffff) & 0xffffffff;
  return (((crc >>> 15) | (crc << 17)) + 0xa282ead8) & 0xffffffff;
}

String _utf16(Uint8List bytes, Endian endian) {
  if (bytes.length.isOdd) throw const FormatException('utf16');
  final data = ByteData.sublistView(bytes);
  return String.fromCharCodes([
    for (var i = 0; i < bytes.length; i += 2) data.getUint16(i, endian),
  ]);
}

dynamic _blink(Uint8List bytes, [int depth = 0]) {
  if (depth > 4) throw const FormatException('wrapping');
  final c = _Cursor(bytes);
  if (c.byte() != 255) throw const FormatException('blink');
  final version = c.uint();
  if (version == 17) {
    if (c.byte() != 2) throw const FormatException('external blob');
    return _blink(decodeSnappy(c.take(c.remaining)), depth + 1);
  }
  if (version >= 21) {
    if (c.byte() != 0xfe) throw const FormatException('trailer');
    c.take(12);
  }
  return _V8(c).read();
}

class _V8 {
  final _Cursor c;
  final objects = <dynamic>[];
  _V8(this.c);
  dynamic read([int depth = 0]) {
    if (depth > 64 || objects.length > 10000) {
      throw const FormatException('v8 limit');
    }
    var tag = c.byte();
    while (tag == 0) {
      tag = c.byte();
    }
    switch (tag) {
      case 255:
        if (c.uint() > 15) throw const FormatException('v8 version');
        return read(depth);
      case 63:
        c.uint();
        return read(depth);
      case 48:
      case 95:
      case 45:
        return null;
      case 84:
        return true;
      case 70:
        return false;
      case 73:
        final n = c.uint();
        return (n >>> 1) ^ -(n & 1);
      case 85:
        return c.uint();
      case 78:
        return ByteData.sublistView(c.take(8)).getFloat64(0, Endian.little);
      case 34:
        return latin1.decode(c.blob());
      case 83:
        return utf8.decode(c.blob());
      case 99:
        return _utf16(c.blob(), Endian.little);
      case 94:
        final index = c.uint();
        if (index >= objects.length) {
          throw const FormatException('v8 reference');
        }
        return objects[index];
      case 111:
        final result = <String, dynamic>{};
        objects.add(result);
        while (c.peek() != 123) {
          final key = read(depth + 1);
          if (key is! String && key is! num) {
            throw const FormatException('v8 property');
          }
          result['$key'] = read(depth + 1);
        }
        c.byte();
        if (c.uint() != result.length) {
          throw const FormatException('v8 properties');
        }
        return result;
      case 65:
      case 97:
        final length = c.uint();
        if (length > 10000) throw const FormatException('v8 array');
        final result = List<dynamic>.filled(length, null);
        objects.add(result);
        if (tag == 65) {
          for (var i = 0; i < length; i++) {
            result[i] = read(depth + 1);
          }
        }
        var count = 0;
        final end = tag == 65 ? 36 : 64;
        while (c.peek() != end) {
          final key = read(depth + 1), value = read(depth + 1);
          count++;
          final index = int.tryParse('$key');
          if (index != null && index >= 0 && index < length) {
            result[index] = value;
          }
        }
        c.byte();
        if (c.uint() != count || c.uint() != length) {
          throw const FormatException('v8 array properties');
        }
        return result;
      case 68:
        final millis = ByteData.sublistView(
          c.take(8),
        ).getFloat64(0, Endian.little);
        final value = DateTime.fromMillisecondsSinceEpoch(
          millis.toInt(),
          isUtc: true,
        ).toIso8601String();
        objects.add(value);
        return value;
      default:
        throw const FormatException('unsupported v8 value');
    }
  }
}

class _Cursor {
  final Uint8List data;
  int at = 0;
  _Cursor(this.data);
  int get remaining => data.length - at;
  int peek() {
    if (remaining <= 0) throw const FormatException('truncated');
    return data[at];
  }

  int byte() {
    final v = peek();
    at++;
    return v;
  }

  Uint8List take(int n) {
    if (n < 0 || n > remaining) throw const FormatException('truncated');
    final start = at;
    at += n;
    return Uint8List.sublistView(data, start, at);
  }

  int uint() {
    var result = 0;
    for (var i = 0; i < 10; i++) {
      final b = byte();
      result |= (b & 127) << (i * 7);
      if (b < 128) return result;
    }
    throw const FormatException('varint');
  }

  int le(int n) {
    if (n > 8) throw const FormatException('integer');
    var v = 0;
    for (var i = 0; i < n; i++) {
      v |= byte() << (i * 8);
    }
    return v;
  }

  Uint8List blob() => take(uint());
  (int, int, int) prefix() {
    final b = byte();
    return (le((b >> 5) + 1), le(((b >> 2) & 7) + 1), le((b & 3) + 1));
  }
}

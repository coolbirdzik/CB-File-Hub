import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings.dart' as b;

/// Copies a buffer returned by the Rust library into Dart memory and frees it.
Uint8List takeBuffer(Pointer<Uint8> ptr, int len) {
  if (ptr == nullptr || len == 0) return Uint8List(0);
  final copy = Uint8List.fromList(ptr.asTypedList(len));
  b.cb_buffer_free(ptr, len);
  return copy;
}

/// Bytes copied into [Arena] memory for one call into the Rust library.
class Utf8Arg {
  const Utf8Arg(this.ptr, this.length);

  final Pointer<Uint8> ptr;
  final int length;

  static Utf8Arg of(String value, Arena arena) =>
      bytes(utf8.encode(value), arena);

  static Utf8Arg bytes(List<int> data, Arena arena) {
    if (data.isEmpty) return Utf8Arg(nullptr, 0);
    final ptr = arena<Uint8>(data.length);
    ptr.asTypedList(data.length).setAll(0, data);
    return Utf8Arg(ptr, data.length);
  }
}

/// Little-endian writer matching `wire::Reader` in the Rust crate.
class WireWriter {
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  final ByteData _scratch = ByteData(8);

  void _put(int length) =>
      _bytes.add(Uint8List.fromList(_scratch.buffer.asUint8List(0, length)));

  void u8(int value) => _bytes.addByte(value);

  void boolean(bool value) => u8(value ? 1 : 0);

  void u32(int value) {
    _scratch.setUint32(0, value, Endian.little);
    _put(4);
  }

  void i32(int value) {
    _scratch.setInt32(0, value, Endian.little);
    _put(4);
  }

  /// Also used for u64 fields; values stay below 2^63.
  void i64(int value) {
    _scratch.setInt64(0, value, Endian.little);
    _put(8);
  }

  void str(String value) {
    final encoded = utf8.encode(value);
    u32(encoded.length);
    _bytes.add(encoded);
  }

  void strs(Iterable<String> values) {
    final list = values.toList(growable: false);
    u32(list.length);
    list.forEach(str);
  }

  void raw(Uint8List value) => _bytes.add(value);

  int get length => _bytes.length;

  Uint8List takeBytes() => _bytes.takeBytes();
}

/// Little-endian reader matching `wire::Writer` in the Rust crate.
class WireReader {
  WireReader(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _offset = 0;

  bool get isDone => _offset >= _bytes.length;

  int u8() => _data.getUint8(_offset++);

  bool boolean() => u8() != 0;

  int u32() {
    final value = _data.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  int i32() {
    final value = _data.getInt32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  /// Also used for u64 fields: sizes, FILETIMEs and counts stay below 2^63,
  /// so the signed read is exact.
  int i64() {
    final value = _data.getInt64(_offset, Endian.little);
    _offset += 8;
    return value;
  }

  String str() {
    final length = u32();
    final value = utf8.decode(
      Uint8List.sublistView(_bytes, _offset, _offset + length),
      allowMalformed: true,
    );
    _offset += length;
    return value;
  }

  /// The remaining bytes, as a view.
  Uint8List rest() {
    final view = Uint8List.sublistView(_bytes, _offset);
    _offset = _bytes.length;
    return view;
  }
}

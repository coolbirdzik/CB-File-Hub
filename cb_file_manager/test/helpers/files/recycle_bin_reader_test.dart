import 'dart:io';
import 'dart:typed_data';

import 'package:cb_file_manager/helpers/files/recycle_bin_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late File metadata;
  late String payload;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cb_recycle_metadata_');
    metadata = File(p.join(temp.path, r'$Iexample.mp4'));
    payload = p.join(temp.path, r'$Rexample.mp4');
    final path = '${p.join(temp.path, 'original.mp4')}\u0000';
    final data = ByteData(28 + path.length * 2)
      ..setInt64(0, 2, Endian.little)
      ..setInt64(8, 123, Endian.little)
      ..setInt64(16, 133000000000000000, Endian.little)
      ..setInt32(24, path.length, Endian.little);
    for (var i = 0; i < path.length; i++) {
      data.setUint16(28 + i * 2, path.codeUnitAt(i), Endian.little);
    }
    await metadata.writeAsBytes(data.buffer.asUint8List());
  });
  tearDown(() async => temp.delete(recursive: true));

  test('omits orphan metadata whose payload has already been deleted', () {
    expect(readRecycleBinMetadata(metadata), isNull);
  });
  test('reads an existing file payload', () async {
    await File(payload).writeAsString('video');
    final item = readRecycleBinMetadata(metadata)!;
    expect(item.recycleBinPath, payload);
    expect(item.size, 123);
    expect(item.isFolder, isFalse);
  });
  test('reads an existing directory payload', () async {
    await Directory(payload).create();
    expect(readRecycleBinMetadata(metadata)!.isFolder, isTrue);
  });
}

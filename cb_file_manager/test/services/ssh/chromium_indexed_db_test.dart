import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/ssh/chromium_indexed_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

List<int> uint(int n) {
  final out = <int>[];
  do {
    final byte = n & 127;
    n >>>= 7;
    out.add(byte | (n == 0 ? 0 : 128));
  } while (n != 0);
  return out;
}

List<int> le(int n, int length) => [
  for (var i = 0; i < length; i++) (n >>> (i * 8)) & 255,
];
List<int> blob(List<int> bytes) => [...uint(bytes.length), ...bytes];
List<int> utf16be(String s) => [
  for (final unit in s.codeUnits) ...[unit >> 8, unit & 255],
];
List<int> v8(dynamic value) {
  if (value is String) return [83, ...blob(utf8.encode(value))];
  if (value is Map) {
    return [
      111,
      for (final e in value.entries) ...[...v8(e.key), ...v8(e.value)],
      123,
      ...uint(value.length),
    ];
  }
  if (value is int) return [85, ...uint(value)];
  throw UnsupportedError('fixture type');
}

List<int> row(String host) => [
  1,
  255,
  16,
  255,
  15,
  ...v8({'address': host, 'id': 1}),
];
final databaseName = [
  0,
  0,
  0,
  0,
  201,
  ...uint(7),
  ...utf16be('file://'),
  ...uint(5),
  ...utf16be('hosts'),
];
final firstHost = [0, 1, 1, 1, 1];
final secondHost = [0, 1, 1, 1, 2];

List<int> log(List<int> payload) {
  final out = <int>[];
  for (var offset = 0; offset < payload.length;) {
    final length = (payload.length - offset).clamp(0, 32761);
    final fragment = payload.sublist(offset, offset + length);
    final type = offset == 0
        ? (length == payload.length ? 1 : 2)
        : (offset + length == payload.length ? 4 : 3);
    out.addAll([
      ...le(maskedCrc32c([type, ...fragment]), 4),
      ...le(length, 2),
      type,
      ...fragment,
    ]);
    offset += length;
  }
  return out;
}

List<int> batch(int sequence, List<(List<int>, List<int>?)> changes) => log([
  ...le(sequence, 8),
  ...le(changes.length, 4),
  for (final change in changes) ...[
    change.$2 == null ? 0 : 1,
    ...blob(change.$1),
    if (change.$2 != null) ...blob(change.$2!),
  ],
]);

List<int> tableBlock(List<(List<int>, List<int>)> entries) => [
  for (final e in entries) ...[
    0,
    ...uint(e.$1.length),
    ...uint(e.$2.length),
    ...e.$1,
    ...e.$2,
  ],
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
];
List<int> trailer(List<int> block) => [
  ...block,
  0,
  ...le(maskedCrc32c([...block, 0]), 4),
];

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cb-idb-test-');
    await File(p.join(root.path, 'CURRENT')).writeAsString('MANIFEST-000001\n');
    await File(p.join(root.path, 'MANIFEST-000001')).writeAsBytes(log([2, 2]));
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'uses current manifest/WAL and tombstones; does not resurrect stale credentials',
    () async {
      await File(
        p.join(root.path, '000001.log'),
      ).writeAsBytes(batch(999, [(firstHost, row('stale.test'))]));
      await File(
        p.join(root.path, '999999.ldb'),
      ).writeAsBytes([1, 2, 3]); // inactive table, ignored
      await File(p.join(root.path, '000002.log')).writeAsBytes([
        ...batch(100, [
          (databaseName, [1]),
          (firstHost, row('deleted.test')),
          (secondHost, row('old.test')),
        ]),
        ...batch(200, [(firstHost, null), (secondHost, row('current.test'))]),
        ...[1, 2], // partially written WAL tail is ignored
      ]);
      final tables = await ChromiumIndexedDb(root.path).readTables({'hosts'});
      expect(tables['hosts']!.single['address'], 'current.test');
    },
  );

  test(
    'reads active SST blocks with internal sequence keys and validates checksums',
    () async {
      final data = tableBlock([
        ([...databaseName, ...le((100 << 8) | 1, 8)], [1]),
        ([...firstHost, ...le((101 << 8) | 1, 8)], row('from-table.test')),
      ]);
      final dataWithTrailer = trailer(data);
      final index = tableBlock([
        ([0], [...uint(0), ...uint(data.length)]),
      ]);
      final handles = [
        0,
        0,
        ...uint(dataWithTrailer.length),
        ...uint(index.length),
      ];
      final table = [
        ...dataWithTrailer,
        ...trailer(index),
        ...handles,
        ...List<int>.filled(40 - handles.length, 0),
        0x57,
        0xfb,
        0x80,
        0x8b,
        0x24,
        0x75,
        0x47,
        0xdb,
      ];
      await File(p.join(root.path, '000003.ldb')).writeAsBytes(table);
      await File(
        p.join(root.path, 'MANIFEST-000001'),
      ).writeAsBytes(log([2, 4, 7, 0, 3, ...uint(table.length), 0, 0]));
      final result = await ChromiumIndexedDb(root.path).readTables({'hosts'});
      expect(result['hosts']!.single['address'], 'from-table.test');
      table[10] ^= 1;
      await File(p.join(root.path, '000003.ldb')).writeAsBytes(table);
      await expectLater(
        ChromiumIndexedDb(root.path).readTables({'hosts'}),
        throwsFormatException,
      );
    },
  );

  test(
    'joins fragmented WAL records and rejects corrupt completed records',
    () async {
      final large = List.filled(40000, 'x').join();
      final content = batch(100, [
        (databaseName, [1]),
        (firstHost, row(large)),
      ]);
      await File(p.join(root.path, '000002.log')).writeAsBytes(content);
      expect(
        (await ChromiumIndexedDb(
          root.path,
        ).readTables({'hosts'}))['hosts']!.single['address'],
        large,
      );
      content[12] ^= 1;
      await File(p.join(root.path, '000002.log')).writeAsBytes(content);
      await expectLater(
        ChromiumIndexedDb(root.path).readTables({'hosts'}),
        throwsFormatException,
      );
    },
  );
}

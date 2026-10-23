import 'dart:typed_data';
import 'package:cb_file_manager/services/torrent/torrent_metainfo.dart';
import 'package:cb_native/cb_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'torrent_fixtures.dart';

void main() {
  final skip = CbNative.isAvailable ? null : 'Rust library not built';
  test(
    'native metainfo matches every Dart field for original unsorted info',
    () async {
      for (final bytes in [
        torrentBytes(),
        torrentBytes(info: torrentInfo(name: 'Ảnh.txt', size: 0)),
        Uint8List.fromList(
          bencode({
            'announce-list': [
              [' https://one/ ', 'https://one/'],
              ['udp://two:80'],
            ],
            'announce': 'https://three/',
            'comment.utf-8': 'Ghi chú',
            'created by': 'x' * 5000,
            'creation date': 1700000000,
            'info': {
              'private': 1,
              'name': 'bundle',
              'files': [
                {
                  'path': ['Âm nhạc', 'a.MP3'],
                  'length': 4,
                },
                {
                  'path': ['b.flac'],
                  'length': 4,
                },
              ],
              'piece length': 16,
              'pieces': Uint8List(20),
            },
          }),
        ),
      ]) {
        final native = await NativeTorrentMetainfo.parse(bytes);
        expect(native, isNotNull);
        final dart = TorrentMetainfo.parse(bytes);
        expect(
          [
            native!.hash,
            native.name,
            native.totalBytes,
            native.fileCount,
            native.category,
            native.trackers,
            native.comment,
            native.createdBy,
            native.creationDate,
            native.isPrivate,
            native.pieceLength,
            native.pieceCount,
          ],
          [
            dart.hash,
            dart.name,
            dart.totalBytes,
            dart.fileCount,
            dart.category,
            dart.trackers,
            dart.comment,
            dart.createdBy,
            dart.creationDate,
            dart.isPrivate,
            dart.pieceLength,
            dart.pieceCount,
          ],
        );
        expect((await TorrentMetainfo.parseAsync(bytes)).hash, dart.hash);
        expect(
          (await TorrentMetainfo.parseAsync(bytes, useNative: false)).hash,
          dart.hash,
        );
      }
    },
    skip: skip,
  );

  test(
    'native rejects unsafe paths, corrupt pieces and truncated bencode',
    () async {
      for (final bytes in [
        for (final name in ['../x', 'NUL.txt', 'COM1', 'x.', 'x/y'])
          torrentBytes(name: name),
        torrentBytes(info: torrentInfo()..['pieces'] = Uint8List(19)),
        torrentBytes(info: torrentInfo()..['length'] = -1),
        Uint8List.fromList([100, 52, 58, 105]),
        Uint8List.fromList([...torrentBytes(), 101]),
        Uint8List.fromList(
          bencode({
            'info': {'name': 'v2', 'meta version': 2},
          }),
        ),
      ]) {
        expect(await NativeTorrentMetainfo.parse(bytes), isNull);
        await expectLater(
          TorrentMetainfo.parseAsync(bytes),
          throwsFormatException,
        );
      }
    },
    skip: skip,
  );
}

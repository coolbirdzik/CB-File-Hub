import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cb_file_manager/services/torrent/torrent_metainfo.dart';
import 'torrent_fixtures.dart';

void main() {
  test(
    'extracts bounded tracker and creation metadata without changing identity',
    () {
      final info = {...torrentInfo(), 'private': 1};
      final metadata = TorrentMetainfo.parse(
        Uint8List.fromList(
          bencode({
            'announce': 'https://one.example/announce',
            'announce-list': [
              ['https://one.example/announce'],
              ['udp://two.example:80', 'https://one.example/announce'],
            ],
            'creation date': 1700000000,
            'created by': 'qBittorrent',
            'comment.utf-8': 'Ghi chú',
            'info': info,
          }),
        ),
      );
      expect(metadata.hash, sha1.convert(bencode(info)).toString());
      expect(metadata.trackers, [
        'https://one.example/announce',
        'udp://two.example:80',
      ]);
      expect(metadata.creationDate, 1700000000000);
      expect(metadata.createdBy, 'qBittorrent');
      expect(metadata.comment, 'Ghi chú');
      expect(metadata.isPrivate, isTrue);
      expect(metadata.pieceLength, 16384);
      expect(metadata.pieceCount, 1);
    },
  );

  test(
    'optional malformed metadata does not reject an otherwise valid torrent',
    () {
      final metadata = TorrentMetainfo.parse(
        Uint8List.fromList(
          bencode({
            'announce-list': 1,
            'creation date': -1,
            'created by': 9,
            'comment': 'x' * 5000,
            'info': torrentInfo(),
          }),
        ),
      );
      expect(metadata.trackers, isEmpty);
      expect(metadata.creationDate, isNull);
      expect(metadata.createdBy, isNull);
      expect(metadata.comment!.length, 4096);
      expect(metadata.isPrivate, isFalse);
    },
  );
  test('identity uses original info bytes and ignores tracker differences', () {
    final info = torrentInfo(); // Deliberately not sorted lexicographically.
    final expected = sha1.convert(bencode(info)).toString();
    final first = TorrentMetainfo.parse(
      torrentBytes(info: info, tracker: 'http://a/announce'),
    );
    final second = TorrentMetainfo.parse(
      torrentBytes(info: info, tracker: 'http://b/announce'),
    );
    expect(first.hash, expected);
    expect(second.hash, expected);
    expect(first.name, 'example.mp4');
    expect(first.category, 'video');
    expect(first.totalBytes, 4);
  });

  test('multifile unicode metadata counts size and content category', () {
    final metadata = TorrentMetainfo.parse(
      torrentBytes(
        info: {
          'name': 'Âm nhạc',
          'files': <Object>[
            {
              'length': 3,
              'path': <Object>['Album', 'Một.flac'],
            },
            {
              'length': 5,
              'path': <Object>['Album', 'Hai.mp3'],
            },
          ],
          'piece length': 16,
          'pieces': Uint8List(20),
        },
      ),
    );
    expect(metadata.fileCount, 2);
    expect(metadata.totalBytes, 8);
    expect(metadata.category, 'audio');
  });

  for (final name in [
    '../escape',
    '..',
    'C:\\escape',
    '/etc/passwd',
    'x/y',
    'nul.txt',
    'COM1',
    'trailing.',
    'trailing ',
    'bad\u0000name',
  ]) {
    test('rejects unsafe name $name', () {
      expect(
        () => TorrentMetainfo.parse(torrentBytes(name: name)),
        throwsFormatException,
      );
    });
  }

  test('valid utf8 alternate cannot hide an unsafe legacy path', () {
    final info = torrentInfo(name: '../escape')..['name.utf-8'] = 'safe';
    expect(
      () => TorrentMetainfo.parse(torrentBytes(info: info)),
      throwsFormatException,
    );
  });

  test('rejects duplicate file targets on case insensitive volumes', () {
    expect(
      () => TorrentMetainfo.parse(
        torrentBytes(
          info: {
            'name': 'bundle',
            'files': <Object>[
              {
                'length': 1,
                'path': <Object>['A.mp4'],
              },
              {
                'length': 1,
                'path': <Object>['a.mp4'],
              },
            ],
            'piece length': 16,
            'pieces': Uint8List(20),
          },
        ),
      ),
      throwsFormatException,
    );
  });

  test('rejects corrupt hashes, negative sizes and pure v2', () {
    for (final info in [
      torrentInfo()..['pieces'] = Uint8List(19),
      torrentInfo()..['length'] = -1,
      <String, Object>{
        'name': 'v2',
        'meta version': 2,
        'file tree': <String, Object>{},
      },
    ]) {
      expect(
        () => TorrentMetainfo.parse(torrentBytes(info: info)),
        throwsFormatException,
      );
    }
  });

  test('rejects truncated, trailing and excessive nesting metainfo', () {
    final valid = torrentBytes();
    for (final bytes in [
      valid.sublist(0, valid.length - 1),
      [...valid, 101],
      [...List.filled(70, 108), ...List.filled(70, 101)],
      [100, 52, 58, 105],
    ]) {
      expect(
        () => TorrentMetainfo.parse(Uint8List.fromList(bytes)),
        throwsFormatException,
      );
    }
  });
}

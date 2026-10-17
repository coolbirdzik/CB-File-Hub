import 'package:cb_file_manager/services/torrent/magnet_link.dart';
import 'package:cb_file_manager/services/torrent/torrent_launch_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hash = '0123456789abcdef0123456789abcdef01234567';
  test('hex, base32, unicode names and tracker parameters are preserved', () {
    final link = MagnetLink.parse(
      'magnet:?xt=urn:btih:${hash.toUpperCase()}&dn=Phim%20Vi%E1%BB%87t&tr=https%3A%2F%2Ftracker.example%2Fannounce',
    );
    expect(link.hash, hash);
    expect(link.name, 'Phim Việt');
    expect(
      Uri.parse(link.uri).queryParameters['tr'],
      'https://tracker.example/announce',
    );
    expect(
      MagnetLink.parse(
        'magnet:?xt=urn:btih:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      ).hash,
      '0' * 40,
    );
    expect(
      MagnetLink.parse(
        'magnet:?xt=urn:btih:77777777777777777777777777777777',
      ).hash,
      'f' * 40,
    );
  });
  test('invalid, ambiguous and pure v2 magnets are rejected', () {
    for (final value in [
      'https://example.com/',
      'magnet://host/path?xt=urn:btih:$hash',
      'magnet:?xt=urn:btih:invalid',
      'magnet:?xt=urn:btmh:1220abc',
      'magnet:?xt=urn:btih:$hash&xt=urn:btih:${'f' * 40}',
      'magnet:?xt=urn:btih:$hash\n',
      'magnet:?xt=urn:btih:$hash"',
    ]) {
      expect(
        () => MagnetLink.parse(value),
        throwsFormatException,
        reason: value,
      );
    }
  });
  test(
    'metainfo export encodes names, retains trackers and never copies HTTP source as a magnet',
    () {
      final link = MagnetLink.fromMetadata(
        hash: hash.toUpperCase(),
        name: 'Phim Việt & #1 🎬',
        sourceUri: 'https://example.com/source.torrent',
        trackers: [
          'udp://tracker.example:80/announce',
          'https://tracker.example/announce?key=a&b=2',
          'udp://tracker.example:80/announce',
        ],
      );
      expect(link.hash, hash);
      expect(link.name, 'Phim Việt & #1 🎬');
      expect(Uri.parse(link.uri).queryParametersAll['tr'], [
        'udp://tracker.example:80/announce',
        'https://tracker.example/announce?key=a&b=2',
      ]);
      expect(link.uri, startsWith('magnet:?xt=urn:btih:$hash'));
      expect(link.uri, isNot(contains('source.torrent')));
    },
  );
  test('plainUri leaves values unescaped except structural characters', () {
    final link = MagnetLink.parse(
      'magnet:?xt=urn:btih:$hash&dn=Phim%20Vi%E1%BB%87t%20%26%20%231'
      '&tr=udp%3A%2F%2Ftracker.example%3A80%2Fannounce',
    );
    expect(
      link.plainUri,
      'magnet:?xt=urn:btih:$hash&dn=Phim%20Việt%20%26%20%231'
      '&tr=udp://tracker.example:80/announce',
    );
    final reparsed = MagnetLink.parse(link.plainUri);
    expect(reparsed.hash, hash);
    expect(reparsed.name, 'Phim Việt & #1');
  });
  test(
    'magnet export retains a matching original and replaces a mismatched source',
    () {
      const original =
          'magnet:?xt=urn:btih:$hash&dn=Original&tr=udp%3A%2F%2Ftracker.example%3A80&x.pe=127.0.0.1%3A9999';
      expect(
        MagnetLink.fromMetadata(
          hash: hash,
          name: 'Name',
          sourceUri: original,
        ).uri,
        original,
      );
      final link = MagnetLink.fromMetadata(
        hash: 'f' * 40,
        name: 'Other',
        sourceUri: original,
      );
      expect(link.hash, 'f' * 40);
      expect(link.name, 'Other');
      expect(
        () => MagnetLink.fromMetadata(hash: 'invalid', name: 'Bad'),
        throwsFormatException,
      );
    },
  );
  test('export remains within magnet limits for large metadata', () {
    final link = MagnetLink.fromMetadata(
      hash: hash,
      name: '🎬' * 10000,
      trackers: List.generate(
        1000,
        (i) => 'https://tracker.example/$i/${'x' * 100}',
      ),
    );
    expect(link.uri.length, lessThanOrEqualTo(32768));
    expect(MagnetLink.parse(link.uri).hash, hash);
    expect(link.name.runes.length, 1024);
  });
  test('association arguments preserve unrelated options and videos', () {
    final arguments = [
      '--open-torrent',
      r'C:\Tải về\One.TORRENT',
      'magnet:?xt=urn:btih:$hash',
      '--flag',
      r'C:\Videos\a.mp4',
    ];
    expect(TorrentLaunchRequest.takeArguments(arguments), [
      r'C:\Tải về\One.TORRENT',
      'magnet:?xt=urn:btih:$hash',
    ]);
    expect(arguments, ['--flag', r'C:\Videos\a.mp4']);
  });
  test('tab routes preserve ampersands, hashes and unicode filenames', () {
    for (final source in [
      r'C:\Tải về\A & B #1.torrent',
      'magnet:?xt=urn:btih:$hash&dn=A%20%26%20B&tr=https%3A%2F%2Ftracker.example',
    ]) {
      final path = TorrentLaunchRequest.pathFor(source);
      expect(TorrentLaunchRequest.isPath(path), isTrue);
      expect(TorrentLaunchRequest.sourceFromPath(path), source);
    }
    expect(
      TorrentLaunchRequest.sourceFromPath(
        '#torrents?open=https%3A%2F%2Fexample.com',
      ),
      isNull,
    );
    expect(TorrentLaunchRequest.isSource('--not-a-file.torrent'), isFalse);
  });
}

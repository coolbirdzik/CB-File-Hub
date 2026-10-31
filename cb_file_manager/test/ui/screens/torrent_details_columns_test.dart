import 'package:cb_file_manager/config/languages/english_localizations.dart';
import 'package:cb_file_manager/services/torrent/torrent_entry.dart';
import 'package:cb_file_manager/ui/screens/torrent/torrent_details_columns.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TorrentEntry entry(Map<String, Object?> values) => TorrentEntry.fromMap({
    'hash': 'a' * 40,
    'name': 'Example',
    'torrent_path': '/example.torrent',
    'category': 'other',
    'group_name': '',
    'total_bytes': 1000,
    'file_count': 2,
    'status': 'active',
    'completed_bytes': 400,
    'download_speed': 99,
    'added_at': 1700000000000,
    ...values,
  });

  Map<String, String> values(TorrentEntry e) => {
    for (final c in TorrentDetailsColumns.build(
      l: EnglishLocalizations(),
      entries: {'file': e},
      visible: {},
      formatSize: (bytes) => '$bytes B',
    ))
      c.id: c.valueOf('file'),
  };

  test('torrent columns distinguish unknown measurements and known zero', () {
    final unknown = values(entry({}));
    expect(unknown['seeds'], '—');
    expect(unknown['uploaded'], '—');
    expect(unknown['ratio'], '—');
    expect(unknown['eta'], '00:00:07');
    final measured = values(
      entry({
        'seeders': 0,
        'connections': 8,
        'uploaded_bytes': 200,
        'upload_speed': 25,
        'group_name': 'Movies',
        'download_dir': '/downloads',
      }),
    );
    expect(measured['seeds'], '0');
    expect(measured['peers'], '8');
    expect(measured['uploaded'], '200 B');
    expect(measured['upSpeed'], '25 B/s');
    expect(measured['ratio'], '0.50');
    expect(measured['files'], '2');
    expect(measured['group'], 'Movies');
    expect(measured['destination'], '/downloads');
    expect(measured['hash'], 'a' * 40);
  });

  test(
    'all 28 torrent columns expose real metadata with unknown values left blank',
    () {
      final data = values(
        entry({
          'trackers':
              '["https://tracker.example/announce","udp://two.example:80"]',
          'is_private': 1,
          'piece_length': 16384,
          'piece_count': 1,
          'comment': 'My comment',
          'created_by': 'qBittorrent',
          'metainfo_bytes': 250,
          'torrent_created_at': 1700000000000,
          'error': 'Disk full',
          'gid': 'task',
        }),
      );
      expect(data, hasLength(28));
      expect(data['trackerCount'], '2');
      expect(data['tracker'], 'https://tracker.example/announce');
      expect(data['private'], 'Private');
      expect(data['pieceSize'], '16384 B');
      expect(data['pieceCount'], '1');
      expect(data['metainfoSize'], '250 B');
      expect(data['remaining'], '600 B');
      expect(data['comment'], 'My comment');
      expect(data['createdBy'], 'qBittorrent');
      expect(data['torrentFile'], '/example.torrent');
      expect(data['source'], '/example.torrent');
      expect(data['taskId'], 'task');
      expect(data['error'], 'Disk full');
      final unknown = values(entry({}));
      expect(unknown['trackerCount'], '—');
      expect(unknown['private'], '—');
      expect(
        unknown['torrentCreated'],
        DateTime.fromMillisecondsSinceEpoch(
          1700000000000,
        ).toLocal().toString().split('.').first,
      );
    },
  );

  test(
    'creation column uses library addition time instead of metainfo date',
    () {
      final original = values(entry({}))['torrentCreated'];
      expect(
        values(entry({'torrent_created_at': 1000}))['torrentCreated'],
        original,
      );
      expect(
        values(entry({'modified_at': 1800000000000}))['torrentCreated'],
        original,
      );
    },
  );

  test(
    'offline imports and unknown magnet lengths show no invented progress',
    () {
      final offline = values(entry({'status': 'library'}));
      expect(offline['progress'], '—');
      expect(offline['downSpeed'], '—');
      expect(offline['eta'], '—');
      final magnet = values(entry({'total_bytes': 0, 'file_count': 0}));
      expect(magnet['progress'], '—');
      expect(magnet['files'], '—');
      expect(magnet['eta'], '—');
      expect(entry({'completed_bytes': 0, 'uploaded_bytes': 0}).ratio, isNull);
    },
  );
}

import 'dart:io';
import 'package:cb_file_manager/services/torrent/torrent_source_discovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'finds each Windows client separately and includes them in refresh',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'cb-client-discovery-',
      );
      try {
        final env = {
          'USERPROFILE': root.path,
          'APPDATA': p.join(root.path, 'Roaming'),
          'LOCALAPPDATA': p.join(root.path, 'Local'),
        };
        final expected = {
          TorrentClient.utorrent: p.join(env['APPDATA']!, 'uTorrent'),
          TorrentClient.bittorrent: p.join(env['APPDATA']!, 'BitTorrent'),
          TorrentClient.transmission: p.join(
            env['LOCALAPPDATA']!,
            'transmission',
            'torrents',
          ),
          TorrentClient.deluge: p.join(env['APPDATA']!, 'deluge', 'state'),
        };
        for (final item in expected.entries) {
          await Directory(item.value).create(recursive: true);
          expect(
            await TorrentSourceDiscovery.discoverClient(
              item.key,
              environment: env,
              operatingSystem: 'windows',
            ),
            [item.value],
          );
        }
        expect(
          await TorrentSourceDiscovery.discover(
            environment: env,
            operatingSystem: 'windows',
          ),
          containsAll(expected.values),
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('uses Linux XDG paths and Transmission custom profiles', () async {
    final root = await Directory.systemTemp.createTemp('cb-xdg-discovery-');
    try {
      final env = {
        'HOME': root.path,
        'XDG_CONFIG_HOME': p.join(root.path, 'custom-config'),
        'TRANSMISSION_HOME': p.join(root.path, 'portable'),
      };
      final transmission = await Directory(
        p.join(env['TRANSMISSION_HOME']!, 'torrents'),
      ).create(recursive: true);
      final daemon = await Directory(
        p.join(env['XDG_CONFIG_HOME']!, 'transmission-daemon', 'torrents'),
      ).create(recursive: true);
      final deluge = await Directory(
        p.join(env['XDG_CONFIG_HOME']!, 'deluge', 'state'),
      ).create(recursive: true);
      expect(
        await TorrentSourceDiscovery.discoverClient(
          TorrentClient.transmission,
          environment: env,
          operatingSystem: 'linux',
        ),
        [transmission.path, daemon.path],
      );
      expect(
        await TorrentSourceDiscovery.discoverClient(
          TorrentClient.deluge,
          environment: env,
          operatingSystem: 'linux',
        ),
        [deluge.path],
      );
      expect(
        await TorrentSourceDiscovery.discoverClient(
          TorrentClient.utorrent,
          environment: env,
          operatingSystem: 'linux',
        ),
        isEmpty,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'discovers a qBittorrent folder created after the first discovery',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'cb-torrent-discovery-',
      );
      try {
        final env = {
          'USERPROFILE': root.path,
          'LOCALAPPDATA': p.join(root.path, 'Local'),
          'APPDATA': p.join(root.path, 'Roaming'),
        };
        final downloads = await Directory(
          p.join(root.path, 'Downloads'),
        ).create();
        expect(
          await TorrentSourceDiscovery.discover(
            environment: env,
            operatingSystem: 'windows',
          ),
          [downloads.path],
        );
        final client = await Directory(
          p.join(env['LOCALAPPDATA']!, 'qBittorrent', 'BT_backup'),
        ).create(recursive: true);
        expect(
          await TorrentSourceDiscovery.discover(
            environment: env,
            operatingSystem: 'windows',
          ),
          contains(client.path),
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}

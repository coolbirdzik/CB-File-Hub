import 'dart:io';
import 'package:path/path.dart' as p;

enum TorrentClient {
  utorrent('µTorrent'),
  bittorrent('BitTorrent'),
  transmission('Transmission'),
  deluge('Deluge');

  final String label;
  const TorrentClient(this.label);
}

/// Discover existing client folders again on refresh, not just on first launch.
class TorrentSourceDiscovery {
  static Future<List<String>> discoverClient(
    TorrentClient client, {
    Map<String, String>? environment,
    String? operatingSystem,
  }) => _existing(
    _clientCandidates(
      client,
      environment ?? Platform.environment,
      operatingSystem ?? Platform.operatingSystem,
    ),
  );

  static Iterable<String> _clientCandidates(
    TorrentClient client,
    Map<String, String> env,
    String os,
  ) sync* {
    final home = env['USERPROFILE'] ?? env['HOME'];
    final config =
        env['XDG_CONFIG_HOME'] ??
        (home == null ? null : p.join(home, '.config'));
    if (client == TorrentClient.transmission) {
      if (env['TRANSMISSION_HOME'] case final String directory) {
        yield p.join(directory, 'torrents');
      }
    }
    if (os == 'windows') {
      final roaming = env['APPDATA'];
      final local = env['LOCALAPPDATA'];
      if (roaming != null) {
        switch (client) {
          case TorrentClient.utorrent:
            yield p.join(roaming, 'uTorrent');
          case TorrentClient.bittorrent:
            yield p.join(roaming, 'BitTorrent');
          case TorrentClient.deluge:
            yield p.join(roaming, 'deluge', 'state');
          case TorrentClient.transmission:
            break;
        }
      }
      if (client == TorrentClient.transmission && local != null) {
        yield p.join(local, 'transmission', 'torrents');
        yield p.join(local, 'transmission-daemon', 'torrents');
      }
    }
    if (client == TorrentClient.transmission) {
      if (os == 'linux' && config != null) {
        for (final profile in [
          'transmission',
          'transmission-daemon',
          'transmission-cli',
        ]) {
          yield p.join(config, profile, 'torrents');
        }
      }
      if (os == 'macos' && home != null) {
        yield p.join(
          home,
          'Library',
          'Application Support',
          'Transmission',
          'Torrents',
        );
      }
    }
    if (client == TorrentClient.deluge && config != null && os != 'windows') {
      yield p.join(config, 'deluge', 'state');
    }
  }

  static Future<List<String>> _existing(Iterable<String> candidates) async {
    final paths = candidates
        .map((path) => p.normalize(p.absolute(path)))
        .toSet();
    final results = await Future.wait(
      paths.map((path) async {
        try {
          return await Directory(path).exists() ? path : null;
        } on FileSystemException {
          return null;
        }
      }),
    );
    return results.whereType<String>().toList();
  }

  static Future<List<String>> discover({
    Map<String, String>? environment,
    String? operatingSystem,
  }) async {
    final env = environment ?? Platform.environment;
    final os = operatingSystem ?? Platform.operatingSystem;
    final home = env['USERPROFILE'] ?? env['HOME'];
    final candidates = <String>{
      if (home != null) p.join(home, 'Downloads'),
      for (final client in TorrentClient.values)
        ..._clientCandidates(client, env, os),
      if (env['APPDATA'] case final String appData) ...[
        p.join(appData, 'uTorrent'),
        p.join(appData, 'BitTorrent'),
        p.join(appData, 'qBittorrent', 'BT_backup'),
      ],
      if (env['LOCALAPPDATA'] case final String localData)
        p.join(localData, 'qBittorrent', 'BT_backup'),
      if (home != null && os == 'linux') ...[
        p.join(
          env['XDG_DATA_HOME'] ?? p.join(home, '.local', 'share'),
          'qBittorrent',
          'BT_backup',
        ),
        p.join(home, '.local', 'share', 'data', 'qBittorrent', 'BT_backup'),
        p.join(
          env['XDG_CONFIG_HOME'] ?? p.join(home, '.config'),
          'transmission',
          'torrents',
        ),
      ],
      if (home != null && os == 'macos') ...[
        p.join(
          home,
          'Library',
          'Application Support',
          'qBittorrent',
          'BT_backup',
        ),
        p.join(
          home,
          'Library',
          'Application Support',
          'Transmission',
          'Torrents',
        ),
      ],
    };
    return _existing(candidates);
  }
}

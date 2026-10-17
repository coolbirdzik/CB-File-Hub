/// BitTorrent v1/hybrid magnets understood by aria2, normalized to a v1 hash.
class MagnetLink {
  final String uri;
  final String hash;
  final String name;
  const MagnetLink._(this.uri, this.hash, this.name);

  factory MagnetLink.fromMetadata({
    required String hash,
    required String name,
    Iterable<String> trackers = const [],
    String? sourceUri,
  }) {
    if (!RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(hash)) {
      throw const FormatException('Invalid magnet info hash');
    }
    final normalizedHash = hash.toLowerCase();
    if (sourceUri != null) {
      try {
        final original = MagnetLink.parse(sourceUri);
        if (original.hash == normalizedHash) {
          return original.withTrackers(trackers);
        }
      } on FormatException {
        // A metainfo HTTP URL is a source, not a magnet. Build from the index.
      }
    }
    final displayName = String.fromCharCodes(name.runes.take(1024));
    var uri = 'magnet:?xt=urn:btih:$normalizedHash';
    if (displayName.isNotEmpty) {
      uri += '&dn=${Uri.encodeComponent(displayName)}';
    }
    for (final tracker in trackers.toSet()) {
      final parsed = Uri.tryParse(tracker);
      if (parsed == null ||
          parsed.host.isEmpty ||
          !const [
            'udp',
            'https',
            'http',
            'wss',
            'ws',
          ].contains(parsed.scheme)) {
        continue;
      }
      final parameter = '&tr=${Uri.encodeComponent(tracker)}';
      if (uri.length + parameter.length <= 32768) uri += parameter;
    }
    return MagnetLink.parse(uri);
  }

  factory MagnetLink.parse(String value) {
    if (value.length > 32768 || value.contains(RegExp(r'[\x00-\x1f"]'))) {
      throw const FormatException('Invalid magnet link');
    }
    final parsed = Uri.parse(value.trim());
    if (parsed.scheme.toLowerCase() != 'magnet' ||
        parsed.hasAuthority ||
        parsed.path.isNotEmpty) {
      throw const FormatException('Invalid magnet link');
    }
    final hashes = <String>{};
    for (final topic in parsed.queryParametersAll['xt'] ?? <String>[]) {
      if (!topic.toLowerCase().startsWith('urn:btih:')) continue;
      final raw = topic.substring(9);
      if (RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(raw)) {
        hashes.add(raw.toLowerCase());
      } else if (RegExp(r'^[A-Za-z2-7]{32}$').hasMatch(raw)) {
        const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
        var bits = 0, buffer = 0;
        final bytes = <int>[];
        for (final char in raw.toUpperCase().split('')) {
          buffer = (buffer << 5) | alphabet.indexOf(char);
          bits += 5;
          if (bits >= 8) {
            bits -= 8;
            bytes.add((buffer >> bits) & 255);
            buffer &= (1 << bits) - 1;
          }
        }
        hashes.add(
          bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        );
      } else {
        throw const FormatException('Invalid magnet info hash');
      }
    }
    if (hashes.length != 1) {
      throw const FormatException('One BitTorrent v1 info hash is required');
    }
    final hash = hashes.single;
    final name = parsed.queryParameters['dn']?.trim();
    return MagnetLink._(
      parsed.toString(),
      hash,
      name == null || name.isEmpty ? hash : name,
    );
  }

  MagnetLink withTrackers(Iterable<String> trackers) {
    final parsed = Uri.parse(uri);
    final known = (parsed.queryParametersAll['tr'] ?? const <String>[]).toSet();
    var query = parsed.query;
    for (final tracker in trackers) {
      if (!known.add(tracker)) continue;
      final addition = '&tr=${Uri.encodeComponent(tracker)}';
      if (uri.length + query.length - parsed.query.length + addition.length <=
          32768) {
        query += addition;
      }
    }
    return query == parsed.query
        ? this
        : MagnetLink.parse(parsed.replace(query: query).toString());
  }

  MagnetLink merge(MagnetLink incoming, {required String displayName}) {
    if (hash != incoming.hash) {
      throw const FormatException('Different torrent hashes');
    }
    final original = Uri.parse(uri);
    final params = <String, List<String>>{
      for (final item in original.queryParametersAll.entries)
        item.key: [...item.value],
    };
    for (final item in Uri.parse(incoming.uri).queryParametersAll.entries) {
      if (item.key == 'xt' || item.key == 'dn') continue;
      params[item.key] = {...?params[item.key], ...item.value}.toList();
    }
    params['dn'] = [displayName];
    return MagnetLink.parse(
      original.replace(queryParameters: params).toString(),
    );
  }
}

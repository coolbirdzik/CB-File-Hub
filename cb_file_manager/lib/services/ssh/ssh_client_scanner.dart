import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'local_ssh_discovery.dart';
import 'ssh_client_platform.dart';
import 'ssh_import.dart';
import 'ssh_profile_store.dart';
import 'termius_local_reader.dart';

enum SshClientScanStatus { ready, notFound, unreadable, keyUnavailable }

class SshClientScanResult {
  final String app, location;
  final SshClientScanStatus status;
  final SshImportPreview preview;
  const SshClientScanResult(this.app, this.location, this.status, this.preview);
}

/// Known per-user locations only; no full-disk crawl and no external exporters.
/// Run in a worker isolate. Scanning never changes either client's data/vault.
class SshClientScanner {
  int _bytesRead = 0;
  final String home, roaming, local, operatingSystem;
  final Future<List<Uint8List>> Function() readLocalKeys;
  final List<Map<String, String>> Function(String) readRegistry;
  SshClientScanner({
    String? home,
    String? roaming,
    String? local,
    String? operatingSystem,
    this.readLocalKeys = readTermiusLocalKeys,
    this.readRegistry = readWindowsSshSessions,
  }) : home =
           home ??
           Platform.environment['USERPROFILE'] ??
           Platform.environment['HOME'] ??
           '',
       roaming = roaming ?? Platform.environment['APPDATA'] ?? '',
       local = local ?? Platform.environment['LOCALAPPDATA'] ?? '',
       operatingSystem = operatingSystem ?? Platform.operatingSystem;

  Future<List<SshClientScanResult>> scan({
    String passphrase = '',
    List<SshStoredKey> existingKeys = const [],
  }) async {
    if (home.isEmpty) return [];
    final results = <SshClientScanResult>[];
    SshImportPreview parse(List<SshImportFile> files) => SshImporter.parse(
      files,
      passphrase: passphrase,
      existingKeys: existingKeys,
    );
    Future<void> source(
      String app,
      String location,
      Future<SshImportPreview?> Function() action,
    ) async {
      _bytesRead = 0;
      try {
        final preview = await action();
        results.add(
          SshClientScanResult(
            app,
            location,
            preview == null
                ? SshClientScanStatus.notFound
                : SshClientScanStatus.ready,
            preview ?? const SshImportPreview([], [], []),
          ),
        );
      } catch (error) {
        results.add(
          SshClientScanResult(
            app,
            location,
            error is TermiusKeyUnavailable
                ? SshClientScanStatus.keyUnavailable
                : SshClientScanStatus.unreadable,
            const SshImportPreview([], [], []),
          ),
        );
      }
    }

    final username =
        Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? '';
    await source('OpenSSH', p.join(home, '.ssh'), () async {
      if (!await Directory(p.join(home, '.ssh')).exists()) return null;
      final snapshot = await LocalSshDiscovery(
        homeDirectory: home,
        username: username,
      ).scan();
      final files = <SshImportFile>[];
      final keyIssues = <SshImportIssue>[];
      // Resolve Include/wildcard semantics through the existing discovery layer.
      final document = {
        'hosts': [
          for (final host in snapshot.hosts)
            {
              'label': host.alias,
              'host': host.host,
              'username': host.username,
              'port': host.port,
              if (host.identityFiles.isNotEmpty)
                'identity_file': host.identityFiles.first,
              if (host.unsupportedOptions.isNotEmpty) 'proxy': true,
            },
        ],
      };
      files.add(SshImportFile('OpenSSH.json', jsonEncode(document)));
      for (final key in snapshot.keys.take(SshImporter.maxFiles - 1)) {
        try {
          if (!await _localKeyPath(key.path)) continue;
          files.add(await _read(key.path));
        } catch (_) {
          keyIssues.add(SshImportIssue(key.name, SshImportProblem.key));
        }
      }
      if (snapshot.hosts.isEmpty && files.length == 1) {
        return const SshImportPreview([], [], []);
      }
      final preview = parse(files);
      return SshImportPreview(preview.hosts, preview.keys, [
        ...preview.issues,
        ...keyIssues,
        if (snapshot.warnings.isNotEmpty)
          const SshImportIssue('OpenSSH', SshImportProblem.unsupported),
      ], proxies: preview.proxies);
    });
    final termiusRoots = <String>{
      if (roaming.isNotEmpty) p.join(roaming, 'Termius'),
      p.join(home, '.config', 'Termius'),
      p.join(home, 'snap', 'termius-app', 'current', '.config', 'Termius'),
      p.join(home, 'Library', 'Application Support', 'Termius'),
    };
    if (operatingSystem == 'macos') {
      final containers = Directory(p.join(home, 'Library', 'Containers'));
      if (await containers.exists()) {
        await for (final d in containers.list(followLinks: false)) {
          if (d is Directory &&
              p.basename(d.path).toLowerCase().contains('termius')) {
            termiusRoots.add(
              p.join(
                d.path,
                'Data',
                'Library',
                'Application Support',
                'Termius',
              ),
            );
          }
        }
      }
    }
    var termiusFound = false;
    for (final root in termiusRoots) {
      final directory = p.join(root, 'IndexedDB', 'file__0.indexeddb.leveldb');
      if (!await File(p.join(directory, 'CURRENT')).exists()) continue;
      termiusFound = true;
      await source('Termius', root, () async {
        final document = await TermiusLocalReader(
          directory,
        ).read(await readLocalKeys());
        return parse([SshImportFile('Termius.json', jsonEncode(document))]);
      });
    }
    if (!termiusFound) {
      results.add(
        const SshClientScanResult(
          'Termius',
          '',
          SshClientScanStatus.notFound,
          SshImportPreview([], [], []),
        ),
      );
    }

    for (final app in ['PuTTY', 'WinSCP']) {
      await source(app, 'HKCU', () async {
        final sessions = operatingSystem == 'windows'
            ? readRegistry(app)
            : <Map<String, String>>[];
        final files = <SshImportFile>[];
        if (sessions.isNotEmpty) {
          // Feed the existing INI/registry validator, preserving encrypted-password warnings.
          final buffer = StringBuffer();
          for (final row in sessions) {
            if (app == 'PuTTY') {
              buffer.writeln(
                '[HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\Sessions\\${row['name']}]',
              );
              for (final e in row.entries.where((e) => e.key != 'name')) {
                buffer.writeln('"${e.key}"=${jsonEncode(e.value)}');
              }
            } else {
              buffer.writeln('[Sessions\\${row['name']}]');
              for (final e in row.entries.where((e) => e.key != 'name')) {
                buffer.writeln('${e.key}=${e.value}');
              }
            }
          }
          files.add(
            SshImportFile(
              app == 'PuTTY' ? 'PuTTY.reg' : 'WinSCP.ini',
              '${app == 'PuTTY' ? 'Windows Registry Editor Version 5.00\n' : ''}$buffer',
            ),
          );
        }
        if (app == 'WinSCP') {
          for (final path in [
            if (roaming.isNotEmpty) p.join(roaming, 'WinSCP.ini'),
            p.join(home, 'WinSCP.ini'),
          ]) {
            if (await File(path).exists()) files.add(await _read(path));
          }
        }
        if (files.isEmpty) return null;
        return _withReferencedKeys(files, parse);
      });
    }
    final crtRoots = <String>{
      if (roaming.isNotEmpty) p.join(roaming, 'VanDyke', 'Config', 'Sessions'),
      p.join(home, '.vandyke', 'SecureCRT', 'Config', 'Sessions'),
      p.join(
        home,
        'Library',
        'Application Support',
        'VanDyke',
        'SecureCRT',
        'Config',
        'Sessions',
      ),
    };
    await source('SecureCRT', crtRoots.first, () async {
      final files = <SshImportFile>[];
      for (final root in crtRoots) {
        if (!await Directory(root).exists()) continue;
        await for (final file in Directory(
          root,
        ).list(recursive: true, followLinks: false)) {
          if (file is File &&
              file.path.toLowerCase().endsWith('.ini') &&
              p.basename(file.path) != '__FolderData__.ini') {
            files.add(await _read(file.path));
          }
          if (files.length >= SshImporter.maxFiles) break;
        }
      }
      if (files.isEmpty) return null;
      return _withReferencedKeys(files, parse);
    });
    await source(
      'Tabby',
      roaming.isEmpty
          ? p.join(home, '.config', 'tabby')
          : p.join(roaming, 'tabby'),
      () async {
        final files = <SshImportFile>[];
        for (final root in {
          if (roaming.isNotEmpty) p.join(roaming, 'tabby'),
          p.join(home, '.config', 'tabby'),
          p.join(home, 'Library', 'Application Support', 'tabby'),
        }) {
          final file = p.join(root, 'config.yaml');
          if (await File(file).exists()) files.add(await _read(file));
        }
        return files.isEmpty ? null : _withReferencedKeys(files, parse);
      },
    );
    return results;
  }

  Future<SshImportFile> _read(String path) async {
    final file = File(path);
    final size = await file.length();
    _bytesRead += size;
    if (size > SshImporter.maxFileBytes ||
        _bytesRead > SshImporter.maxTotalBytes) {
      throw const FormatException('limit');
    }
    final bytes = await file.readAsBytes();
    final text = bytes.length >= 2 && bytes[0] == 255 && bytes[1] == 254
        ? String.fromCharCodes([
            for (var i = 2; i + 1 < bytes.length; i += 2)
              bytes[i] | bytes[i + 1] << 8,
          ])
        : utf8.decode(bytes);
    return SshImportFile(path, text);
  }

  Future<SshImportPreview> _withReferencedKeys(
    List<SshImportFile> files,
    SshImportPreview Function(List<SshImportFile>) parse,
  ) async {
    // Local installed configurations are the source of these paths. Never execute
    // commands, follow network/UNC references, or access another user's home.
    final references = SshImporter.referencedKeyFiles(files);
    final seen = <String>{};
    final issues = <SshImportIssue>[];
    for (var path in references) {
      if (path.startsWith('~/') || path.startsWith('~\\')) {
        path = p.join(home, path.substring(2));
      }
      path = path.replaceAllMapped(
        RegExp(r'%([^%]+)%'),
        (m) => Platform.environment[m[1]!] ?? m[0]!,
      );
      if (!p.isAbsolute(path)) path = p.join(home, path);
      path = p.normalize(path);
      if (!seen.add(path)) continue;
      try {
        if (await _localKeyPath(path)) files.add(await _read(path));
      } catch (_) {
        issues.add(SshImportIssue(p.basename(path), SshImportProblem.key));
      }
      if (files.length >= SshImporter.maxFiles) break;
    }
    final preview = parse(files);
    return SshImportPreview(preview.hosts, preview.keys, [
      ...preview.issues,
      ...issues,
    ], proxies: preview.proxies);
  }

  Future<bool> _localKeyPath(String path) async {
    if (path.startsWith('\\\\') ||
        !p.isWithin(home, path) ||
        await FileSystemEntity.isLink(path)) {
      return false;
    }
    if (!await File(path).exists()) return false;
    final resolvedHome = await Directory(home).resolveSymbolicLinks();
    final resolved = await File(path).resolveSymbolicLinks();
    return !resolved.startsWith('\\\\') && p.isWithin(resolvedHome, resolved);
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cb_file_manager/services/torrent/aria2_engine.dart';
import 'package:cb_file_manager/services/torrent/torrent_repository.dart';
import 'package:cb_file_manager/services/torrent/torrent_service.dart';
import 'package:cb_file_manager/services/torrent/torrent_metainfo.dart';
import 'package:cb_file_manager/services/torrent/torrent_import_confirmation.dart';
import 'torrent_fixtures.dart';
import 'package:cb_file_manager/services/torrent/torrent_entry.dart';
import 'package:cb_file_manager/services/torrent/torrent_background_receiver.dart';

// Override widget-test networking only for temporary loopback test servers.
class _LoopbackHttpOverrides extends HttpOverrides {}

class _RefreshRepository extends TorrentRepository {
  _RefreshRepository(super.db);
  int initializations = 0;
  int fullSnapshots = 0;
  int storedPathScans = 0;

  @override
  Future<void> initialize() async {
    initializations++;
    await super.initialize();
  }

  @override
  Stream<Map<String, Object?>> scanSources() {
    fullSnapshots++;
    return super.scanSources();
  }

  @override
  Stream<String> storedPaths() {
    storedPathScans++;
    return super.storedPaths();
  }
}

class FakeEngine extends Aria2Engine {
  final tasks = <String, Map<String, dynamic>>{};
  final addedDirectories = <String>[];
  final addedMagnets = <String>[];
  Completer<void>? statusGate;
  Completer<void>? statusStarted;
  bool _running = false;
  Object? startError;
  @override
  bool get running => _running;
  @override
  Future<void> start(String stateDirectory, {String? executable}) async {
    if (startError != null) throw startError!;
    _running = true;
  }

  @override
  Future<String> add(
    String torrentPath,
    String destination,
    String gid, {
    bool paused = false,
    String? expectedHash,
  }) async {
    addedDirectories.add(destination);
    tasks[gid] = {
      'status': paused ? 'paused' : 'waiting',
      'completedLength': '0',
      'downloadSpeed': '0',
    };
    return gid;
  }

  @override
  Future<String> addMagnet(
    String uri,
    String destination,
    String gid, {
    bool paused = false,
  }) async {
    addedMagnets.add(uri);
    return add('', destination, gid, paused: paused);
  }

  @override
  Future<Object?> call(String method, [List<Object?> args = const []]) async {
    final gid = args.first as String;
    if (method == 'removeDownloadResult') {
      return 'OK';
    }
    final task = tasks[gid];
    if (task == null) throw Aria2RpcException(1, 'GID#$gid is not found');
    switch (method) {
      case 'tellStatus':
        final snapshot = Map<String, dynamic>.from(task);
        if (statusStarted != null && !statusStarted!.isCompleted) {
          statusStarted!.complete();
        }
        await statusGate?.future;
        return snapshot;
      case 'pause':
        task['status'] = 'paused';
        return gid;
      case 'unpause':
        task['status'] = 'waiting';
        return gid;
      case 'forceRemove':
        tasks.remove(gid);
        return gid;
      default:
        throw StateError(method);
    }
  }

  @override
  Future<void> dispose() async {
    _running = false;
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database db;
  late TorrentRepository repo;
  late TorrentService service;
  late FakeEngine engine;
  Future<TorrentEntry> openHttpLink(String url) =>
      HttpOverrides.runWithHttpOverrides(
        () => service.openLink(url),
        _LoopbackHttpOverrides(),
      );
  List<String> discoveredRoots = [];
  Completer<void>? discoveryGate;
  int discoveries = 0;
  Future<File> create(String path, {String name = 'example.mp4'}) async {
    final file = File(p.normalize(p.join(root.path, path)));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(torrentBytes(name: name));
    return file;
  }

  setUp(() async {
    discoveredRoots = [];
    discoveryGate = null;
    discoveries = 0;
    root = await Directory.systemTemp.createTemp('cb-torrent-test-');
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    repo = _RefreshRepository(db);
    await repo.initialize();
    SharedPreferences.setMockInitialValues({
      'torrent.autoImport': false,
      'torrent.scanRoots': <String>[],
    });
    engine = FakeEngine();
    service = TorrentService.forTesting(
      repository: repo,
      preferences: await SharedPreferences.getInstance(),
      stateDirectory: root.path,
      engine: engine,
      sourceDiscovery: () async {
        discoveries++;
        await discoveryGate?.future;
        return discoveredRoots;
      },
    );
  });
  tearDown(() async {
    service.dispose();
    await db.close();
    // The only recursive cleanup target is the temporary directory created by
    // this test; no user folders or system torrent clients are scanned.
    await root.delete(recursive: true);
  });

  test(
    'individual file import notifies after the index commit without a scan',
    () async {
      await service.initialize();
      final file = await create('inbox/new.torrent');
      final visible = Completer<TorrentPage>();
      var notifications = 0;
      service.addListener(() {
        notifications++;
        if (!visible.isCompleted) visible.complete(repo.page());
      });
      expect(await service.importFile(file.path), isTrue);
      final page = await visible.future;
      expect(page.entries.single.torrentPath, file.path);
      expect(notifications, 1);
      expect(service.scan.running, isFalse);
      expect(engine.running, isFalse);
    },
  );

  test(
    'opening preferences persist, validate folders and do not start downloads',
    () async {
      expect(service.showDownloadDialog, isTrue);
      expect(service.startDownloadsImmediately, isTrue);
      expect(service.defaultDownloadDirectory, isNull);
      final directory = p.join(root.path, 'future', 'downloads');
      await service.setShowDownloadDialog(false);
      await service.setReceiveInBackground(true);
      await service.setStartDownloadsImmediately(false);
      await service.setDefaultDownloadDirectory(directory);
      expect(await Directory(directory).exists(), isFalse);
      await expectLater(
        service.setDefaultDownloadDirectory('relative/path'),
        throwsFormatException,
      );
      expect(service.defaultDownloadDirectory, directory);
      final restored = TorrentService.forTesting(
        repository: repo,
        preferences: await SharedPreferences.getInstance(),
        stateDirectory: root.path,
        engine: FakeEngine(),
      );
      expect(restored.showDownloadDialog, isFalse);
      expect(restored.receiveInBackground, isTrue);
      expect(restored.startDownloadsImmediately, isFalse);
      expect(restored.defaultDownloadDirectory, directory);
      expect(restored.ownsEngine, isFalse);
      restored.dispose();
      await service.setDefaultDownloadDirectory('');
      expect(service.defaultDownloadDirectory, isNull);
      expect(engine.addedDirectories, isEmpty);
    },
  );

  for (final start in [false, true]) {
    test(
      'background open archives and starts according to saved preference $start',
      () async {
        final source = await create('Downloads/silent.torrent');
        final destination = p.join(root.path, 'payload');
        await service.setDefaultDownloadDirectory(destination);
        await service.setStartDownloadsImmediately(start);
        // An unset library folder must not cause a chooser in background mode.
        await (await SharedPreferences.getInstance()).setString(
          'torrent.storageMode',
          'move',
        );
        final entry = await service.openSourceInBackground(source.path);
        expect(entry.status, start ? 'waiting' : 'paused');
        expect(entry.downloadDir, destination);
        expect(await source.exists(), isTrue);
        expect(
          p.isWithin(p.join(root.path, 'opened-torrents'), entry.torrentPath),
          isTrue,
        );
        expect(engine.addedDirectories, [destination]);
        await source.delete();
        expect(await File(entry.torrentPath).readAsBytes(), torrentBytes());
      },
    );
  }

  for (final start in [false, true]) {
    for (final sourceType in ['file', 'magnet', 'entry']) {
      test(
        'background $sourceType reloads saved start preference $start',
        () async {
          final source = await create('Downloads/preferences.torrent');
          final existing = sourceType == 'entry'
              ? await service.openSource(source.path)
              : null;
          await service.setStartDownloadsImmediately(!start);
          await service.setDefaultDownloadDirectory(p.join(root.path, 'old'));
          final destination = p.join(root.path, 'user-configured');
          // A different app window saves preferences while this service retains
          // its old SharedPreferences instance/cache.
          SharedPreferences.setMockInitialValues({
            'torrent.autoImport': false,
            'torrent.scanRoots': <String>[],
            'torrent.receiveInBackground': true,
            'torrent.startImmediately': start,
            'torrent.lastDownloadDirectory': destination,
          });
          expect(service.startDownloadsImmediately, !start);
          final entry = existing != null
              ? await service.downloadInBackground(existing)
              : await service.openSourceInBackground(
                  sourceType == 'magnet'
                      ? 'magnet:?xt=urn:btih:${'1' * 40}'
                      : source.path,
                );
          expect(entry.status, start ? 'waiting' : 'paused');
          expect(entry.downloadDir, destination);
          expect(
            engine.tasks[entry.gid]!['status'],
            start ? 'waiting' : 'paused',
          );
          await service.sync();
          expect(
            (await repo.get(entry.hash))!.status,
            start ? 'waiting' : 'paused',
          );
          expect(service.startDownloadsImmediately, start);
        },
      );
    }
  }

  test('repeated background opens preserve an existing paused task', () async {
    final source = await create('Downloads/repeated.torrent');
    await service.setDefaultDownloadDirectory(p.join(root.path, 'payload'));
    await service.setStartDownloadsImmediately(false);
    final paused = await service.openSourceInBackground(source.path);
    await service.setStartDownloadsImmediately(true);
    final repeated = await service.openSourceInBackground(source.path);
    expect(repeated.status, 'paused');
    expect(repeated.gid, paused.gid);
    expect(engine.addedDirectories, hasLength(1));
    expect((await repo.page()).total, 1);
  });

  test(
    'background failure is indexed and notified without blocking the next import',
    () async {
      final source = await create('Downloads/first.torrent');
      final second = await create(
        'Downloads/second.torrent',
        name: 'Second.mp4',
      );
      await service.setDefaultDownloadDirectory(p.join(root.path, 'payload'));
      engine.startError = StateError('aria2 unavailable');
      final notices = <({String title, String body, bool isError})>[];
      final receiver = TorrentBackgroundReceiver(
        service,
        notify: ({required title, required body, required isError}) async {
          notices.add((title: title, body: body, isError: isError));
        },
      );
      expect(await receiver.receiveSource(source.path), isNull);
      final failed = (await repo.page()).entries.single;
      expect(failed.status, 'error');
      expect(failed.error, contains('aria2 unavailable'));
      expect(notices.single.isError, isTrue);
      engine.startError = null;
      expect(await receiver.receiveSource(second.path), isNotNull);
      expect(notices.last.isError, isFalse);
      expect(notices.last.body, contains('Second.mp4'));
      expect((await repo.page()).total, 2);
    },
  );

  test(
    'unavailable notifications never replay a committed background import',
    () async {
      final source = await create('Downloads/notify.torrent');
      await service.setDefaultDownloadDirectory(p.join(root.path, 'payload'));
      final receiver = TorrentBackgroundReceiver(
        service,
        notify: ({required title, required body, required isError}) async {
          throw StateError('notifications disabled');
        },
      );
      expect(await receiver.receiveSource(source.path), isNotNull);
      expect(engine.addedDirectories, hasLength(1));
      expect((await repo.page()).total, 1);
    },
  );

  test(
    'index mode keeps originals and needs no central storage folder',
    () async {
      final file = await create('inbox/a.torrent');
      expect(await service.importFile(file.path), isTrue);
      final entry = (await repo.page()).entries.single;
      expect(entry.torrentPath, file.path);
      expect(await file.exists(), isTrue);
      expect(engine.addedDirectories, isEmpty);
    },
  );

  test(
    'refresh waits for an already running import instead of failing',
    () async {
      final file = await create('client/a.torrent');
      discoveredRoots = [file.parent.path];
      final started = Completer<void>();
      service.addListener(() {
        if (service.scan.running && !started.isCompleted) started.complete();
      });
      final importing = service.scanDirectories(discoveredRoots);
      await started.future;
      final refreshing = service.refreshImports();
      await Future.wait([importing, refreshing]);
      expect((await repo.page()).total, 1);
      expect(service.scan.running, isFalse);
      expect(service.scan.duplicates, 1);
      expect(discoveries, 1);
    },
  );

  test(
    'an unset discovery callback falls back instead of failing with a null function',
    () async {
      final legacy = TorrentService.forTesting(
        repository: repo,
        preferences: await SharedPreferences.getInstance(),
        stateDirectory: root.path,
        sourceDiscovery: null,
      );
      try {
        // Existence checks only: do not import or modify real client folders.
        expect(await legacy.discoverScanRoots(), isA<List<String>>());
      } finally {
        legacy.dispose();
      }
    },
  );

  test(
    'F5 upgrades a retained service whose database still uses the old schema',
    () async {
      await db.execute('DROP TABLE torrent_sources');
      await db.execute('DROP TABLE torrents');
      await db.execute('''CREATE TABLE torrents (
      hash TEXT PRIMARY KEY, name TEXT NOT NULL, torrent_path TEXT NOT NULL,
      category TEXT NOT NULL, group_name TEXT NOT NULL DEFAULT '',
      total_bytes INTEGER NOT NULL, file_count INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'library', download_dir TEXT, gid TEXT,
      completed_bytes INTEGER NOT NULL DEFAULT 0,
      download_speed INTEGER NOT NULL DEFAULT 0, error TEXT,
      added_at INTEGER NOT NULL)''');
      final file = await create('legacy/a.torrent');
      discoveredRoots = [file.parent.path];
      await service.refreshImports();
      final entry = (await repo.page()).entries.single;
      expect(entry.pieceCount, 1);
      expect(entry.status, 'library');
      expect(service.scan.failed, 0);
    },
  );

  test('magnet import is offline and merges with later metainfo', () async {
    final file = await create('a.torrent');
    final metadata = TorrentMetainfo.parse(torrentBytes());
    final entry = await service.importMagnet(
      'magnet:?xt=urn:btih:${metadata.hash}&dn=Unknown',
    );
    expect(entry.torrentPath, isEmpty);
    expect(engine.addedMagnets, isEmpty);
    await service.openSource(file.path);
    final merged = (await repo.page()).entries.single;
    expect(merged.hash, entry.hash);
    expect(merged.name, 'example.mp4');
    expect(merged.sourceUri, isNotNull);
    expect(merged.torrentPath, isNot(file.path));
    expect(await File(merged.torrentPath).readAsBytes(), torrentBytes());
  });

  for (final mode in ['index', 'copy', 'move']) {
    for (final location in ['temporary', 'Downloads']) {
      test(
        '$location browser file remains usable after cleanup in $mode mode',
        () async {
          final source = await create('$location/download.torrent');
          final prefs = await SharedPreferences.getInstance();
          final library = p.join(root.path, 'library');
          await prefs.setString('torrent.storageMode', mode);
          if (mode != 'index') {
            await prefs.setString('torrent.libraryDirectory', library);
          }
          if (Platform.isWindows) {
            final result = await Process.run('attrib', ['+R', source.path]);
            expect(result.exitCode, 0);
          }
          try {
            final entry = await IOOverrides.runZoned(
              () {
                expect(
                  p.isWithin(Directory.systemTemp.path, source.path),
                  location == 'temporary',
                );
                return service.openSource(source.path);
              },
              // All fixtures stay in our disposable test root. Downloads must
              // reproduce a browser source outside the OS temporary directory.
              getSystemTempDirectory: () => Directory(
                location == 'temporary'
                    ? root.path
                    : p.join(root.path, 'system-temp'),
              ),
            );
            expect(entry.torrentPath, isNot(source.path));
            expect(await source.exists(), isTrue);
            expect(await File(entry.torrentPath).readAsBytes(), torrentBytes());
            expect(service.storageMode, mode);
            expect(engine.running, isFalse);
            expect(engine.addedDirectories, isEmpty);
            expect(
              p.isWithin(
                mode == 'index'
                    ? p.join(root.path, 'opened-torrents')
                    : library,
                entry.torrentPath,
              ),
              isTrue,
            );
            if (Platform.isWindows) {
              await Process.run('attrib', ['-R', source.path]);
            }
            await source.delete();
            // The download reads the durable archive after the browser temp file
            // is gone, without contacting any real tracker or engine.
            await service.download(
              entry,
              p.join(root.path, 'payload'),
              startImmediately: false,
            );
            expect((await repo.get(entry.hash))!.status, 'paused');
            expect(await File(entry.torrentPath).readAsBytes(), torrentBytes());
          } finally {
            if (Platform.isWindows && await source.exists()) {
              await Process.run('attrib', ['-R', source.path]);
            }
          }
        },
      );
    }
  }

  test(
    'browser cleanup during merge uses the bytes captured before the dialog',
    () async {
      final original = await create('library/original.torrent');
      await service.importFile(original.path);
      final previous = (await repo.page()).entries.single;
      await repo.update(previous.hash, {
        'status': 'paused',
        'download_dir': p.join(root.path, 'keep'),
        'completed_bytes': 3,
      });
      final source = await create('browser-temp/duplicate.torrent');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('torrent.storageMode', 'move');
      await prefs.setString(
        'torrent.libraryDirectory',
        p.join(root.path, 'archive'),
      );
      var prompts = 0;
      final merged = await IOOverrides.runZoned(
        () => service.openSource(
          source.path,
          onDuplicate: (entry) async {
            prompts++;
            expect(entry.hash, previous.hash);
            await source.delete();
            return true;
          },
        ),
        getSystemTempDirectory: () =>
            Directory(p.join(root.path, 'system-temp')),
      );
      expect(prompts, 1);
      expect((await repo.page()).total, 1);
      expect(merged.status, 'paused');
      expect(merged.downloadDir, p.join(root.path, 'keep'));
      expect(merged.completedBytes, 3);
      expect(await File(merged.torrentPath).readAsBytes(), torrentBytes());
      expect(engine.running, isFalse);
    },
  );

  test('invalid browser file leaves no archive or index entry', () async {
    final source = await create('browser-temp/invalid.torrent');
    await source.writeAsString('not torrent metainfo');
    await expectLater(service.openSource(source.path), throwsFormatException);
    expect((await repo.page()).total, 0);
    expect(
      await Directory(p.join(root.path, 'opened-torrents')).exists(),
      isFalse,
    );
    expect(await source.exists(), isTrue);
  });

  test(
    'duplicate magnet asks before merging, preserves task state, and becomes recent',
    () async {
      const hash = 'a45ac4a7e94abc3a6b3c9d52af178018d60d4e22';
      final original =
          'magnet:?xt=urn:btih:$hash&dn=Existing&tr=https%3A%2F%2Fold.example%2Fannounce&x.pe=127.0.0.1%3A9999';
      await service.importMagnet(original);
      await repo.update(hash, {
        'added_at': 1,
        'modified_at': 1,
        'status': 'paused',
        'download_dir': '/keep',
        'gid': 'keep-task',
        'completed_bytes': 25,
      });
      await service.importMagnet('magnet:?xt=urn:btih:${'b' * 40}&dn=Other');
      expect(await repo.offsetInNewestOrder(hash), 1);
      final incoming =
          'magnet:?xt=urn:btih:$hash&dn=New%20name&tr=udp%3A%2F%2Fnew.example%3A80%2Fannounce';
      var prompts = 0;
      await expectLater(
        service.openLink(
          incoming,
          onDuplicate: (existing) async {
            prompts++;
            expect(existing.hash, hash);
            return false;
          },
        ),
        throwsA(isA<TorrentImportCancelled>()),
      );
      var entry = (await repo.get(hash))!;
      expect(entry.sourceUri, original);
      expect(entry.modifiedAt.millisecondsSinceEpoch, 1);
      expect(entry.trackers, ['https://old.example/announce']);
      entry = await service.openLink(
        incoming,
        onDuplicate: (_) async {
          prompts++;
          return true;
        },
      );
      expect(prompts, 2);
      expect(entry.name, 'Existing');
      expect(entry.status, 'paused');
      expect(entry.gid, 'keep-task');
      expect(entry.downloadDir, '/keep');
      expect(entry.completedBytes, 25);
      expect(entry.sourceUris, containsAll([original, incoming]));
      expect(entry.trackers.toSet(), {
        'https://old.example/announce',
        'udp://new.example:80/announce',
      });
      expect(
        Uri.parse(entry.sourceUri!).queryParameters['x.pe'],
        '127.0.0.1:9999',
      );
      expect(await repo.offsetInNewestOrder(hash), 0);
      expect((await repo.page()).entries.first.hash, hash);
      expect((await repo.page()).total, 2);
      expect(engine.running, isFalse);
      expect(engine.addedMagnets, isEmpty);
    },
  );

  test(
    'declining duplicate metainfo in Move mode leaves both index and source alone',
    () async {
      final original = await create('original.torrent');
      await service.importFile(original.path);
      final entry = (await repo.page()).entries.single;
      final duplicate = await create('duplicate.torrent');
      final prefs = await SharedPreferences.getInstance();
      final archive = p.join(root.path, 'archive');
      await prefs.setString('torrent.storageMode', 'move');
      await prefs.setString('torrent.libraryDirectory', archive);
      await expectLater(
        service.openSource(duplicate.path, onDuplicate: (_) async => false),
        throwsA(isA<TorrentImportCancelled>()),
      );
      expect(await duplicate.exists(), isTrue);
      expect(await Directory(archive).exists(), isFalse);
      expect((await repo.get(entry.hash))!.torrentPath, original.path);
      expect(await repo.sources(entry.hash), [original.path]);
    },
  );

  test(
    'HTTP torrent link follows redirects, keeps valid metainfo and never starts payload transfer',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final data = torrentBytes();
      server.listen((request) async {
        if (request.uri.path == '/redirect') {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            '/download?id=1',
          );
        } else {
          request.response.add(data);
        }
        await request.response.close();
      });
      try {
        final url = 'http://127.0.0.1:${server.port}/redirect';
        final entry = await openHttpLink(url);
        expect(entry.sourceUri, url);
        expect(entry.status, 'library');
        expect(entry.name, 'example.mp4');
        expect(await File(entry.torrentPath).readAsBytes(), data);
        expect(p.isWithin(root.path, entry.torrentPath), isTrue);
        await openHttpLink(url);
        expect((await repo.page()).total, 1);
        expect(engine.addedDirectories, isEmpty);
        expect(engine.tasks, isEmpty);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test(
    'invalid URL responses leave no indexed torrents or temporary files',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        try {
          if (request.uri.path == '/missing') {
            request.response.statusCode = HttpStatus.notFound;
          } else if (request.uri.path == '/large') {
            request.response.contentLength = 16 * 1024 * 1024 + 1;
            request.response.add([0]);
            await request.response.flush();
          } else {
            request.response.write('<html>Not a torrent</html>');
          }
          await request.response.close();
        } catch (_) {
          // The client intentionally rejects oversized/incomplete responses.
        }
      });
      try {
        final base = 'http://127.0.0.1:${server.port}';
        await expectLater(
          openHttpLink('$base/missing'),
          throwsA(isA<HttpException>()),
        );
        await expectLater(openHttpLink('$base/html'), throwsFormatException);
        await expectLater(openHttpLink('$base/large'), throwsFormatException);
        expect((await repo.page()).total, 0);
        expect(
          await Directory(p.join(root.path, 'link-imports')).exists(),
          isFalse,
        );
        expect(engine.tasks, isEmpty);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test(
    'link action accepts offline magnets and rejects non-web schemes',
    () async {
      final entry = await service.openLink(
        'magnet:?xt=urn:btih:${'c' * 40}&dn=Link',
      );
      expect(entry.hash, 'c' * 40);
      expect(entry.torrentPath, isEmpty);
      expect(engine.tasks, isEmpty);
      for (final source in [
        '',
        'not a url',
        'file:///secret.torrent',
        'ftp://example.com/a.torrent',
      ]) {
        await expectLater(service.openLink(source), throwsFormatException);
      }
      expect((await repo.page()).total, 1);
    },
  );

  test(
    'refresh rediscovers qBittorrent sources and imports new files with auto import disabled',
    () async {
      final file = await create(
        'qBittorrent/BT_backup/old.torrent',
        name: 'Old.mp4',
      );
      discoveredRoots = [file.parent.path];
      await service.refreshImports();
      expect((await repo.page()).total, 1);
      expect(service.autoImport, isFalse);
      await create('qBittorrent/BT_backup/new.torrent', name: 'New.mp4');
      await service.refreshImports();
      expect(discoveries, 2);
      expect((await repo.page()).total, 2);
      expect(service.scan.imported, 1);
      expect(service.scan.duplicates, 1);
      expect(engine.addedDirectories, isEmpty);
      expect(await file.exists(), isTrue);
    },
  );

  test(
    'refresh coalesces and leaves metadata maintenance to explicit scans',
    () async {
      final file = await create('qBittorrent/BT_backup/old.torrent');
      discoveredRoots = [file.parent.path];
      discoveryGate = Completer<void>();
      final a = service.refreshImports();
      final b = service.refreshImports();
      discoveryGate!.complete();
      await Future.wait([a, b]);
      expect(discoveries, 1);
      final entry = (await repo.page()).entries.single;
      await repo.update(entry.hash, {
        'metainfo_version': 0,
        'piece_length': null,
        'status': 'paused',
      });
      discoveryGate = null;
      await service.refreshImports();
      expect((await repo.get(entry.hash))!.pieceLength, isNull);
      expect(service.scan.duplicates, 1);
      await service.scanDirectories(discoveredRoots);
      final refreshed = (await repo.get(entry.hash))!;
      expect(refreshed.pieceLength, 16384);
      expect(refreshed.pieceCount, 1);
      expect(refreshed.status, 'paused');
      expect(refreshed.metainfoBytes, await file.length());
    },
  );

  test(
    'F5 only adds new source names without inspecting or moving old files',
    () async {
      final old = await create('sources/old.torrent', name: 'Old.mp4');
      await service.importFile(old.path);
      final storage = p.join(root.path, 'storage');
      await service.setLibraryDirectory(storage);
      // Simulate a persisted move policy at app startup, without running the
      // explicit organization action. F5 must leave this old file alone.
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('torrent.storageMode', 'move');
      await old.writeAsString('must never be parsed during refresh');
      final archiveOnly = File(p.join(storage, 'unindexed.torrent'));
      await archiveOnly.writeAsString('must never be scanned by F5');
      final added = await create('sources/new.torrent', name: 'New.mp4');
      discoveredRoots = [old.parent.path];
      await service.refreshImports();
      final measured = repo as _RefreshRepository;
      final initializations = measured.initializations;
      expect(measured.fullSnapshots, 0);
      expect(measured.storedPathScans, 0);
      expect(service.scan.visited, 2);
      expect(service.scan.imported, 1);
      expect(service.scan.duplicates, 1);
      expect(service.scan.failed, 0);
      expect(await old.exists(), isTrue);
      expect(await added.exists(), isFalse);
      expect((await repo.page()).total, 2);
      expect(engine.addedDirectories, isEmpty);

      await service.refreshImports();
      expect(measured.initializations, initializations);
      expect(measured.fullSnapshots, 0);
      expect(measured.storedPathScans, 0);
      expect(service.scan.visited, 1);
      expect(service.scan.duplicates, 1);
      expect(service.scan.imported, 0);
      expect(service.scan.failed, 0);
    },
  );

  test(
    'F5 skips duplicate filenames discovered during the same pass',
    () async {
      final first = await create('one/same.torrent');
      final duplicate = File(p.join(root.path, 'two', 'SAME.TORRENT'));
      await duplicate.parent.create(recursive: true);
      await duplicate.writeAsString('must not be parsed');
      discoveredRoots = [first.parent.path, duplicate.parent.path];
      await service.refreshImports();
      expect(service.scan.imported, 1);
      expect(service.scan.duplicates, 1);
      expect(service.scan.failed, 0);
      expect((await repo.page()).total, 1);
    },
  );

  test(
    'quick refresh finds nested new files and continues after a missing source',
    () async {
      final old = await create('sources/nested/old.torrent', name: 'Old.mp4');
      await service.importFile(old.path);
      await create('sources/deeper/again/new.torrent', name: 'New.mp4');
      discoveredRoots = [
        p.join(root.path, 'missing-source'),
        p.join(root.path, 'sources'),
      ];
      await service.refreshImports();
      expect(service.scan.visited, 2);
      expect(service.scan.imported, 1);
      expect(service.scan.duplicates, 1);
      expect(service.scan.failed, 1);
      expect((await repo.page()).total, 2);
    },
  );

  test('live torrent measurements persist and clear when inactive', () async {
    final file = await create('metrics.torrent');
    await service.importFile(file.path);
    var entry = (await repo.page()).entries.single;
    await service.download(entry, p.join(root.path, 'payload'));
    entry = (await repo.get(entry.hash))!;
    final task = engine.tasks[entry.gid]!;
    task.addAll({
      'status': 'active',
      'totalLength': '1000',
      'completedLength': '400',
      'downloadSpeed': '100',
      'uploadSpeed': '25',
      'uploadLength': '200',
      'numSeeders': '3',
      'connections': '8',
    });
    await service.sync();
    entry = (await repo.get(entry.hash))!;
    expect(entry.seeders, 3);
    expect(entry.connections, 8);
    expect(entry.uploadSpeed, 25);
    expect(entry.uploadedBytes, 200);
    expect(entry.eta, const Duration(seconds: 6));
    expect(entry.ratio, 0.5);

    task['numSeeders'] = '0';
    task['connections'] = '0';
    await service.sync();
    entry = (await repo.get(entry.hash))!;
    expect(entry.seeders, 0);
    expect(entry.connections, 0);
    await service.pause(entry);
    entry = (await repo.get(entry.hash))!;
    expect(entry.downloadSpeed, 0);
    expect(entry.uploadSpeed, 0);
    expect(entry.seeders, isNull);
    expect(entry.connections, isNull);
    expect(entry.eta, isNull);

    await service.resume(entry);
    task['status'] = 'active';
    task.remove('numSeeders');
    task.remove('connections');
    await service.sync();
    entry = (await repo.get(entry.hash))!;
    expect(entry.seeders, isNull);
    expect(entry.connections, isNull);
    task['status'] = 'complete';
    task['completedLength'] = '1000';
    await service.sync();
    entry = (await repo.get(entry.hash))!;
    expect(entry.status, 'complete');
    expect(entry.uploadSpeed, 0);
    expect(entry.downloadSpeed, 0);
    expect(entry.uploadedBytes, 200);
    expect(entry.eta, isNull);
  });

  test(
    'magnet follows metadata to payload and restores the saved URI',
    () async {
      var entry = await service.importMagnet(
        'magnet:?xt=urn:btih:${'a' * 40}&dn=Test',
      );
      await service.download(entry, p.join(root.path, 'payload'));
      entry = (await repo.get(entry.hash))!;
      engine.tasks[entry.gid!] = {
        'status': 'complete',
        'followedBy': ['payload-gid'],
      };
      engine.tasks['payload-gid'] = {
        'status': 'active',
        'completedLength': '50',
        'totalLength': '100',
        'downloadSpeed': '5',
        'bittorrent': {
          'info': {'name': 'Real name'},
        },
      };
      await service.sync();
      entry = (await repo.get(entry.hash))!;
      expect(entry.gid, 'payload-gid');
      expect(entry.status, 'active');
      expect(entry.name, 'Real name');
      expect(entry.totalBytes, 100);
      expect(entry.completedBytes, 50);
      engine.tasks.clear();
      await service.sync();
      expect(engine.addedMagnets.length, 2);
      expect(engine.tasks.containsKey('payload-gid'), isTrue);
    },
  );

  test(
    'pause and stop follow payload before the first metadata sync',
    () async {
      var entry = await service.importMagnet('magnet:?xt=urn:btih:${'b' * 40}');
      await service.download(entry, p.join(root.path, 'payload'));
      entry = (await repo.get(entry.hash))!;
      engine.tasks[entry.gid!] = {
        'status': 'complete',
        'followedBy': ['payload'],
      };
      engine.tasks['payload'] = {
        'status': 'active',
        'completedLength': '0',
        'downloadSpeed': '0',
      };
      await service.pause(entry);
      expect(engine.tasks['payload']!['status'], 'paused');
      await service.stop(entry);
      expect(engine.tasks.containsKey('payload'), isFalse);
      expect((await repo.get(entry.hash))!.status, 'library');
    },
  );

  test('copy mode shards metainfo, keeps originals and deduplicates', () async {
    final a = await create('inbox/a.torrent');
    final b = await create('inbox/b.torrent');
    final storage = p.join(root.path, 'storage');
    await service.setLibraryDirectory(storage);
    await service.setStorageMode('copy');
    await service.importFiles([a.path, b.path]);
    final page = await repo.page();
    expect(page.total, 1);
    final entry = page.entries.single;
    expect(
      entry.torrentPath,
      p.join(storage, entry.hash.substring(0, 2), '${entry.hash}.torrent'),
    );
    expect(await File(entry.torrentPath).exists(), isTrue);
    expect(await a.exists(), isTrue);
    expect(await b.exists(), isTrue);
    expect(service.scan.imported, 1);
    expect(service.scan.duplicates, 1);
    expect(await repo.sources(entry.hash), containsAll([a.path, b.path]));
  });

  test(
    'scan skips same filenames across folders without parsing them',
    () async {
      final file = await create('inbox/same.torrent');
      await service.importFile(file.path);
      final duplicate = File(p.join(root.path, 'another', 'SAME.TORRENT'));
      await duplicate.parent.create(recursive: true);
      // A name duplicate is skipped, so even parsing this sentinel would fail.
      await duplicate.writeAsString('must not be parsed');
      await service.scanDirectories([duplicate.parent.path]);
      expect(service.scan.visited, 1);
      expect(service.scan.duplicates, 1);
      expect(service.scan.failed, 0);
      expect((await repo.page()).total, 1);
      expect(await duplicate.exists(), isTrue);
    },
  );

  test('a changed known filename is still reimported', () async {
    final file = await create('inbox/same.torrent', name: 'First.mp4');
    await service.importFile(file.path);
    await file.writeAsBytes(torrentBytes(name: 'Second longer name.mp4'));
    await service.scanDirectories([file.parent.path]);
    expect(service.scan.imported, 1);
    expect((await repo.page()).total, 2);
  });

  test('confirmed move organizes existing indexed files', () async {
    final file = await create('outside-scan-roots/a.torrent');
    await service.importFile(file.path);
    final hash = (await repo.page()).entries.single.hash;
    await repo.update(hash, {'status': 'paused', 'completed_bytes': 42});
    final storage = p.join(root.path, 'storage');
    await service.setLibraryDirectory(storage);
    await service.setStorageMode(
      'move',
      approvedMove: await service.previewMove(),
    );
    final entry = (await repo.get(hash))!;
    expect(await file.exists(), isFalse);
    expect(p.isWithin(storage, entry.torrentPath), isTrue);
    expect(await File(entry.torrentPath).exists(), isTrue);
    expect(entry.status, 'paused');
    expect(entry.completedBytes, 42);
    await service.scanDirectories([storage]);
    expect(service.scan.visited, 1);
    expect(service.scan.duplicates, 1);
    expect(service.scan.failed, 0);
  });

  test(
    'copy to move cleans originals and changing folders moves existing archives',
    () async {
      final first = await create('inbox/a.torrent');
      final second = await create('other/b.torrent');
      final storage = p.join(root.path, 'storage');
      await service.setLibraryDirectory(storage);
      await service.setStorageMode('copy');
      await service.importFiles([first.path, second.path]);
      final originalArchive = (await repo.page()).entries.single.torrentPath;
      final archivedStat = await File(originalArchive).stat();
      await expectLater(service.setStorageMode('move'), throwsStateError);
      expect(service.storageMode, 'copy');
      expect(await first.exists(), isTrue);
      expect(await second.exists(), isTrue);
      final preview = await service.previewMove();
      expect(preview.sources.map((source) => source.path).toSet(), {
        first.path,
        second.path,
      });
      final companion = File(p.join(first.parent.path, 'a.fastresume'));
      await companion.writeAsString('client state');
      final downloaded = File(p.join(first.parent.path, 'video.mp4'));
      await downloaded.writeAsString('downloaded content');
      await service.setStorageMode('move', approvedMove: preview);
      expect(await first.exists(), isFalse);
      expect(await second.exists(), isFalse);
      expect(await companion.exists(), isTrue);
      expect(await downloaded.exists(), isTrue);
      expect(
        (await File(originalArchive).stat()).modified,
        archivedStat.modified,
      );
      final previous = (await repo.page()).entries.single.torrentPath;
      final nextStorage = p.join(root.path, 'next-storage');
      await service.setLibraryDirectory(
        nextStorage,
        approvedMove: await service.previewMove(destination: nextStorage),
      );
      final entry = (await repo.page()).entries.single;
      expect(p.isWithin(nextStorage, entry.torrentPath), isTrue);
      expect(await File(entry.torrentPath).exists(), isTrue);
      expect(await File(previous).exists(), isFalse);
      expect(service.scan.failed, 0);
    },
  );

  test(
    'confirmed cleanup is limited to the preview and skips changed sources',
    () async {
      final changed = await create('inbox/a.torrent', name: 'alpha.mp4');
      final unchanged = await create('inbox/b.torrent', name: 'second.mp4');
      await service.setLibraryDirectory(p.join(root.path, 'storage'));
      await service.setStorageMode('copy');
      await service.importFiles([changed.path, unchanged.path]);
      final preview = await service.previewMove();
      final before = await changed.stat();
      // Preserve the fingerprint: the expected info-hash must also be checked.
      await changed.writeAsBytes(torrentBytes(name: 'omega.mp4'));
      await changed.setLastModified(before.modified);
      expect(await changed.length(), before.size);
      final later = await create('inbox/later.torrent', name: 'later.mp4');
      await service.importFile(later.path);
      await service.setStorageMode('move', approvedMove: preview);
      expect(await changed.exists(), isTrue);
      expect(await unchanged.exists(), isFalse);
      expect(await later.exists(), isTrue);
      expect(service.scan.failed, 1);
      expect(service.scan.visited, 2);
      expect(
        await File(service.scanLogPath).readAsString(),
        contains(changed.path),
      );
      expect((await repo.page()).total, 3);
    },
  );

  test('a stale destination approval cannot delete source files', () async {
    final file = await create('inbox/a.torrent');
    await service.setLibraryDirectory(p.join(root.path, 'storage'));
    await service.setStorageMode('copy');
    await service.importFile(file.path);
    final preview = await service.previewMove();
    await service.setLibraryDirectory(p.join(root.path, 'another-storage'));
    await expectLater(
      service.setStorageMode('move', approvedMove: preview),
      throwsStateError,
    );
    expect(service.storageMode, 'copy');
    expect(await file.exists(), isTrue);
  });

  test(
    'move never deletes distinct torrents just because filenames match',
    () async {
      final first = await create('inbox/same.torrent', name: 'First.mp4');
      final second = await create('other/same.torrent', name: 'Second.mp4');
      await service.setLibraryDirectory(p.join(root.path, 'storage'));
      await service.setStorageMode('move');
      await service.importFiles([first.path, second.path]);
      final entries = (await repo.page()).entries;
      expect(entries, hasLength(2));
      for (final entry in entries) {
        expect(await File(entry.torrentPath).exists(), isTrue);
      }
      expect(await first.exists(), isFalse);
      expect(await second.exists(), isFalse);
      expect(service.scan.failed, 0);
    },
  );

  test(
    'move mode removes originals only after a verified archive and index',
    () async {
      final file = await create('inbox/a.torrent');
      await service.setLibraryDirectory(p.join(root.path, 'storage'));
      await service.setStorageMode('move');
      await service.importFiles([file.path]);
      final entry = (await repo.page()).entries.single;
      expect(await file.exists(), isFalse);
      expect(await File(entry.torrentPath).exists(), isTrue);
      expect(service.scan.failed, 0);
    },
  );

  test('corrupt existing archive never causes source deletion', () async {
    final file = await create('inbox/a.torrent');
    await service.setLibraryDirectory(p.join(root.path, 'storage'));
    await service.setStorageMode('copy');
    await service.importFile(file.path);
    final entry = (await repo.page()).entries.single;
    await File(entry.torrentPath).writeAsString('corrupt');
    await service.setStorageMode(
      'move',
      approvedMove: await service.previewMove(),
    );
    expect(service.scan.failed, 1);
    expect(await file.exists(), isTrue);
  });

  test(
    'scan handles overlapping roots, bad files and archive repair',
    () async {
      final file = await create('inbox/sub/a.TORRENT');
      final bad = File(p.join(root.path, 'inbox', 'broken.torrent'));
      await bad.writeAsString('bad');
      await service.setLibraryDirectory(p.join(root.path, 'storage'));
      await service.setStorageMode('copy');
      await service.scanDirectories([
        p.join(root.path, 'inbox'),
        p.join(root.path, 'inbox', 'sub'),
      ]);
      expect(service.scan.visited, 2);
      expect(service.scan.imported, 1);
      expect(service.scan.failed, 1);
      expect(
        await File(service.scanLogPath).readAsString(),
        contains(bad.path),
      );
      final entry = (await repo.page()).entries.single;
      await File(entry.torrentPath).delete();
      await service.scanDirectories([file.parent.path]);
      expect(await File(entry.torrentPath).exists(), isTrue);
      expect((await repo.page()).total, 1);
    },
  );

  test(
    'storage folder can contain originals and archived files can rebuild the index',
    () async {
      final file = await create('inbox/ab/original.torrent');
      final inbox = p.join(root.path, 'inbox');
      await service.setLibraryDirectory(inbox);
      await service.setStorageMode('copy');
      await service.scanDirectories([inbox]);
      expect((await repo.page()).total, 1);
      var entry = (await repo.page()).entries.single;
      expect(await file.exists(), isTrue);
      await repo.remove(entry.hash);
      await file.delete();
      await service.scanDirectories([inbox]);
      entry = (await repo.page()).entries.single;
      expect(await File(entry.torrentPath).exists(), isTrue);
      expect(service.scan.failed, 0);
    },
  );

  test(
    'another window cannot remove task intent without owning its engine',
    () async {
      final file = await create('a.torrent');
      await service.importFile(file.path);
      var entry = (await repo.page()).entries.single;
      await repo.update(entry.hash, {
        'status': 'active',
        'gid': entry.hash.substring(0, 16),
        'download_dir': root.path,
      });
      entry = (await repo.get(entry.hash))!;
      engine.startError = StateError('Managed by another window');
      await expectLater(service.remove(entry), throwsStateError);
      expect((await repo.get(entry.hash))!.status, 'active');
    },
  );

  test('cancelled scan can run again and reports unavailable roots', () async {
    for (var i = 0; i < 10; i++) {
      await create('inbox/$i.torrent', name: '$i.txt');
    }
    void cancel() {
      if (service.scan.running) service.cancelScan();
    }

    service.addListener(cancel);
    await service.scanDirectories([p.join(root.path, 'inbox')]);
    expect(service.scan.cancelled, isTrue);
    service.removeListener(cancel);
    await service.scanDirectories([
      p.join(root.path, 'inbox'),
      p.join(root.path, 'missing'),
    ]);
    expect(service.scan.running, isFalse);
    expect(service.scan.cancelled, isFalse);
    expect(service.scan.imported, 10);
    expect(service.scan.failed, 1);
  });

  test(
    'download persists destination and restarts pending tasks, preserving pause',
    () async {
      final file = await create('a.torrent');
      await service.importFile(file.path);
      var entry = (await repo.page()).entries.single;
      final destination = p.join(root.path, 'payload');
      await service.download(entry, destination);
      entry = (await repo.get(entry.hash))!;
      expect(entry.downloadDir, destination);
      expect(engine.addedDirectories, [destination]);
      await service.pause(entry);
      engine.tasks.clear(); // Simulate a fresh engine after app restart.
      await service.sync();
      entry = (await repo.get(entry.hash))!;
      expect(entry.status, 'paused');
      expect(engine.tasks[entry.gid]!['status'], 'paused');
      await service.resume(entry);
      expect((await repo.get(entry.hash))!.status, 'waiting');
      await service.stop(entry); // Even this stale row must read current state.
      expect((await repo.get(entry.hash))!.status, 'library');
      expect(engine.tasks, isEmpty);
      expect(await file.exists(), isTrue);
    },
  );

  test(
    'adding without immediate start persists a paused task and restores it paused',
    () async {
      final file = await create('later.torrent');
      await service.importFile(file.path);
      var entry = (await repo.page()).entries.single;
      final destination = p.join(root.path, 'later-payload');
      await service.download(entry, destination, startImmediately: false);
      entry = (await repo.get(entry.hash))!;
      expect(entry.status, 'paused');
      expect(entry.downloadDir, destination);
      expect(entry.completedBytes, 0);
      expect(engine.tasks[entry.gid]!['status'], 'paused');
      engine.tasks.clear();
      await service.sync();
      entry = (await repo.get(entry.hash))!;
      expect(entry.status, 'paused');
      expect(engine.tasks[entry.gid]!['status'], 'paused');
      await service.resume(entry);
      expect((await repo.get(entry.hash))!.status, 'waiting');
    },
  );

  test(
    'pause waits for an in-flight status reply and is not overwritten',
    () async {
      final file = await create('a.torrent');
      await service.importFile(file.path);
      var entry = (await repo.page()).entries.single;
      await service.download(entry, p.join(root.path, 'payload'));
      entry = (await repo.get(entry.hash))!;
      engine.statusGate = Completer<void>();
      engine.statusStarted = Completer<void>();
      final syncing = service.sync();
      await engine.statusStarted!.future;
      final pausing = service.pause(entry);
      engine.statusGate!.complete();
      await Future.wait([syncing, pausing]);
      expect((await repo.get(entry.hash))!.status, 'paused');
    },
  );

  test(
    'changing a paused destination replaces its task and retains existing payload',
    () async {
      final file = await create('change-folder.torrent');
      await service.importFile(file.path);
      var entry = (await repo.page()).entries.single;
      final original = p.join(root.path, 'old-download');
      final destination = p.join(root.path, 'new-download');
      await service.download(entry, original, startImmediately: false);
      final payload = await File(
        p.join(original, 'keep.mp4'),
      ).writeAsString('existing data');
      await repo.update(entry.hash, {'completed_bytes': 4});
      entry = (await repo.get(entry.hash))!;
      await service.download(entry, destination, startImmediately: false);
      final updated = (await repo.get(entry.hash))!;
      expect(updated.downloadDir, destination);
      expect(updated.status, 'paused');
      expect(updated.completedBytes, 0);
      expect(engine.addedDirectories, [original, destination]);
      expect(engine.tasks, hasLength(1));
      expect(engine.tasks[updated.gid]!['status'], 'paused');
      expect(await payload.readAsString(), 'existing data');
      expect(await file.exists(), isTrue);
      await service.resume(updated);
      await expectLater(service.download(updated, original), throwsStateError);
      expect((await repo.get(entry.hash))!.downloadDir, destination);
      expect(engine.addedDirectories, [original, destination]);
    },
  );

  test(
    'changed indexed metainfo is rejected before a download starts',
    () async {
      final file = await create('a.torrent');
      await service.importFile(file.path);
      final entry = (await repo.page()).entries.single;
      await file.writeAsBytes(torrentBytes(name: 'different.mp4'));
      await expectLater(
        service.download(entry, p.join(root.path, 'payload')),
        throwsFormatException,
      );
      expect(engine.addedDirectories, isEmpty);
    },
  );

  test('removing from index retains all files and stops the task', () async {
    final file = await create('a.torrent');
    await service.importFile(file.path);
    final entry = (await repo.page()).entries.single;
    final destination = p.join(root.path, 'payload');
    await service.download(entry, destination);
    final payload = File(p.join(destination, 'keep.mp4'));
    await payload.writeAsString('retain me');
    await service.remove(entry);
    expect((await repo.page()).total, 0);
    expect(await file.exists(), isTrue);
    expect(await payload.readAsString(), 'retain me');
    expect(engine.tasks, isEmpty);
  });
}

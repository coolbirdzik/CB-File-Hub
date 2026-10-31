import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cb_file_manager/services/torrent/aria2_engine.dart';
import 'package:cb_file_manager/services/torrent/qbittorrent_backup_importer.dart';
import 'package:cb_file_manager/services/torrent/torrent_metainfo.dart';
import 'package:cb_file_manager/services/torrent/torrent_repository.dart';
import 'package:cb_file_manager/services/torrent/torrent_service.dart';
import 'package:cb_file_manager/services/torrent/windows_qbittorrent_process.dart';
import 'torrent_fixtures.dart';

class _NoDownloads extends Aria2Engine {
  @override
  Future<void> start(
    String stateDirectory, {
    String? executable,
    bool takeOver = false,
  }) async {
    throw StateError('Import must not start payload downloads');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory backup;
  late String destination;
  late Database db;
  late TorrentRepository repository;
  late TorrentService service;
  late QbittorrentBackupImporter importer;
  Future<({String hash, File torrent, File resume})> create(String name) async {
    final bytes = torrentBytes(name: name);
    final hash = TorrentMetainfo.parse(bytes).hash;
    final torrent = File(p.join(backup.path, '$hash.torrent'));
    final resume = File(p.join(backup.path, '$hash.fastresume'));
    await torrent.writeAsBytes(bytes);
    await resume.writeAsBytes(
      bencode({
        'file-format': 'libtorrent resume file',
        'info-hash': Uint8List.fromList([
          for (var i = 0; i < hash.length; i += 2)
            int.parse(hash.substring(i, i + 2), radix: 16),
        ]),
        'qBt-name': name,
        'qBt-savePath': p.join(root.path, 'existing-payload'),
        'qBt-category': 'Movies',
        'added_time': 1737096422,
        'total_downloaded': 999999,
        'num_complete': 16777215,
        'trackers': [
          ['https://tracker.example/announce'],
        ],
      }),
    );
    return (hash: hash, torrent: torrent, resume: resume);
  }

  Future<QbittorrentImportPlan> preview() =>
      QbittorrentBackupImporter.preview([backup.path]);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cb-qbit-import-');
    backup = await Directory(
      p.join(root.path, 'profile', 'BT_backup'),
    ).create(recursive: true);
    destination = p.join(root.path, 'library');
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    repository = TorrentRepository(db);
    await repository.initialize();
    SharedPreferences.setMockInitialValues({
      'torrent.autoImport': false,
      'torrent.storageMode': 'move',
    });
    service = TorrentService.forTesting(
      repository: repository,
      preferences: await SharedPreferences.getInstance(),
      stateDirectory: p.join(root.path, 'state'),
      engine: _NoDownloads(),
    );
    importer = service.qbittorrentImporter(isRunning: () async => false);
  });
  tearDown(() async {
    service.dispose();
    await db.close();
    // Only the exact temporary root created by this test is removed.
    expect(p.isWithin(Directory.systemTemp.path, root.path), isTrue);
    await root.delete(recursive: true);
  });

  test(
    'discovers Windows roots and groups only matching qBit source files',
    () async {
      final first = await create('First.mp4');
      await create('Second.mp4');
      await File(
        p.join(backup.path, 'unrelated.fastresume'),
      ).writeAsString('keep');
      final nested = await Directory(p.join(backup.path, 'nested')).create();
      await File(
        p.join(nested.path, '${first.hash}.torrent'),
      ).writeAsString('ignored');
      final roaming = await Directory(
        p.join(root.path, 'Roaming', 'qBittorrent', 'BT_backup'),
      ).create(recursive: true);
      final found = await QbittorrentBackupImporter.discoverWindowsRoots(
        environment: {'APPDATA': p.dirname(p.dirname(roaming.path))},
      );
      expect(found, [roaming.path]);
      final plan = await preview();
      expect(plan.items, hasLength(2));
      expect(plan.fileCount, 4);
    },
  );

  test(
    'import always copies even in Move mode, without touching qBit or payload',
    () async {
      final item = await create('First.mp4');
      final before = DateTime.now().millisecondsSinceEpoch;
      final result = await importer.run(await preview(), destination);
      final after = DateTime.now().millisecondsSinceEpoch;
      expect(result.stored, 1);
      expect(result.cleaned, 0);
      expect(result.failed, 0);
      expect(await item.torrent.exists(), isTrue);
      expect(await item.resume.exists(), isTrue);
      expect(service.storageMode, 'move');
      final entry = (await repository.get(item.hash))!;
      expect(
        entry.addedAt.millisecondsSinceEpoch,
        inInclusiveRange(before, after),
      );
      expect(p.isWithin(destination, entry.torrentPath), isTrue);
      expect(
        TorrentMetainfo.parse(await File(entry.torrentPath).readAsBytes()).hash,
        item.hash,
      );
      expect(entry.status, 'library');
    },
  );

  test(
    'copy-only import tolerates qBit updating fastresume while running',
    () async {
      final item = await create('Running.mp4');
      final plan = await preview();
      await item.resume.writeAsString('qBit updated progress after preview');
      var checks = 0;
      final running = service.qbittorrentImporter(
        isRunning: () async {
          checks++;
          return true;
        },
      );
      final result = await running.run(plan, destination);
      expect(result.stored, 1);
      expect(result.failed, 0);
      expect(checks, 0);
      expect(await item.torrent.exists(), isTrue);
      expect(await item.resume.exists(), isTrue);
    },
  );

  test(
    'cleanup requires confirmation and removes only verified matching files',
    () async {
      final item = await create('First.mp4');
      final payload = File(p.join(backup.path, 'downloaded.mp4'));
      await payload.writeAsString('keep payload');
      final other = File(p.join(backup.path, 'other.fastresume'));
      await other.writeAsString('keep unrelated state');
      final plan = await preview();
      await expectLater(
        importer.run(plan, destination, removeSources: true),
        throwsStateError,
      );
      expect((await repository.page()).total, 0);
      final result = await importer.run(
        plan,
        destination,
        removeSources: true,
        confirmedRemoval: true,
      );
      expect(result.cleaned, 1);
      expect(result.failed, 0);
      expect(await item.torrent.exists(), isFalse);
      expect(await item.resume.exists(), isFalse);
      expect(await payload.exists(), isTrue);
      expect(await other.exists(), isTrue);
      expect(
        await File((await repository.get(item.hash))!.torrentPath).exists(),
        isTrue,
      );
    },
  );

  test(
    'resume-only entries use retained indexed metainfo and can be cleaned',
    () async {
      final item = await create('Already imported.mp4');
      await importer.run(await preview(), destination);
      await item.torrent.delete();
      final result = await importer.run(
        await preview(),
        destination,
        removeSources: true,
        confirmedRemoval: true,
      );
      expect(result.cleaned, 1);
      expect(result.failed, 0);
      expect(await item.resume.exists(), isFalse);
      expect(
        await File((await repository.get(item.hash))!.torrentPath).exists(),
        isTrue,
      );
    },
  );

  test(
    'missing metainfo recovers offline magnet; invalid metainfo is retained',
    () async {
      final missing = await create('Missing.mp4');
      final invalid = await create('Invalid.mp4');
      await missing.torrent.delete();
      await invalid.torrent.writeAsString('invalid torrent');
      final before = DateTime.now().millisecondsSinceEpoch;
      final result = await importer.run(
        await preview(),
        destination,
        removeSources: true,
        confirmedRemoval: true,
      );
      final after = DateTime.now().millisecondsSinceEpoch;
      expect(result.stored, 1);
      expect(result.cleaned, 1);
      expect(result.failed, 1);
      expect(await missing.resume.exists(), isFalse);
      final entry = (await repository.get(missing.hash))!;
      expect(entry.torrentPath, isEmpty);
      expect(entry.sourceUri, contains('urn:btih:${missing.hash}'));
      expect(entry.name, 'Missing.mp4');
      expect(entry.downloadDir, p.join(root.path, 'existing-payload'));
      expect(entry.group, 'Movies');
      expect(entry.trackers, ['https://tracker.example/announce']);
      expect(
        entry.addedAt.millisecondsSinceEpoch,
        inInclusiveRange(before, after),
      );
      expect(entry.status, 'library');
      expect(entry.completedBytes, 0);
      expect(entry.seeders, isNull);
      expect(await invalid.resume.exists(), isTrue);
      expect(await invalid.torrent.exists(), isTrue);
      expect(
        await File(importer.logPath).readAsString(),
        contains(invalid.torrent.path),
      );
    },
  );

  test(
    'resume-only copy retains exact backup and deduplicates on retry',
    () async {
      final item = await create('Resume only.mp4');
      await item.torrent.delete();
      final bytes = await item.resume.readAsBytes();
      final plan = await preview();
      DateTime? addedAt;
      for (var i = 0; i < 2; i++) {
        final result = await importer.run(plan, destination);
        expect(result.stored, 1);
        expect(result.failed, 0);
        final entry = (await repository.get(item.hash))!;
        addedAt ??= entry.addedAt;
        expect(entry.addedAt, addedAt);
      }
      expect((await repository.page()).total, 1);
      expect(await item.resume.readAsBytes(), bytes);
      final archive = plan.items.single.resumeArchivePath(
        item.resume.path,
        destination,
      );
      expect(await File(archive).readAsBytes(), bytes);
    },
  );

  test(
    'resume recovery upgrades old schema and preserves this app task state',
    () async {
      final item = await create('Existing task.mp4');
      final bytes = await item.torrent.readAsBytes();
      final stat = await item.torrent.stat();
      await repository.import(
        TorrentMetainfo.parse(bytes),
        item.torrent.path,
        item.torrent.path,
        stat.modified.microsecondsSinceEpoch,
        stat.size,
      );
      await repository.update(item.hash, {
        'status': 'paused',
        'gid': 'existing-task',
        'completed_bytes': 3,
        'download_dir': p.join(root.path, 'app-payload'),
        'group_name': 'User group',
      });
      final addedAt = (await repository.get(item.hash))!.addedAt;
      await item.torrent.delete();
      await db.execute(
        'ALTER TABLE torrents DROP COLUMN qbittorrent_resume_path',
      );
      await db.execute(
        'ALTER TABLE torrents DROP COLUMN qbittorrent_resume_digest',
      );
      final result = await importer.run(await preview(), destination);
      expect(result.stored, 1);
      expect(result.failed, 0);
      final entry = (await repository.get(item.hash))!;
      expect(entry.addedAt, addedAt);
      expect(entry.status, 'paused');
      expect(entry.gid, 'existing-task');
      expect(entry.completedBytes, 3);
      expect(entry.downloadDir, p.join(root.path, 'app-payload'));
      expect(entry.group, 'User group');
      expect(entry.torrentPath, isEmpty);
    },
  );

  test('corrupt or mismatched resume-only state is never removed', () async {
    final corrupt = await create('Corrupt.mp4');
    final mismatch = await create('Mismatch.mp4');
    await corrupt.torrent.delete();
    await mismatch.torrent.delete();
    await mismatch.resume.writeAsBytes(await corrupt.resume.readAsBytes());
    await corrupt.resume.writeAsString('broken bencode');
    final result = await importer.run(
      await preview(),
      destination,
      removeSources: true,
      confirmedRemoval: true,
    );
    expect(result.stored, 0);
    expect(result.failed, 2);
    expect(await corrupt.resume.exists(), isTrue);
    expect(await mismatch.resume.exists(), isTrue);
    expect((await repository.page()).total, 0);
  });

  test(
    'finds alternate indexed metainfo when canonical file disappeared',
    () async {
      final item = await create('Alternate.mp4');
      final bytes = await item.torrent.readAsBytes();
      final alternate = File(p.join(root.path, 'alternate.torrent'));
      await alternate.writeAsBytes(bytes);
      final stat = await alternate.stat();
      await repository.import(
        TorrentMetainfo.parse(bytes),
        p.join(root.path, 'missing.torrent'),
        alternate.path,
        stat.modified.microsecondsSinceEpoch,
        stat.size,
      );
      await item.torrent.delete();
      final result = await importer.run(await preview(), destination);
      expect(result.stored, 1);
      expect(result.failed, 0);
      final entry = (await repository.get(item.hash))!;
      expect(p.isWithin(destination, entry.torrentPath), isTrue);
      expect(await alternate.exists(), isTrue);
    },
  );

  test(
    'embedded original info recovers full torrent without a source torrent',
    () async {
      final item = await create('Embedded.mp4');
      final rawHash = Uint8List.fromList([
        for (var i = 0; i < item.hash.length; i += 2)
          int.parse(item.hash.substring(i, i + 2), radix: 16),
      ]);
      await item.resume.writeAsBytes(
        bencode({
          'file-format': 'libtorrent resume file',
          'info-hash': rawHash,
          'info': torrentInfo(name: 'Embedded.mp4'),
        }),
      );
      await item.torrent.delete();
      final result = await importer.run(
        await preview(),
        destination,
        removeSources: true,
        confirmedRemoval: true,
      );
      expect(result.stored, 1);
      expect(result.cleaned, 1);
      expect(result.failed, 0);
      final entry = (await repository.get(item.hash))!;
      expect(
        TorrentMetainfo.parse(await File(entry.torrentPath).readAsBytes()).hash,
        item.hash,
      );
      expect(await item.resume.exists(), isFalse);
    },
  );

  test(
    'resume backup tampering blocks cleanup even with valid metainfo',
    () async {
      final item = await create('Backup verification.mp4');
      final plan = await preview();
      final altered = QbittorrentBackupImporter(
        save: (item, destination) async {
          await importer.save(item, destination);
          await File(
            item.resumeArchivePath(
              item.files
                  .firstWhere((file) => file.path.endsWith('.fastresume'))
                  .path,
              destination,
            ),
          ).writeAsString('damaged backup');
        },
        verify: importer.verify,
        verifyResumeCopies: importer.verifyResumeCopies,
        logPath: importer.logPath,
        isRunning: () async => false,
      );
      final result = await altered.run(
        plan,
        destination,
        removeSources: true,
        confirmedRemoval: true,
      );
      expect(result.cleaned, 0);
      expect(result.failed, 1);
      expect(await item.torrent.exists(), isTrue);
      expect(await item.resume.exists(), isTrue);
    },
  );

  test(
    'a running qBit or SQLite profile blocks cleanup before importing',
    () async {
      final item = await create('First.mp4');
      final running = service.qbittorrentImporter(isRunning: () async => true);
      await expectLater(
        running.run(
          await preview(),
          destination,
          removeSources: true,
          confirmedRemoval: true,
        ),
        throwsA(isA<QbittorrentImportException>()),
      );
      await File(
        p.join(backup.parent.path, 'torrents.db'),
      ).writeAsString('sqlite state');
      await expectLater(
        importer.run(
          await preview(),
          destination,
          removeSources: true,
          confirmedRemoval: true,
        ),
        throwsA(isA<QbittorrentImportException>()),
      );
      expect(await item.torrent.exists(), isTrue);
      expect(await item.resume.exists(), isTrue);
      expect((await repository.page()).total, 0);
    },
  );

  test(
    'verification failure after staging restores both source files',
    () async {
      final item = await create('First.mp4');
      var verifications = 0;
      final failing = QbittorrentBackupImporter(
        save: importer.save,
        logPath: importer.logPath,
        isRunning: () async => false,
        verify: (hash, folder) async {
          if (++verifications == 2) {
            throw StateError('Stored archive disappeared');
          }
          await importer.verify(hash, folder);
        },
      );
      final result = await failing.run(
        await preview(),
        destination,
        removeSources: true,
        confirmedRemoval: true,
      );
      expect(result.cleaned, 0);
      expect(result.failed, 1);
      expect(await item.torrent.exists(), isTrue);
      expect(await item.resume.exists(), isTrue);
      expect(
        (await backup.list().toList()).where(
          (file) => file.path.endsWith('.cleanup'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'qBit starting during cleanup restores files and stops the job',
    () async {
      final item = await create('First.mp4');
      var checks = 0;
      final starting = service.qbittorrentImporter(
        isRunning: () async => ++checks >= 4,
      );
      final result = await starting.run(
        await preview(),
        destination,
        removeSources: true,
        confirmedRemoval: true,
      );
      expect(result.stoppedBy, QbittorrentImportProblem.running);
      expect(result.cleaned, 0);
      expect(await item.torrent.exists(), isTrue);
      expect(await item.resume.exists(), isTrue);
    },
  );

  test(
    'changed sources, late arrivals and cancellation never broaden cleanup',
    () async {
      final item = await create('First.mp4');
      final plan = await preview();
      await item.resume.writeAsString('changed source data');
      final later = await create('Later.mp4');
      final result = await importer.run(
        plan,
        destination,
        removeSources: true,
        confirmedRemoval: true,
      );
      expect(result.failed, 1);
      expect(await later.torrent.exists(), isTrue);
      expect(await later.resume.exists(), isTrue);
      expect(await item.resume.exists(), isTrue);
      var cancelled = false;
      final cancelling = QbittorrentBackupImporter(
        logPath: importer.logPath,
        isRunning: () async => false,
        verify: importer.verify,
        save: (item, folder) async {
          await importer.save(item, folder);
          cancelled = true;
        },
      );
      final cancelledResult = await cancelling.run(
        await preview(),
        destination,
        removeSources: true,
        confirmedRemoval: true,
        isCancelled: () => cancelled,
      );
      expect(cancelledResult.cancelled, isTrue);
      expect(cancelledResult.cleaned, 0);
      expect(await later.torrent.exists(), isTrue);
    },
  );

  test(
    'same-size source changes during import are restored instead of deleted',
    () async {
      final item = await create('First.mp4');
      final before = await item.resume.stat();
      final changing = QbittorrentBackupImporter(
        logPath: importer.logPath,
        isRunning: () async => false,
        verify: importer.verify,
        save: (candidate, folder) async {
          await importer.save(candidate, folder);
          await item.resume.writeAsString('x' * before.size);
          await item.resume.setLastModified(before.modified);
        },
      );
      final result = await changing.run(
        await preview(),
        destination,
        removeSources: true,
        confirmedRemoval: true,
      );
      expect(result.failed, 1);
      expect(result.cleaned, 0);
      expect(await item.resume.exists(), isTrue);
      expect(await item.torrent.exists(), isTrue);
    },
  );

  test(
    'service coordinates imports with scan state and remembers chosen folders',
    () async {
      await create('Coordinated.mp4');
      var sawRunning = false;
      service.addListener(() {
        sawRunning = sawRunning || service.scan.running;
      });
      final result = await service.importQbittorrent(
        await preview(),
        destination,
        removeSources: false,
        confirmedRemoval: false,
        isCancelled: () => false,
        onProgress: (_, _) => expect(service.scan.running, isTrue),
      );
      expect(result.stored, 1);
      expect(sawRunning, isTrue);
      expect(service.scan.running, isFalse);
      expect(service.scan.visited, 1);
      expect(service.scanLogPath, service.qbittorrentLogPath);
      expect(service.qbittorrentSources, [backup.path]);
      expect(service.qbittorrentImportDirectory, destination);
    },
  );

  test('native process inventory is read-only and returns a boolean', () {
    if (Platform.isWindows) {
      expect(WindowsQbittorrentProcess.isRunning(), isA<bool>());
    }
  });
}

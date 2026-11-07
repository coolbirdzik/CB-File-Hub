import 'dart:io';
import 'package:cb_file_manager/services/media/subtitle_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SubtitleCache cache;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE unrelated (value TEXT)');
    await db.insert('unrelated', {'value': 'keep'});
    cache = SubtitleCache(openDatabase: () async => db);
  });
  tearDown(() => db.close());

  test(
    'saved subtitles survive closing and reopening the database file',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'subtitle-persistence-',
      );
      final path = '${dir.path}/app.sqlite';
      try {
        final first = await databaseFactoryFfi.openDatabase(path);
        final writer = SubtitleCache(openDatabase: () async => first);
        await writer.save('video', await writer.revision(), 0, 8000, [
          const LocalSubtitleCue(0, 8000, 'original', 'translation'),
        ]);
        await first.close();
        final second = await databaseFactoryFfi.openDatabase(path);
        try {
          final reader = SubtitleCache(openDatabase: () async => second);
          expect(
            (await reader.read('video', 0, 8000)).cues.single.text,
            'translation',
          );
        } finally {
          await second.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'reopening restores text and silent intervals, with bounded cue reads',
    () async {
      final revision = await cache.revision();
      await cache.save('video', revision, 0, 8000, [
        const LocalSubtitleCue(0, 8000, 'hello', 'xin chào'),
      ]);
      await cache.save('video', revision, 8000, 16000, []);
      await cache.save('video', revision, 50000, 58000, [
        const LocalSubtitleCue(50000, 58000, 'later', 'sau đó'),
      ]);
      final reopened = SubtitleCache(openDatabase: () async => db);
      final saved = await reopened.read('video', 0, 16000);
      expect(saved.ranges.length, 2);
      expect(saved.ranges.first.start.inMilliseconds, 0);
      expect(saved.ranges.first.end.inMilliseconds, 16000);
      expect(saved.ranges.last.start.inMilliseconds, 50000);
      expect(saved.cues.single.text, 'xin chào');
      expect(saved.cues.single.original, 'hello');
      expect((await cache.stats()).entries, 1);
      expect((await cache.stats()).bytes, greaterThan(0));
      expect((await cache.read('other-language', 0, 16000)).ranges, isEmpty);
    },
  );

  test(
    'clearing one version rejects late writers across repository instances',
    () async {
      final revision = await cache.revision();
      await cache.save('one', revision, 0, 8, []);
      await cache.save('two', revision, 0, 8, []);
      final other = SubtitleCache(openDatabase: () async => db);
      await other.clear(key: 'one');
      expect(await cache.save('one', revision, 8, 16, []), isFalse);
      expect((await cache.read('one', 0, 16)).ranges, isEmpty);
      expect((await cache.read('two', 0, 16)).ranges, hasLength(1));
      await cache.clear();
      expect((await cache.stats()).entries, 0);
      expect((await db.query('unrelated')).single['value'], 'keep');
    },
  );

  test('source fingerprint changes when the same file is replaced', () async {
    final dir = await Directory.systemTemp.createTemp('subtitle-fingerprint-');
    try {
      final file = File('${dir.path}/movie.mp4');
      await file.writeAsBytes([1]);
      final first = await subtitleSourceFingerprint(file.path, file.path);
      expect(first, isNotNull);
      expect(await subtitleSourceFingerprint(file.path, file.path), first);
      await file.writeAsBytes([1, 2]);
      expect(
        await subtitleSourceFingerprint(file.path, file.path),
        isNot(first),
      );
      expect(
        await subtitleSourceFingerprint(
          '${dir.path}/missing',
          '${dir.path}/missing',
        ),
        isNull,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test(
    'concurrent overlapping chunks retain one result and preserve gaps',
    () async {
      final revision = await cache.revision();
      expect(
        await cache.save('video', revision, 4000, 12000, [
          const LocalSubtitleCue(4000, 12000, 'first', 'first'),
        ]),
        isTrue,
      );
      final other = SubtitleCache(openDatabase: () async => db);
      expect(
        await other.save('video', revision, 0, 8000, [
          const LocalSubtitleCue(0, 8000, 'duplicate', 'duplicate'),
        ]),
        isFalse,
      );
      final snapshot = await cache.read('video', 0, 20000);
      expect(snapshot.cues.single.text, 'first');
      expect(snapshot.ranges.single.start.inMilliseconds, 4000);
    },
  );

  test(
    'HTTP cache requires validators and excludes credentials from stored identity',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var version = 'v1';
      var validated = true;
      server.listen((request) async {
        if (validated) {
          request.response.headers.set(HttpHeaders.etagHeader, version);
        }
        request.response.contentLength = 123;
        await request.response.close();
      });
      try {
        final url = 'http://127.0.0.1:${server.port}/movie?token=secret';
        final first = await subtitleSourceFingerprint(url, url);
        expect(first, matches(RegExp(r'^[a-f0-9]{64}$')));
        version = 'v2';
        expect(await subtitleSourceFingerprint(url, url), isNot(first));
        validated = false;
        expect(await subtitleSourceFingerprint(url, url), isNull);
      } finally {
        await server.close(force: true);
      }
    },
  );
}

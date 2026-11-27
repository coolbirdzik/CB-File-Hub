import 'dart:io';
import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:flutter/services.dart';

import 'package:cb_file_manager/services/media/subtitle_srt.dart';
import 'package:cb_file_manager/services/media/subtitle_srt_ownership.dart';
import 'package:cb_file_manager/services/media/subtitle_video_deletion.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_models.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_store.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_generated_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory dir;
  late Database db;
  late SubtitleBatchStore store;
  late SharedPreferences prefs;
  late String video;
  late SubtitleVideoDeletion deletion;
  final calls = <String>[];
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cb-subtitle-delete-');
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    store = SubtitleBatchStore(openDatabase: () async => db);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    deletion = SubtitleVideoDeletion(store: store, prefs: prefs);
    video = p.join(dir.path, 'movie.mp4');
    await File(video).writeAsString('video');
    calls.clear();
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });
  Future<Set<String>> remove(List<String> paths) async {
    calls.addAll(paths);
    for (final path in paths) {
      if (await File(path).exists()) await File(path).delete();
    }
    return paths.toSet();
  }

  Future<String> write({
    String language = 'vi',
    SubtitleFileMode mode = SubtitleFileMode.subsFolder,
  }) async => (await SubtitleSrtWriter(prefs, setHidden: (_, _) async {}).write(
    videoPath: video,
    language: language,
    mode: mode,
    bytes: srtBytes('AI subtitles'),
  )).path;

  test('deletes automatic Subs and hidden sidecars after the video', () async {
    final subs = await write();
    final hidden = await write(
      language: 'en',
      mode: SubtitleFileMode.besideHidden,
    );
    final result = await deletion.delete([video], operation: remove);
    expect(result, {video});
    expect(calls.first, video);
    expect(await File(subs).exists(), isFalse);
    expect(await File(hidden).exists(), isFalse);
    expect(await SubtitleSrtOwnership.read(prefs), isEmpty);
  });

  test('video failure leaves subtitles untouched', () async {
    final output = await write();
    expect(await deletion.delete([video], operation: (_) async => {}), isEmpty);
    expect(await File(output).exists(), isTrue);
  });

  test(
    'a late automatic export cannot recreate SRT after video deletion',
    () async {
      final writer = SubtitleSrtWriter(
        prefs,
        setHidden: (_, hidden) async {
          if (hidden && await File(video).exists()) await File(video).delete();
        },
      );
      await expectLater(
        writer.write(
          videoPath: video,
          language: 'vi',
          mode: SubtitleFileMode.besideHidden,
          bytes: srtBytes('late export'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(p.join(dir.path, 'movie.vi.srt')).exists(), isFalse);
    },
  );

  test('keeps foreign, edited and legacy-unverified subtitles', () async {
    final edited = await write();
    await File(edited).writeAsString('user edits');
    final foreign = p.join(dir.path, 'movie.en.srt');
    await File(foreign).writeAsString('external');
    final legacy = p.join(dir.path, 'movie.ja.srt');
    await File(legacy).writeAsString('legacy');
    await prefs.setStringList(SubtitleSrtWriter.writtenKey, [legacy]);
    await deletion.delete([video], operation: remove);
    for (final path in [edited, foreign, legacy]) {
      expect(await File(path).exists(), isTrue);
    }
  });

  test('cleans a manual AI export at its recorded destination', () async {
    final output = p.join(dir.path, 'custom-export.srt');
    final bytes = srtBytes('manual export');
    await File(output).writeAsBytes(bytes);
    await SubtitleSrtOwnership.remember(
      prefs,
      video: video,
      output: output,
      bytes: bytes,
    );
    await deletion.delete([video], operation: remove);
    expect(await File(output).exists(), isFalse);
  });

  test(
    'legacy batch metadata proves ownership and removes cbmeta with SRT',
    () async {
      const settings = SubtitleBatchSettings(
        speechModel: 'whisper/small',
        sourceLanguage: 'auto',
        translationModel: 'translator',
        targetLanguage: 'vi',
      );
      final output = p.join(dir.path, 'movie.vi.srt');
      final bytes = srtBytes('batch');
      await File(output).writeAsBytes(bytes);
      final metadata = SubtitleGeneratedMetadata(
        settings: settings,
        generatedAt: DateTime(2026),
        outputPath: output,
        outputSha256: SubtitleGeneratedMetadata.hash(bytes),
      );
      await store.recordGenerated(
        SubtitleBatchJob(
          id: 1,
          path: video,
          ruleName: '',
          settings: settings,
          status: SubtitleBatchStatus.done,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        metadata,
      );
      await metadata.writeSidecar();
      await deletion.delete([video], operation: remove);
      expect(await File(output).exists(), isFalse);
      expect(
        await File(SubtitleGeneratedMetadata.sidecarPath(output)).exists(),
        isFalse,
      );
    },
  );

  test('a shared output now owned by another source is retained', () async {
    final output = await write();
    final other = p.join(dir.path, 'movie.mkv');
    await SubtitleSrtOwnership.remember(
      prefs,
      video: other,
      output: output,
      bytes: srtBytes('AI subtitles'),
    );
    await deletion.delete([video], operation: remove);
    expect(await File(output).exists(), isTrue);
  });

  test(
    'companion deletion failure is reported instead of full success',
    () async {
      final output = await write();
      final errors = <String, Object>{};
      final result = await deletion.delete(
        [video],
        operation: (paths) async {
          if (paths.contains(output)) return {};
          return remove(paths);
        },
        onError: (path, error) => errors[path] = error,
      );
      expect(result, isEmpty);
      expect(errors[video].toString(), contains('Video deleted'));
      expect(await File(output).exists(), isTrue);
    },
  );

  for (final permanent in [false, true]) {
    test(
      'TrashManager cascades using the same delete mode ($permanent)',
      () async {
        final output = await write();
        final trash = TrashManager.forTesting(deletion);
        const channel = MethodChannel('cb_file_manager/file_operations');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final flags = <bool>[];
        final recycle = await Directory(p.join(dir.path, 'recycle')).create();
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'deleteItems') return null;
          final args = call.arguments as Map;
          flags.add(args['permanent'] as bool);
          for (final path in (args['sources'] as List).cast<String>()) {
            await File(path).rename(p.join(recycle.path, p.basename(path)));
          }
          return true;
        });
        try {
          final removed = permanent
              ? await trash.deleteMultiplePermanently([video], useNative: false)
              : await trash.moveMultipleToTrashBatched([video]);
          expect(removed, {video});
          expect(await File(output).exists(), isFalse);
          if (!permanent) {
            expect(flags, [false, false]);
            expect(
              await File(p.join(recycle.path, p.basename(output))).exists(),
              isTrue,
            );
          }
        } finally {
          messenger.setMockMethodCallHandler(channel, null);
        }
      },
      skip: !Platform.isWindows && !permanent,
    );
  }
}

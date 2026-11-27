import 'dart:io';

import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_models.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_store.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_generated_cleanup.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_generated_metadata.dart';
import 'package:cb_file_manager/services/media/subtitle_cache.dart';
import 'package:cb_file_manager/services/media/subtitle_srt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const settings = SubtitleBatchSettings(
  speechModel: 'whisper/small',
  translationModel: 'translation/model',
  sourceLanguage: 'ja',
  targetLanguage: 'vi',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  late Database db;
  late SubtitleBatchStore store;
  late SubtitleCache cache;
  late SharedPreferences prefs;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('subtitle-clean-test');
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    store = SubtitleBatchStore(openDatabase: () async => db);
    cache = SubtitleCache(openDatabase: () async => db);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<SubtitleBatchJob> complete(
    String name, {
    bool metadata = true,
    bool appOnly = false,
    int? ruleId,
  }) async {
    final source = await File(
      p.join(root.path, '$name.mp4'),
    ).writeAsString('video');
    await store.enqueue(
      [source.path],
      settings: settings,
      ruleName: 'test',
      ruleId: ruleId,
    );
    final job = (await store.claimNext())!;
    final bytes = srtBytes('generated $name');
    final output = appOnly
        ? null
        : (await SubtitleSrtWriter(prefs, setHidden: (_, _) async {}).write(
            videoPath: source.path,
            language: settings.targetLanguage,
            mode: SubtitleFileMode.subsFolder,
            bytes: bytes,
          )).path;
    if (metadata) {
      final generated = SubtitleGeneratedMetadata(
        settings: settings,
        generatedAt: DateTime.now(),
        cacheKey: name,
        outputPath: output,
        outputSha256: output == null
            ? null
            : SubtitleGeneratedMetadata.hash(bytes),
      );
      await generated.writeSidecar();
      await store.recordGenerated(job, generated);
      await cache.save(name, await cache.revision(), 0, 1000, const []);
    }
    await store.finish(
      job,
      SubtitleBatchStatus.done,
      outputPath: output,
      progress: 1,
    );
    return (await store.job(job.id))!;
  }

  test(
    'cleans owned SRT, metadata and exact cache; requeues the job',
    () async {
      final job = await complete('movie');
      final output = job.outputPath!;
      final saved = await SubtitleGeneratedMetadata.readSidecar(output);
      expect(saved?.settings.speechModel, settings.speechModel);
      expect(saved?.settings.translationModel, settings.translationModel);
      expect(
        (await store.generatedMetadata(job))?.outputSha256,
        saved?.outputSha256,
      );
      await cache.save('unrelated', await cache.revision(), 0, 1000, const []);
      final report = await SubtitleGeneratedCleanup(
        store,
        cache,
        prefs,
      ).clean();
      expect(report.cleaned, 1);
      expect(report.failed, 0);
      expect(await File(output).exists(), isFalse);
      expect(
        await File(SubtitleGeneratedMetadata.sidecarPath(output)).exists(),
        isFalse,
      );
      expect(await File(job.path).exists(), isTrue);
      expect((await cache.stats()).entries, 1);
      expect((await store.job(job.id))?.status, SubtitleBatchStatus.pending);
      expect(await store.generatedMetadata(job), isNull);
    },
  );

  test('keeps edited subtitles and skipped external files', () async {
    final job = await complete('edited');
    await File(job.outputPath!).writeAsString('user edit');
    final external = await File(
      p.join(root.path, 'external.vi.srt'),
    ).writeAsString('external');
    await store.enqueue(
      [p.join(root.path, 'external.mp4')],
      settings: settings,
      ruleName: 'test',
      status: SubtitleBatchStatus.skipped,
      outputs: {p.join(root.path, 'external.mp4'): external.path},
    );
    final report = await SubtitleGeneratedCleanup(store, cache, prefs).clean();
    expect(report.retained, 1);
    expect(report.cleaned, 0);
    expect(await File(job.outputPath!).readAsString(), 'user edit');
    expect(await external.readAsString(), 'external');
    expect((await store.job(job.id))?.status, SubtitleBatchStatus.done);
  });

  test(
    'cleans app-only cache and known legacy output in selected rule',
    () async {
      SubtitleBatchRule rule(String name) => SubtitleBatchRule(
        name: name,
        speechModel: settings.speechModel,
        sourceLanguage: settings.sourceLanguage,
        translationModel: settings.translationModel,
        targetLanguage: settings.targetLanguage,
      );
      final first = await store.saveRule(rule('one'));
      final second = await store.saveRule(rule('two'));
      final a = await complete('cache-only', appOnly: true, ruleId: first.id);
      final b = await complete('legacy', metadata: false, ruleId: first.id);
      final c = await complete('other', ruleId: second.id);
      final report = await SubtitleGeneratedCleanup(
        store,
        cache,
        prefs,
      ).clean(ruleId: first.id);
      expect(report.cleaned, 2);
      expect(report.failed, 0);
      expect((await store.job(a.id))?.status, SubtitleBatchStatus.pending);
      expect(await File(b.outputPath!).exists(), isFalse);
      expect(await File(c.outputPath!).exists(), isTrue);
      expect((await cache.stats()).entries, 1);
    },
  );

  test('metadata survives clearing queue history', () async {
    final job = await complete('history');
    await store.clearFinished();
    expect(await store.job(job.id), isNull);
    expect(
      (await store.generatedMetadata(job))?.settings.speechModel,
      settings.speechModel,
    );
  });

  test('retains legacy outputs modified after completion', () async {
    final job = await complete('edited-legacy', metadata: false);
    final file = File(job.outputPath!);
    await file.writeAsString('user edit');
    await file.setLastModified(job.updatedAt.add(const Duration(seconds: 2)));
    final report = await SubtitleGeneratedCleanup(store, cache, prefs).clean();
    expect(report.retained, 1);
    expect(await file.readAsString(), 'user edit');
  });

  test('refuses cleanup while queue is requested to run', () async {
    final job = await complete('running');
    await store.setRunRequested(true);
    await expectLater(
      SubtitleGeneratedCleanup(store, cache, prefs).clean(),
      throwsStateError,
    );
    expect(await File(job.outputPath!).exists(), isTrue);
  });
}

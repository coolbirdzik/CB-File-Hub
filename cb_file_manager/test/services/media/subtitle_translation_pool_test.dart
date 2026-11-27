import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/models/local_ai/local_ai_advisor_model.dart';
import 'package:cb_file_manager/services/local_ai/gguf_llama_cpp_runtime.dart';
import 'package:cb_file_manager/services/local_ai/llama_cpp_server_launch.dart';
import 'package:cb_file_manager/services/media/subtitle_translation_pool.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_models.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_processes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dart_executable.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File script;
  late HttpOverrides? oldOverrides;
  var sequence = 0;

  setUpAll(() async {
    oldOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    root = await Directory.systemTemp.createTemp('subtitle-pool-');
    script = File('${root.path}/server.dart');
    await script.writeAsString(r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
Future<void> main(List<String> args) async {
  String arg(String name) => args[args.indexOf(name) + 1];
  final path = arg('-m');
  if (arg('--batch-size') != '512' || arg('--ubatch-size') != '128' || arg('--cache-ram') != '0') exit(24);
  File('$path.trace').writeAsStringSync('${arg('--parallel')}:${arg('-c')}\n', mode: FileMode.append);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, int.parse(arg('--port')));
  var arrived = 0;
  final all = Completer<void>();
  server.listen((req) async {
    try {
      if (req.uri.path == '/health') {
        req.response.write('{"status":"ok"}');
      } else {
        final body = jsonDecode(await utf8.decoder.bind(req).join());
        final text = body['messages'].last['content'] as String;
        if (text == 'crash') exit(23);
        req.response.headers.set('content-type', 'text/event-stream');
        req.response.bufferOutput = false;
        if (text.startsWith('parallel')) {
          if (++arrived == 4) all.complete();
          await all.future.timeout(const Duration(seconds: 15));
        }
        req.response.write('data: ${jsonEncode({'choices':[{'delta':{'content':text}}]})}\n\n');
        await req.response.flush();
        if (text == 'hold') await Future<void>.delayed(const Duration(seconds: 30));
        req.response.write('data: ${jsonEncode({'choices':[{'delta':{},'finish_reason':'stop'}]})}\n\ndata: [DONE]\n\n');
      }
      await req.response.close();
    } catch (_) { try { await req.response.close(); } catch (_) {} }
  });
}
''');
  });
  tearDownAll(() async {
    HttpOverrides.global = oldOverrides;
    await root.delete(recursive: true);
  });

  Future<InstalledLocalModel> model() async {
    final file = File('${root.path}/model-${sequence++}.gguf');
    await file.writeAsBytes([1]);
    return InstalledLocalModel(
      catalogId: 'test/translation',
      displayName: 'Translation',
      localPath: file.path,
      sizeBytes: 1,
      installedAt: DateTime(2026),
      purpose: LocalModelPurpose.translation,
    );
  }

  SubtitleTranslationPool pool([SubtitleBatchProcesses? registry]) =>
      SubtitleTranslationPool(
        slots: 4,
        createRuntime: (slots) => GgufLlamaCppLocalAiChatRuntime(
          nGpuLayers: 0,
          parallelSlots: slots,
          maxResponseTokens: 512,
          backgroundInference: true,
          onProcessStarted: registry?.register,
          serverLaunchOverride: LlamaCppServerLaunch(
            executablePath: dartExecutable(),
            argumentsPrefix: [script.path],
            isAndroid: false,
          ),
        ),
      );

  Stream<String> request(
    SubtitleTranslator lease,
    InstalledLocalModel model,
    String text,
  ) => lease.sendDirectConversationStream(
    model: model,
    maxTokens: 2048,
    messages: [
      {'role': 'user', 'content': text},
    ],
  );

  Future<List<String>> launches(InstalledLocalModel model) =>
      File('${model.localPath}.trace').readAsLines();

  test(
    'four concurrent translations share one server and full contexts',
    () async {
      final installed = await model();
      final registry = SubtitleBatchProcesses();
      final shared = pool(registry);
      final leases = List.generate(4, (_) => shared.acquire(installed));
      for (final lease in leases) {
        addTearDown(lease.dispose);
      }
      final results = await Future.wait([
        for (var i = 0; i < leases.length; i++)
          request(leases[i], installed, 'parallel-$i').join(),
      ]);
      expect(results, List.generate(4, (i) => 'parallel-$i'));
      expect(await launches(installed), ['4:8192']);
      expect(registry.ids, hasLength(1));
      await leases.first.dispose();
      expect(registry.ids, hasLength(1));
      expect(
        await request(leases.last, installed, 'still working').join(),
        'still working',
      );
      expect(await launches(installed), ['4:8192']);
      final closing = Future.wait(leases.map((lease) => lease.dispose()));
      final next = shared.acquire(installed);
      addTearDown(next.dispose);
      expect(
        await request(next, installed, 'fresh lease').join(),
        'fresh lease',
      );
      expect(await launches(installed), ['4:8192', '4:8192']);
      await closing;
      expect(registry.ids, hasLength(1));
      await next.dispose();
      expect(registry.ids, isEmpty);
    },
  );

  test(
    'disposing a streaming lease does not interrupt the other lease',
    () async {
      final installed = await model();
      final shared = pool();
      final first = shared.acquire(installed),
          second = shared.acquire(installed);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final received = Completer<void>();
      final ended = Completer<void>();
      final subscription = request(first, installed, 'hold').listen(
        (_) {
          if (!received.isCompleted) received.complete();
        },
        onDone: () => ended.complete(),
        onError: (Object _) {
          if (!ended.isCompleted) ended.complete();
        },
        cancelOnError: true,
      );
      addTearDown(subscription.cancel);
      await received.future.timeout(const Duration(seconds: 10));
      await first.dispose();
      await ended.future.timeout(const Duration(seconds: 5));
      expect(
        await request(second, installed, 'uninterrupted').join(),
        'uninterrupted',
      );
      expect(await launches(installed), ['4:8192']);
    },
  );

  test(
    'different models use separate servers and recover a failed server once',
    () async {
      final one = await model(), two = await model();
      final shared = pool();
      final a = shared.acquire(one),
          b = shared.acquire(one),
          c = shared.acquire(two);
      for (final lease in [a, b, c]) {
        addTearDown(lease.dispose);
      }
      await Future.wait([
        a.prepareModel(model: one),
        b.prepareModel(model: one),
        c.prepareModel(model: two),
      ]);
      expect(await launches(one), ['4:8192']);
      expect(await launches(two), ['4:8192']);
      await expectLater(
        request(a, one, 'crash').join(),
        throwsA(
          predicate<Object>(
            (error) => SubtitleBatchFailure.transient(error.toString()),
          ),
        ),
      );
      // The OS exit notification clears the stopped server before the next cue.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final responses = await Future.wait([
        request(a, one, 'recovered-a').join(),
        request(b, one, 'recovered-b').join(),
        request(c, two, 'other model').join(),
      ]);
      expect(responses, ['recovered-a', 'recovered-b', 'other model']);
      expect(await launches(one), ['4:8192', '4:8192']);
      expect(await launches(two), ['4:8192']);
    },
  );
}

import 'dart:io';
import 'package:cb_file_manager/models/local_ai/local_ai_advisor_model.dart';
import 'package:cb_file_manager/services/local_ai/gguf_llama_cpp_runtime.dart';
import 'package:cb_file_manager/services/local_ai/llama_cpp_server_launch.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/dart_executable.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late String server;
  late HttpOverrides? previousHttp;
  var sequence = 0;
  final runtimes = <GgufLlamaCppLocalAiChatRuntime>[];
  setUpAll(() async {
    previousHttp = HttpOverrides.current;
    HttpOverrides.global = null;
    root = await Directory.systemTemp.createTemp('llama-preparation-');
    final script = File('${root.path}/server.dart');
    await script.writeAsString(r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
Future<void> main(List<String> args) async {
  String option(String key)=>args[args.indexOf(key)+1];
  final model=option('-m'), layers=int.parse(option('-ngl'));
  File('$model.trace').writeAsStringSync('$layers\n',mode:FileMode.append);
  if(layers>0) {
    if(model.contains('wait')) await Future<void>.delayed(const Duration(minutes:10));
    stderr.writeln('GPU allocator unavailable');exit(23);
  }
  final server=await HttpServer.bind(InternetAddress.loopbackIPv4,int.parse(option('--port')));
  await for(final request in server) {
    if(request.uri.path=='/health') {
      request.response.headers.contentType=ContentType.json;
      request.response.write('{"status":"ok"}');
    } else {
      await request.drain<void>();
      request.response.headers.set('content-type','text/event-stream; charset=utf-8');
      request.response.write('data: ${jsonEncode({'choices':[{'delta':{'content':'Bản dịch'}}]})}\n\n');
      request.response.write('data: ${jsonEncode({'choices':[{'delta':{},'finish_reason':'stop'}]})}\n\ndata: [DONE]\n\n');
    }
    await request.response.close();
  }
}
''');
    server = script.path;
  });
  tearDown(() async {
    for (final runtime in runtimes) {
      await runtime.dispose();
    }
    runtimes.clear();
  });
  tearDownAll(() async {
    HttpOverrides.global = previousHttp;
    await root.delete(recursive: true);
  });
  Future<InstalledLocalModel> model({bool wait = false}) async {
    final file = File(
      '${root.path}/${wait ? 'wait' : 'model'}-${sequence++}.gguf',
    );
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

  GgufLlamaCppLocalAiChatRuntime runtime({
    bool fallback = false,
    int gpu = 99,
  }) {
    final value = GgufLlamaCppLocalAiChatRuntime(
      allowCpuFallback: fallback,
      nGpuLayers: gpu,
      serverLaunchOverride: LlamaCppServerLaunch(
        executablePath: dartExecutable(),
        argumentsPrefix: [server],
        isAndroid: false,
      ),
    );
    runtimes.add(value);
    return value;
  }

  test(
    'preparation coalesces, retries GPU failure once on CPU, and survives file release',
    () async {
      final installed = await model();
      final r = runtime(fallback: true);
      final first = r.prepareModel(model: installed);
      expect(identical(first, r.prepareModel(model: installed)), isTrue);
      await first;
      final result = await r
          .sendDirectConversationStream(
            model: installed,
            maxTokens: 2048,
            messages: [
              {'role': 'user', 'content': 'Translate'},
            ],
          )
          .where((c) => !c.startsWith('[STATUS]'))
          .join();
      expect(result, 'Bản dịch');
      expect(await File('${installed.localPath}.trace').readAsLines(), [
        '99',
        '0',
      ]);
      await r.releaseModelFiles();
      await r.prepareModel(model: installed);
      expect(await File('${installed.localPath}.trace').readAsLines(), [
        '99',
        '0',
        '0',
      ]);
    },
  );
  test(
    'the existing chat default does not silently retry a failed GPU on CPU',
    () async {
      final installed = await model();
      final r = runtime();
      await expectLater(r.prepareModel(model: installed), throwsStateError);
      expect(await File('${installed.localPath}.trace').readAsLines(), ['99']);
    },
  );
  test(
    'preparing another model and context starts the requested model before sending',
    () async {
      final first = await model(), second = await model();
      final r = runtime(gpu: 0);
      await r.prepareModel(model: first);
      await r.prepareModel(model: second, contextTokens: 4096);
      expect(await File('${second.localPath}.trace').readAsLines(), ['0']);
    },
  );
  test(
    'disposing during preparation prevents a CPU replacement process',
    () async {
      final installed = await model(wait: true);
      final r = runtime(fallback: true);
      final preparing = r.prepareModel(model: installed);
      final check = expectLater(preparing, throwsStateError);
      final trace = File('${installed.localPath}.trace');
      for (var i = 0; i < 100 && !await trace.exists(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(await trace.exists(), isTrue);
      await r.dispose();
      await check;
      expect(await trace.readAsLines(), ['99']);
    },
  );
}

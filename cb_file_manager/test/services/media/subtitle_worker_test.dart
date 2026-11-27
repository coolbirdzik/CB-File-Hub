import 'dart:io';
import 'dart:ffi';

import 'package:cb_file_manager/services/media/subtitle_worker.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_processes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win;
import '../../support/dart_executable.dart';

void main() {
  late Directory root;
  late File fixture, trace;
  final workers = <SubtitleWorker>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('subtitle-worker-');
    trace = File(p.join(root.path, 'trace.txt'));
    fixture = File(p.join(root.path, 'worker.dart'));
    await fixture.writeAsString(r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
Future<void> main(List<String> args) async {
  final trace = File(args[1]);
  var gpu = false;
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final event = jsonDecode(line) as Map<String,dynamic>;
    if (event['command'] == 'init') {
      gpu = event['gpu'] == true;
      if (gpu && args[0] == 'wait') {
        // Make the file-created / trace-written race deterministic. The
        // parent must wait for the init record, not merely this empty file.
        trace.createSync();
        final resume = File('${trace.path}.resume');
        while (!await resume.exists()) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }
      trace.writeAsStringSync('$gpu\n',mode:FileMode.append);
      if (gpu && args[0] == 'reject') {
        stdout.writeln(jsonEncode({'id':event['id'],'error':'GPU upload failed'})); continue;
      }
      if (gpu && args[0] == 'crash') exit(23);
      if (gpu && args[0] == 'wait') { await Completer<void>().future; }
      stdout.writeln(jsonEncode({'id':event['id'],'protocol':1,'ready':true}));
    } else {
      if ((gpu && args[0] == 'compute-crash') || args[0] == 'compute-crash-all') exit(23);
      stdout.writeln(jsonEncode({'id':event['id'],'language':'ja','segments':[]}));
    }
  }
}
''');
  });
  tearDown(() async {
    for (final worker in workers) {
      await worker.stop();
    }
    workers.clear();
    await root.delete(recursive: true);
  });
  SubtitleWorker worker(String mode, {SubtitleBatchProcesses? registry}) {
    final value = SubtitleWorker(
      executableOverride: dartExecutable(),
      arguments: [fixture.path, mode, trace.path],
      onProcessStarted: registry?.register,
    );
    workers.add(value);
    return value;
  }

  test(
    'only registered queue workers are counted, including CPU fallback',
    () async {
      final registry = SubtitleBatchProcesses();
      final queued = worker('reject', registry: registry);
      final preview = worker('ready');
      await queued.start('model.bin');
      await preview.start('model.bin');
      expect(queued.gpuRequested, isFalse);
      expect(registry.ids, [queued.processId]);
      expect(registry.ids, isNot(contains(preview.processId)));
      await queued.stop();
      expect(registry.ids, isEmpty);
    },
  );

  test(
    'recognition process runs below the player CPU priority on Windows',
    () async {
      final w = worker('ready');
      await w.start('model.bin');
      final pid = w.processId!;
      final handle = win.OpenProcess(
        win.PROCESS_QUERY_LIMITED_INFORMATION,
        false,
        pid,
      ).value;
      expect(handle.isValid, isTrue);
      try {
        final priority = DynamicLibrary.open('kernel32.dll')
            .lookupFunction<Uint32 Function(Pointer), int Function(Pointer)>(
              'GetPriorityClass',
            );
        expect(priority(handle), win.BELOW_NORMAL_PRIORITY_CLASS);
      } finally {
        win.CloseHandle(handle);
      }
    },
    skip: !Platform.isWindows,
  );

  for (final mode in ['reject', 'crash']) {
    test(
      'GPU $mode during initialization falls back to a fresh CPU process',
      () async {
        final w = worker(mode);
        await w.start('model.bin');
        expect(w.gpuRequested, isFalse);
        final result = await w.request({'command': 'transcribe'});
        expect(result['language'], 'ja');
        expect(await trace.readAsLines(), ['true', 'false']);
      },
    );
  }
  test('GPU compute crash retries the same recognition on CPU', () async {
    final w = worker('compute-crash');
    await w.start('model.bin');
    expect(w.gpuRequested, isTrue);
    expect((await w.request({'command': 'transcribe'}))['language'], 'ja');
    expect(w.gpuRequested, isFalse);
    expect(await trace.readAsLines(), ['true', 'false']);
  });
  test('Nemotron selects its own runtime and starts on CPU', () async {
    const model = 'nemotron-3.5-asr-streaming-0.6b.q8_0.gguf';
    expect(
      SubtitleWorker.runtimeForModel(model),
      endsWith('subtitles/nemo/cb-subtitle-nemo-worker.exe'),
    );
    final w = worker('ready');
    await w.start(model);
    expect(w.gpuRequested, isFalse);
    expect(await trace.readAsLines(), ['false']);
  });
  test(
    'a crashed CPU worker fails requests without writing to its dead pipe',
    () async {
      final w = worker('compute-crash-all');
      await w.start('model.bin');
      await expectLater(w.request({'command': 'transcribe'}), throwsStateError);
      await expectLater(w.request({'command': 'transcribe'}), throwsStateError);
      expect(w.processId, isNull);
    },
  );
  test(
    'cancellation during GPU initialization does not launch a CPU replacement',
    () async {
      Future<void> waitForTrace(bool Function(String) ready) async {
        final elapsed = Stopwatch()..start();
        while (elapsed.elapsed < const Duration(seconds: 30)) {
          if (await trace.exists() && ready(await trace.readAsString())) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        fail(
          'Subtitle fixture did not reach the GPU initialization checkpoint',
        );
      }

      final w = worker('wait');
      final starting = w.start('model.bin');
      final check = expectLater(starting, throwsStateError);
      await waitForTrace((_) => true);
      expect(await trace.readAsString(), isEmpty);
      await File('${trace.path}.resume').writeAsString('continue');
      // Creation alone isn't readiness: stop only after the worker has
      // committed the GPU init record, while its init response stays pending.
      await waitForTrace((text) => text == 'true\n');
      await w.stop();
      await check;
      expect(await trace.readAsLines(), ['true']);
    },
  );
}

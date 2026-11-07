import 'dart:io';
import 'dart:ffi';

import 'package:cb_file_manager/services/media/subtitle_worker.dart';
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
      trace.writeAsStringSync('$gpu\n',mode:FileMode.append);
      if (gpu && args[0] == 'reject') {
        stdout.writeln(jsonEncode({'id':event['id'],'error':'GPU upload failed'})); continue;
      }
      if (gpu && args[0] == 'crash') exit(23);
      if (gpu && args[0] == 'wait') { await Completer<void>().future; }
      stdout.writeln(jsonEncode({'id':event['id'],'protocol':1,'ready':true}));
    } else {
      if (gpu && args[0] == 'compute-crash') exit(23);
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
  SubtitleWorker worker(String mode) {
    final value = SubtitleWorker(
      executableOverride: dartExecutable(),
      arguments: [fixture.path, mode, trace.path],
    );
    workers.add(value);
    return value;
  }

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
  test(
    'cancellation during GPU initialization does not launch a CPU replacement',
    () async {
      final w = worker('wait');
      final starting = w.start('model.bin');
      final check = expectLater(starting, throwsStateError);
      for (var i = 0; i < 100 && !await trace.exists(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(await trace.exists(), isTrue);
      await w.stop();
      await check;
      expect(await trace.readAsLines(), ['true']);
    },
  );
}

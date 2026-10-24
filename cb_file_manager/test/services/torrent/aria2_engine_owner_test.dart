import 'dart:io';

import 'package:cb_file_manager/services/torrent/aria2_engine.dart';
import 'package:cb_file_manager/services/windowing/windows_engine_host.dart';
import 'package:flutter_test/flutter_test.dart';

class _RunningEngine extends Aria2Engine {
  var active = true;
  @override
  bool get running => active;
  @override
  Future<void> stop() async => active = false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cb-engine-owner-');
    messenger.setMockMethodCallHandler(
      WindowsEngineHost.channel,
      (call) async => {
        'primary': false,
        'engineId': 'engine-one',
        'environment': <String, String>{},
      },
    );
    await WindowsEngineHost.initializeForTesting();
  });
  tearDown(() async {
    WindowsEngineHost.resetForTesting();
    messenger.setMockMethodCallHandler(WindowsEngineHost.channel, null);
    await root.delete(recursive: true);
  });

  test(
    'own engine is ignored but another engine with the same PID can take over',
    () async {
      final engine = _RunningEngine();
      final request = File(
        '${root.path}${Platform.pathSeparator}engine.takeover',
      );
      await request.writeAsString(
        '$pid-engine-one:${DateTime.now().millisecondsSinceEpoch}',
      );
      expect(await engine.releaseIfRequested(root.path), isFalse);
      expect(engine.running, isTrue);
      await request.writeAsString(
        '$pid-engine-two:${DateTime.now().millisecondsSinceEpoch}',
      );
      expect(await engine.releaseIfRequested(root.path), isTrue);
      expect(engine.running, isFalse);
    },
  );

  test('expired requests cannot stop the current engine', () async {
    final engine = _RunningEngine();
    await File(
      '${root.path}${Platform.pathSeparator}engine.takeover',
    ).writeAsString('$pid-engine-two:0');
    expect(await engine.releaseIfRequested(root.path), isFalse);
    expect(engine.running, isTrue);
  });
}

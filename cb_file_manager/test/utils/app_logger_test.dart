import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  test('flush waits for every pending performance log write', () async {
    final root = await Directory.systemTemp.createTemp('cb_perf_log_');
    final first = await Directory(p.join(root.path, 'first')).create();
    final second = await Directory(p.join(root.path, 'second')).create();
    final paths = [Completer<String>(), Completer<String>()];
    var requests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => paths[requests++].future);
    addTearDown(() async {
      for (final path in paths) {
        if (!path.isCompleted) path.complete(root.path);
      }
      await AppLogger.flushPerfLogs();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await root.delete(recursive: true);
    });

    AppLogger.perf('first write');
    AppLogger.perf('second write');
    var flushed = false;
    final flushing = AppLogger.flushPerfLogs().then((_) => flushed = true);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 2);
    expect(flushed, isFalse);

    paths[0].complete(first.path);
    await Future<void>.delayed(Duration.zero);
    expect(flushed, isFalse);
    paths[1].complete(second.path);
    await flushing;

    expect(
      await File(p.join(first.path, 'cb_file_manager_perf.log')).readAsString(),
      contains('first write'),
    );
    final log = File(p.join(second.path, 'cb_file_manager_perf.log'));
    expect(await log.readAsString(), contains('second write'));
    // The flush includes closing the file, so immediate deletion is safe.
    await log.delete();
    expect(await log.exists(), isFalse);
    await AppLogger.flushPerfLogs();
  });

  test('flush completes when performance logging fails', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'unavailable');
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    AppLogger.perf('unavailable log directory');
    await AppLogger.flushPerfLogs();
    await AppLogger.flushPerfLogs();
  });
}

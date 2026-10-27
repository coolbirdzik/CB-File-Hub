import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/services/directory_watcher_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final watcher = DirectoryWatcherService.instance;

  setUp(watcher.stopWatching);
  tearDown(watcher.stopWatching);

  test(
    'stopping during a root probe cannot open a watcher afterwards',
    () async {
      final exists = Completer<bool>();
      final probed = Completer<void>();
      final events = StreamController<FileSystemEvent>.broadcast();
      addTearDown(events.close);
      final directory = _WatchDirectory('/pending', () {
        probed.complete();
        return exists.future;
      }, events.stream);

      await IOOverrides.runZoned(() async {
        final starting = watcher.startWatching(directory.path);
        await probed.future;
        // Stopping need not wait for a filesystem probe to return; it must
        // prevent that pending probe from arming a watch when it does return.
        await watcher.stopWatching();
        exists.complete(true);
        await starting;

        expect(watcher.isWatching, isFalse);
        expect(events.hasListener, isFalse);
        expect(watcher.currentWatchPath, isNull);
      }, createDirectory: (_) => directory);
    },
  );

  test('overlapping starts leave only the latest directory watched', () async {
    final first = StreamController<FileSystemEvent>.broadcast();
    final second = StreamController<FileSystemEvent>.broadcast();
    addTearDown(first.close);
    addTearDown(second.close);
    final directories = {
      '/first': _WatchDirectory('/first', () async => true, first.stream),
      '/second': _WatchDirectory('/second', () async => true, second.stream),
    };

    await IOOverrides.runZoned(() async {
      await Future.wait([
        watcher.startWatching('/first'),
        watcher.startWatching('/second'),
      ]);

      expect(watcher.currentWatchPath, '/second');
      expect(first.hasListener, isFalse);
      expect(second.hasListener, isTrue);
      await watcher.stopWatching();
      expect(second.hasListener, isFalse);
    }, createDirectory: (path) => directories[path]!);
  });

  test('repeated stops wait for the same native cancellation', () async {
    final cancelled = Completer<void>();
    final events = StreamController<FileSystemEvent>(
      onCancel: () => cancelled.future,
    );
    addTearDown(() async {
      if (!cancelled.isCompleted) cancelled.complete();
      await watcher.stopWatching();
      await events.close();
    });
    final directory = _WatchDirectory(
      '/active',
      () async => true,
      events.stream,
    );

    await IOOverrides.runZoned(() async {
      await watcher.startWatching(directory.path);
      var firstStopped = false;
      var secondStopped = false;
      final first = watcher.stopWatching().then((_) => firstStopped = true);
      final second = watcher.stopWatching().then((_) => secondStopped = true);
      await Future<void>.delayed(Duration.zero);

      expect(firstStopped, isFalse);
      expect(secondStopped, isFalse);
      cancelled.complete();
      await Future.wait([first, second]);
      expect(firstStopped, isTrue);
      expect(secondStopped, isTrue);
      expect(watcher.isWatching, isFalse);
    }, createDirectory: (_) => directory);
  });
}

class _WatchDirectory implements Directory {
  _WatchDirectory(this.path, this._exists, this._events);

  @override
  final String path;
  final Future<bool> Function() _exists;
  final Stream<FileSystemEvent> _events;

  @override
  Future<bool> exists() => _exists();

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => _events;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

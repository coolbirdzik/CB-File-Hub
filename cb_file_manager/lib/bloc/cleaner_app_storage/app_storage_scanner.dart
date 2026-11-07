import 'dart:async';
import 'dart:isolate';

import '../../services/app_insights/app_insights_models.dart';
import '../../services/disk_cleaner/app_storage/app_space_analyzer.dart';
import '../../services/disk_cleaner/app_storage/app_space_models.dart';
import '../../services/disk_cleaner/app_storage/running_processes.dart';
import '../../services/disk_cleaner/docker/docker_storage.dart';

/// Runs one App storage analysis. [cancel] stops a running one; its future
/// then completes with null.
abstract class AppStorageScanner {
  Future<AppSpaceReport?> scan({
    required void Function(int done, int total) onProgress,
    required void Function(AppSpaceReport partial) onPartial,
  });

  void cancel();
}

/// Analyses on its own isolate: listing a few thousand folders, one process
/// snapshot and the size walk (Rust when available, Dart otherwise).
class IsolateAppStorageScanner implements AppStorageScanner {
  /// Read on the calling isolate: Windows reads the inventory through
  /// platform code.
  final Future<List<InstalledAppInfo>> Function() installedApps;

  Isolate? _isolate;
  Completer<AppSpaceReport?>? _done;

  IsolateAppStorageScanner({required this.installedApps});

  @override
  Future<AppSpaceReport?> scan({
    required void Function(int done, int total) onProgress,
    required void Function(AppSpaceReport partial) onPartial,
  }) async {
    cancel();
    final environment = AppSpaceEnvironment.current();
    if (environment == null) {
      return AppSpaceReport(entries: const [], generatedAt: DateTime.now());
    }
    final done = _done = Completer<AppSpaceReport?>();
    final apps = await installedApps();
    if (done.isCompleted) return done.future;
    final port = ReceivePort();
    final errors = ReceivePort();
    void close() {
      port.close();
      errors.close();
    }

    port.listen((message) {
      switch (message) {
        case ('progress', final int current, final int total):
          onProgress(current, total);
        case ('partial', final AppSpaceReport report):
          onPartial(report);
        case ('done', final AppSpaceReport report):
          if (!done.isCompleted) done.complete(report);
          close();
      }
    });
    errors.listen((error) {
      if (!done.isCompleted) {
        done.completeError(
          error is List && error.isNotEmpty ? '${error.first}' : '$error',
        );
      }
      close();
    });
    final isolate = await Isolate.spawn(
      _run,
      (port.sendPort, environment, apps),
      onError: errors.sendPort,
      debugName: 'cb_file_manager.app_storage',
    );
    if (done.isCompleted) {
      isolate.kill(priority: Isolate.immediate);
      close();
    } else {
      _isolate = isolate;
    }
    return done.future.whenComplete(() {
      if (identical(_done, done)) _isolate = null;
    });
  }

  static Future<void> _run(
    (SendPort, AppSpaceEnvironment, List<InstalledAppInfo>) args,
  ) async {
    final (send, environment, apps) = args;
    // Docker answers on its own; read it while the folders are walked.
    final docker = DockerTool().load().timeout(
      const Duration(minutes: 1),
      onTimeout: () => const DockerReport(
        status: DockerStatus.failed,
        message: 'Docker did not answer within a minute.',
      ),
    );
    final report =
        await AppSpaceAnalyzer(
          environment: environment,
          apps: apps,
          processes: RunningProcesses.snapshot(),
        ).analyze(
          onProgress: (current, total) =>
              send.send(('progress', current, total)),
          onPartial: (partial) => send.send(('partial', partial)),
        );
    send.send(('done', report.withDocker(await docker)));
  }

  @override
  void cancel() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    final done = _done;
    if (done != null && !done.isCompleted) done.complete(null);
  }
}

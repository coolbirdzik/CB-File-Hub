import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../local_ai/windows_process_reaper.dart';

/// One bounded request at a time. Killing this process also interrupts a native
/// decoder/inference call; no stale seek work can keep consuming CPU/GPU.
class SubtitleWorker {
  final String? executableOverride;
  final List<String> arguments;
  final bool preferGpu;
  bool gpuRequested = false;
  String? _modelPath;
  Future<void>? _cpuRecovery;
  SubtitleWorker({
    this.executableOverride,
    this.arguments = const [],
    this.preferGpu = true,
  });
  Process? _process;
  int? get processId => _process?.pid;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _nextId = 0;
  bool _stopped = false;

  static String get executablePath {
    final exe = File(Platform.resolvedExecutable).parent;
    final root = Platform.isMacOS ? '${exe.parent.path}/Helpers' : exe.path;
    return '$root/subtitles/cb-subtitle-worker${Platform.isWindows ? '.exe' : ''}';
  }

  Future<void> start(String model) async {
    _modelPath = model;
    if (_stopped) throw StateError('Subtitle worker stopped');
    final path = executableOverride ?? executablePath;
    if (!await File(path).exists()) {
      throw StateError(
        'Subtitle runtime is missing. Rebuild or reinstall the desktop app.',
      );
    }
    await _launch(path);
    try {
      await _initialize(model, preferGpu);
    } catch (_) {
      if (_stopped || !preferGpu) rethrow;
      // A broken GPU driver/model upload must not leave subtitles unusable.
      // Restart in a fresh process so even a driver crash can fall back to CPU.
      await _closeProcess();
      if (_stopped) throw StateError('Subtitle processing cancelled');
      await _launch(path);
      await _initialize(model, false);
    }
  }

  Future<void> _initialize(String model, bool gpu) async {
    final response = await request({
      'command': 'init',
      'model': model,
      'gpu': gpu,
    });
    if (response['protocol'] != 1 || response['ready'] != true) {
      throw StateError('Incompatible subtitle runtime');
    }
    gpuRequested = gpu;
    // Runtime initialization may adjust its own process priority. Reassert the
    // background budget once it is ready to accept recognition work.
    final process = _process;
    if (Platform.isWindows && process != null) {
      WindowsProcessReaper.instance.lowerPriority(process.pid);
    }
  }

  Future<void> _launch(String path) async {
    final process = await Process.start(
      path,
      arguments,
      workingDirectory: File(path).parent.path,
    );
    if (_stopped) {
      process.kill();
      await process.exitCode;
      throw StateError('Subtitle processing cancelled');
    }
    _process = process;
    if (Platform.isWindows) {
      WindowsProcessReaper.instance.assignProcess(
        process.pid,
        background: true,
      );
    }
    process.stderr.drain<void>();
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (!identical(_process, process)) return;
            try {
              final event = jsonDecode(line) as Map<String, dynamic>;
              final completer = _pending.remove(event['id']);
              if (completer == null) return;
              if (event['error'] != null) {
                completer.completeError(StateError(event['error'].toString()));
              } else {
                completer.complete(event);
              }
            } catch (_) {
              _fail(StateError('Invalid subtitle runtime response'));
            }
          },
          onError: (Object e) {
            if (identical(_process, process)) _fail(e);
          },
          onDone: () {
            if (identical(_process, process)) {
              _fail(StateError('Subtitle runtime exited'));
            }
          },
        );
    unawaited(
      process.exitCode.then((_) {
        if (identical(_process, process)) {
          _fail(StateError('Subtitle runtime exited'));
        }
      }),
    );
  }

  Future<Map<String, dynamic>> request(Map<String, Object?> command) async {
    final process = _process;
    if (_stopped || process == null) {
      throw StateError('Subtitle runtime is unavailable');
    }
    final id = ++_nextId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    process.stdin.writeln(jsonEncode({...command, 'id': id}));
    try {
      return await completer.future.timeout(const Duration(minutes: 3));
    } on TimeoutException {
      await stop();
      rethrow;
    } catch (error) {
      final failure = error.toString();
      if (!_stopped &&
          gpuRequested &&
          command['command'] == 'transcribe' &&
          (failure.contains('Subtitle runtime exited') ||
              failure.contains('Speech recognition failed'))) {
        await (_cpuRecovery ??= _recoverOnCpu());
        return await request(command);
      }
      rethrow;
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> _recoverOnCpu() async {
    await _closeProcess();
    if (_stopped) throw StateError('Subtitle processing cancelled');
    await _launch(executableOverride ?? executablePath);
    await _initialize(_modelPath!, false);
  }

  void _fail(Object error) {
    final requests = _pending.values.toList();
    _pending.clear();
    for (final request in requests) {
      if (!request.isCompleted) request.completeError(error);
    }
  }

  Future<void> stop() async {
    _stopped = true;
    await _closeProcess();
  }

  Future<void> _closeProcess() async {
    final process = _process;
    _process = null;
    _fail(StateError('Subtitle processing cancelled'));
    if (process == null) return;
    process.kill();
    await process.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }
}

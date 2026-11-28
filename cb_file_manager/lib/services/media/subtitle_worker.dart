import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../local_ai/windows_process_reaper.dart';
import '../local_ai/subtitle_model_catalog.dart';

/// One bounded request at a time. Killing this process also interrupts a native
/// decoder/inference call; no stale seek work can keep consuming CPU/GPU.
class SubtitleWorker {
  final String? executableOverride;
  final List<String> arguments;
  final bool preferGpu;
  final void Function(Process)? onProcessStarted;
  bool gpuRequested = false;
  String? _modelPath;
  String? _runtimePath;
  Future<void>? _cpuRecovery;
  Future<void>? _launching, _closing;
  SubtitleWorker({
    this.executableOverride,
    this.arguments = const [],
    this.preferGpu = true,
    this.onProcessStarted,
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

  static String runtimeForModel(String model) {
    if (model.toLowerCase().endsWith(SubtitleModelCatalog.nemotronArtifact)) {
      return '${File(Platform.resolvedExecutable).parent.path}/subtitles/nemo/cb-subtitle-nemo-worker.exe';
    }
    return executablePath;
  }

  Future<void> start(String model) async {
    _modelPath = model;
    if (_stopped) throw StateError('Subtitle worker stopped');
    final path = _runtimePath = executableOverride ?? runtimeForModel(model);
    if (!await File(path).exists()) {
      throw StateError(
        'Subtitle runtime is missing. Rebuild or reinstall the desktop app.',
      );
    }
    // Nemotron's cache-aware CPU backend is a good fit for parallel subtitle
    // jobs; leave VRAM available for translation. On this runtime's Windows
    // Vulkan backend, first inference can take minutes compiling shaders.
    final useGpu =
        preferGpu &&
        !model.toLowerCase().endsWith(SubtitleModelCatalog.nemotronArtifact);
    await _launch(path);
    try {
      await _initialize(model, useGpu);
    } catch (_) {
      if (_stopped || !useGpu) rethrow;
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

  Future<void> _launch(String path) {
    if (_stopped) {
      return Future.error(StateError('Subtitle processing cancelled'));
    }
    return _launching = _launchProcess(
      path,
    ).whenComplete(() => _launching = null);
  }

  Future<void> _launchProcess(String path) async {
    final process = await Process.start(
      path,
      arguments,
      workingDirectory: File(path).parent.path,
      // Imported FFmpeg DLLs live at the app root. Keep the executable and
      // real Vulkan loader in subtitles/: moving them beside Flutter's
      // vulkan-1.dll would load the incompatible ANGLE loader.
      environment: Platform.isWindows
          ? {
              'PATH':
                  '${File(Platform.resolvedExecutable).parent.path};'
                  '${Platform.environment['PATH'] ?? ''}',
            }
          : null,
    );
    onProcessStarted?.call(process);
    if (_stopped) {
      process.kill();
      await process.exitCode;
      throw StateError('Subtitle processing cancelled');
    }
    _process = process;
    // IOSink.done can error asynchronously after a native process dies, even
    // if the request's own completer has already failed. Always observe it.
    unawaited(
      process.stdin.done.then<void>(
        (_) {},
        onError: (Object error) {
          if (identical(_process, process)) {
            _fail(
              StateError('Subtitle runtime exited or closed its input: $error'),
            );
          }
        },
      ),
    );
    if (Platform.isWindows) {
      WindowsProcessReaper.instance.assignProcess(
        process.pid,
        background: true,
      );
    }
    // Keep bounded native diagnostics instead of losing the reason a worker
    // died. Do not let a worker crash tear down the app or another job.
    var stderrTail = '';
    process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((
      chunk,
    ) {
      stderrTail += chunk;
      if (stderrTail.length > 3000) {
        stderrTail = stderrTail.substring(stderrTail.length - 3000);
      }
    }, onError: (Object _) {});
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
        );
    unawaited(
      process.exitCode.then((code) {
        if (identical(_process, process)) {
          final details =
              'Subtitle runtime exited (code $code)'
              '${stderrTail.trim().isEmpty ? '' : ': ${stderrTail.trim()}'}';
          _process = null;
          if (code != 0) _recordCrash(details, process.pid);
          _fail(StateError(details));
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
    try {
      try {
        process.stdin.writeln(jsonEncode({...command, 'id': id}));
      } catch (error) {
        // Do not leave a pending completer or write to a dead pipe again.
        _pending.remove(id);
        throw StateError('Subtitle runtime exited or closed its input: $error');
      }
      return await completer.future.timeout(const Duration(minutes: 3));
    } on TimeoutException {
      // A timed-out GPU init/request must permit a fresh CPU fallback, unless
      // the user explicitly cancelled the worker.
      await _closeProcess();
      if (!_stopped && gpuRequested && command['command'] == 'transcribe') {
        await (_cpuRecovery ??= _recoverOnCpu());
        return await request(command);
      }
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

  static void _recordCrash(String details, int processId) {
    try {
      final file = File(
        '${Directory.systemTemp.path}/cb-subtitle-worker-crashes.log',
      );
      // Keep a bounded local trace, useful even when the Flutter console is gone.
      final mode = file.existsSync() && file.lengthSync() > 256 * 1024
          ? FileMode.write
          : FileMode.append;
      file.writeAsStringSync(
        '${DateTime.now().toIso8601String()} pid=$processId $details\n',
        mode: mode,
      );
    } catch (_) {
      // Diagnostics must never crash the application.
    }
  }

  Future<void> _recoverOnCpu() async {
    await _closeProcess();
    if (_stopped) throw StateError('Subtitle processing cancelled');
    await _launch(_runtimePath ?? executableOverride ?? executablePath);
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
    final launching = _launching;
    await _closeProcess();
    if (launching != null) {
      try {
        await launching;
      } catch (_) {
        // A cancelled launch waits for its child to exit before throwing.
      }
    }
  }

  Future<void> _closeProcess() =>
      _closing ??= _terminateProcess().whenComplete(() => _closing = null);

  Future<void> _terminateProcess() async {
    final process = _process;
    _process = null;
    _fail(StateError('Subtitle processing cancelled'));
    if (process == null) return;
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(const Duration(seconds: 5));
    }
  }
}

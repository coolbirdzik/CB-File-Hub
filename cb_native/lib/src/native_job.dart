import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings.dart' as b;
import 'buffers.dart';
import 'native_search.dart' show CbNative;

/// A native job ended in failure; [message] comes from Rust.
class NativeJobException implements Exception {
  const NativeJobException(this.message);

  final String message;

  @override
  String toString() => 'NativeJobException: $message';
}

/// Four job-specific counters plus the path being worked on.
class NativeJobProgress {
  const NativeJobProgress(this.counters, this.currentPath);

  final List<int> counters;
  final String currentPath;
}

/// One background operation in the Rust library (see job.rs).
///
/// Starting and polling never block. When the isolate can post from native
/// threads (dart_api_dl), the job wakes [result] through a port the moment it
/// ends, so a 2 ms listing is not stretched to a timer tick; otherwise
/// [result] polls. Always [dispose]; [result] does it for you.
class NativeJob implements Finalizable {
  NativeJob._(this._handle, this._port) {
    _finalizer.attach(this, _handle.cast(), detach: this);
  }

  static final _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(
      b.cb_job_free,
    ),
  );

  /// Per isolate: whether Rust can post to this isolate's ports.
  static final bool _canNotify = _initDartApi();

  static bool _initDartApi() {
    try {
      return b.cb_native_init_dart_api(NativeApi.initializeApiDLData) == 1;
    } catch (_) {
      return false;
    }
  }

  Pointer<b.JobHandle> _handle;
  final RawReceivePort? _port;
  final Completer<void> _ended = Completer<void>();

  /// Starts a job of [kind] (`b.job*`). Returns null when the library is
  /// unavailable or rejects [config]; [onInvalidRegex] is called instead when
  /// Rust cannot compile a regex in it.
  static NativeJob? start(
    int kind,
    Uint8List config, {
    void Function()? onInvalidRegex,
  }) {
    if (!CbNative.isAvailable) return null;
    final port = _canNotify ? RawReceivePort() : null;
    final status = using((arena) {
      final buffer = config.isEmpty
          ? nullptr
          : b.cb_buffer_alloc(config.length);
      if (config.isNotEmpty) {
        buffer.asTypedList(config.length).setAll(0, config);
      }
      final outHandle = arena<Pointer<b.JobHandle>>();
      // Takes ownership of `buffer` whatever it returns.
      final status = b.cb_job_start(
        kind,
        buffer,
        config.length,
        port?.sendPort.nativePort ?? 0,
        outHandle,
      );
      return (status, outHandle.value);
    });
    if (status.$1 != b.statusOk) {
      port?.close();
      if (status.$1 == b.statusInvalidRegex) onInvalidRegex?.call();
      return null;
    }
    final job = NativeJob._(status.$2, port);
    port?.handler = (Object? message) {
      // -1 is a liveness ping; anything else is the final state.
      if (message is int && message >= 0 && !job._ended.isCompleted) {
        job._ended.complete();
      }
    };
    return job;
  }

  bool get isDisposed => _handle == nullptr;

  /// The state (`b.job*`) and the output produced since the last poll.
  (int, Uint8List) poll() {
    if (isDisposed) return (b.jobCancelled, Uint8List(0));
    return using((arena) {
      final outPtr = arena<Pointer<Uint8>>();
      final outLen = arena<Size>();
      final state = b.cb_job_poll(_handle, outPtr, outLen);
      return (state, takeBuffer(outPtr.value, outLen.value));
    });
  }

  String error() {
    if (isDisposed) return '';
    return using((arena) {
      final outPtr = arena<Pointer<Uint8>>();
      final outLen = arena<Size>();
      b.cb_job_error(_handle, outPtr, outLen);
      return utf8.decode(
        takeBuffer(outPtr.value, outLen.value),
        allowMalformed: true,
      );
    });
  }

  NativeJobProgress progress() {
    if (isDisposed) return const NativeJobProgress([0, 0, 0, 0], '');
    return using((arena) {
      final counts = arena<Uint64>(4);
      final outPtr = arena<Pointer<Uint8>>();
      final outLen = arena<Size>();
      b.cb_job_progress(_handle, counts, outPtr, outLen);
      return NativeJobProgress(
        [counts[0], counts[1], counts[2], counts[3]],
        utf8.decode(
          takeBuffer(outPtr.value, outLen.value),
          allowMalformed: true,
        ),
      );
    });
  }

  void cancel() {
    if (!isDisposed) b.cb_job_cancel(_handle);
  }

  /// Cancels the job if it still runs and frees the handle.
  void dispose() {
    _port?.close();
    if (isDisposed) return;
    _finalizer.detach(this);
    b.cb_job_free(_handle.cast());
    _handle = nullptr;
  }

  /// Waits for the job and returns all of its output, then disposes it.
  ///
  /// Returns null when the job was cancelled, including because
  /// [shouldContinue] turned false (checked every [tick]). Throws
  /// [NativeJobException] when it failed. [onProgress] runs every [tick]
  /// while the job is running, and [onOutput] receives output as it arrives
  /// for jobs that stream records.
  Future<Uint8List?> result({
    bool Function()? shouldContinue,
    void Function(NativeJobProgress progress)? onProgress,
    void Function(Uint8List chunk)? onOutput,
    Duration tick = const Duration(milliseconds: 100),
  }) async {
    final output = BytesBuilder(copy: false);
    void collect(Uint8List chunk) {
      if (chunk.isEmpty) return;
      if (onOutput != null) {
        onOutput(chunk);
      } else {
        output.add(chunk);
      }
    }

    try {
      if (_port != null) {
        Timer? timer;
        if (shouldContinue != null || onProgress != null || onOutput != null) {
          timer = Timer.periodic(tick, (_) {
            if (_ended.isCompleted) return;
            if (shouldContinue != null && !shouldContinue()) {
              cancel();
              _ended.complete();
              return;
            }
            onProgress?.call(progress());
            if (onOutput != null) collect(poll().$2);
          });
        }
        try {
          await _ended.future;
        } finally {
          timer?.cancel();
        }
      }

      // Without a port, or after the port fired: poll to the final state.
      var delay = Duration.zero;
      var lastTick = DateTime.now();
      while (true) {
        final (state, chunk) = poll();
        collect(chunk);
        if (state != b.jobRunning) {
          if (state == b.jobFailed) throw NativeJobException(error());
          if (state == b.jobCancelled) return null;
          return output.takeBytes();
        }
        if (_port != null) {
          // Cancelled through shouldContinue while still winding down.
          return null;
        }
        if (DateTime.now().difference(lastTick) >= tick) {
          lastTick = DateTime.now();
          if (shouldContinue != null && !shouldContinue()) return null;
          onProgress?.call(progress());
        }
        await Future<void>.delayed(delay);
        delay = delay == Duration.zero
            ? const Duration(milliseconds: 1)
            : Duration(
                milliseconds: (delay.inMilliseconds * 2).clamp(1, 25).toInt(),
              );
      }
    } finally {
      dispose();
    }
  }
}

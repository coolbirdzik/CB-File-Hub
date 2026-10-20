import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings.dart' as b;
import 'buffers.dart';

/// Whether the Rust library is loaded and speaks the expected ABI.
class CbNative {
  CbNative._();

  static bool? _available;

  static bool get isAvailable => _available ??= _probe();

  static bool _probe() {
    try {
      return b.cb_native_abi_version() == b.expectedAbiVersion;
    } catch (_) {
      // ArgumentError: the asset was not bundled (no Rust toolchain at build
      // time, or an unsupported target).
      return false;
    }
  }

  /// The native port of `TextUtils.searchKey`, or null when unavailable.
  /// Exposed so tests can check it folds names exactly like the Dart code.
  static String? searchKey(String value) {
    if (!isAvailable) return null;
    return using((arena) {
      final input = Utf8Arg.of(value, arena);
      final outPtr = arena<Pointer<Uint8>>();
      final outLen = arena<Size>();
      final status = b.cb_search_key(input.ptr, input.length, outPtr, outLen);
      if (status != b.statusOk) return null;
      return utf8.decode(takeBuffer(outPtr.value, outLen.value));
    });
  }
}

enum NativeEntryKind { directory, file, link }

class NativeSearchHit {
  const NativeSearchHit(this.path, this.kind);

  final String path;
  final NativeEntryKind kind;
}

class NativeSearchBatch {
  const NativeSearchBatch(this.hits, {required this.finished});

  final List<NativeSearchHit> hits;

  /// No further hits will arrive after this batch.
  final bool finished;
}

/// A recursive name search running on native worker threads.
///
/// Starting and polling never block on the filesystem, so both are safe to
/// call from the UI isolate. Always call [dispose], which also cancels.
class NativeSearch implements Finalizable {
  NativeSearch._(this._handle) {
    _finalizer.attach(this, _handle.cast(), detach: this);
  }

  /// Frees the handle if this object is dropped without [dispose], e.g. when
  /// its isolate is killed.
  static final _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(
      b.cb_search_free,
    ),
  );

  Pointer<b.SearchHandle> _handle;

  /// Starts searching below [root], or returns null when the native library
  /// is unavailable or rejects [regex] (its syntax is Rust's, not Dart's), so
  /// the caller can fall back to its Dart walker.
  ///
  /// Without [regex], a name matches when its `TextUtils.searchKey` contains
  /// every entry of [words] (already search keys, as `TextUtils.searchWords`
  /// returns them). With [regex], the raw name is matched case-insensitively.
  static NativeSearch? start({
    required String root,
    List<String> words = const [],
    String? regex,
  }) {
    if (!CbNative.isAvailable || root.isEmpty) return null;
    return using((arena) {
      final rootArg = Utf8Arg.of(root, arena);
      final wordsArg = Utf8Arg.of(words.join('\u0000'), arena);
      final regexArg = Utf8Arg.of(regex ?? '', arena);
      final outHandle = arena<Pointer<b.SearchHandle>>();
      final status = b.cb_search_start(
        rootArg.ptr,
        rootArg.length,
        wordsArg.ptr,
        wordsArg.length,
        regexArg.ptr,
        regexArg.length,
        outHandle,
      );
      if (status != b.statusOk) return null;
      return NativeSearch._(outHandle.value);
    });
  }

  bool get isDisposed => _handle == nullptr;

  /// Hits found since the previous poll.
  NativeSearchBatch poll() {
    if (isDisposed) return const NativeSearchBatch([], finished: true);
    return using((arena) {
      final outPtr = arena<Pointer<Uint8>>();
      final outLen = arena<Size>();
      final finished = b.cb_search_poll(_handle, outPtr, outLen) == 1;
      final bytes = takeBuffer(outPtr.value, outLen.value);
      return NativeSearchBatch(_decodeHits(bytes), finished: finished);
    });
  }

  void cancel() {
    if (!isDisposed) b.cb_search_cancel(_handle);
  }

  /// Cancels the walk and frees the handle. Never waits for workers.
  void dispose() {
    if (isDisposed) return;
    _finalizer.detach(this);
    b.cb_search_free(_handle.cast());
    _handle = nullptr;
  }

  /// Polls until the walk ends and returns every hit, or null if
  /// [shouldContinue] turned false first (the search is cancelled then).
  static Future<List<NativeSearchHit>?> collect(
    NativeSearch search, {
    required bool Function() shouldContinue,
    Duration pollInterval = const Duration(milliseconds: 25),
  }) async {
    final hits = <NativeSearchHit>[];
    try {
      while (true) {
        final batch = search.poll();
        hits.addAll(batch.hits);
        if (batch.finished) return hits;
        if (!shouldContinue()) return null;
        await Future<void>.delayed(pollInterval);
      }
    } finally {
      search.dispose();
    }
  }

  static List<NativeSearchHit> _decodeHits(Uint8List bytes) {
    final hits = <NativeSearchHit>[];
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != 0) continue;
      if (i > start) {
        final kind = switch (bytes[start]) {
          b.kindDirectory => NativeEntryKind.directory,
          b.kindLink => NativeEntryKind.link,
          _ => NativeEntryKind.file,
        };
        final path = utf8.decode(
          Uint8List.sublistView(bytes, start + 1, i),
          allowMalformed: true,
        );
        hits.add(NativeSearchHit(path, kind));
      }
      start = i + 1;
    }
    return hits;
  }
}

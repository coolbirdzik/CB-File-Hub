import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Coordinates listing work without letting one tab unlock another tab's scan.
class ThumbnailListingGate {
  static final instance = ThumbnailListingGate();

  bool _legacyReady = true;
  final Map<Object, String?> _scans = {};
  final List<({String? source, void Function() callback})> _waiting = [];
  bool _flushScheduled = false;

  bool get isReady => _legacyReady && _scans.isEmpty;

  String _key(String source) {
    final normalized = path.normalize(source);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  bool isReadyFor(String? source) {
    if (!_legacyReady) return false;
    if (source == null) return _scans.isEmpty;
    final key = _key(source);
    return !_scans.values.any(
      (folder) => folder == null || key == folder || path.isWithin(folder, key),
    );
  }

  /// The returned release is idempotent and must run on every exit path.
  void Function() pause({String? folder}) {
    final token = Object();
    _scans[token] = folder == null ? null : _key(folder);
    var released = false;
    return () {
      if (released) return;
      released = true;
      _scans.remove(token);
      _flush();
    };
  }

  void setLegacyReady(bool ready) {
    _legacyReady = ready;
    if (ready) _flush();
  }

  void whenReady(void Function() callback, {String? source}) {
    if (isReadyFor(source)) {
      callback();
    } else {
      _waiting.add((source: source, callback: callback));
    }
  }

  void _flush() {
    if (_flushScheduled || _waiting.isEmpty) return;
    _flushScheduled = true;
    scheduleMicrotask(() {
      _flushScheduled = false;
      final waiting = List.of(_waiting);
      _waiting.clear();
      for (final pending in waiting) {
        whenReady(pending.callback, source: pending.source);
      }
    });
  }
}

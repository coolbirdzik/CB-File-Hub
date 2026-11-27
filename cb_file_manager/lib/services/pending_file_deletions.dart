import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Pending item identity, independent of progress ticks and tab lifetimes.
class PendingFileDeletions extends ChangeNotifier {
  static final instance = PendingFileDeletions();
  final Map<String, int> _references = {};

  String _key(String path) {
    final normalized = p.normalize(path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  bool contains(String path) => _references.containsKey(_key(path));

  Future<T> track<T>(Iterable<String> paths, Future<T> Function() work) async {
    final keys = paths.map(_key).toSet();
    for (final key in keys) {
      _references.update(key, (count) => count + 1, ifAbsent: () => 1);
    }
    notifyListeners();
    try {
      return await work();
    } finally {
      for (final key in keys) {
        final count = _references[key]! - 1;
        if (count == 0) {
          _references.remove(key);
        } else {
          _references[key] = count;
        }
      }
      notifyListeners();
    }
  }
}

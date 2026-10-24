import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// Legacy `SharedPreferences` store for Windows that shares the stock
/// plugin's `shared_preferences.json`.
///
/// The stock store writes its cached copy of the whole file on every change.
/// Each app window and the hidden torrent options window is a separate
/// process, so a write from one of them silently reverted settings another
/// process saved after it started (for example the torrent page size). This
/// store re-reads the file under a cross-process lock before every change and
/// writes back only that change.
class WindowsPreferencesStore extends SharedPreferencesStorePlatform {
  WindowsPreferencesStore({Future<File> Function()? file})
    : _resolveFile = file ?? _defaultFile;

  static const _prefix = 'flutter.';

  final Future<File> Function() _resolveFile;
  Future<void> _queue = Future<void>.value();
  Map<String, Object> _cache = {};
  FileStat? _cacheStat;

  static Future<File> _defaultFile() async => File(
    p.join(
      (await getApplicationSupportDirectory()).path,
      'shared_preferences.json',
    ),
  );

  @override
  Future<Map<String, Object>> getAll() => getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: _prefix)),
  );

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) =>
      getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: prefix)),
      );

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    Map<String, Object> values;
    try {
      values = await _transaction();
    } catch (e) {
      debugPrint('Error reading preferences: $e');
      values = _cache;
    }
    final filter = parameters.filter;
    return Map<String, Object>.of(values)..removeWhere(
      (key, _) =>
          !key.startsWith(filter.prefix) ||
          !(filter.allowList?.contains(key) ?? true),
    );
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _change((values) => values[key] = value);

  @override
  Future<bool> remove(String key) => _change((values) => values.remove(key));

  @override
  Future<bool> clear() => clearWithParameters(
    ClearParameters(filter: PreferencesFilter(prefix: _prefix)),
  );

  @override
  Future<bool> clearWithPrefix(String prefix) => clearWithParameters(
    ClearParameters(filter: PreferencesFilter(prefix: prefix)),
  );

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) {
    final filter = parameters.filter;
    return _change(
      (values) => values.removeWhere(
        (key, _) =>
            key.startsWith(filter.prefix) &&
            (filter.allowList?.contains(key) ?? true),
      ),
    );
  }

  Future<bool> _change(void Function(Map<String, Object> values) change) async {
    try {
      await _transaction(change);
      return true;
    } catch (e) {
      debugPrint('Error saving preferences to disk: $e');
      return false;
    }
  }

  /// Runs one read (and optional change) at a time in this process, and
  /// under an exclusive file lock across processes.
  Future<Map<String, Object>> _transaction([
    void Function(Map<String, Object> values)? change,
  ]) {
    final result = _queue.then((_) => _locked(change));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Map<String, Object>> _locked(
    void Function(Map<String, Object> values)? change,
  ) async {
    final file = await _resolveFile();
    await file.parent.create(recursive: true);
    final lock = await File('${file.path}.lock').open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.blockingExclusive);
      final values = await _read(file);
      if (change == null) return values;
      change(values);
      try {
        await file.writeAsString(jsonEncode(values), flush: true);
        _cacheStat = await file.stat();
      } catch (_) {
        // The cache no longer matches the file; read it again next time.
        _cacheStat = null;
        rethrow;
      }
      return values;
    } finally {
      // Closing the handle releases the lock.
      await lock.close();
    }
  }

  /// The file's current contents, reusing the cache while the file is
  /// unchanged since this store last read or wrote it.
  Future<Map<String, Object>> _read(File file) async {
    final stat = await file.stat();
    final known = _cacheStat;
    if (known != null &&
        known.type == stat.type &&
        known.modified == stat.modified &&
        known.size == stat.size) {
      return _cache;
    }
    var values = <String, Object>{};
    if (stat.type != FileSystemEntityType.notFound) {
      final text = await file.readAsString();
      if (text.isNotEmpty) {
        final data = jsonDecode(text);
        if (data is Map) values = data.cast<String, Object>();
      }
    }
    _cache = Map<String, Object>.of(values);
    _cacheStat = stat;
    return _cache;
  }
}

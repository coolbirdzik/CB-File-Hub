import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

/// All pin mutations share a SQLite transaction, including the one-time macOS
/// defaults. Opening another window cannot seed over a concurrent manual pin.
class SidebarPinsRepository {
  static const pathsKey = 'sidebar_pinned_paths';
  static const _macosDefaultsKey = 'macos_sidebar_defaults_v1';
  final Database database;

  SidebarPinsRepository(this.database);

  Future<String?> _read(DatabaseExecutor executor, String key) async {
    final rows = await executor.query(
      'preferences',
      columns: ['string_value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['string_value'] as String?;
  }

  Future<void> _write(DatabaseExecutor executor, String key, String value) =>
      executor.insert('preferences', {
        'key': key,
        'type': 'string',
        'string_value': value,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  List<String> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty && !value.startsWith('#'))
          .toList();
    } on FormatException {
      return [];
    }
  }

  bool _samePath(String a, String b) =>
      p.equals(p.normalize(a), p.normalize(b));

  Future<List<String>> read({bool validateDirectories = true}) async {
    final paths = _decode(await _read(database, pathsKey));
    if (!validateDirectories) return paths;
    final valid = <String>[];
    for (final path in paths) {
      try {
        if (await FileSystemEntity.type(path) !=
            FileSystemEntityType.notFound) {
          valid.add(path);
        }
      } on FileSystemException {
        // Unavailable folders remain persisted and can be reached again later.
      }
    }
    return valid;
  }

  Future<bool> contains(String path) async => (await read(
    validateDirectories: false,
  )).any((value) => _samePath(value, path.trim()));

  Future<bool> setPinned(String path, {required bool pinned}) async {
    final target = path.trim();
    if (target.isEmpty || target.startsWith('#')) return false;
    return database.transaction((txn) async {
      final existing = _decode(await _read(txn, pathsKey));
      if (pinned && existing.any((value) => _samePath(value, target))) {
        return true;
      }
      final updated = existing
          .where((value) => !_samePath(value, target))
          .toList();
      if (pinned) updated.insert(0, target);
      await _write(txn, pathsKey, jsonEncode(updated));
      return true;
    });
  }

  /// A single transaction commits the defaults and marker. Removing every
  /// default remains an intentional empty list on every later app launch.
  Future<bool> seedMacosDefaults(List<String> defaults) async {
    final candidates = defaults.where((value) => p.isAbsolute(value)).toList();
    if (candidates.isEmpty) return false;
    return database.transaction((txn) async {
      if (await _read(txn, _macosDefaultsKey) == '1') return false;
      final existing = _decode(await _read(txn, pathsKey));
      final merged = <String>[];
      for (final path in [...candidates, ...existing]) {
        if (!merged.any((value) => _samePath(value, path))) merged.add(path);
      }
      await _write(txn, pathsKey, jsonEncode(merged));
      await _write(txn, _macosDefaultsKey, '1');
      return true;
    });
  }
}

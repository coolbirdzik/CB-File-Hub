import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Shared filesystem primitives, with bounded scans and resumable result pages.
/// Approval is owned by the agent loop, before calling any mutating primitive.
class AgentFileTools {
  static const names = {
    'list_directory',
    'search_files',
    'search_content',
    'read_file',
    'get_file_info',
    'file_checksum',
    'create_directory',
    'copy_file',
    'move_file',
    'write_file',
  };
  final _pages = <String, _ResultSnapshot>{};
  int _sequence = 0;

  static String resolvePath(String input, String workingDirectory) {
    final value = input.trim();
    if (value.startsWith('#') || value.contains('://')) {
      throw ArgumentError(
        'Use a local filesystem path, not a virtual screen or network URL.',
      );
    }
    if (p.isAbsolute(value)) return p.normalize(value);
    if (workingDirectory.isEmpty || workingDirectory.startsWith('#')) {
      throw ArgumentError(
        'No working directory is available. Ask the user for a folder.',
      );
    }
    return p.normalize(p.join(workingDirectory, value));
  }

  Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args, {
    required bool Function() isCancelled,
  }) async {
    void check() {
      if (isCancelled()) throw StateError('Operation stopped by user.');
    }

    check();
    if (args['cursor'] != null) return page(name, args, null);
    final path = args['path'] as String? ?? '';
    if (name == 'list_directory' && path.isEmpty) {
      final drives = <Map<String, dynamic>>[];
      if (Platform.isWindows) {
        for (var code = 65; code <= 90; code++) {
          check();
          final root = '${String.fromCharCode(code)}:\\';
          if (await Directory(root).exists()) {
            drives.add({'path': root, 'type': 'directory'});
          }
        }
      } else {
        drives.add({'path': '/', 'type': 'directory'});
      }
      return page(name, args, drives);
    }
    if (name == 'list_directory' ||
        name == 'search_files' ||
        name == 'search_content') {
      return _scan(name, args, check);
    }
    if (name == 'read_file') {
      final bytes = await File(path)
          .openRead(0, 1024 * 1024 + 1)
          .fold<List<int>>([], (all, chunk) {
            check();
            return all..addAll(chunk);
          });
      if (bytes.length > 1024 * 1024) {
        throw ArgumentError(
          'Text read limit is 1 MiB. Narrow the request or use an approved command.',
        );
      }
      if (bytes.contains(0)) {
        throw ArgumentError('Binary file. Use get_file_info or file_checksum.');
      }
      final lines = const LineSplitter().convert(utf8.decode(bytes));
      final start = args['start_line'] as int? ?? 1;
      final count = (args['max_lines'] as int? ?? 50).clamp(1, 100);
      final selected = <Map<String, dynamic>>[];
      var chars = 0;
      var index = start - 1;
      for (; index < lines.length && selected.length < count; index++) {
        if (chars + lines[index].length > 10000) {
          if (selected.isEmpty) {
            throw ArgumentError(
              'Line ${index + 1} exceeds the text page limit. Use an approved command to inspect it.',
            );
          }
          break;
        }
        chars += lines[index].length;
        selected.add({'line': index + 1, 'text': lines[index]});
      }
      return {
        'ok': true,
        'path': path,
        'lines': selected,
        'total_lines': lines.length,
        'next_start_line': index < lines.length ? index + 1 : null,
      };
    }
    if (name == 'get_file_info' || name == 'file_checksum') {
      final before = await FileStat.stat(path);
      if (before.type == FileSystemEntityType.notFound) {
        throw FileSystemException('Path not found', path);
      }
      final result = _metadata(path, before);
      if (name == 'file_checksum') {
        if (before.type != FileSystemEntityType.file) {
          throw ArgumentError('file_checksum requires a regular file.');
        }
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        final stream = File(path)
            .openRead()
            .map((chunk) {
              check();
              if (DateTime.now().isAfter(deadline)) {
                throw TimeoutException('Checksum timed out.');
              }
              return chunk;
            })
            .timeout(const Duration(seconds: 15));
        final hash = await sha256.bind(stream).first;
        final after = await FileStat.stat(path);
        if (before.size != after.size || before.modified != after.modified) {
          throw StateError('File changed while hashing. Retry.');
        }
        result['sha256'] = hash.toString();
      }
      return {'ok': true, ...result};
    }
    if (name == 'create_directory') {
      check();
      await Directory(path).create(recursive: true);
      return {'ok': true, 'path': path, 'type': 'directory'};
    }
    if (name == 'write_file') {
      final file = File(path);
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw ArgumentError('Refusing to write through a symbolic link.');
      }
      final append = args['append'] == true;
      if (await file.exists() && !append && args['overwrite'] != true) {
        throw ArgumentError(
          'File exists. Use overwrite:true only if replacing its contents was requested.',
        );
      }
      check();
      await file.parent.create(recursive: true);
      check();
      await file.writeAsString(
        args['content'] as String,
        mode: append ? FileMode.append : FileMode.write,
        flush: true,
      );
      return {'ok': true, 'path': path, 'size_bytes': await file.length()};
    }
    final source = args['source'] as String;
    final destination = args['destination'] as String;
    if (await FileSystemEntity.type(source, followLinks: false) !=
        FileSystemEntityType.file) {
      throw ArgumentError('Source must be a regular file.');
    }
    if (await FileSystemEntity.type(destination, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw ArgumentError(
        'Destination exists; choose a different destination. No overwrite occurred.',
      );
    }
    if (!await Directory(p.dirname(destination)).exists()) {
      throw ArgumentError(
        'Destination folder does not exist. Use create_directory first.',
      );
    }
    check();
    // Exclusive reservation prevents accidentally replacing a destination that
    // appeared after the inspection/approval step.
    final target = File(destination);
    final sourceBefore = await File(source).stat();
    await target.create(exclusive: true);
    final sink = target.openWrite();
    try {
      await sink.addStream(
        File(source).openRead().map((chunk) {
          check();
          return chunk;
        }),
      );
      await sink.flush();
      await sink.close();
      final sourceAfter = await File(source).stat();
      if (sourceBefore.size != sourceAfter.size ||
          sourceBefore.modified != sourceAfter.modified ||
          sourceBefore.size != await target.length()) {
        throw StateError(
          'Source changed during copy. Original file was kept. Retry.',
        );
      }
      if (name == 'move_file') {
        check();
        await File(source).delete();
      }
    } catch (error) {
      await sink.close();
      // Only this invocation's exclusively-created destination is removed.
      if (await target.exists()) await target.delete();
      rethrow;
    }
    return {
      'ok': true,
      'source': source,
      'destination': destination,
      'size_bytes': await target.length(),
    };
  }

  Future<Map<String, dynamic>> _scan(
    String name,
    Map<String, dynamic> args,
    void Function() check,
  ) async {
    final path = args['path'] as String;
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw FileSystemException('Directory not found', path);
    }
    final results = <Map<String, dynamic>>[];
    final warnings = <String>[];
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    final recursive = args['recursive'] as bool? ?? name != 'list_directory';
    final query = (args['query'] as String? ?? args['pattern'] as String? ?? '')
        .toLowerCase();
    final ext = (args['extension'] as String? ?? '').toLowerCase();
    var visited = 0;
    var textBytes = 0;
    var complete = true;
    final entities = directory
        .list(recursive: recursive, followLinks: false)
        .handleError((Object error) {
          complete = false;
          if (warnings.length < 5) warnings.add(error.toString());
        })
        .timeout(const Duration(seconds: 15));
    try {
      await for (final entity in entities) {
        check();
        if (++visited > 20000 ||
            results.length >= 10000 ||
            DateTime.now().isAfter(deadline)) {
          complete = false;
          warnings.add(
            'Scan bounds reached. Narrow the folder or filters for remaining results.',
          );
          break;
        }
        if (name != 'list_directory' && entity is! File) {
          continue;
        }
        final filename = p.basename(entity.path).toLowerCase();
        if (ext.isNotEmpty &&
            !filename.endsWith(ext.startsWith('.') ? ext : '.$ext')) {
          continue;
        }
        if (name != 'search_content' &&
            query.isNotEmpty &&
            !filename.contains(query)) {
          continue;
        }
        try {
          final stat = await entity.stat();
          if (name != 'search_content') {
            results.add(_metadata(entity.path, stat));
            continue;
          }
          if (stat.size > 1024 * 1024) {
            complete = false;
            if (!warnings.contains(
              'Files larger than 1 MiB were skipped by text search.',
            )) {
              warnings.add(
                'Files larger than 1 MiB were skipped by text search.',
              );
            }
            continue;
          }
          if ((textBytes += stat.size) > 32 * 1024 * 1024) {
            complete = false;
            warnings.add(
              'Text search byte budget reached. Narrow the folder or extension.',
            );
            break;
          }
          final bytes = await File(entity.path).readAsBytes();
          if (bytes.contains(0)) continue;
          String content;
          try {
            content = utf8.decode(bytes);
          } on FormatException {
            continue;
          }
          final lines = const LineSplitter().convert(content);
          for (var i = 0; i < lines.length; i++) {
            check();
            final haystack = args['case_sensitive'] == true
                ? lines[i]
                : lines[i].toLowerCase();
            final needle = args['case_sensitive'] == true
                ? args['query'] as String
                : query;
            if (!haystack.contains(needle)) continue;
            results.add({
              'path': entity.path,
              'line': i + 1,
              'text': lines[i].length > 200
                  ? '${lines[i].substring(0, 200)}…'
                  : lines[i],
            });
            if (results.length >= 10000) {
              complete = false;
              break;
            }
          }
        } on FileSystemException catch (error) {
          complete = false;
          if (warnings.length < 5) warnings.add(error.toString());
        }
      }
    } on TimeoutException {
      complete = false;
      warnings.add('Scan timed out. Narrow the folder or filters.');
    }
    results.sort(
      (a, b) => (a['path'] as String).compareTo(b['path'] as String),
    );
    return page(name, args, results, complete: complete, warnings: warnings);
  }

  Map<String, dynamic> page(
    String name,
    Map<String, dynamic> args,
    List<Map<String, dynamic>>? items, {
    bool complete = true,
    List<String> warnings = const [],
  }) {
    _pages.removeWhere(
      (_, value) =>
          DateTime.now().difference(value.created) >
          const Duration(minutes: 10),
    );
    final filtered = Map<String, dynamic>.from(args)
      ..remove('cursor')
      ..remove('limit');
    final keys = filtered.keys.toList()..sort();
    final fingerprint = jsonEncode({
      'tool': name,
      'args': {for (final key in keys) key: filtered[key]},
    });
    String id;
    var offset = 0;
    _ResultSnapshot snapshot;
    final cursor = args['cursor'] as String?;
    if (cursor != null) {
      final parts = cursor.split(':');
      id = parts.first;
      final existing = _pages[id];
      offset = parts.length == 2 ? int.tryParse(parts[1]) ?? -1 : -1;
      if (existing == null ||
          existing.fingerprint != fingerprint ||
          offset < 0 ||
          offset > existing.items.length) {
        throw ArgumentError(
          'Invalid/expired cursor or changed filters. Restart the search without cursor.',
        );
      }
      snapshot = existing;
    } else {
      while (_pages.length >= 8) {
        _pages.remove(_pages.keys.first);
      }
      id = '${DateTime.now().microsecondsSinceEpoch}-${++_sequence}';
      snapshot = _ResultSnapshot(fingerprint, items!, complete, warnings);
      _pages[id] = snapshot;
    }
    final limit = (args['limit'] as int? ?? 30).clamp(1, 100);
    final selected = <Map<String, dynamic>>[];
    var chars = 0;
    while (offset < snapshot.items.length && selected.length < limit) {
      final item = snapshot.items[offset];
      final length = jsonEncode(item).length;
      if (selected.isNotEmpty && chars + length > 10000) break;
      selected.add(item);
      chars += length;
      offset++;
    }
    return {
      'ok': true,
      'items': selected,
      'matched_in_scan': snapshot.items.length,
      'scope_complete': snapshot.complete,
      'next_cursor': offset < snapshot.items.length ? '$id:$offset' : null,
      'warnings': snapshot.warnings,
    };
  }

  static Map<String, dynamic> _metadata(String path, FileStat stat) => {
    'path': path,
    'name': p.basename(path),
    'type': stat.type.toString(),
    'size_bytes': stat.type == FileSystemEntityType.file ? stat.size : null,
    'modified': stat.modified.toIso8601String(),
  };
}

class _ResultSnapshot {
  final String fingerprint;
  final List<Map<String, dynamic>> items;
  final bool complete;
  final List<String> warnings;
  final DateTime created = DateTime.now();
  _ResultSnapshot(this.fingerprint, this.items, this.complete, this.warnings);
}

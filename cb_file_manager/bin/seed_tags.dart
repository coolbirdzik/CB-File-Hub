#!/usr/bin/env dart
// CLI tool to seed tags for CB File Manager (SQLite)
// Run with: dart run bin/seed_tags.dart [options]
//
// Options:
//   --list       : List all existing tags
//   --seed <n>   : Seed n tags (default: 20)
//   --clear      : Clear all tags
//   --add <tag>  : Add a specific tag
//   --remove <tag> : Remove a specific tag
//   --refresh    : Refresh/re-scan tags from database

import 'dart:io';

void main(List<String> args) async {
  final seedIndex = args.indexOf('--seed');
  final seedCount = seedIndex != -1 && seedIndex + 1 < args.length
      ? int.tryParse(args[seedIndex + 1]) ?? 20
      : 0;

  if (args.contains('--help') || args.contains('-h')) {
    print('''
CB File Manager Tag Seeder (SQLite)

Usage: dart run bin/seed_tags.dart [options]

Options:
  --list          : List all existing tags
  --seed <n>      : Seed n tags (default: 20)
  --clear         : Clear all tags from database
  --add <tag>     : Add a specific tag to first file
  --remove <tag>  : Remove a specific tag from all files
  --refresh       : Refresh tags (clear and seed 20)
  --help, -h      : Show this help message

Examples:
  dart run bin/seed_tags.dart --list
  dart run bin/seed_tags.dart --seed 50
  dart run bin/seed_tags.dart --clear
  dart run bin/seed_tags.dart --add "My Tag"
  dart run bin/seed_tags.dart --refresh
''');
    exit(0);
  }

  await runSeedTool(args, seedCount);
}

Future<void> runSeedTool(List<String> args, int seedCount) async {
  final dbPath = findDbFile();

  if (dbPath == null) {
    print('Error: cb_file_hub.sqlite not found.');
    print('Expected location:');
    print('  - \$HOME/Documents/CBFileHub_v2/cb_file_hub.sqlite');
    exit(1);
  }

  print('Found database: $dbPath');

  try {
    if (args.contains('--list')) {
      await listTags(dbPath);
      return;
    }

    if (args.contains('--clear')) {
      await clearTags(dbPath);
      return;
    }

    final addIndex = args.indexOf('--add');
    if (addIndex != -1 && addIndex + 1 < args.length) {
      final tag = args[addIndex + 1];
      await addTag(dbPath, tag);
      return;
    }

    final removeIndex = args.indexOf('--remove');
    if (removeIndex != -1 && removeIndex + 1 < args.length) {
      final tag = args[removeIndex + 1];
      await removeTag(dbPath, tag);
      return;
    }

    if (seedCount > 0) {
      await seedTags(dbPath, seedCount);
      return;
    }

    if (args.contains('--refresh')) {
      await refreshTags(dbPath);
      return;
    }

    print('No option specified. Use --help for usage information.');
  } catch (e) {
    print('Error: $e');
    exit(1);
  }
}

String? findDbFile() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  final documents = '$home/Documents';

  final candidates = <String>[
    '$documents/CBFileHub_v2/cb_file_hub.sqlite',
    '$documents/cb_file_hub/cb_file_hub.sqlite',
  ];

  for (final path in candidates) {
    if (File(path).existsSync()) {
      return path;
    }
  }

  return null;
}

/// Runs a parameterized SQLite query and returns result lines.
/// Parameters are safely escaped to prevent SQL injection.
Future<List<String>> queryDb(
  String dbPath,
  String sql, [
  List<Object?>? params,
]) async {
  final args = _buildArgs(dbPath, sql, params);
  final result = await Process.run('sqlite3', args);
  if (result.exitCode != 0) {
    throw Exception('SQLite error: ${result.stderr}');
  }
  return (result.stdout as String)
      .split('\n')
      .where((line) => line.isNotEmpty)
      .toList();
}

/// Runs a parameterized SQLite statement.
/// Parameters are safely escaped to prevent SQL injection.
Future<void> runSql(
  String dbPath,
  String sql, [
  List<Object?>? params,
]) async {
  final args = _buildArgs(dbPath, sql, params);
  final result = await Process.run('sqlite3', args);
  if (result.exitCode != 0) {
    throw Exception('SQLite error: ${result.stderr}');
  }
}

/// Builds the argument list for sqlite3, safely escaping parameter values.
List<String> _buildArgs(String dbPath, String sql, List<Object?>? params) {
  final args = <String>[dbPath, sql];
  if (params != null) {
    for (final param in params) {
      args.add(_escapeParam(param));
    }
  }
  return args;
}

/// Escapes a parameter value for safe use in SQLite shell commands.
/// Handles single quotes by doubling them (SQLite standard).
String _escapeParam(Object? param) {
  final str = param?.toString() ?? '';
  return str.replaceAll("'", "''");
}

Future<void> listTags(String dbPath) async {
  final tags =
      await queryDb(dbPath, "SELECT DISTINCT tag FROM file_tags ORDER BY tag;");

  print('');
  print('=== Tags in database (${tags.length}) ===');
  for (final tag in tags) {
    print('  - $tag');
  }
  print('');
}

Future<void> clearTags(String dbPath) async {
  final count = await queryDb(dbPath, "SELECT COUNT(*) FROM file_tags;");
  if (count.isEmpty || count.first == '0') {
    print('No tags to clear.');
    return;
  }

  print('Clearing all tags from database...');
  await runSql(dbPath, "DELETE FROM file_tags;");
  print('Done!');
}

Future<void> addTag(String dbPath, String tag) async {
  // Get first file path
  final files = await queryDb(
      dbPath, "SELECT DISTINCT file_path FROM file_tags LIMIT 1;");

  String filePath;
  if (files.isEmpty) {
    // Create a placeholder file entry
    filePath = '/seed_test/placeholder.mp4';
  } else {
    filePath = files.first;
  }

  final now = DateTime.now().millisecondsSinceEpoch;
  await runSql(
    dbPath,
    'INSERT OR REPLACE INTO file_tags (file_path, tag, normalized_tag, created_at) VALUES (?, ?, ?, ?)',
    [filePath, tag, tag.toLowerCase(), now],
  );

  print('Added tag "$tag" to file: $filePath');
}

Future<void> removeTag(String dbPath, String tag) async {
  await runSql(dbPath, 'DELETE FROM file_tags WHERE tag = ?', [tag]);
  print('Removed tag "$tag" from all files');
}

Future<void> refreshTags(String dbPath) async {
  print('Refreshing tags...');
  await clearTags(dbPath);
  print('');
  await seedTags(dbPath, 20);
}

Future<void> seedTags(String dbPath, int count) async {
  final categories = [
    'Music',
    'Video',
    'Photo',
    'Work',
    'Personal',
    'Project',
    'Archive',
    'Important',
    'Draft',
    'Final',
  ];

  final adjectives = [
    'Urgent',
    'Review',
    'Pending',
    'Completed',
    'Archived',
    'Backup',
    'Temp',
    'New',
    'Old',
    'Favorite',
  ];

  final suffixes = [
    'Q1',
    'Q2',
    'Q3',
    'Q4',
    '2024',
    '2025',
    '2026',
    'v1',
    'v2',
    'v3',
    'Final',
    'Draft',
    'Backup',
  ];

  // Get first file path or create placeholder
  var files = await queryDb(
      dbPath, "SELECT DISTINCT file_path FROM file_tags LIMIT 1;");

  String filePath;
  if (files.isEmpty) {
    filePath = '/seed_test/placeholder.mp4';
  } else {
    filePath = files.first;
  }

  final now = DateTime.now().millisecondsSinceEpoch;

  print('Seeding $count tags to file: $filePath');

  for (int i = 0; i < count; i++) {
    final category = categories[i % categories.length];
    final adjective = adjectives[i % adjectives.length];
    final suffix = suffixes[i % suffixes.length];
    final tag = '$category - $adjective $suffix ${i + 1}';

    await runSql(
      dbPath,
      'INSERT OR REPLACE INTO file_tags (file_path, tag, normalized_tag, created_at) VALUES (?, ?, ?, ?)',
      [filePath, tag, tag.toLowerCase(), now],
    );

    if ((i + 1) % 10 == 0) {
      print('  Progress: ${i + 1}/$count');
    }
  }

  print('');
  print('Successfully seeded $count tags!');

  await listTags(dbPath);
}

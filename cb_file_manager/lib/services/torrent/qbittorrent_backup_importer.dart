import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cb_file_manager/helpers/core/file_hash.dart';
import 'package:path/path.dart' as p;

import 'windows_qbittorrent_process.dart';

enum QbittorrentImportProblem {
  running,
  sqlite,
  changed,
  destination,
  missingMetainfo,
}

class QbittorrentImportException implements Exception {
  final QbittorrentImportProblem problem;
  const QbittorrentImportException(this.problem);
  @override
  String toString() => 'qBittorrent: ${problem.name}';
}

class QbittorrentSourceFile {
  final String path;
  final int modified;
  final int size;
  const QbittorrentSourceFile(this.path, this.modified, this.size);
}

class QbittorrentBackupItem {
  final String hash;
  final List<QbittorrentSourceFile> files;
  QbittorrentBackupItem(this.hash, List<QbittorrentSourceFile> files)
    : files = List.unmodifiable(files);
  String? get torrentPath => files
      .where((file) => p.extension(file.path).toLowerCase() == '.torrent')
      .firstOrNull
      ?.path;

  /// Keep profiles separate even when their hashes match but resume state differs.
  String resumeArchivePath(String source, String destination) => p.join(
    destination,
    hash.substring(0, 2),
    '$hash.qbit',
    '${sha256.convert(utf8.encode(p.normalize(source)))}.fastresume',
  );
}

class QbittorrentImportPlan {
  final List<String> roots;
  final List<QbittorrentBackupItem> items;
  QbittorrentImportPlan(List<String> roots, List<QbittorrentBackupItem> items)
    : roots = List.unmodifiable(roots),
      items = List.unmodifiable(items);
  int get fileCount =>
      items.fold(0, (count, item) => count + item.files.length);
}

class QbittorrentImportResult {
  final int processed;
  final int stored;
  final int cleaned;
  final int failed;
  final bool cancelled;
  final QbittorrentImportProblem? stoppedBy;
  final List<String> errors;
  const QbittorrentImportResult({
    this.processed = 0,
    required this.stored,
    required this.cleaned,
    required this.failed,
    required this.cancelled,
    required this.stoppedBy,
    required this.errors,
  });
}

class QbittorrentBackupImporter {
  final Future<void> Function(QbittorrentBackupItem, String) save;
  final Future<void> Function(String, String) verify;
  final Future<void> Function(
    QbittorrentBackupItem,
    String,
    Map<String, Digest>,
  )?
  verifyResumeCopies;
  final Future<bool> Function() isRunning;
  final String logPath;
  QbittorrentBackupImporter({
    required this.save,
    required this.verify,
    required this.logPath,
    this.verifyResumeCopies,
    Future<bool> Function()? isRunning,
  }) : isRunning =
           isRunning ?? (() async => WindowsQbittorrentProcess.isRunning());

  static Future<List<String>> discoverWindowsRoots({
    Map<String, String>? environment,
  }) async {
    final env = environment ?? Platform.environment;
    final roots = <String>[];
    for (final parent in {
      env['LOCALAPPDATA'],
      env['APPDATA'],
    }.whereType<String>()) {
      final folder = p.normalize(
        p.absolute(p.join(parent, 'qBittorrent', 'BT_backup')),
      );
      if (await Directory(folder).exists()) roots.add(folder);
    }
    return roots;
  }

  static Future<QbittorrentImportPlan> preview(List<String> folders) async {
    final roots = folders
        .map((folder) => p.normalize(p.absolute(folder)))
        .toSet()
        .toList();
    final items = <String, List<QbittorrentSourceFile>>{};
    final hashPattern = RegExp(r'^[a-f0-9]{40}(?:[a-f0-9]{24})?$');
    for (final root in roots) {
      await for (final file in Directory(root).list(followLinks: false)) {
        if (file is! File) continue;
        final extension = p.extension(file.path).toLowerCase();
        if (extension != '.torrent' && extension != '.fastresume') continue;
        final hash = p.basenameWithoutExtension(file.path).toLowerCase();
        if (!hashPattern.hasMatch(hash)) continue;
        final stat = await file.stat();
        items
            .putIfAbsent(hash, () => [])
            .add(
              QbittorrentSourceFile(
                p.normalize(p.absolute(file.path)),
                stat.modified.microsecondsSinceEpoch,
                stat.size,
              ),
            );
      }
    }
    final ordered = items.keys.toList()..sort();
    return QbittorrentImportPlan(roots, [
      for (final hash in ordered) QbittorrentBackupItem(hash, items[hash]!),
    ]);
  }

  Future<void> checkCleanupAllowed(QbittorrentImportPlan plan) async {
    if (await isRunning()) {
      throw const QbittorrentImportException(QbittorrentImportProblem.running);
    }
    for (final root in plan.roots) {
      if (await File(p.join(p.dirname(root), 'torrents.db')).exists()) {
        throw const QbittorrentImportException(QbittorrentImportProblem.sqlite);
      }
    }
  }

  Future<bool> _unchanged(QbittorrentSourceFile file) async {
    final stat = await File(file.path).stat();
    return stat.type == FileSystemEntityType.file &&
        stat.modified.microsecondsSinceEpoch == file.modified &&
        stat.size == file.size;
  }

  Future<void> _cleanup(
    QbittorrentImportPlan plan,
    QbittorrentBackupItem item,
    String destination,
    Map<String, Digest> sourceDigests,
  ) async {
    // Never broaden the approved plan to files found after confirmation.
    await checkCleanupAllowed(plan);
    for (final file in item.files) {
      if (!await _unchanged(file)) {
        throw const QbittorrentImportException(
          QbittorrentImportProblem.changed,
        );
      }
    }
    final staged = <String, String>{};
    try {
      for (final file in item.files) {
        final temporary =
            '${file.path}.cb-file-hub-${DateTime.now().microsecondsSinceEpoch}.cleanup';
        if (await File(temporary).exists()) {
          throw StateError('Cleanup file exists: $temporary');
        }
        await File(file.path).rename(temporary);
        staged[file.path] = temporary;
      }
      await checkCleanupAllowed(plan);
      await verify(item.hash, destination);
      await verifyResumeCopies?.call(item, destination, sourceDigests);
      for (final pair in staged.entries) {
        final digest = await sha256OfFile(pair.value);
        if (digest != sourceDigests[pair.key]) {
          throw const QbittorrentImportException(
            QbittorrentImportProblem.changed,
          );
        }
      }
      // Verification of large resume files can take time. Check once more
      // immediately before committing deletion, not just before staging.
      await checkCleanupAllowed(plan);
      for (final temporary in staged.values) {
        await File(temporary).delete();
      }
    } catch (error) {
      final recoveryErrors = <String>[];
      for (final pair in staged.entries) {
        if (!await File(pair.value).exists()) continue;
        try {
          if (await File(pair.key).exists()) {
            throw StateError('Source was recreated');
          }
          await File(pair.value).rename(pair.key);
        } catch (restoreError) {
          recoveryErrors.add('${pair.value}: $restoreError');
        }
      }
      if (recoveryErrors.isNotEmpty) {
        throw StateError('$error; ${recoveryErrors.join('; ')}');
      }
      rethrow;
    }
  }

  Future<QbittorrentImportResult> run(
    QbittorrentImportPlan plan,
    String destination, {
    bool removeSources = false,
    bool confirmedRemoval = false,
    bool Function()? isCancelled,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (destination.trim().isEmpty) {
      throw const QbittorrentImportException(
        QbittorrentImportProblem.destination,
      );
    }
    final target = p.normalize(p.absolute(destination));
    for (final item in plan.items) {
      for (final file in item.files) {
        if (!plan.roots.any((root) => p.equals(root, p.dirname(file.path))) ||
            p.basenameWithoutExtension(file.path).toLowerCase() != item.hash ||
            !const [
              '.torrent',
              '.fastresume',
            ].contains(p.extension(file.path).toLowerCase())) {
          throw StateError(
            'File is outside the qBittorrent cleanup preview: ${file.path}',
          );
        }
      }
    }
    if (plan.roots.any(
      (root) => p.equals(root, target) || p.isWithin(root, target),
    )) {
      throw const QbittorrentImportException(
        QbittorrentImportProblem.destination,
      );
    }
    if (removeSources) {
      if (!confirmedRemoval) {
        throw StateError('Confirm the qBittorrent source cleanup first');
      }
      await checkCleanupAllowed(plan);
    }
    await File(logPath).parent.create(recursive: true);
    final log = File(logPath).openWrite();
    var stored = 0, cleaned = 0, failed = 0, completed = 0;
    QbittorrentImportProblem? stoppedBy;
    final errors = <String>[];
    try {
      for (final item in plan.items) {
        if (isCancelled?.call() == true) break;
        completed++;
        try {
          if (removeSources) {
            for (final file in item.files) {
              if (!await _unchanged(file)) {
                throw const QbittorrentImportException(
                  QbittorrentImportProblem.changed,
                );
              }
            }
          }
          final digests = <String, Digest>{};
          if (removeSources) {
            for (final file in item.files) {
              digests[file.path] = await sha256OfFile(file.path);
            }
          }
          await save(item, target);
          await verify(item.hash, target);
          stored++;
          if (removeSources && isCancelled?.call() != true) {
            await _cleanup(plan, item, target, digests);
            cleaned++;
          }
        } catch (error) {
          failed++;
          final message =
              '${item.files.map((file) => file.path).join(', ')}: $error';
          log.writeln(message);
          if (errors.length < 100) errors.add(message);
          if (error is QbittorrentImportException &&
              (error.problem == QbittorrentImportProblem.running ||
                  error.problem == QbittorrentImportProblem.sqlite)) {
            stoppedBy = error.problem;
            break;
          }
        }
        onProgress?.call(completed, plan.items.length);
      }
    } finally {
      await log.flush();
      await log.close();
    }
    return QbittorrentImportResult(
      processed: completed,
      stored: stored,
      cleaned: cleaned,
      failed: failed,
      cancelled: isCancelled?.call() == true,
      stoppedBy: stoppedBy,
      errors: List.unmodifiable(errors),
    );
  }
}

import 'dart:async';
import 'dart:io';

import '../../../ui/utils/file_type_utils.dart';
import '../../video_library_service.dart';
import 'subtitle_batch_models.dart';
import 'subtitle_batch_store.dart';

class SubtitleBatchScanReport {
  final int found;
  final int added;
  final int skippedExisting;
  const SubtitleBatchScanReport({
    this.found = 0,
    this.added = 0,
    this.skippedExisting = 0,
  });

  /// Found videos this rule had queued before.
  int get alreadyQueued => found - added - skippedExisting;

  SubtitleBatchScanReport operator +(SubtitleBatchScanReport other) =>
      SubtitleBatchScanReport(
        found: found + other.found,
        added: added + other.added,
        skippedExisting: skippedExisting + other.skippedExisting,
      );
}

/// Finds the local videos a rule covers and queues them.
class SubtitleBatchScanner {
  final SubtitleBatchStore store;
  final Future<List<String>> Function(int libraryId) libraryFiles;

  SubtitleBatchScanner({
    SubtitleBatchStore? store,
    Future<List<String>> Function(int libraryId)? libraryFiles,
  }) : store = store ?? SubtitleBatchStore.instance,
       libraryFiles = libraryFiles ?? VideoLibraryService().getLibraryFiles;

  /// Every matching video of [rule]; folders are listed asynchronously so a
  /// large tree does not block the UI.
  Future<List<String>> videos(SubtitleBatchRule rule) async {
    final found = <String>{};
    for (final folder in rule.folders) {
      final dir = Directory(folder);
      if (!await dir.exists()) continue;
      await for (final entity
          in dir
              .list(recursive: rule.recursive, followLinks: false)
              .handleError((Object _) {})) {
        if (entity is File && _accepts(rule, entity.path)) {
          found.add(entity.path);
        }
      }
    }
    for (final id in rule.libraryIds) {
      try {
        for (final path in await libraryFiles(id)) {
          if (_isLocal(path) && _accepts(rule, path)) found.add(path);
        }
      } catch (_) {
        // A removed library is not an error for the other sources.
      }
    }
    return found.toList()..sort();
  }

  static bool _accepts(SubtitleBatchRule rule, String path) =>
      FileTypeUtils.isVideoFile(path) && rule.matches(path);

  /// Generation and sidecar export need a local path; SMB/HTTP sources are
  /// not supported by the queue.
  static bool _isLocal(String path) =>
      !RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]+://').hasMatch(path);

  Future<SubtitleBatchScanReport> enqueueRule(
    SubtitleBatchRule rule, {
    required String appLanguage,
  }) async {
    final settings = rule.resolve(appLanguage);
    final all = await videos(rule);
    return enqueuePaths(
      all,
      settings: settings,
      ruleId: rule.id,
      ruleName: rule.name,
    );
  }

  Future<SubtitleBatchScanReport> enqueuePaths(
    List<String> paths, {
    required SubtitleBatchSettings settings,
    int? ruleId,
    required String ruleName,
  }) async {
    final queue = <String>[];
    // Videos that already have the subtitle are still listed under the
    // rule, as skipped, so every rule shows all of its videos.
    final existing = <String, String>{};
    for (final path in paths) {
      final sidecar =
          settings.skipExisting && settings.outputMode.writesAutomatically
          ? await existingSubtitleSidecar(path, settings.targetLanguage)
          : null;
      if (sidecar != null) {
        existing[path] = sidecar;
      } else {
        queue.add(path);
      }
    }
    final added = await store.enqueue(
      queue,
      settings: settings,
      ruleId: ruleId,
      ruleName: ruleName,
    );
    await store.enqueue(
      existing.keys,
      settings: settings,
      ruleId: ruleId,
      ruleName: ruleName,
      status: SubtitleBatchStatus.skipped,
      outputs: existing,
      message: 'Subtitle already exists',
    );
    return SubtitleBatchScanReport(
      found: paths.length,
      added: added,
      skippedExisting: existing.length,
    );
  }
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../subtitle_cache.dart';
import '../subtitle_srt.dart';
import 'subtitle_batch_models.dart';
import 'subtitle_batch_store.dart';
import 'subtitle_generated_metadata.dart';

class SubtitleGeneratedCleanupResult {
  final int cleaned, retained, failed;
  const SubtitleGeneratedCleanupResult(
    this.cleaned,
    this.retained,
    this.failed,
  );
}

/// Clears generated outputs for completed jobs, not existing/skipped SRTs.
/// The queue must be paused and its lease free while files are being cleaned.
class SubtitleGeneratedCleanup {
  final SubtitleBatchStore store;
  final SubtitleCache cache;
  final SharedPreferences prefs;

  const SubtitleGeneratedCleanup(this.store, this.cache, this.prefs);

  Future<SubtitleGeneratedCleanupResult> clean({int? ruleId}) async {
    final owner =
        'subtitle-clean-$pid-${DateTime.now().microsecondsSinceEpoch}';
    const ttl = Duration(minutes: 5);
    if (await store.runRequested() ||
        ((await store.counts())[SubtitleBatchStatus.running] ?? 0) > 0 ||
        await store.tryLease(owner, ttl) == SubtitleBatchLease.denied) {
      throw StateError(
        'Pause the subtitle queue and wait for running jobs to stop.',
      );
    }
    var cleaned = 0, retained = 0, failed = 0;
    try {
      await prefs.reload();
      final remembered = {
        ...?prefs.getStringList(SubtitleSrtWriter.writtenKey),
      };
      final jobs = await store.jobs(
        statuses: {SubtitleBatchStatus.done},
        ruleId: ruleId,
      );
      final seen = <(String, String)>{};
      for (final job in jobs) {
        if (!seen.add((job.path, job.settings.signature))) continue;
        if (await store.runRequested() ||
            await store.tryLease(owner, ttl) == SubtitleBatchLease.denied) {
          throw StateError('Subtitle queue started during cleanup.');
        }
        try {
          // Re-read the row, since another window may have retried/removed it.
          final current = await store.job(job.id);
          if (current == null ||
              current.status != SubtitleBatchStatus.done ||
              current.settings.signature != job.settings.signature ||
              current.updatedAt != job.updatedAt) {
            retained++;
            continue;
          }
          final metadata = await store.generatedMetadata(job);
          final output = metadata?.outputPath ?? job.outputPath;
          if (output == null && metadata?.cacheKey == null) {
            retained++;
            continue;
          }
          if (output != null &&
              !await _removeOutput(job, output, metadata, remembered)) {
            retained++;
            continue;
          }
          if (output != null) {
            await prefs.reload();
            await prefs.setStringList(SubtitleSrtWriter.writtenKey, [
              ...?prefs
                  .getStringList(SubtitleSrtWriter.writtenKey)
                  ?.where((path) => path != _key(output)),
            ]);
          }
          if (metadata?.cacheKey case final key?) await cache.clear(key: key);
          await store.resetCleanedGeneration(job);
          cleaned++;
        } catch (_) {
          failed++;
        }
      }
    } finally {
      await store.releaseLease(owner);
    }
    return SubtitleGeneratedCleanupResult(cleaned, retained, failed);
  }

  static String _key(String value) {
    final normalized = p.normalize(p.absolute(value));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  Future<bool> _removeOutput(
    SubtitleBatchJob job,
    String output,
    SubtitleGeneratedMetadata? metadata,
    Set<String> remembered,
  ) async {
    if (!subtitleSidecarCandidates(
      job.path,
      job.settings.targetLanguage,
    ).any((candidate) => _key(candidate) == _key(output))) {
      return false;
    }
    final type = await FileSystemEntity.type(output, followLinks: false);
    final file = File(output);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      return false;
    }
    final sidecar = await SubtitleGeneratedMetadata.readSidecar(output);
    if (metadata != null) {
      if (!await store.ownsGeneratedOutput(job, output) ||
          metadata.outputSha256 == null ||
          (type == FileSystemEntityType.file &&
              SubtitleGeneratedMetadata.hash(await file.readAsBytes()) !=
                  metadata.outputSha256) ||
          (sidecar != null && sidecar.generatedAt != metadata.generatedAt)) {
        return false;
      }
    } else {
      // Legacy jobs have no checksum. Both the original writer's ownership
      // record and the completed job must agree; preserve later edits.
      if (!remembered.contains(_key(output)) ||
          sidecar != null ||
          await store.hasGeneratedOutput(output) ||
          (type == FileSystemEntityType.file &&
              (await file.lastModified()).isAfter(job.updatedAt))) {
        return false;
      }
    }
    if (type == FileSystemEntityType.file) await file.delete();
    if (sidecar != null &&
        metadata != null &&
        sidecar.generatedAt == metadata.generatedAt) {
      await File(SubtitleGeneratedMetadata.sidecarPath(output)).delete();
    }
    return true;
  }
}

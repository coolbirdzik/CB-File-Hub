import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/files/file_type_registry.dart';
import 'subtitle_batch/subtitle_batch_models.dart';
import 'subtitle_batch/subtitle_batch_store.dart';
import 'subtitle_batch/subtitle_generated_metadata.dart';
import 'subtitle_srt_ownership.dart';
import 'subtitle_srt.dart';

typedef SubtitleDeleteBatch = Future<Set<String>> Function(List<String> paths);

/// Delete verified AI outputs only after their source was successfully deleted.
/// The caller supplies the same delete operation (Trash/permanent/elevated).
class SubtitleVideoDeletion {
  SubtitleVideoDeletion({SubtitleBatchStore? store, this.prefs})
    : _store = store ?? SubtitleBatchStore();

  final SubtitleBatchStore _store;
  final SharedPreferences? prefs;

  static bool isVideo(String path) =>
      FileTypeRegistry.getCategory(p.extension(path).toLowerCase()) ==
      FileCategory.video;

  Future<Set<String>> delete(
    List<String> paths, {
    required SubtitleDeleteBatch operation,
    void Function(String path, Object error)? onError,
  }) async {
    final deleted = Set<String>.of(await operation(paths));
    for (final video in deleted.where(isVideo).toList()) {
      try {
        final prefs = this.prefs ?? await SharedPreferences.getInstance();
        final owners = await SubtitleSrtOwnership.read(prefs);
        final videoKey = SubtitleSrtOwnership.pathKey(video);
        final outputs = <String, ({String path, String hash})>{
          for (final entry in owners.entries)
            if (entry.value.source == videoKey)
              entry.key: (path: entry.value.output, hash: entry.value.hash),
        };
        for (final metadata in await _store.generatedForVideo(video)) {
          final output = metadata.outputPath;
          final hash = metadata.outputSha256;
          if (output == null || hash == null) continue;
          final key = SubtitleSrtOwnership.pathKey(output);
          final owner = owners[key];
          if (owner != null && owner.source != videoKey) continue;
          if (!subtitleSidecarCandidates(
            video,
            metadata.settings.targetLanguage,
          ).any((path) => SubtitleSrtOwnership.pathKey(path) == key)) {
            continue;
          }
          outputs.putIfAbsent(key, () => (path: output, hash: hash));
        }
        for (final entry in outputs.entries) {
          final output = entry.value.path;
          // No link traversal, name-only matches, or deletion of later edits.
          final type = await FileSystemEntity.type(output, followLinks: false);
          if (type != FileSystemEntityType.file &&
              type != FileSystemEntityType.notFound) {
            continue;
          }
          if (type == FileSystemEntityType.file) {
            if (SubtitleGeneratedMetadata.hash(
                  await File(output).readAsBytes(),
                ) !=
                entry.value.hash) {
              continue;
            }
            final removed = await operation([output]);
            if (!removed.contains(output)) {
              throw FileSystemException(
                'AI subtitle could not be deleted',
                output,
              );
            }
          }
          final sidecar = await SubtitleGeneratedMetadata.readSidecar(output);
          if (sidecar?.outputSha256 == entry.value.hash &&
              sidecar?.outputPath != null &&
              SubtitleSrtOwnership.pathKey(sidecar!.outputPath!) == entry.key) {
            final metadataPath = SubtitleGeneratedMetadata.sidecarPath(output);
            if (!(await operation([metadataPath])).contains(metadataPath)) {
              throw FileSystemException(
                'AI subtitle metadata could not be deleted',
                metadataPath,
              );
            }
          }
          final owner = owners[entry.key];
          if (owner != null) await prefs.remove(owner.preference);
          await prefs.reload();
          await prefs.setStringList(SubtitleSrtWriter.writtenKey, [
            ...?prefs
                .getStringList(SubtitleSrtWriter.writtenKey)
                ?.where(
                  (path) => SubtitleSrtOwnership.pathKey(path) != entry.key,
                ),
          ]);
        }
      } catch (error) {
        deleted.remove(video);
        onError?.call(
          video,
          FileSystemException(
            'Video deleted, but generated subtitle cleanup failed: $error',
            video,
            OSError(
              'Video deleted, but generated subtitle cleanup failed: $error',
            ),
          ),
        );
      }
    }
    return deleted;
  }
}

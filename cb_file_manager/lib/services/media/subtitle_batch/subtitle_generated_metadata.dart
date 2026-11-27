import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'subtitle_batch_models.dart';

/// Provenance of a completed generation, not the current rule configuration.
/// The cache may exist even when no SRT was written (app-only or silent video).
class SubtitleGeneratedMetadata {
  final SubtitleBatchSettings settings;
  final DateTime generatedAt;
  final String? cacheKey;
  final String? outputPath;
  final String? outputSha256;

  const SubtitleGeneratedMetadata({
    required this.settings,
    required this.generatedAt,
    this.cacheKey,
    this.outputPath,
    this.outputSha256,
  });

  Map<String, Object?> toJson() => {
    'generator': 'CB File Hub',
    'version': 1,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'speechModel': settings.speechModel,
    'translationModel': settings.translationModel,
    'sourceLanguage': settings.sourceLanguage,
    'targetLanguage': settings.targetLanguage,
    'settings': settings.toJson(),
    'cacheKey': cacheKey,
    'outputPath': outputPath,
    'outputSha256': outputSha256,
  };

  factory SubtitleGeneratedMetadata.fromJson(Map<String, Object?> json) =>
      SubtitleGeneratedMetadata(
        settings: SubtitleBatchSettings.fromJson(
          Map<String, Object?>.from(json['settings'] as Map),
        ),
        generatedAt: DateTime.parse(json['generatedAt'] as String),
        cacheKey: json['cacheKey'] as String?,
        outputPath: json['outputPath'] as String?,
        outputSha256: json['outputSha256'] as String?,
      );

  static String hash(List<int> bytes) => sha256.convert(bytes).toString();

  static String sidecarPath(String srt) => '$srt.cbmeta.json';

  /// Write a portable copy without putting non-SRT data in the subtitle.
  /// An unrelated file at the metadata path is never replaced.
  Future<void> writeSidecar() async {
    final output = outputPath;
    if (output == null) return;
    final file = File(sidecarPath(output));
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await file.create(exclusive: true);
    } else if (type != FileSystemEntityType.file ||
        await readSidecar(output) == null) {
      return;
    }
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
      flush: true,
    );
  }

  static Future<SubtitleGeneratedMetadata?> readSidecar(String output) async {
    try {
      final file = File(sidecarPath(output));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['generator'] != 'CB File Hub' || json['version'] != 1) {
        return null;
      }
      return SubtitleGeneratedMetadata.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}

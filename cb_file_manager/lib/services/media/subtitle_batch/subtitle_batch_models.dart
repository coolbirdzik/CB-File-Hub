import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as pathlib;

import '../subtitle_preferences.dart';

/// Lifecycle of one queued video.
enum SubtitleBatchStatus {
  pending,
  running,
  done,
  skipped,
  failed,
  cancelled;

  static SubtitleBatchStatus parse(String? value) =>
      values.where((s) => s.name == value).firstOrNull ?? pending;

  bool get finished => this == done || this == skipped || this == cancelled;
  bool get retryable => this == failed || this == cancelled || this == done;
}

/// Output modes that need nobody to answer a prompt.
List<SubtitleFileMode> get subtitleBatchOutputModes => [
  for (final mode in SubtitleFileMode.available)
    if (mode != SubtitleFileMode.askWhenDone) mode,
];

/// The concrete settings one job is generated with. "Follow app language" is
/// resolved when the job is queued, so a later language switch does not
/// change half-finished work.
class SubtitleBatchSettings {
  final String speechModel;
  final String sourceLanguage;
  final String translationModel;
  final String targetLanguage;
  final bool bilingual;
  final SubtitleFileMode outputMode;

  /// Skip a video that already has a `<name>.<lang>.srt` sidecar.
  final bool skipExisting;

  const SubtitleBatchSettings({
    required this.speechModel,
    required this.sourceLanguage,
    required this.translationModel,
    required this.targetLanguage,
    this.bilingual = false,
    this.outputMode = SubtitleFileMode.subsFolder,
    this.skipExisting = true,
  });

  /// Identifies equivalent work; two rules producing the same subtitles for
  /// the same video queue it once.
  String get signature => [
    speechModel,
    sourceLanguage,
    translationModel,
    targetLanguage,
    bilingual,
    outputMode.name,
  ].join('|');

  Map<String, Object?> toJson() => {
    'speech': speechModel,
    'source': sourceLanguage,
    'translation': translationModel,
    'target': targetLanguage,
    'bilingual': bilingual,
    'output': outputMode.name,
    'skipExisting': skipExisting,
  };

  factory SubtitleBatchSettings.fromJson(Map<String, Object?> json) =>
      SubtitleBatchSettings(
        speechModel: json['speech'] as String? ?? 'whisper/small',
        sourceLanguage: json['source'] as String? ?? 'auto',
        translationModel:
            json['translation'] as String? ?? 'tencent/Hy-MT2-1.8B-GGUF',
        targetLanguage: json['target'] as String? ?? 'en',
        bilingual: json['bilingual'] as bool? ?? false,
        outputMode: _mode(json['output'] as String?),
        skipExisting: json['skipExisting'] as bool? ?? true,
      );
}

SubtitleFileMode _mode(String? name) {
  final mode = SubtitleFileMode.values.where((m) => m.name == name).firstOrNull;
  return mode != null && subtitleBatchOutputModes.contains(mode)
      ? mode
      : SubtitleFileMode.subsFolder;
}

/// Which videos to queue and how to subtitle them.
class SubtitleBatchRule {
  final int? id;
  final String name;
  final bool enabled;
  final List<String> folders;
  final List<int> libraryIds;
  final bool recursive;

  /// Lower-case extensions without the dot; empty means every video type.
  final List<String> extensions;

  /// Case-insensitive file-name pattern; `*` matches anything. Without a `*`
  /// it matches names that contain the text. Empty matches everything.
  final String namePattern;

  final String speechModel;
  final String sourceLanguage;
  final String translationModel;

  /// A language code, or [SubtitlePreferences.followApp].
  final String targetLanguage;
  final bool bilingual;
  final SubtitleFileMode outputMode;
  final bool skipExisting;

  const SubtitleBatchRule({
    this.id,
    required this.name,
    this.enabled = true,
    this.folders = const [],
    this.libraryIds = const [],
    this.recursive = true,
    this.extensions = const [],
    this.namePattern = '',
    required this.speechModel,
    required this.sourceLanguage,
    required this.translationModel,
    required this.targetLanguage,
    this.bilingual = false,
    this.outputMode = SubtitleFileMode.subsFolder,
    this.skipExisting = true,
  });

  /// A new rule starts from the player's current subtitle settings.
  factory SubtitleBatchRule.fromPreferences(
    SubtitlePreferences prefs, {
    required String name,
  }) => SubtitleBatchRule(
    name: name,
    speechModel: prefs.speechModel,
    sourceLanguage: prefs.resolvedSourceLanguage,
    translationModel: prefs.translationModel,
    targetLanguage: prefs.targetLanguage,
    bilingual: prefs.bilingual,
  );

  bool get hasSources => folders.isNotEmpty || libraryIds.isNotEmpty;

  SubtitleBatchSettings resolve(String appLanguage) => SubtitleBatchSettings(
    speechModel: speechModel,
    sourceLanguage: sourceLanguage,
    translationModel: translationModel,
    targetLanguage: targetLanguage == SubtitlePreferences.followApp
        ? appLanguage
        : targetLanguage,
    bilingual: bilingual,
    outputMode: outputMode,
    skipExisting: skipExisting,
  );

  bool matches(String path) {
    final ext = pathlib.extension(path).toLowerCase().replaceFirst('.', '');
    if (extensions.isNotEmpty && !extensions.contains(ext)) return false;
    final pattern = namePattern.trim().toLowerCase();
    if (pattern.isEmpty) return true;
    final name = pathlib.basename(path).toLowerCase();
    if (!pattern.contains('*')) return name.contains(pattern);
    final regex = RegExp(
      '^${pattern.split('*').map(RegExp.escape).join('.*')}\$',
    );
    return regex.hasMatch(name);
  }

  /// Accepts "mp4, .mkv avi" and similar input.
  static List<String> parseExtensions(String text) => {
    for (final part in text.split(RegExp(r'[\s,;]+')))
      if (part.trim().replaceFirst('.', '').isNotEmpty)
        part.trim().replaceFirst('.', '').toLowerCase(),
  }.toList();

  SubtitleBatchRule copyWith({
    int? id,
    String? name,
    bool? enabled,
    List<String>? folders,
    List<int>? libraryIds,
    bool? recursive,
    List<String>? extensions,
    String? namePattern,
    String? speechModel,
    String? sourceLanguage,
    String? translationModel,
    String? targetLanguage,
    bool? bilingual,
    SubtitleFileMode? outputMode,
    bool? skipExisting,
  }) => SubtitleBatchRule(
    id: id ?? this.id,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    folders: folders ?? this.folders,
    libraryIds: libraryIds ?? this.libraryIds,
    recursive: recursive ?? this.recursive,
    extensions: extensions ?? this.extensions,
    namePattern: namePattern ?? this.namePattern,
    speechModel: speechModel ?? this.speechModel,
    sourceLanguage: sourceLanguage ?? this.sourceLanguage,
    translationModel: translationModel ?? this.translationModel,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    bilingual: bilingual ?? this.bilingual,
    outputMode: outputMode ?? this.outputMode,
    skipExisting: skipExisting ?? this.skipExisting,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'enabled': enabled,
    'folders': folders,
    'libraries': libraryIds,
    'recursive': recursive,
    'extensions': extensions,
    'pattern': namePattern,
    'speech': speechModel,
    'source': sourceLanguage,
    'translation': translationModel,
    'target': targetLanguage,
    'bilingual': bilingual,
    'output': outputMode.name,
    'skipExisting': skipExisting,
  };

  factory SubtitleBatchRule.fromJson(Map<String, Object?> json, {int? id}) =>
      SubtitleBatchRule(
        id: id,
        name: json['name'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        folders: [...?(json['folders'] as List?)?.whereType<String>()],
        libraryIds: [...?(json['libraries'] as List?)?.whereType<int>()],
        recursive: json['recursive'] as bool? ?? true,
        extensions: [...?(json['extensions'] as List?)?.whereType<String>()],
        namePattern: json['pattern'] as String? ?? '',
        speechModel: json['speech'] as String? ?? 'whisper/small',
        sourceLanguage: json['source'] as String? ?? 'auto',
        translationModel:
            json['translation'] as String? ?? 'tencent/Hy-MT2-1.8B-GGUF',
        targetLanguage:
            json['target'] as String? ?? SubtitlePreferences.followApp,
        bilingual: json['bilingual'] as bool? ?? false,
        outputMode: _mode(json['output'] as String?),
        skipExisting: json['skipExisting'] as bool? ?? true,
      );

  String encode() => jsonEncode(toJson());
}

/// One video in the queue.
class SubtitleBatchJob {
  final int id;
  final String path;
  final int? ruleId;
  final String ruleName;
  final SubtitleBatchSettings settings;
  final SubtitleBatchStatus status;

  /// 0–1, the share of the timeline recognized and translated.
  final double progress;
  final String? message;
  final String? outputPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Original video modification time, not the queue row's update time.
  final DateTime? fileModifiedAt;

  const SubtitleBatchJob({
    required this.id,
    required this.path,
    this.ruleId,
    required this.ruleName,
    required this.settings,
    required this.status,
    this.progress = 0,
    this.message,
    this.outputPath,
    required this.createdAt,
    required this.updatedAt,
    this.fileModifiedAt,
  });

  String get fileName => pathlib.basename(path);
  String get folder => pathlib.dirname(path);

  factory SubtitleBatchJob.fromRow(Map<String, Object?> row) {
    Map<String, Object?> settings;
    try {
      settings = Map<String, Object?>.from(
        jsonDecode(row['settings'] as String) as Map,
      );
    } catch (_) {
      settings = const {};
    }
    return SubtitleBatchJob(
      id: row['id'] as int,
      path: row['path'] as String,
      // 0 marks jobs queued without a rule.
      ruleId: switch (row['rule_id']) {
        final int id when id != 0 => id,
        _ => null,
      },
      ruleName: row['rule_name'] as String? ?? '',
      settings: SubtitleBatchSettings.fromJson(settings),
      status: SubtitleBatchStatus.parse(row['status'] as String?),
      progress: (row['progress'] as num?)?.toDouble() ?? 0,
      message: row['message'] as String?,
      outputPath: row['output_path'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int? ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at'] as int? ?? 0,
      ),
      fileModifiedAt: switch (row['file_modified_at']) {
        final int ms when ms != 0 => DateTime.fromMillisecondsSinceEpoch(ms),
        _ => null,
      },
    );
  }
}

/// The sidecar paths [SubtitleSrtWriter] could produce for [language], in
/// both the video's folder and its `Subs` folder.
List<String> subtitleSidecarCandidates(String videoPath, String language) {
  final base = '${pathlib.basenameWithoutExtension(videoPath)}.$language';
  final folder = pathlib.dirname(videoPath);
  return [
    for (final dir in [folder, pathlib.join(folder, 'Subs')])
      for (final name in ['$base.srt', '$base.ai.srt']) pathlib.join(dir, name),
  ];
}

/// The first existing sidecar for [language], or null.
Future<String?> existingSubtitleSidecar(
  String videoPath,
  String language,
) async {
  for (final candidate in subtitleSidecarCandidates(videoPath, language)) {
    if (await File(candidate).exists()) return candidate;
  }
  return null;
}

/// Why a job failed, from its stored message. The raw message stays in the
/// database; screens show [SubtitleBatchFailure.kind] in plain words.
enum SubtitleBatchFailureKind {
  /// Reading the audio took too long: a busy or slow drive.
  slowRead,
  fileMissing,

  /// Damaged file or an audio format the decoder does not support.
  unreadable,
  noAudio,
  language,
  speechModel,
  translation,
  runtimeMissing,

  /// The worker exited or stopped answering: usually memory pressure.
  runtimeCrashed,

  /// Nothing left to schedule, yet the video is not covered.
  stalledIdle,

  /// No progress for a long time.
  stalledSlow,
  unknown,
}

class SubtitleBatchFailure {
  static const stalledIdle = 'Stalled: nothing left to schedule at';
  static const stalledSlow = 'Stalled: no progress for 10 minutes at';
  static const openTimedOut = 'Audio read timed out: opening the video';

  /// Attempts for a [transient] failure before the job is marked failed.
  static const maxAttempts = 3;

  static const _kinds = <(SubtitleBatchFailureKind, List<String>)>[
    (SubtitleBatchFailureKind.stalledIdle, [stalledIdle]),
    (SubtitleBatchFailureKind.stalledSlow, [stalledSlow]),
    (
      SubtitleBatchFailureKind.fileMissing,
      ['File not found', 'No such file or directory'],
    ),
    (
      SubtitleBatchFailureKind.unreadable,
      ['Invalid data found when processing input'],
    ),
    (
      SubtitleBatchFailureKind.slowRead,
      [
        'Audio read failed',
        'Audio read timed out',
        'Cannot open media audio',
        'Cannot inspect audio streams',
      ],
    ),
    (SubtitleBatchFailureKind.noAudio, ['Selected audio track is unavailable']),
    (
      SubtitleBatchFailureKind.language,
      ['Unsupported audio language', 'Cannot detect audio language'],
    ),
    (
      SubtitleBatchFailureKind.speechModel,
      [
        'Cannot read speech model',
        'Speech model could not be loaded',
        'Speech model is not initialized',
      ],
    ),
    (
      SubtitleBatchFailureKind.runtimeMissing,
      ['Subtitle runtime is missing', 'Incompatible subtitle runtime'],
    ),
    (
      SubtitleBatchFailureKind.runtimeCrashed,
      [
        'Subtitle runtime exited',
        'Subtitle runtime is unavailable',
        'Speech recognition failed',
        'TimeoutException',
      ],
    ),
    (
      SubtitleBatchFailureKind.unreadable,
      [
        'Cannot read the video duration',
        'Media audio is not seekable',
        'Audio codec is unsupported',
        'Audio frame decoding failed',
        'Cannot feed audio decoder',
        'Audio resampling failed',
        'audio resampling',
      ],
    ),
    (
      SubtitleBatchFailureKind.translation,
      ['llama', 'translation', 'Translation'],
    ),
  ];

  static SubtitleBatchFailureKind kind(String? message) {
    if (message == null || message.isEmpty) {
      return SubtitleBatchFailureKind.unknown;
    }
    for (final (kind, needles) in _kinds) {
      if (needles.any(message.contains)) return kind;
    }
    return SubtitleBatchFailureKind.unknown;
  }

  /// Failures caused by load rather than by the file; worth another try.
  static bool transient(String? message) => switch (kind(message)) {
    SubtitleBatchFailureKind.slowRead ||
    SubtitleBatchFailureKind.stalledIdle ||
    SubtitleBatchFailureKind.stalledSlow ||
    SubtitleBatchFailureKind.runtimeCrashed => true,
    _ => false,
  };

  /// The message without Dart's exception prefixes, for the details view.
  static String detail(String? message) => (message ?? '').replaceFirst(
    RegExp(r'^(Bad state|Exception|StateError|TimeoutException): ?'),
    '',
  );
}

/// Data models for the Local AI Advisor feature.
///
/// Supports Hugging Face model catalog browsing, local model installation,
/// and on-device cleanup advisory inference. Token storage and runtime state
/// are kept isolated from existing remote AI providers.

/// Download state for a model.
enum LocalModelDownloadState {
  notStarted,
  downloading,
  completed,
  failed,
}

/// On-device runtime family required to run an installed artifact.
enum LocalModelRuntimeKind {
  /// `.litertlm` bundles — run via flutter_gemma LiteRT-LM engine.
  liteRtLm,

  /// `.gguf` quantised models — run via llamadart llama.cpp engine.
  llamaCpp,

  /// Unsupported format (e.g. raw `.safetensors`).
  unsupported,
}

/// A Hugging Face model catalog entry.
class HuggingFaceModelEntry {
  final String id; // e.g. "google/gemma-4-E2B-it-qat-mobile-transformers"
  final String displayName;
  final String? description;
  final int? sizeBytes;
  final String? license;
  final bool compatible;
  final String artifactFileName;

  const HuggingFaceModelEntry({
    required this.id,
    required this.displayName,
    this.description,
    this.sizeBytes,
    this.license,
    this.compatible = true,
    this.artifactFileName = 'model.safetensors',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'description': description,
        'sizeBytes': sizeBytes,
        'license': license,
        'compatible': compatible,
        'artifactFileName': artifactFileName,
      };

  static HuggingFaceModelEntry fromJson(Map<String, dynamic> json) =>
      HuggingFaceModelEntry(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        description: json['description'] as String?,
        sizeBytes: json['sizeBytes'] as int?,
        license: json['license'] as String?,
        compatible: json['compatible'] as bool? ?? true,
        artifactFileName:
            json['artifactFileName'] as String? ?? 'model.safetensors',
      );
}

/// Installed model metadata.
class InstalledLocalModel {
  final String catalogId; // References HuggingFaceModelEntry.id
  final String displayName;
  final String localPath; // Where the model artifact is stored
  final int sizeBytes;
  final DateTime installedAt;
  final String?
      runtimeArtifactId; // Mapped runtime artifact name (if available)

  const InstalledLocalModel({
    required this.catalogId,
    required this.displayName,
    required this.localPath,
    required this.sizeBytes,
    required this.installedAt,
    this.runtimeArtifactId,
  });

  Map<String, dynamic> toJson() => {
        'catalogId': catalogId,
        'displayName': displayName,
        'localPath': localPath,
        'sizeBytes': sizeBytes,
        'installedAt': installedAt.millisecondsSinceEpoch,
        'runtimeArtifactId': runtimeArtifactId,
      };

  static InstalledLocalModel fromJson(Map<String, dynamic> json) =>
      InstalledLocalModel(
        catalogId: json['catalogId'] as String,
        displayName: json['displayName'] as String,
        localPath: json['localPath'] as String,
        sizeBytes: json['sizeBytes'] as int,
        installedAt:
            DateTime.fromMillisecondsSinceEpoch(json['installedAt'] as int),
        runtimeArtifactId: json['runtimeArtifactId'] as String?,
      );

  /// Whether the installed artifact can run in a local on-device runtime.
  ///
  /// `.litertlm` bundles run through the LiteRT-LM runtime and `.gguf` models
  /// run through the llama.cpp runtime. Legacy `model.safetensors` downloads
  /// are Transformers-format and cannot run on-device.
  bool get isRunnableArtifact {
    final lower = localPath.toLowerCase();
    return lower.endsWith('.litertlm') || lower.endsWith('.gguf');
  }

  /// The on-device runtime family required to run this artifact.
  LocalModelRuntimeKind get runtimeKind {
    final lower = localPath.toLowerCase();
    if (lower.endsWith('.gguf')) return LocalModelRuntimeKind.llamaCpp;
    if (lower.endsWith('.litertlm')) return LocalModelRuntimeKind.liteRtLm;
    return LocalModelRuntimeKind.unsupported;
  }
}

/// Model download progress.
class ModelDownloadProgress {
  final String catalogId;
  final int downloadedBytes;
  final int totalBytes;
  final LocalModelDownloadState state;
  final String? errorMessage;

  const ModelDownloadProgress({
    required this.catalogId,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.state,
    this.errorMessage,
  });

  double get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
}

/// Adapter boundary for local chat inference.
abstract class LocalAiChatRuntime {
  Future<String> sendMessage({
    required InstalledLocalModel model,
    required String message,
    String? systemPrompt,
    int maxTokens = 4096,
  });

  Stream<String> sendMessageStream({
    required InstalledLocalModel model,
    required String message,
    String? systemPrompt,
    int maxTokens = 4096,
  });

  /// Releases any runtime resources (child processes, sockets, native handles).
  ///
  /// Default is a no-op for runtimes that hold nothing; process-backed runtimes
  /// override this to terminate their server and close clients.
  Future<void> dispose() async {}
}

/// Result of an advisory inference request.
class AdvisorSuggestion {
  final String itemPath;
  final String reason;
  final bool recommended; // true = safe to delete, false = keep

  const AdvisorSuggestion({
    required this.itemPath,
    required this.reason,
    required this.recommended,
  });

  Map<String, dynamic> toJson() => {
        'itemPath': itemPath,
        'reason': reason,
        'recommended': recommended,
      };

  static AdvisorSuggestion fromJson(Map<String, dynamic> json) =>
      AdvisorSuggestion(
        itemPath: json['itemPath'] as String,
        reason: json['reason'] as String,
        recommended: json['recommended'] as bool,
      );
}

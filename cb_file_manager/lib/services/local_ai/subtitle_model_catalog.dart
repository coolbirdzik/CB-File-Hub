import '../../models/local_ai/local_ai_advisor_model.dart';

/// Speed/accuracy position of a subtitle model within its purpose.
enum SubtitleModelTier { fast, balanced, accurate }

/// Subtitle-specific facts that the shared [HuggingFaceModelEntry] lacks.
class SubtitleModelProfile {
  final SubtitleModelTier tier;
  final bool recommended;

  /// Whisper v3 models have a Cantonese (`yue`) token; v1/v2-era ones do not.
  final bool cantonese;

  /// Set for speech models fine-tuned on a single audio language. Auto
  /// detection is then hidden and the source resolves to this code.
  final String? onlyLanguage;

  const SubtitleModelProfile(
    this.tier, {
    this.recommended = false,
    this.cantonese = false,
    this.onlyLanguage,
  });
}

/// Desktop artifacts verified against the publishers' HF LFS metadata.
/// IDs identify an artifact, since several weights share a repository. Never
/// rename an existing ID: installed models and preferences refer to it.
///
/// Speech models run on the bundled whisper.cpp (ggml `.bin`); translation
/// models run on the bundled llama-server (GGUF). Translation IDs must keep a
/// last path segment starting with `hy-mt` so `LlamaCppChatClient` applies
/// deterministic translation sampling.
abstract final class SubtitleModelCatalog {
  static const _whisperRepo = 'ggerganov/whisper.cpp';

  static const entries = <HuggingFaceModelEntry>[
    // Speech recognition, ordered fastest → most accurate.
    HuggingFaceModelEntry(
      id: 'whisper/tiny',
      repositoryId: _whisperRepo,
      displayName: 'Whisper Tiny',
      purpose: LocalModelPurpose.speech,
      description: '99 languages · fastest, for weak CPUs; frequent mistakes.',
      artifactFileName: 'ggml-tiny.bin',
      sizeBytes: 77691713,
      license: 'MIT',
      sha256:
          'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21',
    ),
    HuggingFaceModelEntry(
      id: 'whisper/base',
      repositoryId: _whisperRepo,
      displayName: 'Whisper Base',
      purpose: LocalModelPurpose.speech,
      description: '99 languages · lightweight; lower accuracy.',
      artifactFileName: 'ggml-base.bin',
      sizeBytes: 147951465,
      license: 'MIT',
      sha256:
          '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe',
    ),
    HuggingFaceModelEntry(
      id: 'whisper/small',
      repositoryId: _whisperRepo,
      displayName: 'Whisper Small',
      purpose: LocalModelPurpose.speech,
      description: '99 languages · balanced speed and accuracy on CPU.',
      artifactFileName: 'ggml-small.bin',
      sizeBytes: 487601967,
      license: 'MIT',
      sha256:
          '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b',
    ),
    HuggingFaceModelEntry(
      id: 'whisper/large-v3-turbo-q5_0',
      repositoryId: _whisperRepo,
      displayName: 'Whisper Large v3 Turbo · Q5_0',
      purpose: LocalModelPurpose.speech,
      description:
          '100 languages · near Turbo accuracy at a third of the download.',
      artifactFileName: 'ggml-large-v3-turbo-q5_0.bin',
      sizeBytes: 574041195,
      license: 'MIT',
      sha256:
          '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2',
    ),
    HuggingFaceModelEntry(
      id: 'whisper/large-v3-turbo',
      repositoryId: _whisperRepo,
      displayName: 'Whisper Large v3 Turbo',
      purpose: LocalModelPurpose.speech,
      description:
          '100 languages · full-precision Turbo; faster hardware recommended.',
      artifactFileName: 'ggml-large-v3-turbo.bin',
      sizeBytes: 1624555275,
      license: 'MIT',
      sha256:
          '1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69',
    ),
    HuggingFaceModelEntry(
      id: 'whisper/large-v3-q5_0',
      repositoryId: _whisperRepo,
      displayName: 'Whisper Large v3 · Q5_0',
      purpose: LocalModelPurpose.speech,
      description:
          '100 languages · most accurate Whisper, slowest; faster hardware recommended.',
      artifactFileName: 'ggml-large-v3-q5_0.bin',
      sizeBytes: 1081140203,
      license: 'MIT',
      sha256:
          'd75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1',
    ),
    HuggingFaceModelEntry(
      id: 'whisper/kotoba-v2.0-q5_0',
      repositoryId: 'kotoba-tech/kotoba-whisper-v2.0-ggml',
      displayName: 'Kotoba Whisper v2.0 · Q5_0',
      purpose: LocalModelPurpose.speech,
      description:
          'Japanese audio only · distilled from Large v3 for Japanese; fast.',
      artifactFileName: 'ggml-kotoba-whisper-v2.0-q5_0.bin',
      sizeBytes: 537819875,
      license: 'Apache 2.0',
      sha256:
          '4a3b92192b5d3578ff854a5876213e2e27af0c2d357492c2d14271e82c303658',
    ),

    // Subtitle translation (Hy-MT2: 33 languages, Apache 2.0).
    HuggingFaceModelEntry(
      id: 'tencent/Hy-MT2-1.8B-GGUF',
      displayName: 'Hy-MT2 1.8B · Q4_K_M',
      purpose: LocalModelPurpose.translation,
      description: '33 languages · translation model; fast on CPU.',
      artifactFileName: 'Hy-MT2-1.8B-Q4_K_M.gguf',
      sizeBytes: 1133080448,
      license: 'Apache 2.0',
      sha256:
          'dc5f44fcf1fa496ee7ad725982c0c8c553a4de00259b53af84c4b89fb0c06699',
    ),
    HuggingFaceModelEntry(
      id: 'tencent/Hy-MT2-1.8B-GGUF-Q8_0',
      repositoryId: 'tencent/Hy-MT2-1.8B-GGUF',
      displayName: 'Hy-MT2 1.8B · Q8_0',
      purpose: LocalModelPurpose.translation,
      description: '33 languages · near-lossless 1.8B; slightly slower.',
      artifactFileName: 'Hy-MT2-1.8B-Q8_0.gguf',
      sizeBytes: 1908528192,
      license: 'Apache 2.0',
      sha256:
          '5c3fe0b1408a5ceb0143184ef247b11b579c525f4b02b060e6c851bb76fef1a4',
    ),
    HuggingFaceModelEntry(
      id: 'tencent/Hy-MT2-7B-GGUF',
      displayName: 'Hy-MT2 7B · Q4_K_M',
      purpose: LocalModelPurpose.translation,
      description:
          '33 languages · best translation quality, slowest; faster hardware recommended.',
      artifactFileName: 'Hy-MT2-7B-Q4_K_M.gguf',
      sizeBytes: 4624648896,
      license: 'Apache 2.0',
      sha256:
          '9f96256500f3fc1ab4d64336b58f52a949a95ad7516b0c229476eef782f9f77b',
    ),
  ];

  static const profiles = <String, SubtitleModelProfile>{
    'whisper/tiny': SubtitleModelProfile(SubtitleModelTier.fast),
    'whisper/base': SubtitleModelProfile(SubtitleModelTier.fast),
    'whisper/small': SubtitleModelProfile(SubtitleModelTier.balanced),
    'whisper/large-v3-turbo-q5_0': SubtitleModelProfile(
      SubtitleModelTier.balanced,
      recommended: true,
      cantonese: true,
    ),
    'whisper/large-v3-turbo': SubtitleModelProfile(
      SubtitleModelTier.accurate,
      cantonese: true,
    ),
    'whisper/large-v3-q5_0': SubtitleModelProfile(
      SubtitleModelTier.accurate,
      cantonese: true,
    ),
    'whisper/kotoba-v2.0-q5_0': SubtitleModelProfile(
      SubtitleModelTier.balanced,
      onlyLanguage: 'ja',
    ),
    'tencent/Hy-MT2-1.8B-GGUF': SubtitleModelProfile(
      SubtitleModelTier.fast,
      recommended: true,
    ),
    'tencent/Hy-MT2-1.8B-GGUF-Q8_0': SubtitleModelProfile(
      SubtitleModelTier.balanced,
    ),
    'tencent/Hy-MT2-7B-GGUF': SubtitleModelProfile(SubtitleModelTier.accurate),
  };

  static List<HuggingFaceModelEntry> forPurpose(LocalModelPurpose purpose) =>
      entries.where((e) => e.purpose == purpose).toList();
}

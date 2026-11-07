import '../../models/local_ai/local_ai_advisor_model.dart';

/// Desktop artifacts verified against the publishers' HF LFS metadata.
/// IDs identify an artifact, since several Whisper weights share a repository.
abstract final class SubtitleModelCatalog {
  static const entries = <HuggingFaceModelEntry>[
    HuggingFaceModelEntry(
      id: 'whisper/base',
      repositoryId: 'ggerganov/whisper.cpp',
      displayName: 'Whisper Base',
      purpose: LocalModelPurpose.speech,
      description:
          '147 MB · 99 audio languages including Japanese · lightweight; lower accuracy.',
      artifactFileName: 'ggml-base.bin',
      sizeBytes: 147951465,
      license: 'MIT',
      sha256:
          '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe',
    ),
    HuggingFaceModelEntry(
      id: 'whisper/small',
      repositoryId: 'ggerganov/whisper.cpp',
      displayName: 'Whisper Small',
      purpose: LocalModelPurpose.speech,
      description:
          '488 MB · 99 audio languages including Japanese · balanced speed and accuracy.',
      artifactFileName: 'ggml-small.bin',
      sizeBytes: 487601967,
      license: 'MIT',
      sha256:
          '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b',
    ),
    HuggingFaceModelEntry(
      id: 'whisper/large-v3-turbo',
      repositoryId: 'ggerganov/whisper.cpp',
      displayName: 'Whisper Large v3 Turbo',
      purpose: LocalModelPurpose.speech,
      description:
          '1.62 GB · 100 audio languages including Japanese · higher accuracy; faster hardware recommended.',
      artifactFileName: 'ggml-large-v3-turbo.bin',
      sizeBytes: 1624555275,
      license: 'MIT',
      sha256:
          '1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69',
    ),
    HuggingFaceModelEntry(
      id: 'tencent/Hy-MT2-1.8B-GGUF',
      displayName: 'Hy-MT2 1.8B · Q4_K_M',
      purpose: LocalModelPurpose.translation,
      description:
          '1.13 GB · subtitle translation, including Japanese, Vietnamese, English, Chinese and Turkish.',
      artifactFileName: 'Hy-MT2-1.8B-Q4_K_M.gguf',
      sizeBytes: 1133080448,
      license: 'Apache 2.0',
      sha256:
          'dc5f44fcf1fa496ee7ad725982c0c8c553a4de00259b53af84c4b89fb0c06699',
    ),
  ];
}

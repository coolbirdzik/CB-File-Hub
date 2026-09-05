/// Enums and models shared by the video player and related components.
library;

enum LoopMode { none, single, all }

enum VideoFilter { none, brightness, contrast, saturation }

/// Subtitle track model
class SubtitleTrack {
  final int id;
  final String language;
  final String? title;
  final bool isEnabled;

  const SubtitleTrack({
    required this.id,
    required this.language,
    this.title,
    this.isEnabled = false,
  });
}

/// Audio track model
class AudioTrack {
  final int id;
  final String language;
  final String? title;
  final bool isEnabled;

  const AudioTrack({
    required this.id,
    required this.language,
    this.title,
    this.isEnabled = false,
  });
}

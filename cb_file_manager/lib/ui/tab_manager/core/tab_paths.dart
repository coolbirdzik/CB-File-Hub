const String kDrivesPath = '#drives';
const String kSettingsPath = '#settings';
const String kAiChatPath = '#ai-chat';
const String kCbAgentCleanerPath = '#cb-agent-cleaner';
const String kBackupSyncPath = '#backup-sync';

bool isDrivesPath(String path) => path == kDrivesPath;
bool isSettingsPath(String path) => path == kSettingsPath;
bool isAiChatPath(String path) => path.startsWith(kAiChatPath);
bool isCbAgentCleanerPath(String path) => path == kCbAgentCleanerPath;
bool isBackupSyncPath(String path) => path == kBackupSyncPath;

/// Durable device-album locations. Album IDs are opaque OS identifiers and
/// must be query encoded (iOS IDs can contain slashes, spaces and percent signs).
class DeviceMediaPath {
  const DeviceMediaPath({required this.isVideo, this.albumId});

  final bool isVideo;
  final String? albumId;

  String get parentPath => isVideo ? '#video' : '#gallery';
  String get path {
    final base = '$parentPath/device';
    return albumId == null
        ? base
        : '$base?${Uri(queryParameters: {'album': albumId!}).query}';
  }

  static DeviceMediaPath? tryParse(String path) {
    final queryIndex = path.indexOf('?');
    final base = queryIndex < 0 ? path : path.substring(0, queryIndex);
    if (base != '#gallery/device' && base != '#video/device') return null;
    try {
      final parameters = queryIndex < 0
          ? <String, String>{}
          : Uri.splitQueryString(path.substring(queryIndex + 1));
      final album = parameters['album'];
      if (album != null && album.isEmpty) return null;
      return DeviceMediaPath(isVideo: base == '#video/device', albumId: album);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}

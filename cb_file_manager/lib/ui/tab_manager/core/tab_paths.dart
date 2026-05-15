const String kDrivesPath = '#drives';
const String kSettingsPath = '#settings';
const String kAiChatPath = '#ai-chat';

bool isDrivesPath(String path) => path == kDrivesPath;
bool isSettingsPath(String path) => path == kSettingsPath;
bool isAiChatPath(String path) => path.startsWith(kAiChatPath);

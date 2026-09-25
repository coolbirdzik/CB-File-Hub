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

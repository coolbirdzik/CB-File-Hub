import 'dart:ui' show Locale;

// Debug log allowlist — only messages containing these tokens are printed.
const List<String> debugLogAllowList = <String>[
  'VideoPlayer',
  'VLC',
  'TAG_RENAME',
  'SEED_DIRECT',
  '[DevTools]',
  '[TagManager]',
  '[SQLite]',
];

// Patterns to suppress (Flutter engine / Windows AXTree noise).
const List<String> debugLogSuppressList = <String>[
  'accessibility_bridge.cc',
  'Failed to update ui::AXTree',
  'Nodes left pending',
];

/// Checks if a log line should be printed based on allow/suppress lists.
bool shouldAllowLog(String message) {
  for (final token in debugLogSuppressList) {
    if (message.contains(token)) return false;
  }
  for (final token in debugLogAllowList) {
    if (message.contains(token)) return true;
  }
  return false;
}

// ─── App metadata ────────────────────────────────────────────────────────────

const String appTitle = 'CB File Hub';

// ─── Image cache limits ──────────────────────────────────────────────────────

const int imageCacheMaximumSize = 200;
const int imageCacheMaximumSizeBytes = 100 * 1024 * 1024; // ~100 MB

// ─── Window defaults ─────────────────────────────────────────────────────────

const double windowMinimumWidth = 800;
const double windowMinimumHeight = 600;

// ─── Acrylic reapply burst delays (milliseconds) ─────────────────────────────

const List<int> acrylicBurstDelaysMs = [0, 80, 180, 320, 560];
const Duration acrylicBurstDelayStep = Duration(milliseconds: 120);

// ─── Skia resource cache ─────────────────────────────────────────────────────

const int skiaResourceCacheMaxBytes = 512 * 1024 * 1024; // 512 MB

// ─── Supported locales ───────────────────────────────────────────────────────

const List<Locale> supportedLocales = <Locale>[
  Locale('vi', ''),
  Locale('en', ''),
];

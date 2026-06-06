import 'dart:io';

import 'cleaner_categories.dart';
import 'cleaner_models.dart';
import 'windows_known_folders.dart';

/// Defense-in-depth path safety checker.
///
/// The AI agent passes [JunkItem] paths into `clean_disk_junk`. Even if the
/// LLM hallucinates or a previous scan was tampered with, every path is
/// re-validated here right before deletion. Anything that does not fall
/// under a known-junk prefix or that lives in a protected location is
/// rejected and logged to `CleanReport.skippedUnsafe`.
class CleanerPathSafety {
  CleanerPathSafety._();

  /// Lazily-resolved set of absolute prefixes derived from
  /// [CleanerCategories.all]. A path is allowed only if it starts with one of
  /// these prefixes.
  static List<String>? _allowedPrefixesCache;

  /// Lazily-resolved set of paths that must NEVER be deleted, regardless of
  /// the category they came from. Uppercased for case-insensitive compare.
  static final List<String> _denyPrefixesUpper = _buildDenyPrefixes();

  /// Re-computes the allowed-prefix list. Tests can call this after stubbing
  /// `Platform.environment` (via a process wrapper) to refresh the cache.
  static void resetCacheForTest() {
    _allowedPrefixesCache = null;
  }

  /// Returns true when [absolutePath] is safe to delete as part of a junk
  /// cleaning operation on Windows.
  ///
  /// `recycleBinItem == true` short-circuits the prefix check because Recycle
  /// Bin items live under `$RECYCLE.BIN` on each drive and are removed via
  /// the system Recycle Bin API, not direct filesystem ops.
  static bool isPathSafeToDelete(
    String absolutePath, {
    bool recycleBinItem = false,
  }) {
    if (!Platform.isWindows) return false;
    if (absolutePath.isEmpty) return false;

    // Reject path traversal attempts and relative paths outright.
    if (absolutePath.contains('..')) return false;
    if (!_isAbsoluteWindowsPath(absolutePath)) return false;

    final upper = absolutePath.toUpperCase();

    // Reject anything containing wildcards or shell metacharacters that may
    // have leaked through tool argument parsing.
    if (upper.contains('*') || upper.contains('?')) return false;

    // Hard deny list — never touched, even if a category misconfigured a rule.
    for (final deny in _denyPrefixesUpper) {
      if (upper == deny || upper.startsWith('$deny\\')) {
        return false;
      }
    }

    // Recycle Bin items don't have to match a known prefix; they are routed
    // through the Bin API.
    if (recycleBinItem) return true;

    final prefixes = _allowedPrefixes();
    for (final prefix in prefixes) {
      final p = prefix.toUpperCase();
      if (upper == p || upper.startsWith('$p\\')) {
        return true;
      }
    }

    return false;
  }

  /// Resolved prefixes from all category rules. Cached after first call.
  static List<String> _allowedPrefixes() {
    final cached = _allowedPrefixesCache;
    if (cached != null) return cached;

    final prefixes = <String>{};
    for (final category in CleanerCategories.all()) {
      for (final rule in category.rules) {
        if (rule.source.kind == PathSourceKind.recycleBin) continue;
        final resolved = WindowsKnownFolders.resolve(rule.source);
        if (resolved == null || resolved.isEmpty) continue;
        prefixes.add(resolved);
      }
    }

    final result = prefixes.toList(growable: false);
    _allowedPrefixesCache = result;
    return result;
  }

  /// Builds the hard deny list. Always uppercased.
  static List<String> _buildDenyPrefixes() {
    final env = Platform.environment;
    final raw = <String>[
      r'C:\Windows\System32',
      r'C:\Windows\SysWOW64',
      r'C:\Windows\WinSxS',
      r'C:\Windows\Boot',
      r'C:\Windows\Fonts',
      r'C:\Program Files',
      r'C:\Program Files (x86)',
      r'C:\ProgramData\Microsoft\Crypto',
    ];

    void addUserDir(String envVar, String relative) {
      final base = env[envVar];
      if (base == null || base.isEmpty) return;
      raw.add('$base\\$relative');
    }

    addUserDir('USERPROFILE', 'Documents');
    addUserDir('USERPROFILE', 'Desktop');
    addUserDir('USERPROFILE', 'Pictures');
    addUserDir('USERPROFILE', 'Music');
    addUserDir('USERPROFILE', 'Videos');
    addUserDir('USERPROFILE', 'Downloads');
    addUserDir('USERPROFILE', 'OneDrive');

    return raw.map((e) => e.toUpperCase()).toList(growable: false);
  }

  static bool _isAbsoluteWindowsPath(String path) {
    if (path.length < 3) return false;
    final first = path.codeUnitAt(0);
    final isLetter =
        (first >= 0x41 && first <= 0x5A) || (first >= 0x61 && first <= 0x7A);
    return isLetter && path[1] == ':' && (path[2] == r'\' || path[2] == '/');
  }
}

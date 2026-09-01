/// Data models for the Disk Cleaner skill.
///
/// All types here are platform-agnostic and contain no Flutter, BLoC, or LLM
/// dependencies, so they are safe to ship into an isolate.

import '../app_insights/app_insights_models.dart';

/// Safety level for a [CleanerCategory].
///
/// - [safe] — almost certainly junk; can be deleted without thinking.
///   The corresponding files are temp / cache that the OS or apps will
///   re-create on demand.
/// - [careful] — usually junk but cleaning may have side effects (e.g.
///   re-downloading Windows Update payloads).
/// - [risky] — only delete if the user explicitly opted in (e.g. dev caches
///   that take a long time to repopulate).
enum CleanerSafety { safe, careful, risky }

/// Where a [CleanerPathRule] resolves its base directory from.
enum PathSourceKind {
  /// An environment variable (`%TEMP%`, `%LOCALAPPDATA%`, ...). Combined with
  /// [PathSource.relative] to produce an absolute path.
  env,

  /// An absolute filesystem path that does NOT depend on the current user
  /// (e.g. `C:\Windows\Prefetch`).
  absolute,

  /// All `$RECYCLE.BIN` folders on every fixed drive. Items are enumerated
  /// via the system Recycle Bin API rather than direct filesystem access.
  recycleBin,
}

/// Describes how to resolve the base directory of a [CleanerPathRule].
class PathSource {
  final PathSourceKind kind;

  /// Environment variable name (without `%`) when [kind] is
  /// [PathSourceKind.env]. Otherwise unused.
  final String? envVar;

  /// Sub-path relative to the resolved base. May be empty for the base itself.
  /// Uses `/` as separator; resolved code converts to native separator.
  final String relative;

  /// Absolute path when [kind] is [PathSourceKind.absolute]. Otherwise unused.
  final String? absolutePath;

  const PathSource._({
    required this.kind,
    this.envVar,
    this.relative = '',
    this.absolutePath,
  });

  /// `%envVar%/relative`
  const PathSource.env(String envVar, [String relative = ''])
      : this._(
          kind: PathSourceKind.env,
          envVar: envVar,
          relative: relative,
        );

  /// Absolute path that does not depend on the user.
  const PathSource.absolute(String path)
      : this._(
          kind: PathSourceKind.absolute,
          absolutePath: path,
        );

  /// Recycle Bin on every fixed drive.
  const PathSource.recycleBin() : this._(kind: PathSourceKind.recycleBin);

  @override
  String toString() {
    switch (kind) {
      case PathSourceKind.env:
        return relative.isEmpty ? '%$envVar%' : '%$envVar%\\$relative';
      case PathSourceKind.absolute:
        return absolutePath ?? '<absolute>';
      case PathSourceKind.recycleBin:
        return '<RecycleBin>';
    }
  }
}

/// A single rule describing a directory tree to scan and how to filter it.
class CleanerPathRule {
  final PathSource source;

  /// Glob-style filename patterns (case-insensitive). If null, all files
  /// match. Matched against the file basename only.
  final List<String>? includeGlobs;

  /// Glob-style filename patterns (case-insensitive). If null, no files are
  /// excluded. Matched against the file basename only.
  final List<String>? excludeGlobs;

  /// Skip files modified more recently than `now - minAge`. Useful for
  /// "logs older than 7 days".
  final Duration? minAge;

  /// When true, only delete files inside the rule's directory but keep the
  /// directory itself. Default; the cleaner never deletes top-level rule
  /// directories.
  final bool emptyOnly;

  /// When true, recurse into subdirectories. Default true.
  final bool recursive;

  /// Stable names, executable names, or package identifiers that can be used
  /// to associate this rule with exactly one installed application.
  ///
  /// Hints are deliberately optional. A rule without an unambiguous owner is
  /// still valid Cleaner data, but App Insights must not attribute it to an
  /// application or offer it from that application's cleanup review.
  final List<String> appOwnerHints;

  /// How App Insights should describe storage matched by this rule.
  final AppStorageKind? storageKind;

  const CleanerPathRule({
    required this.source,
    this.includeGlobs,
    this.excludeGlobs,
    this.minAge,
    this.emptyOnly = true,
    this.recursive = true,
    this.appOwnerHints = const <String>[],
    this.storageKind,
  });
}

/// A logical grouping of junk-file rules surfaced to the user.
class CleanerCategory {
  /// Stable machine ID used by AI tools and storage. Snake_case.
  final String id;

  /// Short human-readable name. English by default; UI may show a localised
  /// label by mapping [id] to the localisation file.
  final String displayName;

  /// One-line description shown to the user under the category title.
  final String description;

  final CleanerSafety safety;

  final List<CleanerPathRule> rules;

  /// Whether this category should be pre-checked when the cleaner UI opens
  /// for the first time, and what `scan_disk_junk` defaults to when no
  /// `categories` argument is supplied.
  final bool defaultEnabled;

  /// Some categories (e.g. `prefetch`) need administrator privileges to
  /// delete. The scanner reports this in `warnings` if it fails to read.
  final bool requiresAdmin;

  const CleanerCategory({
    required this.id,
    required this.displayName,
    required this.description,
    required this.safety,
    required this.rules,
    this.defaultEnabled = false,
    this.requiresAdmin = false,
  });
}

/// A single file or directory found by the scanner.
class JunkItem {
  final String path;
  final int sizeBytes;
  final DateTime? lastModified;
  final String categoryId;

  /// True if [path] is a directory whose contents should be deleted, while
  /// the directory itself is preserved (set by [CleanerPathRule.emptyOnly]).
  final bool isContainerOnly;

  /// True if [path] is a Recycle Bin entry that must be removed via the
  /// Recycle Bin API, not direct file ops.
  final bool isRecycleBinItem;

  /// For Recycle Bin items, the original location reported by the Bin
  /// (display only).
  final String? originalPath;

  /// True when the item came from an explicit user selection in the disk tree,
  /// not from a predefined cleaner rule. This allows the cleaner UI to delete
  /// arbitrary user-selected paths while keeping rule/AI cleanup on the
  /// stricter junk-prefix allowlist.
  final bool isUserSelected;

  const JunkItem({
    required this.path,
    required this.sizeBytes,
    required this.categoryId,
    this.lastModified,
    this.isContainerOnly = false,
    this.isRecycleBinItem = false,
    this.originalPath,
    this.isUserSelected = false,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'sizeBytes': sizeBytes,
        'lastModified': lastModified?.millisecondsSinceEpoch,
        'categoryId': categoryId,
        'isContainerOnly': isContainerOnly,
        'isRecycleBinItem': isRecycleBinItem,
        'originalPath': originalPath,
        'isUserSelected': isUserSelected,
      };

  static JunkItem fromJson(Map<String, dynamic> json) => JunkItem(
        path: json['path'] as String,
        sizeBytes: json['sizeBytes'] as int,
        lastModified: json['lastModified'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['lastModified'] as int)
            : null,
        categoryId: json['categoryId'] as String,
        isContainerOnly: json['isContainerOnly'] as bool? ?? false,
        isRecycleBinItem: json['isRecycleBinItem'] as bool? ?? false,
        originalPath: json['originalPath'] as String?,
        isUserSelected: json['isUserSelected'] as bool? ?? false,
      );
}

/// Free / total / used info for a single drive.
class DriveSpace {
  final String path; // e.g. 'C:\\'
  final String label; // e.g. 'OS' or 'Local Disk'
  final int totalBytes;
  final int freeBytes;
  final bool requiresAdmin;

  const DriveSpace({
    required this.path,
    required this.label,
    required this.totalBytes,
    required this.freeBytes,
    this.requiresAdmin = false,
  });

  int get usedBytes => totalBytes >= freeBytes ? totalBytes - freeBytes : 0;
}

/// Aggregated result of [DiskCleanerService.scanJunk].
class ScanReport {
  final List<String> drivesScanned;
  final Map<String, List<JunkItem>> itemsByCategory;
  final List<String> warnings;
  final DateTime scannedAt;

  const ScanReport({
    required this.drivesScanned,
    required this.itemsByCategory,
    required this.warnings,
    required this.scannedAt,
  });

  int get totalCount =>
      itemsByCategory.values.fold(0, (sum, list) => sum + list.length);

  int get totalBytes => itemsByCategory.values
      .fold(0, (sum, list) => sum + list.fold(0, (s, i) => s + i.sizeBytes));

  /// Flat list of all items across all categories.
  List<JunkItem> get allItems => [
        for (final list in itemsByCategory.values) ...list,
      ];
}

/// Streamed progress event from the isolate scanner.
class ScanProgress {
  /// Path currently being scanned (last seen). Empty for "starting" pings.
  final String currentPath;

  /// Number of items found so far.
  final int itemsFound;

  /// Total size found so far.
  final int bytesFound;

  /// Category being scanned right now.
  final String categoryId;

  const ScanProgress({
    required this.currentPath,
    required this.itemsFound,
    required this.bytesFound,
    required this.categoryId,
  });
}

/// Result of [DiskCleanerService.cleanJunk].
class CleanReport {
  final int freedBytes;
  final List<String> succeeded;
  final Map<String, String> failed;
  final List<String> skippedUnsafe;
  final List<String> skippedInUse;
  final List<String> skippedByUser;
  final bool wasPermanent;

  const CleanReport({
    required this.freedBytes,
    required this.succeeded,
    required this.failed,
    required this.skippedUnsafe,
    required this.skippedInUse,
    this.skippedByUser = const [],
    required this.wasPermanent,
  });

  int get successCount => succeeded.length;
  int get failureCount => failed.length;
  int get skippedInUseCount => skippedInUse.length;
  int get skippedByUserCount => skippedByUser.length;
}

enum CleanFailureAction { skip, skipAll, retry }

class CleanFailureDetails {
  final JunkItem item;
  final String reason;
  final bool isInUse;
  final String? blockedPath;
  final bool permanent;

  const CleanFailureDetails({
    required this.item,
    required this.reason,
    required this.isInUse,
    required this.blockedPath,
    required this.permanent,
  });
}

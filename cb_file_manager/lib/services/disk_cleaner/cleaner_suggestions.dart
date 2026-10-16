import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'cleaner_categories.dart';
import 'cleaner_models.dart';
import 'cleaner_space_insights.dart';
import 'disk_tree_node.dart';

/// How a suggestion can be acted on from the Cleanup suggestions view.
enum CleanerSuggestionTier {
  /// Rule-backed junk the OS or apps recreate. Checked by default.
  clean,

  /// Removable, but the user must recognise each item first. Never checked
  /// by default, and items are only deleted when the user checks them.
  review,

  /// Not deletable from here. Windows or the owning app has a safer way to
  /// reclaim the space (powercfg, Storage settings, a launcher...).
  guided,
}

enum CleanerSuggestionStep { junk, downloads, system, diskScan }

/// One recommendation shown in the Cleanup suggestions view.
///
/// UI text is localised from [id] / [categoryId]; this model carries only
/// data so it can be produced and tested without Flutter.
class CleanerSuggestion {
  /// `junk:<category>`, `downloads_leftovers`, `old_large_files`,
  /// `node_modules`, or a [CleanerSpaceCause.id] for guided causes.
  final String id;
  final CleanerSuggestionTier tier;
  final int sizeBytes;

  /// Deletable targets. Empty for guided suggestions.
  final List<JunkItem> items;
  final bool selectedByDefault;

  /// Set for `junk:` suggestions.
  final String? categoryId;

  /// Folder to open for a closer look.
  final String? folderPath;

  /// Command the user can copy and run (guided suggestions).
  final String? command;

  /// A `ms-settings:` page that reclaims the space (guided suggestions).
  final String? settingsUri;

  /// Size is a lower bound because some content could not be read.
  final bool sizeIsPartial;

  bool get isRecycleBin => categoryId == 'recycle_bin';

  CleanerSuggestion withItems(List<JunkItem> remaining) => CleanerSuggestion(
    id: id,
    tier: tier,
    sizeBytes: remaining.fold(0, (sum, item) => sum + item.sizeBytes),
    items: remaining,
    selectedByDefault: selectedByDefault,
    categoryId: categoryId,
    folderPath: folderPath,
    command: command,
    settingsUri: settingsUri,
    sizeIsPartial: sizeIsPartial,
  );

  const CleanerSuggestion({
    required this.id,
    required this.tier,
    required this.sizeBytes,
    this.items = const [],
    this.selectedByDefault = false,
    this.categoryId,
    this.folderPath,
    this.command,
    this.settingsUri,
    this.sizeIsPartial = false,
  });
}

enum CleanerSuggestionErrorKind {
  /// Another junk scan (Quick clean, CB Agent) was running.
  junkScanBusy,
  junkScanFailed,
  downloadsFailed,
}

class CleanerSuggestionError {
  final CleanerSuggestionErrorKind kind;
  final String detail;

  const CleanerSuggestionError(this.kind, this.detail);
}

class CleanerSuggestionReport {
  final String drivePath;
  final List<CleanerSuggestion> suggestions;
  final bool usedDiskScan;
  final List<String> warnings;

  /// Parts of the scan that failed, so the suggestions may be incomplete.
  final List<CleanerSuggestionError> errors;
  final DateTime scannedAt;

  const CleanerSuggestionReport({
    required this.drivePath,
    required this.suggestions,
    required this.usedDiskScan,
    required this.warnings,
    required this.scannedAt,
    this.errors = const [],
  });

  Iterable<CleanerSuggestion> byTier(CleanerSuggestionTier tier) =>
      suggestions.where((suggestion) => suggestion.tier == tier);

  int get reclaimableBytes => suggestions
      .where((s) => s.tier != CleanerSuggestionTier.guided)
      .fold(0, (sum, s) => sum + s.sizeBytes);
}

typedef JunkScanFunction =
    Future<ScanReport> Function(
      List<String> drivePaths,
      List<String> ids,
      void Function(ScanProgress progress) onProgress,
    );

/// Source keys in [CleanerSuggestionProgress] besides junk category ids.
abstract final class CleanerSuggestionSource {
  static const downloads = 'downloads';
  static const system = 'system';
  static const diskScan = 'disk_scan';
}

/// Live state of a suggestions scan, for drawing real progress.
class CleanerSuggestionProgress {
  final CleanerSuggestionStep step;

  /// Every source this scan checks, in display order: junk category ids,
  /// then the [CleanerSuggestionSource] keys that apply to this drive.
  final List<String> sources;

  /// Source being read right now.
  final String? activeSource;
  final Set<String> doneSources;

  /// Bytes found so far per source. Junk values are live estimates until
  /// the junk scan finishes, then exact.
  final Map<String, int> sourceBytes;
  final int itemsFound;

  /// Overall completion, 0..1, from real work counters.
  final double fraction;
  final String currentPath;

  const CleanerSuggestionProgress({
    required this.step,
    required this.sources,
    required this.activeSource,
    required this.doneSources,
    required this.sourceBytes,
    required this.itemsFound,
    required this.fraction,
    required this.currentPath,
  });

  int get bytesFound => sourceBytes.values.fold(0, (sum, b) => sum + b);
}

class _ProgressTracker {
  final void Function(CleanerSuggestionProgress)? listener;
  final List<String> sources;
  final Map<String, double> weights;
  final Map<String, int> bytes = {};
  final Set<String> done = {};
  final Map<String, double> phase = {};
  CleanerSuggestionStep step = CleanerSuggestionStep.junk;
  String? active;
  String path = '';
  int items = 0;

  _ProgressTracker(this.listener, this.sources, this.weights);

  void emit() {
    final listener = this.listener;
    if (listener == null) return;
    var fraction = 0.0;
    phase.forEach((key, value) => fraction += (weights[key] ?? 0) * value);
    listener(
      CleanerSuggestionProgress(
        step: step,
        sources: sources,
        activeSource: active,
        doneSources: Set.unmodifiable(done),
        sourceBytes: Map.unmodifiable(bytes),
        itemsFound: items,
        fraction: fraction.clamp(0.0, 1.0),
        currentPath: path,
      ),
    );
  }
}

/// Builds cleanup suggestions for one drive from three sources:
/// the rule-based junk scan, quick targeted checks (Downloads, hibernation
/// file, previous Windows installation), and, when the user already ran a
/// Disk usage scan of the same drive, its tree and old-large evidence.
class CleanerSuggestionScanner {
  final JunkScanFunction scanJunk;
  final Map<String, String> environment;
  final DateTime Function() now;

  /// Downloads files older than this are suggested for review.
  static const downloadsMinAge = Duration(days: 30);
  static const downloadsMinBytes = 5 * 1024 * 1024;
  static const _maxItemsPerSuggestion = 200;

  static const downloadsExtensions = {
    'EXE',
    'MSI',
    'MSIX',
    'MSIXBUNDLE',
    'APPX',
    'APPXBUNDLE',
    'ISO',
    'IMG',
    'ZIP',
    'RAR',
    '7Z',
    'TAR',
    'GZ',
    'TGZ',
    'XZ',
    'BZ2',
    'CAB',
    'APK',
  };

  /// Space causes the view explains with a Windows or app action.
  static const guidedCauseIds = {
    'previous_windows',
    'wsl_disk',
    'docker_data',
    'virtual_machine_disk',
    'game_library',
    'phone_backup',
    'android_dev',
    'ai_models',
  };

  CleanerSuggestionScanner({
    required this.scanJunk,
    Map<String, String>? environment,
    DateTime Function()? now,
  }) : environment = environment ?? Platform.environment,
       now = now ?? DateTime.now;

  Future<CleanerSuggestionReport> scan({
    required String drivePath,
    DiskTreeNode? diskTree,
    List<FullDiskScanInsight> oldLargeItems = const [],
    void Function(CleanerSuggestionProgress progress)? onProgress,
  }) async {
    final drive = _driveLetter(drivePath);
    final suggestions = <CleanerSuggestion>[];
    final warnings = <String>[];
    final errors = <CleanerSuggestionError>[];
    final tree = diskTree != null && _driveLetter(diskTree.fullPath) == drive
        ? diskTree
        : null;
    final profile = environment['USERPROFILE'];
    final checkDownloads = profile != null && _driveLetter(profile) == drive;
    final categoryIds = CleanerCategories.all().map((c) => c.id).toList();

    // Weights reflect how long each phase usually takes.
    final tracker = _ProgressTracker(
      onProgress,
      [
        ...categoryIds,
        if (checkDownloads) CleanerSuggestionSource.downloads,
        CleanerSuggestionSource.system,
        if (tree != null) CleanerSuggestionSource.diskScan,
      ],
      _normalized({
        'junk': 0.7,
        if (checkDownloads) CleanerSuggestionSource.downloads: 0.15,
        CleanerSuggestionSource.system: tree == null ? 0.15 : 0.05,
        if (tree != null) CleanerSuggestionSource.diskScan: 0.05,
      }),
    );

    void finish(String source, Iterable<CleanerSuggestion> found) {
      tracker.bytes[source] = found.fold(0, (sum, s) => sum + s.sizeBytes);
      tracker.items += found.fold(0, (sum, s) => sum + s.items.length);
      tracker.done.add(source);
      tracker.phase[source] = 1;
      tracker.emit();
    }

    tracker.emit();
    var lastBytes = 0;
    try {
      final report = await scanJunk(['$drive\\'], categoryIds, (progress) {
        // Bytes between two reports are credited to the category of the
        // later one; exact per-category totals replace this at the end.
        final delta = progress.bytesFound - lastBytes;
        lastBytes = progress.bytesFound;
        if (progress.categoryId.isNotEmpty) {
          tracker.active = progress.categoryId;
          if (delta > 0) {
            tracker.bytes[progress.categoryId] =
                (tracker.bytes[progress.categoryId] ?? 0) + delta;
          }
        }
        tracker.items = progress.itemsFound;
        if (progress.currentPath.isNotEmpty) {
          tracker.path = progress.currentPath;
        }
        if (progress.fraction case final fraction?) {
          tracker.phase['junk'] = fraction;
        }
        tracker.emit();
      });
      final junk = await _junkSuggestionsInBackground(report);
      suggestions.addAll(junk);
      warnings.addAll(report.warnings);
      tracker.bytes.removeWhere((key, _) => categoryIds.contains(key));
      for (final suggestion in junk) {
        tracker.bytes[suggestion.categoryId!] = suggestion.sizeBytes;
      }
      tracker.items = junk.fold(0, (sum, s) => sum + s.items.length);
    } catch (error) {
      errors.add(
        CleanerSuggestionError(
          error is CleanerScanBusyError
              ? CleanerSuggestionErrorKind.junkScanBusy
              : CleanerSuggestionErrorKind.junkScanFailed,
          '$error',
        ),
      );
    }
    tracker.done.addAll(categoryIds);
    tracker.phase['junk'] = 1;

    if (checkDownloads) {
      final downloads = '$profile\\Downloads';
      tracker
        ..step = CleanerSuggestionStep.downloads
        ..active = CleanerSuggestionSource.downloads
        ..path = downloads
        ..emit();
      final cutoff = now().subtract(downloadsMinAge);
      CleanerSuggestion? found;
      try {
        final files = await Isolate.run(
          () => _listDownloadsLeftovers(downloads, cutoff),
        );
        found = downloadsSuggestion(downloads, files);
        if (found != null) suggestions.add(found);
      } catch (error) {
        errors.add(
          CleanerSuggestionError(
            CleanerSuggestionErrorKind.downloadsFailed,
            '$error',
          ),
        );
      }
      finish(CleanerSuggestionSource.downloads, [?found]);
    }

    tracker
      ..step = CleanerSuggestionStep.system
      ..active = CleanerSuggestionSource.system
      ..path = '$drive\\'
      ..emit();
    final system = <CleanerSuggestion>[];
    final hibernation = await _hibernationSuggestion(drive);
    if (hibernation != null) system.add(hibernation);
    if (tree == null) {
      tracker
        ..path = '$drive\\Windows.old'
        ..emit();
      final previous = await _previousWindowsSuggestion(drive);
      if (previous != null) system.add(previous);
    }
    suggestions.addAll(system);
    finish(CleanerSuggestionSource.system, system);

    if (tree != null) {
      tracker
        ..step = CleanerSuggestionStep.diskScan
        ..active = CleanerSuggestionSource.diskScan
        ..path = tree.fullPath
        ..emit();
      final fromTree = await _diskScanSuggestionsInBackground(
        tree,
        oldLargeItems,
        excludePaths: {
          for (final suggestion in suggestions)
            for (final item in suggestion.items) item.path.toUpperCase(),
        },
      );
      suggestions.addAll(fromTree);
      finish(CleanerSuggestionSource.diskScan, fromTree);
    }

    suggestions.sort(_compare);
    return CleanerSuggestionReport(
      drivePath: '$drive\\',
      suggestions: suggestions,
      usedDiskScan: tree != null,
      warnings: warnings,
      errors: errors,
      scannedAt: now(),
    );
  }

  static Map<String, double> _normalized(Map<String, double> weights) {
    final total = weights.values.fold(0.0, (sum, w) => sum + w);
    return weights.map((key, value) => MapEntry(key, value / total));
  }

  /// One suggestion per junk category that found something.
  static Future<List<CleanerSuggestion>> _junkSuggestionsInBackground(
    ScanReport report,
  ) => Isolate.run(() => junkSuggestions(report));

  static Future<List<CleanerSuggestion>> _diskScanSuggestionsInBackground(
    DiskTreeNode tree,
    List<FullDiskScanInsight> oldLargeItems, {
    required Set<String> excludePaths,
  }) => Isolate.run(
    () => diskScanSuggestions(tree, oldLargeItems, excludePaths: excludePaths),
  );

  static List<CleanerSuggestion> junkSuggestions(ScanReport report) {
    final result = <CleanerSuggestion>[];
    for (final entry in report.itemsByCategory.entries) {
      final items = entry.value.where((item) => item.sizeBytes > 0).toList();
      if (items.isEmpty) continue;
      final category = CleanerCategories.byId(entry.key);
      final safe = category?.safety == CleanerSafety.safe;
      result.add(
        CleanerSuggestion(
          id: 'junk:${entry.key}',
          categoryId: entry.key,
          tier: safe
              ? CleanerSuggestionTier.clean
              : CleanerSuggestionTier.review,
          sizeBytes: items.fold(0, (sum, item) => sum + item.sizeBytes),
          items: items,
          // Emptying the Recycle Bin is permanent, so it is opt-in here.
          selectedByDefault:
              safe &&
              entry.key != 'recycle_bin' &&
              (category?.defaultEnabled ?? false) &&
              !(category?.requiresAdmin ?? true),
        ),
      );
    }
    return result;
  }

  static CleanerSuggestion? downloadsSuggestion(
    String downloadsPath,
    List<JunkItem> files,
  ) {
    if (files.isEmpty) return null;
    files.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    final items = files.take(_maxItemsPerSuggestion).toList();
    return CleanerSuggestion(
      id: 'downloads_leftovers',
      tier: CleanerSuggestionTier.review,
      sizeBytes: items.fold(0, (sum, item) => sum + item.sizeBytes),
      items: items,
      folderPath: downloadsPath,
    );
  }

  /// Review and guided suggestions that need the Disk usage tree.
  ///
  /// [excludePaths] (uppercased) are already offered by another suggestion.
  static List<CleanerSuggestion> diskScanSuggestions(
    DiskTreeNode tree,
    List<FullDiskScanInsight> oldLargeItems, {
    Set<String> excludePaths = const {},
  }) {
    final result = <CleanerSuggestion>[];
    final causes = CleanerSpaceInsights.findCauses(tree);
    for (final match in causes) {
      final cause = match.cause;
      if (cause.id == 'node_modules') {
        final items = match.nodes
            .take(_maxItemsPerSuggestion)
            .map((node) => _userSelected(node.fullPath, node.sizeBytes))
            .toList();
        result.add(
          CleanerSuggestion(
            id: 'node_modules',
            tier: CleanerSuggestionTier.review,
            sizeBytes: items.fold(0, (sum, item) => sum + item.sizeBytes),
            items: items,
          ),
        );
        continue;
      }
      if (!guidedCauseIds.contains(cause.id)) continue;
      // Tiny matches are noise next to the rest of the list.
      if (match.totalBytes < 512 * 1024 * 1024) continue;
      result.add(_guided(cause.id, match.totalBytes, match.nodes.first));
    }

    final oldFiles = <JunkItem>[];
    for (final item in oldLargeItems) {
      if (!item.isFile || excludePaths.contains(item.path.toUpperCase())) {
        continue;
      }
      final upper = CleanerSpaceInsights.normalize(item.path);
      // Only a user's own files. App data, cloud-synced files (deleting them
      // deletes the cloud copy), mail stores and VM disks are excluded.
      if (!RegExp(r'^[A-Z]:\\USERS\\[^\\]+\\').hasMatch(upper) ||
          upper.contains(r'\APPDATA\')) {
        continue;
      }
      final cause = CleanerSpaceInsights.causeWithin(item.path, isFile: true);
      if (cause != null &&
          cause.id != 'downloads' &&
          cause.id != 'personal_files') {
        continue;
      }
      oldFiles.add(_userSelected(item.path, item.sizeBytes, item.lastActivity));
    }
    if (oldFiles.isNotEmpty) {
      oldFiles.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      result.add(
        CleanerSuggestion(
          id: 'old_large_files',
          tier: CleanerSuggestionTier.review,
          sizeBytes: oldFiles.fold(0, (sum, item) => sum + item.sizeBytes),
          items: oldFiles,
        ),
      );
    }
    return result;
  }

  static CleanerSuggestion _guided(
    String causeId,
    int bytes,
    DiskTreeNode largest,
  ) {
    final folder = largest.isFile
        ? largest.fullPath.substring(0, largest.fullPath.lastIndexOf(r'\'))
        : largest.fullPath;
    return CleanerSuggestion(
      id: causeId,
      tier: CleanerSuggestionTier.guided,
      sizeBytes: bytes,
      folderPath: causeId == 'previous_windows' ? null : folder,
      command: switch (causeId) {
        'wsl_disk' => 'wsl --shutdown',
        'docker_data' => 'docker system df',
        _ => null,
      },
      settingsUri: switch (causeId) {
        'previous_windows' => 'ms-settings:storagesense',
        'game_library' => 'ms-settings:appsfeatures',
        _ => null,
      },
    );
  }

  Future<CleanerSuggestion?> _hibernationSuggestion(String drive) async {
    final systemDrive = environment['SystemDrive'] ?? 'C:';
    if (_driveLetter(systemDrive) != drive) return null;
    try {
      final stat = await FileStat.stat('$drive\\hiberfil.sys');
      if (stat.type == FileSystemEntityType.notFound || stat.size <= 0) {
        return null;
      }
      return CleanerSuggestion(
        id: 'hibernation_file',
        tier: CleanerSuggestionTier.guided,
        sizeBytes: stat.size,
        command: 'powercfg /h off',
      );
    } catch (_) {
      return null;
    }
  }

  Future<CleanerSuggestion?> _previousWindowsSuggestion(String drive) async {
    final path = '$drive\\Windows.old';
    if (!await Directory(path).exists()) return null;
    final (bytes, partial) = await Isolate.run(() => _directorySize(path));
    if (bytes <= 0) return null;
    return CleanerSuggestion(
      id: 'previous_windows',
      tier: CleanerSuggestionTier.guided,
      sizeBytes: bytes,
      settingsUri: 'ms-settings:storagesense',
      sizeIsPartial: partial,
    );
  }

  static int _compare(CleanerSuggestion a, CleanerSuggestion b) {
    final tier = a.tier.index.compareTo(b.tier.index);
    return tier != 0 ? tier : b.sizeBytes.compareTo(a.sizeBytes);
  }

  static JunkItem _userSelected(String path, int bytes, [DateTime? modified]) =>
      JunkItem(
        path: path,
        sizeBytes: bytes,
        categoryId: 'user_selected',
        lastModified: modified,
        // Deleted only after the user checks this exact item in the view.
        isUserSelected: true,
      );

  static String _driveLetter(String path) {
    final match = RegExp(r'^([A-Za-z]):').firstMatch(path.trim());
    return match == null ? '' : '${match.group(1)!.toUpperCase()}:';
  }

  /// Installers, disk images and archives in Downloads (and one level below)
  /// that have not been modified since [cutoff].
  static List<JunkItem> listDownloadsLeftovers(String path, DateTime cutoff) =>
      _listDownloadsLeftovers(path, cutoff);

  static List<JunkItem> _listDownloadsLeftovers(String path, DateTime cutoff) {
    final root = Directory(path);
    if (!root.existsSync()) return const [];
    final result = <JunkItem>[];
    void visit(Directory dir, int depth) {
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } catch (_) {
        return;
      }
      for (final entity in entries) {
        if (entity is Directory) {
          if (depth < 1) visit(entity, depth + 1);
          continue;
        }
        if (entity is! File) continue;
        final extension = CleanerSpaceInsights.extensionOf(
          p.basename(entity.path),
        );
        if (!downloadsExtensions.contains(extension)) continue;
        try {
          final stat = entity.statSync();
          if (stat.size < downloadsMinBytes) continue;
          if (stat.modified.isAfter(cutoff)) continue;
          result.add(_userSelected(entity.path, stat.size, stat.modified));
        } catch (_) {
          continue;
        }
      }
    }

    visit(root, 0);
    return result;
  }

  static (int, bool) _directorySize(String path) {
    var total = 0;
    var partial = false;
    final stack = <Directory>[Directory(path)];
    while (stack.isNotEmpty) {
      final dir = stack.removeLast();
      try {
        for (final entity in dir.listSync(followLinks: false)) {
          if (entity is Directory) {
            stack.add(entity);
          } else if (entity is File) {
            try {
              total += entity.lengthSync();
            } catch (_) {
              partial = true;
            }
          }
        }
      } catch (_) {
        partial = true;
      }
    }
    return (total, partial);
  }
}

import 'dart:io';

import '../disk_cleaner/cleaner_categories.dart';
import '../disk_cleaner/cleaner_models.dart';
import '../disk_cleaner/disk_tree_node.dart';
import 'app_insights_models.dart';

/// Attributes already-measured nodes from a full-disk scan to installed apps.
///
/// This analyzer never touches the filesystem. The final [DiskTreeNode] graph
/// is its only source of measured bytes, which keeps App Insights from
/// triggering a second scan of the selected drive.
class AppStorageAnalyzer {
  static const int defaultSharedFolderMinimumBytes = 500 * 1024 * 1024;

  const AppStorageAnalyzer();

  AppStorageReport analyze({
    required DiskTreeNode root,
    required FullDiskScanResult scanResult,
    required List<InstalledAppInfo> apps,
    Map<String, AppUsageEvidence> usageByAppId =
        const <String, AppUsageEvidence>{},
    List<String> inventoryWarnings = const <String>[],
    bool inventoryIsPartial = false,
    Map<String, String>? environment,
    DateTime? generatedAt,
    int sharedFolderMinimumBytes = defaultSharedFolderMinimumBytes,
  }) {
    if (sharedFolderMinimumBytes < 0) {
      throw ArgumentError.value(
        sharedFolderMinimumBytes,
        'sharedFolderMinimumBytes',
        'must not be negative',
      );
    }

    final env = _normalizedEnvironment(environment ?? Platform.environment);
    final drivePath = normalizeWindowsPath(root.fullPath);
    final directoryIndex = _buildDirectoryIndex(root);
    final coverageIssues = _combinedCoverageIssues(scanResult, root.fullPath);
    final candidatesByApp = <String, Map<String, _StorageCandidate>>{
      for (final app in apps) app.id: <String, _StorageCandidate>{},
    };

    void addCandidate(String appId, _StorageCandidate candidate) {
      if (!isSameOrDescendant(candidate.path, drivePath)) return;
      final byPath = candidatesByApp[appId];
      if (byPath == null) return;
      final existing = byPath[candidate.path];
      byPath[candidate.path] = existing == null
          ? candidate
          : existing.merge(candidate);
    }

    for (final app in apps) {
      final installLocation = _expandAndNormalize(app.installLocation, env);
      if (installLocation != null) {
        addCandidate(
          app.id,
          _StorageCandidate(
            appId: app.id,
            path: installLocation,
            kind: AppStorageKind.install,
            confidence: AttributionConfidence.confirmed,
          ),
        );
      }

      final packageFamilyName = app.packageFamilyName?.trim();
      final localAppData = env['LOCALAPPDATA'];
      if (app.source == InstalledAppSource.msix &&
          packageFamilyName != null &&
          packageFamilyName.isNotEmpty &&
          !packageFamilyName.contains(RegExp(r'[\\/]')) &&
          localAppData != null) {
        addCandidate(
          app.id,
          _StorageCandidate(
            appId: app.id,
            path: normalizeWindowsPath(
              '$localAppData\\Packages\\$packageFamilyName',
            ),
            kind: AppStorageKind.packageData,
            confidence: AttributionConfidence.confirmed,
          ),
        );
      }

      final possibleIconRoot = _displayIconDirectory(app.displayIconPath, env);
      if (possibleIconRoot != null) {
        addCandidate(
          app.id,
          _StorageCandidate(
            appId: app.id,
            path: possibleIconRoot,
            kind: AppStorageKind.install,
            confidence: AttributionConfidence.likely,
            warnings: const <String>[
              'Possible location inferred from the app display icon.',
            ],
          ),
        );
      }
    }

    // Cleaner paths become confirmed app storage only when their owner hints
    // identify exactly one inventory entry. Ambiguous rules stay unattributed.
    for (final category in CleanerCategories.all()) {
      for (final rule in category.rules) {
        if (rule.appOwnerHints.isEmpty ||
            rule.source.kind == PathSourceKind.recycleBin) {
          continue;
        }
        final resolvedPath = _resolveSource(rule.source, env);
        if (resolvedPath == null ||
            !isSameOrDescendant(resolvedPath, drivePath)) {
          continue;
        }
        final scores = <InstalledAppInfo, int>{
          for (final app in apps)
            app: _ownerHintScore(app, rule.appOwnerHints, env),
        }..removeWhere((_, score) => score <= 0);
        if (scores.isEmpty) continue;
        final bestScore = scores.values.reduce(
          (current, score) => score > current ? score : current,
        );
        final owners = scores.entries
            .where((entry) => entry.value == bestScore)
            .map((entry) => entry.key)
            .toList(growable: false);
        if (owners.length != 1) continue;

        addCandidate(
          owners.single.id,
          _StorageCandidate(
            appId: owners.single.id,
            path: resolvedPath,
            kind: rule.storageKind ?? AppStorageKind.cache,
            confidence: AttributionConfidence.confirmed,
            categoryId: category.id,
            cleanableByRule: true,
            containerOnly: rule.emptyOnly,
          ),
        );
      }
    }

    final confirmedByPath = <String, List<_StorageCandidate>>{};
    for (final byPath in candidatesByApp.values) {
      for (final candidate in byPath.values) {
        if (candidate.confidence != AttributionConfidence.confirmed) continue;
        confirmedByPath
            .putIfAbsent(candidate.path, () => <_StorageCandidate>[])
            .add(candidate);
      }
    }

    final sharedExactPaths = <String>{};
    for (final entry in confirmedByPath.entries) {
      final owners = entry.value.map((candidate) => candidate.appId).toSet();
      if (owners.length > 1) sharedExactPaths.add(entry.key);
    }

    final acceptedConfirmed = <_ResolvedRoot>[];
    for (final byPath in candidatesByApp.values) {
      for (final candidate in byPath.values) {
        if (candidate.confidence != AttributionConfidence.confirmed ||
            sharedExactPaths.contains(candidate.path)) {
          continue;
        }
        final node = directoryIndex[candidate.path];
        if (node != null) {
          acceptedConfirmed.add(_ResolvedRoot(candidate.path, node));
        }
      }
    }

    final sharedRoots = <_ResolvedRoot>[];
    for (final path in sharedExactPaths) {
      final node = directoryIndex[path];
      if (node != null) sharedRoots.add(_ResolvedRoot(path, node));
    }

    final profiles = <AppStorageProfile>[];
    for (final app in apps) {
      final appCandidates = candidatesByApp[app.id]!.values;
      final confirmedForApp = appCandidates
          .where(
            (candidate) =>
                candidate.confidence == AttributionConfidence.confirmed &&
                !sharedExactPaths.contains(candidate.path),
          )
          .toList(growable: false);

      final possibleForApp = appCandidates
          .where((candidate) {
            if (candidate.confidence != AttributionConfidence.likely) {
              return false;
            }
            // A possible root already covered by any exact root is not useful and
            // would double-count bytes in the detail panel.
            return !acceptedConfirmed.any(
                  (root) => isSameOrDescendant(candidate.path, root.path),
                ) &&
                !sharedRoots.any(
                  (root) => isSameOrDescendant(candidate.path, root.path),
                );
          })
          .toList(growable: false);

      final entries = <AppStorageEntry>[];
      for (final candidate in <_StorageCandidate>[
        ...confirmedForApp,
        ...possibleForApp,
      ]) {
        final entry = _entryForCandidate(
          candidate,
          directoryIndex: directoryIndex,
          coverageIssues: coverageIssues,
          confirmedRoots: acceptedConfirmed,
          sharedRoots: sharedRoots,
        );
        if (entry != null) entries.add(entry);
      }

      entries.sort((a, b) {
        final confidence = a.attributionConfidence.index.compareTo(
          b.attributionConfidence.index,
        );
        if (confidence != 0) return confidence;
        return b.sizeBytes.compareTo(a.sizeBytes);
      });

      final warnings = <String>{...app.warnings};
      final appSharedPaths = appCandidates
          .where((candidate) => sharedExactPaths.contains(candidate.path))
          .map((candidate) => candidate.path)
          .toList(growable: false);
      if (appSharedPaths.isNotEmpty) {
        warnings.add(
          'Some storage roots are shared by multiple apps and were not '
          'assigned exclusively.',
        );
      }
      if (entries.any(
        (entry) => entry.measurementQuality == MeasurementQuality.partial,
      )) {
        warnings.add('One or more app paths were only partially measured.');
      }

      final hasMeasuredConfirmed = entries.any(
        (entry) =>
            entry.isConfirmed &&
            entry.measurementQuality == MeasurementQuality.measured,
      );
      final hasCandidateOnDrive = appCandidates.isNotEmpty;
      if (!hasMeasuredConfirmed &&
          hasCandidateOnDrive &&
          (app.estimatedSizeBytes ?? 0) > 0) {
        warnings.add(
          'Windows estimate is used when no confirmed path can be measured.',
        );
      }

      if (!_isRelevantToDrive(app, entries, appCandidates, drivePath, env)) {
        continue;
      }

      profiles.add(
        AppStorageProfile(
          app: app,
          usage: usageByAppId[app.id] ?? const AppUsageEvidence(),
          entries: entries,
          warnings: warnings.toList(growable: false),
        ),
      );
    }

    profiles.sort((a, b) {
      final size = b.bestKnownSizeBytes.compareTo(a.bestKnownSizeBytes);
      if (size != 0) return size;
      return a.app.displayName.toLowerCase().compareTo(
        b.app.displayName.toLowerCase(),
      );
    });

    final sharedOrUnattributed = _buildSharedOrUnattributed(
      directoryIndex: directoryIndex,
      env: env,
      drivePath: drivePath,
      coverageIssues: coverageIssues,
      acceptedConfirmed: acceptedConfirmed,
      sharedExactPaths: sharedExactPaths,
      minimumBytes: sharedFolderMinimumBytes,
    );

    final warnings = <String>{...inventoryWarnings};
    if (coverageIssues.isNotEmpty) {
      warnings.add(
        'The disk scan reported ${coverageIssues.length} coverage gap(s); '
        'overlapping app sizes are marked partial.',
      );
    }

    return AppStorageReport(
      drivePath: root.fullPath,
      apps: profiles,
      sharedOrUnattributed: sharedOrUnattributed,
      warnings: warnings.toList(growable: false),
      generatedAt: generatedAt ?? DateTime.now(),
      isPartial: inventoryIsPartial || coverageIssues.isNotEmpty,
    );
  }

  AppStorageReport analyzeInventory({
    required FullDiskScanResult scanResult,
    required InstalledAppInventoryResult inventory,
    Map<String, AppUsageEvidence> usageByAppId =
        const <String, AppUsageEvidence>{},
    Map<String, String>? environment,
    DateTime? generatedAt,
    int sharedFolderMinimumBytes = defaultSharedFolderMinimumBytes,
  }) {
    return analyze(
      root: scanResult.root,
      scanResult: scanResult,
      apps: inventory.apps,
      usageByAppId: usageByAppId,
      inventoryWarnings: inventory.warnings,
      inventoryIsPartial: inventory.isPartial,
      environment: environment,
      generatedAt: generatedAt,
      sharedFolderMinimumBytes: sharedFolderMinimumBytes,
    );
  }

  /// Creates exact Cleaner review targets for one app.
  ///
  /// Only entries produced from an existing owned Cleaner rule survive this
  /// second validation pass. Parent targets suppress their descendants, and
  /// every returned item remains rule-driven (`isUserSelected == false`).
  List<JunkItem> buildCleanableReviewItems(
    AppStorageProfile profile, {
    Map<String, String>? environment,
  }) {
    final env = _normalizedEnvironment(environment ?? Platform.environment);
    final entries =
        profile.entries
            .where(
              (entry) =>
                  entry.isConfirmed &&
                  entry.isCleanable &&
                  entry.categoryId != null,
            )
            .toList(growable: false)
          ..sort(
            (a, b) => normalizeWindowsPath(
              a.path,
            ).length.compareTo(normalizeWindowsPath(b.path).length),
          );

    final selectedPaths = <String>[];
    final items = <JunkItem>[];
    for (final entry in entries) {
      final normalizedPath = normalizeWindowsPath(entry.path);
      if (selectedPaths.any(
        (parent) => isSameOrDescendant(normalizedPath, parent),
      )) {
        continue;
      }

      final category = CleanerCategories.byId(entry.categoryId!);
      if (category == null) continue;
      CleanerPathRule? exactRule;
      for (final rule in category.rules) {
        if (rule.appOwnerHints.isEmpty) continue;
        final resolved = _resolveSource(rule.source, env);
        if (resolved == normalizedPath) {
          exactRule = rule;
          break;
        }
      }
      if (exactRule == null) continue;

      selectedPaths.add(normalizedPath);
      items.add(
        JunkItem(
          path: entry.path,
          sizeBytes: entry.sizeBytes,
          categoryId: entry.categoryId!,
          isContainerOnly: exactRule.emptyOnly,
          isUserSelected: false,
        ),
      );
    }
    return items;
  }

  /// Normalizes a Windows path for case-insensitive lookup and comparison.
  static String normalizeWindowsPath(String rawPath) {
    var path = rawPath.trim();
    if (path.length >= 2 &&
        ((path.startsWith('"') && path.endsWith('"')) ||
            (path.startsWith("'") && path.endsWith("'")))) {
      path = path.substring(1, path.length - 1).trim();
    }
    path = path.replaceAll('/', r'\');

    final upper = path.toUpperCase();
    if (upper.startsWith('\\\\?\\UNC\\')) {
      path = '\\\\${path.substring(8)}';
    } else if (upper.startsWith('\\\\?\\')) {
      path = path.substring(4);
    } else if (upper.startsWith('\\??\\')) {
      path = path.substring(4);
    }

    final isUnc = path.startsWith(r'\\');
    final segments = path
        .split(r'\')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    path = '${isUnc ? r'\\' : ''}${segments.join(r'\')}';

    if (RegExp(r'^[A-Za-z]:$').hasMatch(path)) {
      path = '$path\\';
    } else {
      while (path.length > 3 && path.endsWith(r'\')) {
        path = path.substring(0, path.length - 1);
      }
    }
    return path.toUpperCase();
  }

  /// Returns true only for an exact path or a separator-delimited descendant.
  static bool isSameOrDescendant(String path, String root) {
    final normalizedPath = normalizeWindowsPath(path);
    final normalizedRoot = normalizeWindowsPath(root);
    if (normalizedPath == normalizedRoot) return true;
    final prefix = normalizedRoot.endsWith(r'\')
        ? normalizedRoot
        : '$normalizedRoot\\';
    return normalizedPath.startsWith(prefix);
  }

  static Map<String, DiskTreeNode> _buildDirectoryIndex(DiskTreeNode root) {
    final index = <String, DiskTreeNode>{};
    final stack = <DiskTreeNode>[root];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (node.isFile) continue;
      index[normalizeWindowsPath(node.fullPath)] = node;
      stack.addAll(node.children);
    }
    return index;
  }

  static List<FullDiskScanCoverageIssue> _combinedCoverageIssues(
    FullDiskScanResult result,
    String rootPath,
  ) {
    final issues = <FullDiskScanCoverageIssue>[];
    final keys = <String>{};
    for (final issue in result.coverageIssues) {
      final key = '${normalizeWindowsPath(issue.path)}:${issue.reason.name}';
      if (keys.add(key)) issues.add(issue);
    }
    for (final path in result.inaccessible) {
      final cancelled = path.toLowerCase() == 'cancelled';
      final issue = FullDiskScanCoverageIssue(
        path: cancelled ? rootPath : path,
        reason: cancelled
            ? FullDiskScanCoverageIssueReason.cancelled
            : FullDiskScanCoverageIssueReason.inaccessible,
      );
      final key = '${normalizeWindowsPath(issue.path)}:${issue.reason.name}';
      if (keys.add(key)) issues.add(issue);
    }
    return issues;
  }

  static AppStorageEntry? _entryForCandidate(
    _StorageCandidate candidate, {
    required Map<String, DiskTreeNode> directoryIndex,
    required List<FullDiskScanCoverageIssue> coverageIssues,
    required List<_ResolvedRoot> confirmedRoots,
    required List<_ResolvedRoot> sharedRoots,
  }) {
    final node = directoryIndex[candidate.path];
    final overlappingIssues = coverageIssues
        .where((issue) => _pathsOverlap(candidate.path, issue.path))
        .toList(growable: false);
    if (node == null) {
      if (overlappingIssues.isEmpty) return null;
      return AppStorageEntry(
        path: candidate.path,
        kind: candidate.kind,
        sizeBytes: 0,
        measurementQuality: MeasurementQuality.partial,
        attributionConfidence: candidate.confidence,
        categoryId: candidate.categoryId,
        isCleanable: false,
        warnings: <String>[
          ...candidate.warnings,
          'This path could not be measured completely.',
        ],
      );
    }

    final exclusions = <_ResolvedRoot>[...confirmedRoots, ...sharedRoots];
    final size = candidate.confidence == AttributionConfidence.confirmed
        ? _exclusiveSize(node, candidate.path, exclusions)
        : node.sizeBytes;
    final quality = overlappingIssues.isEmpty
        ? MeasurementQuality.measured
        : MeasurementQuality.partial;
    final categoryMatches =
        candidate.categoryId != null &&
        node.isJunk &&
        node.junkCategoryId == candidate.categoryId;
    final isCleanable = candidate.cleanableByRule && categoryMatches;

    if (size <= 0 && quality == MeasurementQuality.measured && !isCleanable) {
      return null;
    }

    return AppStorageEntry(
      path: node.fullPath,
      kind: candidate.kind,
      sizeBytes: size < 0 ? 0 : size,
      measurementQuality: quality,
      attributionConfidence: candidate.confidence,
      categoryId: candidate.categoryId,
      isCleanable: isCleanable,
      warnings: <String>[
        ...candidate.warnings,
        if (overlappingIssues.isNotEmpty)
          'The scan skipped part of this path; the measured size is a lower bound.',
      ],
    );
  }

  static List<AppStorageEntry> _buildSharedOrUnattributed({
    required Map<String, DiskTreeNode> directoryIndex,
    required Map<String, String> env,
    required String drivePath,
    required List<FullDiskScanCoverageIssue> coverageIssues,
    required List<_ResolvedRoot> acceptedConfirmed,
    required Set<String> sharedExactPaths,
    required int minimumBytes,
  }) {
    final entriesByPath = <String, AppStorageEntry>{};
    final includedSharedRoots = <_ResolvedRoot>[];

    for (final path in sharedExactPaths) {
      final node = directoryIndex[path];
      if (node == null) continue;
      final size = _exclusiveSize(node, path, acceptedConfirmed);
      if (size < minimumBytes) continue;
      final partial = coverageIssues.any(
        (issue) => _pathsOverlap(path, issue.path),
      );
      entriesByPath[path] = AppStorageEntry(
        path: node.fullPath,
        kind: AppStorageKind.shared,
        sizeBytes: size,
        measurementQuality: partial
            ? MeasurementQuality.partial
            : MeasurementQuality.measured,
        attributionConfidence: AttributionConfidence.shared,
        warnings: <String>[
          'Multiple installed apps claim this exact storage root.',
          if (partial) 'The measured size is a lower bound.',
        ],
      );
      includedSharedRoots.add(_ResolvedRoot(path, node));
    }

    final appDataBases = <String>{};
    for (final key in const <String>[
      'LOCALAPPDATA',
      'APPDATA',
      'PROGRAMDATA',
    ]) {
      final path = env[key];
      if (path != null && path.isNotEmpty) appDataBases.add(path);
    }
    for (final basePath in appDataBases) {
      if (!isSameOrDescendant(basePath, drivePath)) continue;
      final baseNode = directoryIndex[normalizeWindowsPath(basePath)];
      if (baseNode == null) continue;
      for (final child in baseNode.children) {
        if (child.isFile) continue;
        final childPath = normalizeWindowsPath(child.fullPath);
        if (!isSameOrDescendant(childPath, drivePath)) continue;
        final remaining = _remainingAfterRoots(
          child,
          childPath,
          <_ResolvedRoot>[...acceptedConfirmed, ...includedSharedRoots],
        );
        if (remaining < minimumBytes) continue;
        final partial = coverageIssues.any(
          (issue) => _pathsOverlap(childPath, issue.path),
        );
        entriesByPath.putIfAbsent(
          childPath,
          () => AppStorageEntry(
            path: child.fullPath,
            kind: AppStorageKind.shared,
            sizeBytes: remaining,
            measurementQuality: partial
                ? MeasurementQuality.partial
                : MeasurementQuality.measured,
            attributionConfidence: AttributionConfidence.shared,
            warnings: <String>[
              'Large top-level app-data folder not attributed to one app.',
              if (partial) 'The measured size is a lower bound.',
            ],
          ),
        );
      }
    }

    final entries = entriesByPath.values.toList(growable: false)
      ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return entries;
  }

  static int _exclusiveSize(
    DiskTreeNode node,
    String path,
    List<_ResolvedRoot> roots,
  ) {
    final descendants = roots
        .where(
          (root) => root.path != path && isSameOrDescendant(root.path, path),
        )
        .toList(growable: false);
    final topLevel = descendants.where((candidate) {
      return !descendants.any(
        (other) =>
            other.path != candidate.path &&
            isSameOrDescendant(candidate.path, other.path),
      );
    });
    final excluded = topLevel.fold<int>(
      0,
      (sum, root) => sum + root.node.sizeBytes,
    );
    final remaining = node.sizeBytes - excluded;
    return remaining < 0 ? 0 : remaining;
  }

  static int _remainingAfterRoots(
    DiskTreeNode node,
    String path,
    List<_ResolvedRoot> roots,
  ) {
    final covered = roots
        .where((root) => isSameOrDescendant(root.path, path))
        .toList(growable: false);
    final topLevel = covered.where((candidate) {
      return !covered.any(
        (other) =>
            other.path != candidate.path &&
            isSameOrDescendant(candidate.path, other.path),
      );
    });
    final excluded = topLevel.fold<int>(
      0,
      (sum, root) => sum + root.node.sizeBytes,
    );
    final remaining = node.sizeBytes - excluded;
    return remaining < 0 ? 0 : remaining;
  }

  static bool _pathsOverlap(String a, String b) {
    return isSameOrDescendant(a, b) || isSameOrDescendant(b, a);
  }

  static bool _isRelevantToDrive(
    InstalledAppInfo app,
    List<AppStorageEntry> entries,
    Iterable<_StorageCandidate> candidates,
    String drivePath,
    Map<String, String> env,
  ) {
    if (entries.isNotEmpty || candidates.isNotEmpty) return true;
    final install = _expandAndNormalize(app.installLocation, env);
    if (install != null) return isSameOrDescendant(install, drivePath);
    final systemDrive = env['SYSTEMDRIVE'];
    return systemDrive == null ||
        isSameOrDescendant(drivePath, normalizeWindowsPath(systemDrive));
  }

  static Map<String, String> _normalizedEnvironment(
    Map<String, String> environment,
  ) {
    return <String, String>{
      for (final entry in environment.entries)
        entry.key.toUpperCase(): normalizeWindowsPath(entry.value),
    };
  }

  static String? _expandAndNormalize(String? rawPath, Map<String, String> env) {
    if (rawPath == null || rawPath.trim().isEmpty) return null;
    final expanded = rawPath.replaceAllMapped(
      RegExp(r'%([^%]+)%'),
      (match) => env[match.group(1)!.toUpperCase()] ?? match.group(0)!,
    );
    final normalized = normalizeWindowsPath(expanded);
    if (normalized.isEmpty || normalized.contains('%')) return null;
    return normalized;
  }

  static String? _resolveSource(PathSource source, Map<String, String> env) {
    switch (source.kind) {
      case PathSourceKind.recycleBin:
        return null;
      case PathSourceKind.absolute:
        return _expandAndNormalize(source.absolutePath, env);
      case PathSourceKind.env:
        final base = env[source.envVar?.toUpperCase()];
        if (base == null || base.isEmpty) return null;
        if (source.relative.isEmpty) return normalizeWindowsPath(base);
        return normalizeWindowsPath('$base\\${source.relative}');
    }
  }

  static String? _displayIconDirectory(
    String? rawValue,
    Map<String, String> env,
  ) {
    if (rawValue == null || rawValue.trim().isEmpty) return null;
    var value = rawValue.trim();
    if (value.startsWith('"')) {
      final closingQuote = value.indexOf('"', 1);
      if (closingQuote > 1) value = value.substring(1, closingQuote);
    } else {
      value = value.replaceFirst(RegExp(r',\s*-?\d+\s*$'), '');
      final executable = RegExp(
        r'^(.+?\.(?:exe|dll|ico))(?=\s|$)',
        caseSensitive: false,
      ).firstMatch(value);
      if (executable != null) value = executable.group(1)!;
    }
    value = value.replaceFirst(RegExp(r',\s*-?\d+\s*$'), '');
    final iconPath = _expandAndNormalize(value, env);
    if (iconPath == null) return null;
    final separator = iconPath.lastIndexOf(r'\');
    if (separator <= 2) return null;
    return iconPath.substring(0, separator);
  }

  static int _ownerHintScore(
    InstalledAppInfo app,
    List<String> hints,
    Map<String, String> env,
  ) {
    final displayName = _identityToken(app.displayName);
    final stableIdentities = <String>{
      _identityToken(app.id),
      _identityToken(app.packageFamilyName ?? ''),
    }..removeWhere((value) => value.isEmpty);
    final executableNames = <String>{
      for (final executable in app.executablePaths)
        _identityToken(_basename(executable)),
      if (app.displayIconPath != null)
        _identityToken(
          _basename(_expandAndNormalize(app.displayIconPath, env) ?? ''),
        ),
    }..removeWhere((value) => value.isEmpty);

    var bestScore = 0;
    for (final hint in hints) {
      final token = _identityToken(hint);
      if (token.isEmpty) continue;
      if (executableNames.contains(token)) {
        bestScore = bestScore < 120 ? 120 : bestScore;
      }
      if (displayName == token) {
        bestScore = bestScore < 110 ? 110 : bestScore;
      }
      if (stableIdentities.contains(token)) {
        bestScore = bestScore < 100 ? 100 : bestScore;
      }
      if (token.length >= 6 && displayName.contains(token)) {
        bestScore = bestScore < 60 ? 60 : bestScore;
      }
      for (final identity in stableIdentities) {
        if (token.length >= 6 && identity.contains(token)) {
          bestScore = bestScore < 50 ? 50 : bestScore;
        }
      }
    }
    return bestScore;
  }

  static String _identityToken(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  static String _basename(String path) {
    final normalized = path.replaceAll('/', r'\');
    final separator = normalized.lastIndexOf(r'\');
    return separator < 0 ? normalized : normalized.substring(separator + 1);
  }
}

class _StorageCandidate {
  final String appId;
  final String path;
  final AppStorageKind kind;
  final AttributionConfidence confidence;
  final String? categoryId;
  final bool cleanableByRule;
  final bool containerOnly;
  final List<String> warnings;

  const _StorageCandidate({
    required this.appId,
    required this.path,
    required this.kind,
    required this.confidence,
    this.categoryId,
    this.cleanableByRule = false,
    this.containerOnly = true,
    this.warnings = const <String>[],
  });

  _StorageCandidate merge(_StorageCandidate other) {
    final confirmed = confidence == AttributionConfidence.confirmed
        ? this
        : other.confidence == AttributionConfidence.confirmed
        ? other
        : this;
    final cleaner = cleanableByRule
        ? this
        : other.cleanableByRule
        ? other
        : confirmed;
    return _StorageCandidate(
      appId: appId,
      path: path,
      kind: cleaner.kind,
      confidence: confirmed.confidence,
      categoryId: cleaner.categoryId ?? confirmed.categoryId,
      cleanableByRule: cleanableByRule || other.cleanableByRule,
      containerOnly: cleaner.cleanableByRule
          ? cleaner.containerOnly
          : containerOnly,
      warnings: <String>{
        ...warnings,
        ...other.warnings,
      }.toList(growable: false),
    );
  }
}

class _ResolvedRoot {
  final String path;
  final DiskTreeNode node;

  const _ResolvedRoot(this.path, this.node);
}

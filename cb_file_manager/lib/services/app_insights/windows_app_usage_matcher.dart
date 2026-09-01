import 'package:path/path.dart' as path;

import 'app_insights_models.dart';
import 'windows_app_usage_parser.dart';

class PrefetchUsageRecord {
  final String executableName;
  final DateTime lastModified;

  const PrefetchUsageRecord({
    required this.executableName,
    required this.lastModified,
  });
}

/// Matches local Windows usage signals without treating absence as inactivity.
class WindowsAppUsageMatcher {
  const WindowsAppUsageMatcher();

  Map<String, AppUsageEvidence> match({
    required List<InstalledAppInfo> apps,
    required Iterable<ParsedUserAssistRecord> userAssistRecords,
    required Iterable<PrefetchUsageRecord> prefetchRecords,
    required DateTime now,
    Map<String, String> resolvedTargets = const <String, String>{},
  }) {
    final result = <String, AppUsageEvidence>{
      for (final app in apps) app.id: const AppUsageEvidence(),
    };
    final byId = <String, InstalledAppInfo>{
      for (final app in apps) app.id: app
    };
    final executableOwners = _executableOwners(apps);

    for (final record in userAssistRecords) {
      if (record.lastOpenedAt.isAfter(now)) continue;
      final resolved = resolvedTargets[record.decodedTarget];
      final target = _extractTarget(resolved ?? record.decodedTarget);
      if (target.isEmpty) continue;

      final match = _matchUserAssistTarget(
        target,
        apps,
        executableOwners,
      );
      if (match == null) continue;
      _replaceIfBetter(
        result,
        match.appId,
        AppUsageEvidence(
          lastOpenedAt: record.lastOpenedAt,
          source: AppUsageSource.userAssist,
          confidence: match.confidence,
          matchedTarget: target,
        ),
      );
    }

    for (final record in prefetchRecords) {
      if (record.lastModified.isAfter(now)) continue;
      final executable =
          path.windows.basename(record.executableName).toLowerCase();
      final owners = executableOwners[executable];
      // Prefetch names are only safe when they identify exactly one app.
      if (owners == null || owners.length != 1) continue;
      final appId = owners.single;
      if (!byId.containsKey(appId)) continue;
      _replaceIfBetter(
        result,
        appId,
        AppUsageEvidence(
          lastOpenedAt: record.lastModified,
          source: AppUsageSource.prefetch,
          confidence: UsageEvidenceConfidence.medium,
          matchedTarget: record.executableName,
        ),
      );
    }

    return result;
  }

  _UsageMatch? _matchUserAssistTarget(
    String target,
    List<InstalledAppInfo> apps,
    Map<String, Set<String>> executableOwners,
  ) {
    final normalized = _normalizePath(target);
    final normalizedLower = normalized.toLowerCase();

    final packageMatches = apps.where((app) {
      final family = app.packageFamilyName?.toLowerCase();
      return family != null &&
          (normalizedLower == family ||
              normalizedLower.startsWith('$family!') ||
              normalizedLower.contains('$family!'));
    }).toList(growable: false);
    if (packageMatches.length == 1) {
      return _UsageMatch(
        packageMatches.single.id,
        UsageEvidenceConfidence.high,
      );
    }

    final exactMatches = <String>{};
    for (final app in apps) {
      for (final executablePath in _appExecutablePaths(app)) {
        if (_normalizePath(executablePath).toLowerCase() == normalizedLower) {
          exactMatches.add(app.id);
        }
      }
    }
    if (exactMatches.length == 1) {
      return _UsageMatch(
        exactMatches.single,
        UsageEvidenceConfidence.high,
      );
    }

    if (_looksLikeWindowsPath(normalized)) {
      final containingApps = apps.where((app) {
        final root = app.installLocation;
        return root != null && _isWithin(normalized, root);
      }).toList(growable: false);
      if (containingApps.length == 1) {
        return _UsageMatch(
          containingApps.single.id,
          UsageEvidenceConfidence.medium,
        );
      }
    }

    final executableName = path.windows.basename(normalized).toLowerCase();
    if (!executableName.endsWith('.exe')) return null;
    final basenameOwners = executableOwners[executableName];
    if (basenameOwners == null || basenameOwners.length != 1) return null;
    return _UsageMatch(
      basenameOwners.single,
      UsageEvidenceConfidence.medium,
    );
  }

  Map<String, Set<String>> _executableOwners(List<InstalledAppInfo> apps) {
    final owners = <String, Set<String>>{};
    for (final app in apps) {
      for (final executablePath in _appExecutablePaths(app)) {
        final name = path.windows.basename(executablePath).toLowerCase();
        if (!name.endsWith('.exe')) continue;
        owners.putIfAbsent(name, () => <String>{}).add(app.id);
      }
    }
    return owners;
  }

  Iterable<String> _appExecutablePaths(InstalledAppInfo app) sync* {
    yield* app.executablePaths;
    final displayIcon = app.displayIconPath;
    if (displayIcon != null &&
        path.windows.extension(displayIcon).toLowerCase() == '.exe') {
      yield displayIcon;
    }
  }

  void _replaceIfBetter(
    Map<String, AppUsageEvidence> result,
    String appId,
    AppUsageEvidence candidate,
  ) {
    final existing = result[appId];
    if (existing == null || !existing.isKnown) {
      result[appId] = candidate;
      return;
    }
    final candidateTime = candidate.lastOpenedAt!;
    final existingTime = existing.lastOpenedAt!;
    if (candidateTime.isAfter(existingTime)) {
      result[appId] = candidate;
      return;
    }
    if (candidateTime.isAtSameMomentAs(existingTime) &&
        _evidenceRank(candidate) > _evidenceRank(existing)) {
      result[appId] = candidate;
    }
  }

  int _evidenceRank(AppUsageEvidence evidence) {
    var rank = evidence.confidence == UsageEvidenceConfidence.high ? 2 : 1;
    if (evidence.source == AppUsageSource.userAssist) rank += 2;
    return rank;
  }

  String _extractTarget(String value) {
    var target = value.trim();
    final drivePath = RegExp(r'[a-zA-Z]:[\\/]').firstMatch(target);
    if (drivePath != null && drivePath.start > 0) {
      target = target.substring(drivePath.start);
    }
    return target.trim().replaceAll('"', '');
  }

  String _normalizePath(String value) {
    var normalized = value.trim().replaceAll('/', r'\');
    if (normalized.startsWith(r'\\?\')) normalized = normalized.substring(4);
    return path.windows.normalize(normalized);
  }

  bool _looksLikeWindowsPath(String value) =>
      RegExp(r'^[a-zA-Z]:\\').hasMatch(value) || value.startsWith(r'\\');

  bool _isWithin(String candidate, String root) {
    final normalizedCandidate = _normalizePath(candidate).toLowerCase();
    var normalizedRoot = _normalizePath(root).toLowerCase();
    while (normalizedRoot.endsWith(r'\')) {
      normalizedRoot = normalizedRoot.substring(0, normalizedRoot.length - 1);
    }
    return normalizedCandidate == normalizedRoot ||
        normalizedCandidate.startsWith('$normalizedRoot\\');
  }
}

class _UsageMatch {
  final String appId;
  final UsageEvidenceConfidence confidence;

  const _UsageMatch(this.appId, this.confidence);
}

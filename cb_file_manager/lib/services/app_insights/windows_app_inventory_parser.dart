import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import 'app_insights_models.dart';

/// Converts raw Windows inventory records into stable App Insights models.
///
/// Keeping this logic separate from the MethodChannel makes filtering and
/// deduplication deterministic and testable without reading the real registry.
class WindowsAppInventoryParser {
  const WindowsAppInventoryParser();

  List<InstalledAppInfo> parseWin32Entries(
    Iterable<Map<String, Object?>> rawEntries,
  ) {
    final candidates = rawEntries
        .where((entry) => !_shouldHideWin32Entry(entry))
        .toList(growable: false)
      ..sort(_compareRawWin32Entries);

    final grouped = <String, List<Map<String, Object?>>>{};
    for (final entry in candidates) {
      final identity = _win32Identity(entry);
      grouped.putIfAbsent(identity, () => <Map<String, Object?>>[]).add(entry);
    }

    final apps = <InstalledAppInfo>[];
    for (final group in grouped.entries) {
      final records = group.value..sort(_compareRawWin32Entries);
      final displayName = _firstString(records, 'displayName');
      if (displayName == null) continue;

      final installLocation = _normalizeDirectory(
        _firstString(records, 'installLocation'),
      );
      final displayIconPath = parseDisplayIconPath(
        _firstString(records, 'displayIcon'),
      );
      final executablePaths = <String>{};
      if (displayIconPath != null &&
          path.windows.extension(displayIconPath).toLowerCase() == '.exe') {
        executablePaths.add(displayIconPath);
      }

      apps.add(
        InstalledAppInfo(
          id: _win32Id(group.key),
          displayName: displayName,
          publisher: _firstString(records, 'publisher'),
          version: _firstString(records, 'displayVersion'),
          source: InstalledAppSource.win32,
          installLocation: installLocation,
          displayIconPath: displayIconPath,
          installedOrUpdatedAt: _parseInstallDate(
            _firstString(records, 'installDate'),
          ),
          estimatedSizeBytes: _largestEstimatedSize(records),
          canManage: records.any(
            (entry) =>
                _string(entry['uninstallString']) != null ||
                _string(entry['quietUninstallString']) != null,
          ),
          executablePaths: executablePaths.toList(growable: false),
        ),
      );
    }

    apps.sort(_compareApps);
    return apps;
  }

  List<InstalledAppInfo> parseMsixEntries(
    Iterable<Map<String, Object?>> rawEntries,
  ) {
    final byFamily = <String, InstalledAppInfo>{};

    for (final entry in rawEntries) {
      if (!_bool(entry['isLaunchable'], defaultValue: true)) continue;
      if (_bool(entry['isFramework']) || _bool(entry['isResourcePackage'])) {
        continue;
      }

      final family = _string(entry['packageFamilyName']);
      final packageName = _string(entry['packageName']);
      final displayName = _string(entry['displayName']) ?? packageName;
      if (family == null || displayName == null) continue;

      final normalizedFamily = family.toLowerCase();
      final candidate = InstalledAppInfo(
        id: 'msix:$normalizedFamily',
        displayName: displayName,
        publisher: _string(entry['publisherDisplayName']) ??
            _string(entry['publisher']),
        version: _string(entry['version']),
        source: InstalledAppSource.msix,
        installLocation: _normalizeDirectory(
          _string(entry['installLocation']),
        ),
        packageFamilyName: family,
        installedOrUpdatedAt: _parseIsoDate(entry['installedDate']),
        canManage: true,
      );

      final existing = byFamily[normalizedFamily];
      if (existing == null || _compareMsixCandidates(candidate, existing) < 0) {
        byFamily[normalizedFamily] = candidate;
      }
    }

    final apps = byFamily.values.toList(growable: false)..sort(_compareApps);
    return apps;
  }

  /// Extracts the executable portion of a DisplayIcon registry value.
  ///
  /// Values commonly look like `"C:\\App\\app.exe",0` or
  /// `C:\\App\\app.exe,-12`. Icon indices are intentionally discarded.
  String? parseDisplayIconPath(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return null;

    String candidate;
    if (raw.startsWith('"')) {
      final closingQuote = raw.indexOf('"', 1);
      candidate =
          closingQuote > 1 ? raw.substring(1, closingQuote) : raw.substring(1);
    } else {
      final iconIndex = RegExp(r',\s*-?\d+\s*$').firstMatch(raw);
      candidate = iconIndex == null
          ? raw
          : raw.substring(0, iconIndex.start).trimRight();
    }

    candidate = candidate.trim();
    return candidate.isEmpty ? null : path.windows.normalize(candidate);
  }

  bool _shouldHideWin32Entry(Map<String, Object?> entry) {
    final displayName = _string(entry['displayName']);
    if (displayName == null) return true;
    if (_bool(entry['systemComponent']) || _bool(entry['noDisplay'])) {
      return true;
    }
    if (_string(entry['parentKeyName']) != null) return true;

    final releaseType = _string(entry['releaseType'])?.toLowerCase() ?? '';
    const hiddenReleaseTypes = <String>{
      'hotfix',
      'security update',
      'update',
      'update rollup',
    };
    if (hiddenReleaseTypes.contains(releaseType)) return true;

    final normalizedName = displayName.toLowerCase();
    if (RegExp(r'^(security update|update|hotfix)\s+for\b')
        .hasMatch(normalizedName)) {
      return true;
    }
    if (RegExp(r'\(kb\d{6,}\)\s*$').hasMatch(normalizedName)) return true;

    return false;
  }

  String _win32Identity(Map<String, Object?> entry) {
    final keyName = _string(entry['registryKeyName']) ?? '';
    final productCode = _extractProductCode(keyName);
    if (productCode != null) return 'product:$productCode';

    final name = _identityPart(_string(entry['displayName']));
    final publisher = _identityPart(_string(entry['publisher']));
    final installLocation = _identityPath(
      _string(entry['installLocation']),
    );
    if (installLocation.isNotEmpty) {
      return 'app:$name|$publisher|$installLocation';
    }

    // Some uninstall entries omit InstallLocation. The registry key is stable
    // across WOW64 views, so it avoids showing the same entry twice.
    return 'key:${_identityPart(keyName)}|$name|$publisher';
  }

  String _win32Id(String identity) {
    if (identity.startsWith('product:')) {
      return 'win32:${identity.substring('product:'.length)}';
    }
    final digest = sha1.convert(utf8.encode(identity)).toString();
    return 'win32:${digest.substring(0, 20)}';
  }

  String? _extractProductCode(String keyName) {
    final match = RegExp(
      r'^\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}$',
      caseSensitive: false,
    ).firstMatch(keyName.trim());
    return match?.group(0)?.toLowerCase();
  }

  int _compareRawWin32Entries(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) {
    final score = _entryScore(right).compareTo(_entryScore(left));
    if (score != 0) return score;

    final leftSignature = <String>[
      _string(left['registryRoot']) ?? '',
      _string(left['registryView']) ?? '',
      _string(left['registryKeyName']) ?? '',
    ].join('|').toLowerCase();
    final rightSignature = <String>[
      _string(right['registryRoot']) ?? '',
      _string(right['registryView']) ?? '',
      _string(right['registryKeyName']) ?? '',
    ].join('|').toLowerCase();
    return leftSignature.compareTo(rightSignature);
  }

  int _entryScore(Map<String, Object?> entry) {
    var score = 0;
    const usefulKeys = <String>[
      'displayVersion',
      'publisher',
      'installLocation',
      'displayIcon',
      'uninstallString',
      'estimatedSizeKb',
      'installDate',
    ];
    for (final key in usefulKeys) {
      if (_string(entry[key]) != null || entry[key] is num) score++;
    }
    if ((_string(entry['registryView']) ?? '') == '64') score++;
    return score;
  }

  int _compareApps(InstalledAppInfo left, InstalledAppInfo right) {
    final byName = left.displayName
        .toLowerCase()
        .compareTo(right.displayName.toLowerCase());
    return byName != 0 ? byName : left.id.compareTo(right.id);
  }

  int _compareMsixCandidates(
    InstalledAppInfo left,
    InstalledAppInfo right,
  ) {
    final leftScore = _msixScore(left);
    final rightScore = _msixScore(right);
    if (leftScore != rightScore) return rightScore.compareTo(leftScore);
    return left.displayName.compareTo(right.displayName);
  }

  int _msixScore(InstalledAppInfo app) {
    var score = 0;
    if (app.installLocation != null) score++;
    if (app.publisher != null) score++;
    if (app.version != null) score++;
    if (!app.displayName.startsWith('ms-resource:')) score++;
    return score;
  }

  String? _firstString(
    Iterable<Map<String, Object?>> records,
    String key,
  ) {
    for (final record in records) {
      final value = _string(record[key]);
      if (value != null) return value;
    }
    return null;
  }

  int? _largestEstimatedSize(Iterable<Map<String, Object?>> records) {
    int? largest;
    for (final record in records) {
      final raw = record['estimatedSizeKb'];
      final kb = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
      if (kb == null || kb <= 0) continue;
      final bytes = kb * 1024;
      if (largest == null || bytes > largest) largest = bytes;
    }
    return largest;
  }

  DateTime? _parseInstallDate(String? raw) {
    if (raw == null || !RegExp(r'^\d{8}$').hasMatch(raw)) return null;
    final year = int.tryParse(raw.substring(0, 4));
    final month = int.tryParse(raw.substring(4, 6));
    final day = int.tryParse(raw.substring(6, 8));
    if (year == null || month == null || day == null) return null;
    try {
      final parsed = DateTime(year, month, day);
      if (parsed.year != year || parsed.month != month || parsed.day != day) {
        return null;
      }
      return parsed;
    } on ArgumentError {
      return null;
    }
  }

  DateTime? _parseIsoDate(Object? raw) {
    final value = _string(raw);
    return value == null ? null : DateTime.tryParse(value);
  }

  String? _normalizeDirectory(String? raw) {
    if (raw == null) return null;
    var value = raw.trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1).trim();
    }
    if (value.isEmpty) return null;
    return path.windows.normalize(value);
  }

  String _identityPart(String? value) =>
      value?.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase() ?? '';

  String _identityPath(String? value) {
    final normalized = _normalizeDirectory(value);
    if (normalized == null) return '';
    return normalized.replaceAll('/', r'\').toLowerCase();
  }

  String? _string(Object? value) {
    if (value == null) return null;
    final string = value.toString().trim();
    return string.isEmpty ? null : string;
  }

  bool _bool(Object? value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == 'yes') return true;
    if (normalized == 'false' || normalized == 'no') return false;
    return int.tryParse(normalized) != 0;
  }
}

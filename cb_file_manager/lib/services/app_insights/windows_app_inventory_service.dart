import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import 'app_insights_models.dart';
import 'windows_app_insights_platform.dart';
import 'windows_app_inventory_parser.dart';
import 'windows_app_usage_matcher.dart';
import 'windows_app_usage_parser.dart';

/// Loads installed Windows apps and best-effort local usage evidence.
class WindowsAppInventoryService {
  final WindowsAppInsightsDataSource _dataSource;
  final WindowsAppInventoryParser _inventoryParser;
  final WindowsAppUsageParser _usageParser;
  final WindowsAppUsageMatcher _usageMatcher;
  final Directory? prefetchDirectory;
  final DateTime Function() _now;

  List<String> _lastUsageWarnings = const <String>[];

  WindowsAppInventoryService({
    WindowsAppInsightsDataSource? dataSource,
    this._inventoryParser = const WindowsAppInventoryParser(),
    this._usageParser = const WindowsAppUsageParser(),
    this._usageMatcher = const WindowsAppUsageMatcher(),
    this.prefetchDirectory,
    DateTime Function()? now,
  }) : _dataSource =
           dataSource ?? const MethodChannelWindowsAppInsightsDataSource(),
       _now = now ?? DateTime.now;

  List<String> get lastUsageWarnings => _lastUsageWarnings;

  Future<InstalledAppInventoryResult> loadInventory({
    void Function(InstalledAppInventoryResult snapshot)? onSnapshot,
  }) async {
    WindowsRawAppInsightsResult? win32;
    WindowsRawAppInsightsResult? msix;

    void publishSnapshot() {
      final callback = onSnapshot;
      if (callback == null) return;
      callback(
        _buildInventoryResult(
          win32: win32,
          msix: msix,
          loadingWin32: win32 == null,
          loadingMsix: msix == null,
        ),
      );
    }

    final win32Future =
        _safeRead(
          _dataSource.readWin32Inventory,
          'Win32 app inventory failed',
        ).then((result) {
          win32 = result;
          publishSnapshot();
          return result;
        });
    final msixFuture =
        _safeRead(
          _dataSource.readMsixInventory,
          'MSIX app inventory failed',
        ).then((result) {
          msix = result;
          publishSnapshot();
          return result;
        });

    await Future.wait<WindowsRawAppInsightsResult>(
      <Future<WindowsRawAppInsightsResult>>[win32Future, msixFuture],
    );
    return _buildInventoryResult(win32: win32, msix: msix);
  }

  InstalledAppInventoryResult _buildInventoryResult({
    WindowsRawAppInsightsResult? win32,
    WindowsRawAppInsightsResult? msix,
    bool loadingWin32 = false,
    bool loadingMsix = false,
  }) {
    final availableWin32 = win32 ?? const WindowsRawAppInsightsResult();
    final availableMsix = msix ?? const WindowsRawAppInsightsResult();

    final apps =
        <InstalledAppInfo>[
          ..._inventoryParser.parseWin32Entries(availableWin32.records),
          ..._inventoryParser.parseMsixEntries(availableMsix.records),
        ]..sort((left, right) {
          final byName = left.displayName.toLowerCase().compareTo(
            right.displayName.toLowerCase(),
          );
          return byName != 0 ? byName : left.id.compareTo(right.id);
        });

    return InstalledAppInventoryResult(
      apps: apps,
      warnings: _unique(<String>[
        ...availableWin32.warnings,
        ...availableMsix.warnings,
        if (loadingWin32) 'Win32 app inventory is still loading.',
        if (loadingMsix) 'MSIX app inventory is still loading.',
      ]),
      isPartial:
          loadingWin32 ||
          loadingMsix ||
          availableWin32.isPartial ||
          availableMsix.isPartial,
    );
  }

  Future<Map<String, AppUsageEvidence>> loadUsageEvidence(
    List<InstalledAppInfo> apps,
  ) async {
    if (apps.isEmpty) {
      _lastUsageWarnings = const <String>[];
      return const <String, AppUsageEvidence>{};
    }

    final warnings = <String>[];
    final userAssistResult = await _safeRead(
      _dataSource.readUserAssist,
      'UserAssist read failed',
    );
    warnings.addAll(userAssistResult.warnings);

    final userAssistRecords = <ParsedUserAssistRecord>[];
    for (final raw in userAssistResult.records) {
      final name = raw['encodedName']?.toString();
      final data = _asBytes(raw['data']);
      if (name == null || name.isEmpty || data == null) continue;
      final parsed = _usageParser.parseUserAssistRecord(name, data);
      if (parsed != null) userAssistRecords.add(parsed);
    }

    Map<String, String> resolvedTargets = const <String, String>{};
    try {
      resolvedTargets = await _dataSource.resolveUserAssistTargets(
        userAssistRecords
            .map((record) => record.decodedTarget)
            .toSet()
            .toList(growable: false),
      );
    } on Object catch (error) {
      warnings.add('UserAssist shortcut resolution failed: $error');
    }

    final prefetchRecords = <PrefetchUsageRecord>[];
    final directory = prefetchDirectory ?? _defaultPrefetchDirectory();
    try {
      if (await directory.exists()) {
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is! File) continue;
          final executable = _usageParser.executableNameFromPrefetch(
            path.windows.basename(entity.path),
          );
          if (executable == null) continue;
          try {
            prefetchRecords.add(
              PrefetchUsageRecord(
                executableName: executable,
                lastModified: await entity.lastModified(),
              ),
            );
          } on FileSystemException {
            // One unreadable Prefetch entry must not hide all other evidence.
          }
        }
      }
    } on FileSystemException catch (error) {
      warnings.add('Prefetch evidence is unavailable: ${error.message}');
    }

    _lastUsageWarnings = List<String>.unmodifiable(_unique(warnings));
    return _usageMatcher.match(
      apps: apps,
      userAssistRecords: userAssistRecords,
      prefetchRecords: prefetchRecords,
      resolvedTargets: resolvedTargets,
      now: _now().toUtc(),
    );
  }

  Future<WindowsRawAppInsightsResult> _safeRead(
    Future<WindowsRawAppInsightsResult> Function() read,
    String label,
  ) async {
    try {
      return await read();
    } on Object catch (error) {
      return WindowsRawAppInsightsResult(
        warnings: <String>['$label: $error'],
        isPartial: true,
      );
    }
  }

  Directory _defaultPrefetchDirectory() {
    final windowsRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    return Directory(path.windows.join(windowsRoot, 'Prefetch'));
  }

  Uint8List? _asBytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is List) {
      try {
        return Uint8List.fromList(value.cast<int>());
      } on Object {
        return null;
      }
    }
    return null;
  }

  List<String> _unique(Iterable<String> values) {
    final seen = <String>{};
    return <String>[
      for (final value in values)
        if (value.trim().isNotEmpty && seen.add(value)) value,
    ];
  }
}

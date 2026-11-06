import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../disk_cleaner/cleaner_installed_apps.dart';
import '../disk_cleaner/cleaner_paths.dart';
import '../disk_cleaner/cleaner_system_protection.dart';
import 'app_insights_models.dart';
import 'app_leftover_finder.dart';
import 'app_leftover_scanner.dart';
import 'windows_app_insights_platform.dart';
import 'windows_app_inventory_service.dart';

typedef AppUninstallInventoryLoader =
    Future<InstalledAppInventoryResult> Function();

class AppUninstallException implements Exception {
  final String message;
  const AppUninstallException(this.message);
  @override
  String toString() => message;
}

class AppUninstallScan {
  final Map<String, AppLeftoverMeasurement> folders;
  final List<String> warnings;
  const AppUninstallScan(this.folders, {this.warnings = const []});
}

/// Interactive Windows uninstall followed by a separate, read-only folder scan.
/// A successful process exit alone never authorizes leftover cleanup.
class AppUninstallService {
  final AppUninstallInventoryLoader loadInventory;
  final AppInsightsProcessRunner processRunner;
  final Map<String, String> environment;

  AppUninstallService({
    AppUninstallInventoryLoader? loadInventory,
    this.processRunner = const SystemAppInsightsProcessRunner(),
    Map<String, String>? environment,
  }) : loadInventory =
           loadInventory ?? WindowsAppInventoryService().loadInventory,
       environment = environment ?? Platform.environment;

  static bool supports(InstalledAppInfo app) =>
      app.canManage &&
      (app.source == InstalledAppSource.win32 &&
              (app.uninstallCommand?.trim().isNotEmpty ?? false) ||
          app.source == InstalledAppSource.msix &&
              (app.packageFamilyName?.trim().isNotEmpty ?? false));

  static bool isStillInstalled(
    InstalledAppInfo removed,
    List<InstalledAppInfo> apps,
  ) {
    final name = CleanerInstalledApps.displayName(removed).toLowerCase();
    return apps.any(
      (app) =>
          app.id == removed.id ||
          (removed.packageFamilyName != null &&
              app.packageFamilyName?.toLowerCase() ==
                  removed.packageFamilyName!.toLowerCase()) ||
          CleanerInstalledApps.displayName(app).toLowerCase() == name,
    );
  }

  Future<InstalledAppInventoryResult> _completeInventory() async {
    final inventory = await loadInventory();
    if (inventory.isPartial) {
      throw const AppUninstallException(
        'The installed app list is incomplete. Refresh it and try again.',
      );
    }
    return inventory;
  }

  Future<InstalledAppInventoryResult> uninstall(
    InstalledAppInfo selected,
  ) async {
    final before = await _completeInventory();
    final matches = before.apps.where((app) => app.id == selected.id).toList();
    if (matches.length != 1 || !supports(matches.single)) {
      throw const AppUninstallException(
        'This app no longer has an interactive uninstaller.',
      );
    }
    // Use fresh registry metadata, never a cached or AI-supplied command.
    final script = buildUninstallScript(matches.single);
    final bytes = ByteData(script.length * 2);
    for (var i = 0; i < script.length; i++) {
      bytes.setUint16(i * 2, script.codeUnitAt(i), Endian.little);
    }
    final systemRoot =
        environment['SystemRoot'] ?? environment['SYSTEMROOT'] ?? r'C:\Windows';
    final result = await processRunner.run(
      p.windows.join(
        systemRoot,
        'System32',
        'WindowsPowerShell',
        'v1.0',
        'powershell.exe',
      ),
      [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-EncodedCommand',
        base64Encode(bytes.buffer.asUint8List()),
      ],
    );
    if (![0, 1641, 3010].contains(result.exitCode)) {
      throw AppUninstallException(
        'Uninstaller exit ${result.exitCode}: ${result.stderr}'.trim(),
      );
    }
    // Some launchers return before their registry entry disappears.
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 1));
      final after = await _completeInventory();
      if (!isStillInstalled(selected, after.apps)) return after;
    }
    throw const AppUninstallException(
      'The app is still installed, or uninstall was cancelled. No leftover files were selected.',
    );
  }

  /// Values are literal PowerShell strings; never evaluated as script text.
  static String _literal(String value) => "'${value.replaceAll("'", "''")}'";

  static String buildUninstallScript(InstalledAppInfo app) {
    if (app.source == InstalledAppSource.msix) {
      final family = app.packageFamilyName;
      if (family == null || family.isEmpty) {
        throw const AppUninstallException('Missing package identity.');
      }
      return "\$ErrorActionPreference = 'Stop'\n"
          "try { Get-AppxPackage | Where-Object { \$_.PackageFamilyName -eq ${_literal(family)} } | "
          "ForEach-Object { Remove-AppxPackage -Package \$_.PackageFullName -ErrorAction Stop }; exit 0 } "
          "catch { [Console]::Error.WriteLine(\$_.Exception.Message); exit 1 }";
    }
    final command = app.uninstallCommand?.trim() ?? '';
    final match = RegExp(
      r'^(?:"([^"]+\.exe)"|(.+?\.exe))\s*(.*)$',
      caseSensitive: false,
    ).firstMatch(command);
    if (match == null) {
      throw const AppUninstallException(
        'Unsupported uninstall command. Use Windows app settings.',
      );
    }
    final exe = (match.group(1) ?? match.group(2))!.trim();
    var arguments = match.group(3)!.trim();
    if (p.windows.basename(exe).toLowerCase() == 'msiexec.exe') {
      // Registry MSI entries frequently open maintenance mode with /I.
      arguments = arguments.replaceFirst(
        RegExp(r'^/I(?=\s|\{)', caseSensitive: false),
        '/X',
      );
    }
    return "\$ErrorActionPreference = 'Stop'\ntry { "
        "\$params = @{ FilePath = [Environment]::ExpandEnvironmentVariables(${_literal(exe)}); Wait = \$true; PassThru = \$true }; "
        "${arguments.isEmpty ? '' : '\$params.ArgumentList = ${_literal(arguments)}; '}"
        "\$process = Start-Process @params; exit \$process.ExitCode "
        "} catch { [Console]::Error.WriteLine(\$_.Exception.Message); exit 1 }";
  }

  Future<AppUninstallScan> scan(
    AppStorageProfile profile, {
    required List<String> excludedPaths,
  }) async {
    final inventory = await _completeInventory();
    if (isStillInstalled(profile.app, inventory.apps)) {
      throw const AppUninstallException(
        'The app is installed. Its data cannot be treated as leftovers.',
      );
    }
    final env = Map<String, String>.from(environment);
    return Isolate.run(
      () => scanUninstalledAppSync(
        profile: profile,
        remainingApps: inventory.apps,
        environment: env,
        excludedPaths: excludedPaths,
      ),
    );
  }
}

/// Narrow folder matching: complete product/install/package names only.
/// Shared vendor roots, links, system locations and remaining apps are excluded.
AppUninstallScan scanUninstalledAppSync({
  required AppStorageProfile profile,
  required List<InstalledAppInfo> remainingApps,
  required Map<String, String> environment,
  required List<String> excludedPaths,
}) {
  final bases = AppLeftoverFinder.baseDirectories(environment);
  final target = CleanerInstalledApps([profile.app]);
  final owners = CleanerInstalledApps(remainingApps);
  final candidates = <String>{};
  final warnings = <String>[];
  bool matchesName(String name) =>
      target.byExactName(name) != null ||
      name.toLowerCase() == profile.app.packageFamilyName?.toLowerCase() ||
      (target.byExe('$name.exe') != null && target.byName(name) != null);
  String nameKey(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  bool withoutLinks(String path) {
    try {
      return !CleanerPaths.ancestors(path).any(
        (ancestor) =>
            FileSystemEntity.typeSync(ancestor, followLinks: false) ==
            FileSystemEntityType.link,
      );
    } on FileSystemException {
      return false;
    }
  }

  bool safe(String path) {
    if (!p.windows.isAbsolute(path) ||
        path.contains('..') ||
        path.contains('*') ||
        path.contains('?') ||
        CleanerSystemProtection.isProtected(path, environment: environment)) {
      return false;
    }
    if (bases.any((base) => CleanerPaths.contains(path, base))) return false;
    if (excludedPaths.any(
      (own) =>
          CleanerPaths.contains(own, path) || CleanerPaths.contains(path, own),
    )) {
      return false;
    }
    if (remainingApps.any(
      (app) =>
          app.installLocation != null &&
          (CleanerPaths.contains(path, app.installLocation!) ||
              CleanerPaths.contains(app.installLocation!, path)),
    )) {
      return false;
    }
    if (owners.byName(p.windows.basename(path)) != null) return false;
    final leaf = nameKey(p.windows.basename(path));
    // A publisher-only root may contain data for several products, even when
    // those products have no useful InstallLocation in the registry.
    if ([profile.app, ...remainingApps].any(
      (app) =>
          app.publisher != null &&
          nameKey(app.publisher!) == leaf &&
          nameKey(CleanerInstalledApps.displayName(app)) != leaf,
    )) {
      return false;
    }
    // Do not traverse a junction in any parent, either.
    try {
      if (!withoutLinks(path)) return false;
      return FileSystemEntity.typeSync(path, followLinks: false) ==
          FileSystemEntityType.directory;
    } on FileSystemException {
      return false;
    }
  }

  void offer(String path) {
    if (safe(path)) candidates.add(p.windows.normalize(path));
  }

  for (final base in bases) {
    try {
      if (!withoutLinks(base)) continue;
      if (FileSystemEntity.typeSync(base, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }
      for (final child in Directory(base).listSync(followLinks: false)) {
        if (child is! Directory || !withoutLinks(child.path)) continue;
        if (matchesName(p.windows.basename(child.path))) {
          offer(child.path);
        } else {
          // Product folders inside a vendor or Packages folder.
          try {
            for (final nested in child.listSync(followLinks: false)) {
              if (nested is Directory &&
                  matchesName(p.windows.basename(nested.path))) {
                offer(nested.path);
              }
            }
          } on FileSystemException {
            warnings.add(child.path);
          }
        }
      }
    } on FileSystemException {
      warnings.add(base);
    }
  }
  final install = profile.app.installLocation;
  if (install != null && matchesName(p.windows.basename(install))) {
    offer(install);
  }
  for (final entry in profile.entries) {
    if (!entry.isConfirmed || entry.kind == AppStorageKind.shared) continue;
    if (!bases.any((base) => CleanerPaths.contains(base, entry.path))) continue;
    // A confirmed subfolder is only eligible under a product-named ancestor.
    if (CleanerPaths.ancestors(
      entry.path,
    ).any((path) => matchesName(p.windows.basename(path)))) {
      offer(entry.path);
    }
  }
  final paths = candidates.toList()
    ..sort((a, b) => a.length.compareTo(b.length));
  final roots = <String>[];
  for (final path in paths) {
    if (!roots.any((root) => CleanerPaths.contains(root, path))) {
      roots.add(path);
    }
  }
  return AppUninstallScan({
    for (final path in roots)
      path: measureAppLeftoverSync(
        path,
        AppLeftoverScanner.defaultMaxEntriesPerFolder,
      ),
  }, warnings: warnings.toSet().toList());
}

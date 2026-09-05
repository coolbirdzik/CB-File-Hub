import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class WindowsRawAppInsightsResult {
  final List<Map<String, Object?>> records;
  final List<String> warnings;
  final bool isPartial;

  const WindowsRawAppInsightsResult({
    this.records = const <Map<String, Object?>>[],
    this.warnings = const <String>[],
    this.isPartial = false,
  });
}

abstract class WindowsAppInsightsDataSource {
  Future<WindowsRawAppInsightsResult> readWin32Inventory();

  Future<WindowsRawAppInsightsResult> readMsixInventory();

  Future<WindowsRawAppInsightsResult> readUserAssist();

  Future<Map<String, String>> resolveUserAssistTargets(List<String> targets);
}

abstract class AppInsightsProcessRunner {
  Future<ProcessResult> run(String executable, List<String> arguments);
}

class SystemAppInsightsProcessRunner implements AppInsightsProcessRunner {
  const SystemAppInsightsProcessRunner();

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) {
    return Process.run(executable, arguments, runInShell: false);
  }
}

/// Windows platform bridge for registry, PackageManager, and UserAssist reads.
class MethodChannelWindowsAppInsightsDataSource
    implements WindowsAppInsightsDataSource {
  static const MethodChannel _defaultChannel = MethodChannel(
    'cb_file_manager/app_insights',
  );

  final MethodChannel channel;
  final AppInsightsProcessRunner processRunner;

  const MethodChannelWindowsAppInsightsDataSource({
    this.channel = _defaultChannel,
    this.processRunner = const SystemAppInsightsProcessRunner(),
  });

  @override
  Future<WindowsRawAppInsightsResult> readWin32Inventory() async {
    if (!Platform.isWindows) {
      return const WindowsRawAppInsightsResult(
        warnings: <String>['Win32 app inventory is only available on Windows.'],
        isPartial: true,
      );
    }
    try {
      return _decodeNativeResult(
        await channel.invokeMethod<Object?>('readWin32UninstallEntries'),
      );
    } on Object catch (error) {
      return WindowsRawAppInsightsResult(
        warnings: <String>['Could not read Win32 app inventory: $error'],
        isPartial: true,
      );
    }
  }

  @override
  Future<WindowsRawAppInsightsResult> readMsixInventory() async {
    if (!Platform.isWindows) {
      return const WindowsRawAppInsightsResult(
        warnings: <String>['MSIX app inventory is only available on Windows.'],
        isPartial: true,
      );
    }

    try {
      return _decodeNativeResult(
        await channel.invokeMethod<Object?>('readMsixPackages'),
      );
    } on Object catch (nativeError) {
      final fallback = await _readMsixWithPowerShell();
      if (!fallback.isPartial) {
        return WindowsRawAppInsightsResult(
          records: fallback.records,
          warnings: <String>[
            'Windows PackageManager was unavailable; used the local '
                'Get-AppxPackage fallback.',
            ...fallback.warnings,
          ],
        );
      }
      return WindowsRawAppInsightsResult(
        records: fallback.records,
        warnings: <String>[
          'Windows PackageManager failed: $nativeError',
          ...fallback.warnings,
        ],
        isPartial: true,
      );
    }
  }

  @override
  Future<WindowsRawAppInsightsResult> readUserAssist() async {
    if (!Platform.isWindows) return const WindowsRawAppInsightsResult();
    try {
      return _decodeNativeResult(
        await channel.invokeMethod<Object?>('readUserAssist'),
      );
    } on Object catch (error) {
      return WindowsRawAppInsightsResult(
        warnings: <String>['Could not read UserAssist evidence: $error'],
        isPartial: true,
      );
    }
  }

  @override
  Future<Map<String, String>> resolveUserAssistTargets(
    List<String> targets,
  ) async {
    if (!Platform.isWindows || targets.isEmpty) return const <String, String>{};
    try {
      final response = await channel.invokeMethod<Object?>(
        'resolveUserAssistTargets',
        <String, Object?>{'targets': targets},
      );
      if (response is! Map) return const <String, String>{};
      return <String, String>{
        for (final entry in response.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } on Object {
      return const <String, String>{};
    }
  }

  WindowsRawAppInsightsResult _decodeNativeResult(Object? value) {
    if (value is! Map) {
      return const WindowsRawAppInsightsResult(
        warnings: <String>['Windows returned an invalid inventory response.'],
        isPartial: true,
      );
    }
    final rawRecords = value['records'];
    final rawWarnings = value['warnings'];
    return WindowsRawAppInsightsResult(
      records: rawRecords is Iterable
          ? rawRecords
                .whereType<Map>()
                .map(_stringKeyedMap)
                .toList(growable: false)
          : const <Map<String, Object?>>[],
      warnings: rawWarnings is Iterable
          ? rawWarnings.map((item) => item.toString()).toList(growable: false)
          : const <String>[],
      isPartial: value['isPartial'] == true,
    );
  }

  Future<WindowsRawAppInsightsResult> _readMsixWithPowerShell() async {
    const script = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$startApps = @{}
Get-StartApps | ForEach-Object {
  $appId = [string]$_.AppID
  $separator = $appId.IndexOf('!')
  if ($separator -gt 0) {
    $family = $appId.Substring(0, $separator)
    if (-not $startApps.ContainsKey($family)) {
      $startApps[$family] = [ordered]@{ names = @(); ids = @() }
    }
    $startApps[$family].names += [string]$_.Name
    $startApps[$family].ids += $appId
  }
}
$result = @(Get-AppxPackage | ForEach-Object {
  $family = [string]$_.PackageFamilyName
  if ($startApps.ContainsKey($family)) {
    $displayName = @($startApps[$family].names | Where-Object { $_ })[0]
    [pscustomobject][ordered]@{
      packageName = [string]$_.Name
      packageFamilyName = $family
      packageFullName = [string]$_.PackageFullName
      displayName = $displayName
      publisher = [string]$_.Publisher
      publisherDisplayName = $null
      version = [string]$_.Version
      installLocation = [string]$_.InstallLocation
      installedDate = if ($_.InstallDate) { $_.InstallDate.ToString('o') } else { $null }
      isFramework = [bool]$_.IsFramework
      isResourcePackage = [bool]$_.IsResourcePackage
      isLaunchable = $true
      appUserModelIds = @($startApps[$family].ids)
    }
  }
})
$result | ConvertTo-Json -Compress -Depth 4
''';

    try {
      final result = await processRunner.run('powershell.exe', <String>[
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-EncodedCommand',
        _encodePowerShellCommand(script),
      ]);
      if (result.exitCode != 0) {
        final message = result.stderr.toString().trim();
        return WindowsRawAppInsightsResult(
          warnings: <String>[
            'Get-AppxPackage fallback failed${message.isEmpty ? '.' : ': $message'}',
          ],
          isPartial: true,
        );
      }

      final output = result.stdout.toString().trim();
      if (output.isEmpty) return const WindowsRawAppInsightsResult();
      final decoded = jsonDecode(output);
      final objects = decoded is List ? decoded : <Object?>[decoded];
      return WindowsRawAppInsightsResult(
        records: objects
            .whereType<Map>()
            .map(_stringKeyedMap)
            .toList(growable: false),
      );
    } on Object catch (error) {
      return WindowsRawAppInsightsResult(
        warnings: <String>['Get-AppxPackage fallback failed: $error'],
        isPartial: true,
      );
    }
  }

  String _encodePowerShellCommand(String script) {
    final units = script.codeUnits;
    final bytes = Uint8List(units.length * 2);
    final data = ByteData.sublistView(bytes);
    for (var index = 0; index < units.length; index++) {
      data.setUint16(index * 2, units[index], Endian.little);
    }
    return base64Encode(bytes);
  }

  Map<String, Object?> _stringKeyedMap(Map<Object?, Object?> value) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
}

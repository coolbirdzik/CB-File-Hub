import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_update_models.dart';

/// Hands a downloaded package to a detached helper script, which waits for
/// this process to exit, installs the package and relaunches the app.
///
/// The files of a running app cannot be replaced (Windows locks them, and
/// macOS would keep running the old bundle), so the install has to happen
/// after exit. The caller quits the app right after [launch] returns.
class DesktopUpdateInstaller {
  /// Starts the helper. Throws when the package or install location is not
  /// usable, before anything is changed.
  static Future<void> launch({
    required AppDistribution distribution,
    required String packagePath,
  }) async {
    if (!File(packagePath).existsSync()) {
      throw FileSystemException('Update package not found', packagePath);
    }
    final workDir = p.dirname(packagePath);
    final logPath = p.join(workDir, 'update.log');
    final executable = Platform.resolvedExecutable;

    switch (distribution) {
      case AppDistribution.windowsInstaller:
      case AppDistribution.windowsPortable:
        final scriptPath = p.join(workDir, 'apply_update.ps1');
        final script = buildWindowsScript(
          portable: distribution == AppDistribution.windowsPortable,
          processId: pid,
          executablePath: executable,
          packagePath: packagePath,
          logPath: logPath,
        );
        // The BOM makes Windows PowerShell 5.1 read non-ASCII paths as UTF-8.
        await File(
          scriptPath,
        ).writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(script)]);
        await Process.start('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-File',
          scriptPath,
        ], mode: ProcessStartMode.detached);
      case AppDistribution.macosDmg:
        final bundlePath = macosBundlePath(executable);
        if (bundlePath == null) {
          throw StateError('Cannot locate the app bundle for $executable');
        }
        final replaceScript = p.join(workDir, 'replace_app.sh');
        final mountPoint = p.join(workDir, 'mount');
        await File(replaceScript).writeAsString(
          buildMacosReplaceScript(
            bundlePath: bundlePath,
            mountPoint: mountPoint,
          ),
        );
        final scriptPath = p.join(workDir, 'apply_update.sh');
        await File(scriptPath).writeAsString(
          buildMacosScript(
            processId: pid,
            bundlePath: bundlePath,
            dmgPath: packagePath,
            mountPoint: mountPoint,
            replaceScriptPath: replaceScript,
            logPath: logPath,
          ),
        );
        await Process.start('/bin/bash', [
          scriptPath,
        ], mode: ProcessStartMode.detached);
      case AppDistribution.microsoftStore:
      case AppDistribution.googlePlay:
      case AppDistribution.unsupported:
        throw UnsupportedError('$distribution is not installed by this helper');
    }
  }

  /// `/Applications/CB File Hub.app/Contents/MacOS/cb` → the `.app` folder.
  static String? macosBundlePath(String executablePath) {
    final bundle = p.dirname(p.dirname(p.dirname(executablePath)));
    return bundle.endsWith('.app') ? bundle : null;
  }

  static String _ps(String value) => "'${value.replaceAll("'", "''")}'";

  static String _sh(String value) => "'${value.replaceAll("'", r"'\''")}'";

  static String buildWindowsScript({
    required bool portable,
    required int processId,
    required String executablePath,
    required String packagePath,
    required String logPath,
  }) {
    final install = portable
        ? r'''
$staging = Join-Path ([IO.Path]::GetTempPath()) ('cbfilehub-update-' + [guid]::NewGuid().ToString('N'))
try {
  Expand-Archive -LiteralPath $package -DestinationPath $staging -Force
  $source = $staging
  if (-not (Test-Path -LiteralPath (Join-Path $source $exeName))) {
    $nested = Get-ChildItem -LiteralPath $staging -Directory |
      Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $exeName) } |
      Select-Object -First 1
    if (-not $nested) { throw "$exeName not found in the update archive" }
    $source = $nested.FullName
  }
  robocopy $source $appDir /E /R:10 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
  Log 'Portable files replaced'
} catch {
  Log "Update failed: $_"
} finally {
  Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
'''
        : r'''
try {
  $msiArgs = @('/i', ('"' + $package + '"'), '/passive', '/norestart')
  $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Verb RunAs -Wait -PassThru
  Log "msiexec exit code $($proc.ExitCode)"
} catch {
  Log "Installer did not run: $_"
}
''';

    return '''
\$ErrorActionPreference = 'Stop'
\$appPid = $processId
\$exe = ${_ps(executablePath)}
\$package = ${_ps(packagePath)}
\$logFile = ${_ps(logPath)}
\$appDir = Split-Path -Parent \$exe
\$exeName = Split-Path -Leaf \$exe

function Log([string]\$message) {
  try { "\$(Get-Date -Format o) \$message" | Out-File -LiteralPath \$logFile -Append -Encoding utf8 } catch {}
}

function Get-AppProcesses {
  Get-Process -ErrorAction SilentlyContinue | Where-Object {
    \$_.Path -and \$_.Path.StartsWith(\$appDir + '\\', [StringComparison]::OrdinalIgnoreCase)
  }
}

Log 'Waiting for the app to exit'
try { Wait-Process -Id \$appPid -Timeout 60 -ErrorAction SilentlyContinue } catch {}
# Other windows of the app run as separate processes; give them a moment,
# then close whatever still holds files in the install folder.
\$deadline = (Get-Date).AddSeconds(15)
while ((Get-AppProcesses) -and (Get-Date) -lt \$deadline) { Start-Sleep -Milliseconds 500 }
Get-AppProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
$install
Remove-Item -LiteralPath \$package -Force -ErrorAction SilentlyContinue
Start-Process -FilePath \$exe
''';
  }

  static String buildMacosReplaceScript({
    required String bundlePath,
    required String mountPoint,
  }) {
    return '''
#!/bin/bash
set -e
APP=${_sh(bundlePath)}
SRC="\$(find ${_sh(mountPoint)} -maxdepth 1 -name '*.app' -print -quit)"
[ -n "\$SRC" ] || { echo "No app bundle in the update image"; exit 1; }
rm -rf "\$APP.update"
ditto "\$SRC" "\$APP.update"
rm -rf "\$APP"
mv "\$APP.update" "\$APP"
xattr -dr com.apple.quarantine "\$APP" 2>/dev/null || true
''';
  }

  static String buildMacosScript({
    required int processId,
    required String bundlePath,
    required String dmgPath,
    required String mountPoint,
    required String replaceScriptPath,
    required String logPath,
  }) {
    final escapedForAppleScript = replaceScriptPath
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"');
    final adminCommand =
        'do shell script "/bin/bash " & quoted form of "$escapedForAppleScript" '
        'with administrator privileges';
    return '''
#!/bin/bash
APP=${_sh(bundlePath)}
DMG=${_sh(dmgPath)}
MOUNT=${_sh(mountPoint)}
REPLACE=${_sh(replaceScriptPath)}
exec >>${_sh(logPath)} 2>&1

echo "\$(date) waiting for the app to exit"
while kill -0 $processId 2>/dev/null; do sleep 0.5; done

mkdir -p "\$MOUNT"
if hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "\$MOUNT" "\$DMG"; then
  # Replace in place; when the folder is not writable (e.g. /Applications
  # for a standard user), ask for an administrator password instead.
  if ! /bin/bash "\$REPLACE"; then
    osascript -e ${_sh(adminCommand)} || echo "update cancelled or failed"
  fi
  hdiutil detach "\$MOUNT" -quiet || hdiutil detach "\$MOUNT" -force -quiet
  rm -f "\$DMG"
else
  echo "could not mount \$DMG"
fi
rmdir "\$MOUNT" 2>/dev/null
open "\$APP"
''';
  }
}

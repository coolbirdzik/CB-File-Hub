param(
    [ValidateSet('desktop', 'android', 'all', 'help')]
    [string]$Target = 'all'
)

$ErrorActionPreference = 'Stop'
# Probing the device for a directory that does not exist makes adb exit
# non-zero, and PowerShell 7.4+ turns a failing native command into a
# terminating error under 'Stop'. The flutter test result is captured from
# $LASTEXITCODE explicitly instead.
$PSNativeCommandUseErrorActionPreference = $false

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = Split-Path -Parent $scriptDir
$projectDir = Join-Path $repoDir 'cb_file_manager'
$reportDir = Join-Path $projectDir 'build/e2e_report'
$reportScreenshotsDir = Join-Path $reportDir 'screenshots'
$outputRoot = Join-Path $repoDir 'screenshots/auto'

$desktopDevice = if ($env:DESKTOP_DEVICE) { $env:DESKTOP_DEVICE } else { 'windows' }
$androidDevice = if ($env:ANDROID_DEVICE) { $env:ANDROID_DEVICE } else { 'android' }
$testFile = if ($env:TEST_FILE) { $env:TEST_FILE } else { 'integration_test/showcase_screenshots_e2e_test.dart' }
$testName = if ($env:TEST_NAME) { $env:TEST_NAME } else { '' }
$fullScreenshots = if ($env:FULL_SCREENSHOTS) { $env:FULL_SCREENSHOTS } else { 'false' }

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-ErrorAndExit {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Show-Usage {
    @"
Usage:
  ./scripts/capture_screenshots.ps1 desktop
  ./scripts/capture_screenshots.ps1 android
  ./scripts/capture_screenshots.ps1 all

Environment overrides:
  DESKTOP_DEVICE=windows|linux|macos
  ANDROID_DEVICE=android|<device-id>
  TEST_FILE=integration_test/showcase_screenshots_e2e_test.dart
  TEST_NAME=Showcase
  FULL_SCREENSHOTS=true|false

Output:
  screenshots/auto/desktop/
  screenshots/auto/android/
"@ | Write-Host
}

function Ensure-Project {
    $pubspecPath = Join-Path $projectDir 'pubspec.yaml'
    if (-not (Test-Path $pubspecPath)) {
        Write-ErrorAndExit "Flutter project not found: $projectDir"
    }
}

function Clean-Report {
    if (Test-Path $reportDir) {
        Remove-Item $reportDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $reportScreenshotsDir -Force | Out-Null
}

# On Android the test process runs inside the app sandbox, so e2e_report.dart
# writes its frames to the app's external files dir on the device. Two things
# follow from that:
#
#   * they have to be pulled back to the host report dir before they can be
#     copied into screenshots/auto/android/, and
#   * `flutter test` uninstalls the app as soon as the run finishes, which wipes
#     `Android/data/<package>` and every frame with it.
#
# So the pull runs continuously *while* the test executes rather than after it.
# Frames are written once and never rewritten, so repeatedly pulling the whole
# directory is safe.
$androidReportRoots = @(
    '/sdcard/Android/data/com.cbv.filehub/files/cb_e2e/build/e2e_report',
    '/storage/emulated/0/Android/data/com.cbv.filehub/files/cb_e2e/build/e2e_report',
    '/sdcard/Download/cb_e2e/build/e2e_report'
)

function Get-AdbArgs {
    param([string]$Device)
    if ([string]::IsNullOrWhiteSpace($Device) -or $Device -eq 'android') {
        return @()
    }
    return @('-s', $Device)
}

function Clear-AndroidReport {
    param([string]$Device)

    $adbArgs = Get-AdbArgs $Device
    foreach ($root in $androidReportRoots) {
        & adb @adbArgs shell rm -rf $root 2>&1 | Out-Null
    }
}

function Pull-AndroidReport {
    param(
        [string]$Device,
        [switch]$Quiet
    )

    $adbArgs = Get-AdbArgs $Device
    foreach ($root in $androidReportRoots) {
        $remote = "$root/screenshots"
        $listing = & adb @adbArgs shell ls $remote 2>&1
        if ($LASTEXITCODE -ne 0 -or -not $listing) { continue }

        if (-not $Quiet) { Write-Info "Pulling Android screenshots from $remote" }
        & adb @adbArgs pull $remote $reportDir 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { return $true }
    }

    return $false
}

# Polls the device for new frames until `Stop-AndroidReportWatcher` is called.
function Start-AndroidReportWatcher {
    param([string]$Device)

    $adbArgs = Get-AdbArgs $Device
    return Start-Job -ScriptBlock {
        param($adbArgs, $roots, $destination)
        while ($true) {
            foreach ($root in $roots) {
                $remote = "$root/screenshots"
                & adb @adbArgs pull $remote $destination 2>&1 | Out-Null
            }
            Start-Sleep -Milliseconds 400
        }
    } -ArgumentList $adbArgs, $androidReportRoots, $reportDir
}

function Stop-AndroidReportWatcher {
    param($Job)
    if ($null -eq $Job) { return }
    Stop-Job $Job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job $Job -Force -ErrorAction SilentlyContinue | Out-Null
}

function Copy-Screenshots {
    param([string]$Platform)

    $outputDir = Join-Path $outputRoot $Platform
    if (Test-Path $outputDir) {
        Remove-Item $outputDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

    if (-not (Test-Path $reportScreenshotsDir)) {
        Write-ErrorAndExit "Screenshot report directory missing: $reportScreenshotsDir"
    }

    $pngFiles = Get-ChildItem -Path $reportScreenshotsDir -Filter '*_result.png' -File -Recurse
    if ($pngFiles.Count -eq 0) {
        $pngFiles = Get-ChildItem -Path $reportScreenshotsDir -Filter '*.png' -File -Recurse
    }
    if ($pngFiles.Count -eq 0) {
        Write-ErrorAndExit "No screenshots produced for $Platform"
    }

    foreach ($file in $pngFiles) {
        Copy-Item $file.FullName -Destination (Join-Path $outputDir $file.Name) -Force
    }

    Write-Info "Copied $($pngFiles.Count) screenshot(s) to $outputDir"
}

function Run-Capture {
    param(
        [string]$Platform,
        [string]$Device
    )

    Write-Info "Capturing $Platform screenshots on device: $Device"
    Clean-Report
    if ($Platform -eq 'android') {
        Clear-AndroidReport $Device
    }

    $watcher = $null
    if ($Platform -eq 'android') {
        $watcher = Start-AndroidReportWatcher $Device
    }

    Push-Location $projectDir
    try {
        $flutterArgs = @(
            'test'
            $testFile
            '-d'
            $Device
            '--dart-define=CB_E2E=true'
            '--dart-define=CB_E2E_FAST=true'
            "--dart-define=CB_E2E_FULL_SCREENSHOTS=$fullScreenshots"
            '--reporter'
            'expanded'
        )
        if (-not [string]::IsNullOrWhiteSpace($testName)) {
            $flutterArgs += @('--plain-name', $testName)
        }

        & flutter @flutterArgs
        $script:testExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
        if ($Platform -eq 'android') {
            # One last pull in case a frame landed between polls, then stop.
            Pull-AndroidReport $Device -Quiet | Out-Null
            Stop-AndroidReportWatcher $watcher
        }
    }

    # Copy whatever was captured before reporting the failure: a single broken
    # scene should not cost the frames every other scene produced.
    Copy-Screenshots $Platform

    if ($script:testExitCode -ne 0) {
        Write-ErrorAndExit "flutter test failed for $Platform"
    }
}

Ensure-Project

switch ($Target) {
    'desktop' { Run-Capture 'desktop' $desktopDevice }
    'android' { Run-Capture 'android' $androidDevice }
    'all' {
        Run-Capture 'desktop' $desktopDevice
        Run-Capture 'android' $androidDevice
    }
    'help' { Show-Usage }
}

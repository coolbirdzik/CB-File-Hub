param(
    [ValidateSet('desktop', 'android', 'all', 'help')]
    [string]$Target = 'all'
)

$ErrorActionPreference = 'Stop'

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

        if ($LASTEXITCODE -ne 0) {
            Write-ErrorAndExit "flutter test failed for $Platform"
        }
    }
    finally {
        Pop-Location
    }

    Copy-Screenshots $Platform
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

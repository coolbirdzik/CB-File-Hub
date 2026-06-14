# justfile for CB File Hub
# Cross-platform build system for Flutter application
# Works on: Windows (PowerShell/cmd/Git Bash), Linux, macOS
#
# Usage: just <recipe> [args...]
#   just                          # show help
#   just e2e Navigation           # run one E2E suite
#   just e2e                      # all E2E suites (single process)
#   just e2e-parallel             # all E2E suites (parallel + dashboard)
#   just analyze                  # analyze code
#   just format                   # format code

# Shell config: use bash on all platforms
set windows-shell := ["C:/Program Files/Git/bin/bash.exe", "-c"]
set shell := ["bash", "-c"]

# Variables
project_dir := "cb_file_manager"
flutter := "flutter"
build_dir := project_dir / "build"
pubspec := project_dir / "pubspec.yaml"
e2e_device := env("E2E_DEVICE", "windows")
test_reporter := env("TEST_REPORTER", "expanded")

# Default recipe: show help
default:
    @just --list --unsorted

# =============================================================================
# Development
# =============================================================================

# Install dependencies
deps:
    cd {{project_dir}} && {{flutter}} pub get

# Run flutter doctor
doctor:
    {{flutter}} doctor -v

# Clean build artifacts
clean:
    cd {{project_dir}} && {{flutter}} clean
    rm -rf {{project_dir}}/build/windows/CMakeCache.txt 2>/dev/null || true
    rm -rf {{project_dir}}/build/windows/CMakeFiles 2>/dev/null || true
    rm -rf {{project_dir}}/build/windows/.cmake 2>/dev/null || true
    rm -rf {{project_dir}}/.dart_tool 2>/dev/null || true
    rm -rf {{project_dir}}/windows/flutter/ephemeral 2>/dev/null || true
    rm -rf {{project_dir}}/linux/flutter/ephemeral 2>/dev/null || true
    rm -rf {{project_dir}}/macos/Flutter/ephemeral 2>/dev/null || true

# Deep clean (remove all build files)
deep-clean:
    cd {{project_dir}} && {{flutter}} clean
    rm -rf {{project_dir}}/build/windows 2>/dev/null || true
    rm -rf {{project_dir}}/build/linux 2>/dev/null || true
    rm -rf {{project_dir}}/build/macos 2>/dev/null || true
    rm -rf {{project_dir}}/.dart_tool 2>/dev/null || true
    rm -rf {{project_dir}}/.flutter-plugins 2>/dev/null || true
    rm -rf {{project_dir}}/.flutter-plugins-dependencies 2>/dev/null || true
    rm -rf {{project_dir}}/.packages 2>/dev/null || true
    rm -rf {{project_dir}}/windows/flutter/ephemeral 2>/dev/null || true
    rm -rf {{project_dir}}/linux/flutter/ephemeral 2>/dev/null || true
    rm -rf {{project_dir}}/macos/Flutter/ephemeral 2>/dev/null || true
    rm -rf {{project_dir}}/ios/.symlinks 2>/dev/null || true
    rm -rf {{project_dir}}/ios/Flutter/Flutter.framework 2>/dev/null || true
    rm -rf {{project_dir}}/ios/Flutter/Flutter.podspec 2>/dev/null || true

# Analyze code
analyze:
    cd {{project_dir}} && {{flutter}} analyze

# Format code
format:
    cd {{project_dir}} && dart format .

# Verify code quality (format check + analyze)
verify:
    cd {{project_dir}} && dart format --output=none --set-exit-if-changed .
    cd {{project_dir}} && {{flutter}} analyze

# Check format only
verify-format:
    cd {{project_dir}} && dart format --output=none --set-exit-if-changed .

# Analyze only
verify-analyze:
    cd {{project_dir}} && {{flutter}} analyze

# =============================================================================
# Testing
# =============================================================================

# Run unit + widget tests
test:
    cd {{project_dir}} && {{flutter}} test --reporter {{test_reporter}}

# Kill stray E2E app instances
kill-e2e:
    taskkill //F //IM cb_file_hub.exe //T 2>/dev/null || true

# E2E single-process: build once, run all (or one suite). Fastest for local iteration.
# Generates dashboard at cb_file_manager/build/e2e_dashboard/index.html when done.
#
# Filter is a substring match against the FULL test name "Group testname":
#   just e2e "Multi-Select"                          # whole suite
#   just e2e "select all with Ctrl+A"                # one specific test
#   just e2e "rename"                                # all tests with "rename"
# See `just e2e-list` for available test names.
#
# Options: just e2e "rename" true true               (full_startup, full_screenshots)
e2e suite="" full_startup="false" full_screenshots="false" no_open="false": kill-e2e
    cd {{project_dir}} && {{flutter}} test integration_test/app_e2e_test.dart --no-pub -d {{e2e_device}} --dart-define=CB_E2E=true --dart-define=CB_E2E_FAST={{ if full_startup == "true" { "false" } else { "true" } }} --dart-define=CB_E2E_FULL_SCREENSHOTS={{full_screenshots}} --reporter {{test_reporter}} --file-reporter json:build/e2e_report.jsonl {{ if suite != "" { '--plain-name "' + suite + '"' } else { "" } }} || true
    cd {{project_dir}} && dart run tool/e2e_dashboard.dart --build-dir build
    @echo ""
    @echo "Dashboard: file://$(pwd)/{{project_dir}}/build/e2e_dashboard/index.html"
    {{ if no_open != "true" { "just _open-dashboard" } else { "true" } }}

# Open the dashboard in default browser (cross-platform)
dashboard: _open-dashboard
    @echo "Dashboard: file://$(pwd)/{{project_dir}}/build/e2e_dashboard/index.html"

# List all available E2E test cases (group + test name).
# Use the printed names with `just e2e "<name>"` to run specific tests.
e2e-list:
    @echo "Available E2E test cases (use as: just e2e \"<name>\"):"
    @echo ""
    @grep -hE "^[[:space:]]*(group\\(|testWidgets\\()'" {{project_dir}}/integration_test/app_e2e_test.dart {{project_dir}}/integration_test/video_thumbnails_e2e_test.dart 2>/dev/null | sed -E -e "s|^[[:space:]]*group\\('([^']+)'.*|\\n[\\1]|" -e "s|^[[:space:]]*testWidgets\\('([^']+)'.*|  - \\1|"

# Internal: open dashboard in default browser
[private]
_open-dashboard:
    @cmd.exe //c start "" "{{project_dir}}\\build\\e2e_dashboard\\index.html" 2>/dev/null || xdg-open "{{project_dir}}/build/e2e_dashboard/index.html" 2>/dev/null || open "{{project_dir}}/build/e2e_dashboard/index.html" 2>/dev/null || true

# E2E parallel runner + dashboard (full run)
# Default workers = half the CPU cores (clamped 2..6). Override via:
#   - args: just e2e-parallel "" 4
#   - env:  CB_E2E_MAX_PARALLEL=4 just e2e-parallel
# Options: just e2e-parallel Navigation  |  just e2e-parallel "" 4 true true true
e2e-parallel suite="" max_parallel="" rerun="false" no_open="false" full_startup="false" full_screenshots="false": kill-e2e
    cd {{project_dir}} && dart run tool/e2e_parallel.dart {{ if suite != "" { '--plain-name "' + suite + '"' } else { "" } }} {{ if max_parallel != "" { "--max-parallel " + max_parallel } else { "" } }} {{ if rerun == "true" { "--rerun-failed" } else { "" } }} {{ if no_open == "true" { "--no-open" } else { "" } }} {{ if full_startup == "true" { "--full-startup" } else { "" } }} {{ if full_screenshots == "true" { "--full-screenshots" } else { "" } }}

# E2E serial runner (debug exact order)
e2e-serial suite="" rerun="false" no_open="false" full_startup="false" full_screenshots="false": kill-e2e
    cd {{project_dir}} && dart run tool/e2e_allure.dart {{ if suite != "" { '--plain-name "' + suite + '"' } else { "" } }} {{ if rerun == "true" { "--rerun-failed" } else { "" } }} {{ if no_open == "true" { "--no-open" } else { "" } }} {{ if full_startup == "true" { "--full-startup" } else { "" } }} {{ if full_screenshots == "true" { "--full-screenshots" } else { "" } }}

# E2E plain output (no dashboard, useful for debugging)
e2e-plain full_startup="false" full_screenshots="false": kill-e2e
    cd {{project_dir}} && dart run tool/run_e2e_with_log.dart {{ if full_startup == "true" { "--full-startup" } else { "" } }} {{ if full_screenshots == "true" { "--full-screenshots" } else { "" } }}

# Rerun only previously-failed E2E tests
e2e-failed no_open="false" full_startup="false" full_screenshots="false": kill-e2e
    cd {{project_dir}} && dart run tool/e2e_allure.dart --rerun-failed {{ if no_open == "true" { "--no-open" } else { "" } }} {{ if full_startup == "true" { "--full-startup" } else { "" } }} {{ if full_screenshots == "true" { "--full-screenshots" } else { "" } }}

# flutter clean + pub get + E2E (fix MSB3073 / bad build)
e2e-clean full_startup="false" full_screenshots="false": kill-e2e
    cd {{project_dir}} && {{flutter}} clean
    cd {{project_dir}} && {{flutter}} pub get
    cd {{project_dir}} && {{flutter}} test integration_test -d {{e2e_device}} --dart-define=CB_E2E=true --dart-define=CB_E2E_FAST={{ if full_startup == "true" { "false" } else { "true" } }} --dart-define=CB_E2E_FULL_SCREENSHOTS={{full_screenshots}} --reporter {{test_reporter}}

# Run E2E by test file name
e2e-file file suite="": kill-e2e
    cd {{project_dir}} && dart run tool/e2e_parallel.dart --file {{file}} {{ if suite != "" { '--plain-name "' + suite + '"' } else { "" } }}

# =============================================================================
# Build
# =============================================================================

# Build Windows portable (ZIP)
windows: deps
    cd {{project_dir}} && {{flutter}} build windows --release
    mkdir -p {{build_dir}}/windows/portable
    cd {{build_dir}}/windows/x64/runner/Release && if command -v zip >/dev/null 2>&1; then zip -r ../../portable/CBFileHub-Portable.zip ./*; elif command -v 7z >/dev/null 2>&1; then 7z a -tzip ../../portable/CBFileHub-Portable.zip ./*; fi

# Build Windows MSI installer
windows-msi:
    bash scripts/build.sh windows-msi

# Build Windows MSIX (interactive: prompts for cert path + password)
windows-msix:
    printf "Certificate path: "; read -r CERT_PATH; printf "Certificate password: "; stty -echo; read -r CERT_PASSWORD; stty echo; echo ""; MSIX_CERT_PATH="$CERT_PATH" MSIX_CERT_PASSWORD="$CERT_PASSWORD" MSIX_REQUIRE_SIGNING=true bash scripts/build.sh windows-msix

# Build Store-ready Windows MSIX (x.y.z.0 version format)
windows-msix-store:
    printf "Certificate path: "; read -r CERT_PATH; printf "Certificate password: "; stty -echo; read -r CERT_PASSWORD; stty echo; echo ""; MSIX_CERT_PATH="$CERT_PATH" MSIX_CERT_PASSWORD="$CERT_PASSWORD" MSIX_REQUIRE_SIGNING=true MSIX_VERSION_OVERRIDE="$(bash scripts/version.sh name).0" bash scripts/build.sh windows-msix

# Build Android APK
android: clean deps
    cd {{project_dir}} && {{flutter}} build apk --release --split-per-abi

# Build Android AAB
android-aab: clean deps
    cd {{project_dir}} && {{flutter}} build appbundle --release

# Build Linux
linux: clean deps
    cd {{project_dir}} && {{flutter}} build linux --release
    mkdir -p {{build_dir}}/linux/portable
    cd {{build_dir}}/linux/x64/release && tar -czf ../portable/CBFileHub-Linux.tar.gz bundle/

# Build macOS
macos: clean deps
    cd {{project_dir}} && {{flutter}} build macos --release
    mkdir -p {{build_dir}}/macos/portable
    cd {{build_dir}}/macos/Build/Products/Release && zip -r ../../../portable/CBFileHub-macOS.zip cb_file_hub.app

# Build iOS
ios: clean deps
    cd {{project_dir}} && {{flutter}} build ios --release --no-codesign

# Build all platforms (best-effort, skips failures)
all:
    just windows || echo "Windows build failed"
    just windows-msi || echo "Windows MSI build failed"
    just android || echo "Android APK build failed"
    just android-aab || echo "Android AAB build failed"
    just linux || echo "Linux build failed"
    if [ "$(uname)" = "Darwin" ]; then just macos || echo "macOS build failed"; just ios || echo "iOS build failed"; fi

# =============================================================================
# Version & Release
# =============================================================================

# Show current version
version:
    @bash scripts/version.sh full

# Show version details
version-info:
    @echo "Version: $(bash scripts/version.sh name)"
    @echo "Build:   $(bash scripts/version.sh build)"
    @echo "Full:    $(bash scripts/version.sh full)"

# Calculate next patch version (x.x.X)
next-patch:
    @bash scripts/version.sh name | awk -F. '{print $1"."$2"."$3+1}'

# Calculate next minor version (x.X.0)
next-minor:
    @bash scripts/version.sh name | awk -F. '{print $1"."$2+1".0"}'

# Calculate next major version (X.0.0)
next-major:
    @bash scripts/version.sh name | awk -F. '{print $1+1".0.0"}'

# Update version in pubspec.yaml
update-version new_version:
    bash scripts/version.sh set-version {{new_version}}

# Bump build number (runs verify first)
bump-build: verify
    bash scripts/version.sh bump
    git add {{pubspec}}
    git commit -m "chore: bump build number to $(bash scripts/version.sh build)" || echo "Nothing to commit"

# Create patch release (x.x.X)
release-patch: verify
    bash -c 'NEW_VER=$(bash scripts/version.sh name | awk -F. "{print \$1\".\"\$2\".\"\$3+1}"); echo "Creating patch release: $NEW_VER"; bash scripts/version.sh set-version $NEW_VER; git add {{pubspec}}; git commit -m "chore: bump version to $NEW_VER"; git tag -a "v$NEW_VER" -m "Release v$NEW_VER"; echo "Created tag v$NEW_VER"; echo "Push with: git push origin main && git push origin v$NEW_VER"'

# Create minor release (x.X.0)
release-minor: verify
    bash -c 'NEW_VER=$(bash scripts/version.sh name | awk -F. "{print \$1\".\"\$2+1\".0\"}"); echo "Creating minor release: $NEW_VER"; bash scripts/version.sh set-version $NEW_VER; git add {{pubspec}}; git commit -m "chore: bump version to $NEW_VER"; git tag -a "v$NEW_VER" -m "Release v$NEW_VER"; echo "Created tag v$NEW_VER"; echo "Push with: git push origin main && git push origin v$NEW_VER"'

# Create major release (X.0.0)
release-major: verify
    bash -c 'NEW_VER=$(bash scripts/version.sh name | awk -F. "{print \$1+1\".0.0\"}"); echo "Creating major release: $NEW_VER"; bash scripts/version.sh set-version $NEW_VER; git add {{pubspec}}; git commit -m "chore: bump version to $NEW_VER"; git tag -a "v$NEW_VER" -m "Release v$NEW_VER"; echo "Created tag v$NEW_VER"; echo "Push with: git push origin main && git push origin v$NEW_VER"'

# Retag: recreate annotated tag and force-push (interactive)
retag tag remote="origin":
    git tag -f -a "{{tag}}" -m "Rebuild {{tag}} - auto-incremented build number"
    git push "{{remote}}" "{{tag}}" -f

# Retag with interactive remote selection (lists available remotes)
retag-one tag:
    bash scripts/retag.sh {{tag}}

# =============================================================================
# Git shortcuts
# =============================================================================

# Git status (short)
git-status:
    @git status --short

# Push current branch to origin
git-push:
    git push origin $(git branch --show-current)

# Push tags to origin
git-push-tags:
    git push --tags

# =============================================================================
# Makefile-compatible names (so old muscle memory still works)
# =============================================================================

# just dev-test-e2e-single                 → all suites, single process + dashboard
# just dev-test-e2e-single Navigation      → one suite + dashboard
dev-test-e2e-single suite="": (e2e suite)

# just dev-test-e2e-only
dev-test-e2e-only: kill-e2e
    cd {{project_dir}} && dart run tool/run_e2e_with_log.dart

# just dev-test-e2e-failed
dev-test-e2e-failed: kill-e2e
    cd {{project_dir}} && dart run tool/e2e_allure.dart --rerun-failed

# just dev-test-e2e-clean
dev-test-e2e-clean: kill-e2e
    cd {{project_dir}} && {{flutter}} clean
    cd {{project_dir}} && {{flutter}} pub get
    cd {{project_dir}} && {{flutter}} test integration_test -d {{e2e_device}} --dart-define=CB_E2E=true --dart-define=CB_E2E_FAST=true --dart-define=CB_E2E_FULL_SCREENSHOTS=false --reporter {{test_reporter}}

# just dev-test                            → unit + widget tests
dev-test: test

# just dev-test-unit
dev-test-unit: test

# just dev-test-e2e                        → parallel E2E + dashboard
# just dev-test-e2e Navigation             → one suite parallel
dev-test-e2e suite="": kill-e2e
    cd {{project_dir}} && dart run tool/e2e_parallel.dart {{ if suite != "" { '--plain-name "' + suite + '"' } else { "" } }}

# just kill-e2e-app
kill-e2e-app: kill-e2e

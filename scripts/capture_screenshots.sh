#!/usr/bin/env bash

# CB File Hub - automated screenshot capture for desktop and Android.
# Uses integration_test screenshot hooks and copies generated PNGs to screenshots/auto.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$REPO_DIR/cb_file_manager"
REPORT_DIR="$PROJECT_DIR/build/e2e_report"
REPORT_SCREENSHOTS_DIR="$REPORT_DIR/screenshots"
OUTPUT_ROOT="$REPO_DIR/screenshots/auto"

TARGET="${1:-all}"
DESKTOP_DEVICE="${DESKTOP_DEVICE:-windows}"
ANDROID_DEVICE="${ANDROID_DEVICE:-android}"
TEST_FILE="${TEST_FILE:-integration_test/showcase_screenshots_e2e_test.dart}"
TEST_NAME="${TEST_NAME:-}"
FULL_SCREENSHOTS="${FULL_SCREENSHOTS:-false}"

print_info() {
  printf '[INFO] %s\n' "$1"
}

print_error() {
  printf '[ERROR] %s\n' "$1" >&2
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/capture_screenshots.sh desktop
  ./scripts/capture_screenshots.sh android
  ./scripts/capture_screenshots.sh all

Environment overrides:
  DESKTOP_DEVICE=windows|linux|macos
  ANDROID_DEVICE=android|<device-id>
  TEST_FILE=integration_test/showcase_screenshots_e2e_test.dart
  TEST_NAME=Showcase
  FULL_SCREENSHOTS=true|false

Output:
  screenshots/auto/desktop/
  screenshots/auto/android/
EOF
}

ensure_project() {
  if [ ! -f "$PROJECT_DIR/pubspec.yaml" ]; then
    print_error "Flutter project not found: $PROJECT_DIR"
    exit 1
  fi
}

clean_report() {
  rm -rf "$REPORT_DIR"
  mkdir -p "$REPORT_SCREENSHOTS_DIR"
}

copy_screenshots() {
  local platform="$1"
  local output_dir="$OUTPUT_ROOT/$platform"

  rm -rf "$output_dir"
  mkdir -p "$output_dir"

  if [ ! -d "$REPORT_SCREENSHOTS_DIR" ]; then
    print_error "Screenshot report directory missing: $REPORT_SCREENSHOTS_DIR"
    exit 1
  fi

  local copied=0
  local pattern='*_result.png'
  if ! find "$REPORT_SCREENSHOTS_DIR" -type f -name "$pattern" | grep -q .; then
    pattern='*.png'
  fi
  while IFS= read -r -d '' file_path; do
    cp "$file_path" "$output_dir/"
    copied=$((copied + 1))
  done < <(find "$REPORT_SCREENSHOTS_DIR" -type f -name "$pattern" -print0)

  if [ "$copied" -eq 0 ]; then
    print_error "No screenshots produced for $platform"
    exit 1
  fi

  print_info "Copied $copied screenshot(s) to $output_dir"
}

run_capture() {
  local platform="$1"
  local device="$2"

  print_info "Capturing $platform screenshots on device: $device"
  clean_report

  (
    cd "$PROJECT_DIR"
    if [ -n "$TEST_NAME" ]; then
      flutter test "$TEST_FILE" \
        -d "$device" \
        --dart-define=CB_E2E=true \
        --dart-define=CB_E2E_FAST=true \
        --dart-define=CB_E2E_FULL_SCREENSHOTS="$FULL_SCREENSHOTS" \
        --plain-name "$TEST_NAME" \
        --reporter expanded
    else
      flutter test "$TEST_FILE" \
        -d "$device" \
        --dart-define=CB_E2E=true \
        --dart-define=CB_E2E_FAST=true \
        --dart-define=CB_E2E_FULL_SCREENSHOTS="$FULL_SCREENSHOTS" \
        --reporter expanded
    fi
  )

  copy_screenshots "$platform"
}

main() {
  ensure_project

  case "$TARGET" in
    desktop)
      run_capture desktop "$DESKTOP_DEVICE"
      ;;
    android)
      run_capture android "$ANDROID_DEVICE"
      ;;
    all)
      run_capture desktop "$DESKTOP_DEVICE"
      run_capture android "$ANDROID_DEVICE"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      print_error "Unknown target: $TARGET"
      exit 1
      ;;
  esac
}

main "$@"

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

# On Android the test process runs inside the app sandbox, so e2e_report.dart
# writes its frames to the app's external files dir on the device. These must be
# pulled back to the host report dir before they can be copied out.
ANDROID_REPORT_ROOTS=(
  '/sdcard/Android/data/com.cbv.filehub/files/cb_e2e/build/e2e_report'
  '/storage/emulated/0/Android/data/com.cbv.filehub/files/cb_e2e/build/e2e_report'
  '/sdcard/Download/cb_e2e/build/e2e_report'
)

adb_args() {
  if [ -z "$ANDROID_DEVICE" ] || [ "$ANDROID_DEVICE" = "android" ]; then
    return 0
  fi
  printf -- '-s\n%s\n' "$ANDROID_DEVICE"
}

clear_android_report() {
  local -a args=()
  while IFS= read -r line; do args+=("$line"); done < <(adb_args)
  local root
  for root in "${ANDROID_REPORT_ROOTS[@]}"; do
    adb "${args[@]}" shell rm -rf "$root" >/dev/null 2>&1 || true
  done
}

pull_android_report() {
  local -a args=()
  while IFS= read -r line; do args+=("$line"); done < <(adb_args)
  local root
  for root in "${ANDROID_REPORT_ROOTS[@]}"; do
    if adb "${args[@]}" shell ls "$root/screenshots" >/dev/null 2>&1; then
      adb "${args[@]}" pull "$root/screenshots" "$REPORT_DIR" >/dev/null 2>&1 && return 0
    fi
  done
  return 1
}

# `flutter test` uninstalls the app when the run ends, which wipes the frames
# with it, so the pull has to happen while the test is still executing.
ANDROID_WATCHER_PID=""

start_android_report_watcher() {
  (
    while true; do
      pull_android_report || true
      sleep 0.4
    done
  ) &
  ANDROID_WATCHER_PID=$!
}

stop_android_report_watcher() {
  if [ -n "$ANDROID_WATCHER_PID" ]; then
    kill "$ANDROID_WATCHER_PID" 2>/dev/null || true
    wait "$ANDROID_WATCHER_PID" 2>/dev/null || true
    ANDROID_WATCHER_PID=""
  fi
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
  if [ "$platform" = "android" ]; then
    clear_android_report
    start_android_report_watcher
  fi

  local test_status=0
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
  ) || test_status=$?

  if [ "$platform" = "android" ]; then
    pull_android_report || true
    stop_android_report_watcher
  fi

  # Copy whatever was captured before reporting the failure: a single broken
  # scene should not cost the frames every other scene produced.
  copy_screenshots "$platform"

  if [ "$test_status" -ne 0 ]; then
    print_error "flutter test failed for $platform"
    exit "$test_status"
  fi
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

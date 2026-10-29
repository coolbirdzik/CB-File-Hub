#!/usr/bin/env bash
# Shared source scope for local formatting and the CI quality checks.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../cb_file_manager"

# Never format build/, .dart_tool/, platform caches or temporary previews.
# Include root-level Dart files and all current source roots (including vendored
# Dart code, as before). Add new source roots here when the package grows.
shopt -s nullglob
root_files=(*.dart)
dart format "$@" "${root_files[@]}" bin integration_test lib test test_driver third_party tool

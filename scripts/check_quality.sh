#!/usr/bin/env bash
# Shared by `just analyze` and the CI analyze job. Stop on the first failure.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../cb_file_manager"
flutter="${1:-flutter}"

echo '==> Install dependencies'
"$flutter" pub get
echo '==> Verify formatting'
dart format --output=none --set-exit-if-changed .
echo '==> Analyze project'
"$flutter" analyze
echo '==> Run unit/widget tests'
"$flutter" test --reporter expanded

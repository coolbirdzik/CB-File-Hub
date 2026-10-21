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
echo '==> Run unit/widget tests (only failures are printed)'
# Passing tests and their log output stay out of the console; the full event
# stream remains in the JSON report for anyone who needs it.
report=build/unit_test_report.jsonl
mkdir -p build
rm -f "$report"
status=0
"$flutter" test --reporter silent --file-reporter "json:$report" || status=$?
# Plain `dart <file>` skips the build hooks `dart run` would rerun (~10 s).
dart tool/unit_test_failures.dart "$report" || status=1
exit "$status"

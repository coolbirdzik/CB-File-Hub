# Windows test harness measurement — 2026-11-07

The four Navigation cases took **126.393 s before and 10.907 s after** the
harness changes: **11.59× faster, 91.37% less executed-test time** in this local
comparison. Compilation is excluded. This is a Navigation measurement, not a
speedup claim for the complete E2E gate.

| Navigation case | Before | After |
| --- | ---: | ---: |
| Lists two files and a subfolder | 28.515 s | 3.327 s |
| Opens a subfolder | 32.756 s | 2.444 s |
| Empty sandbox | 26.723 s | 2.253 s |
| Backspace returns to parent | 38.399 s | 2.883 s |
| **Total** | **126.393 s** | **10.907 s** |

Host: Windows x64, Intel Core i5-14600K (14 cores/20 logical processors),
Flutter 3.47.8 / Dart 3.13.7. Both runs used the real desktop app and
`CB_E2E=true`, `CB_E2E_FAST=true`. Durations are the difference between JSON
`testStart.time` and `testDone.time`; startup and teardown inside each case are
included. Each side is one local run; cache/load/hardware differences remain,
and CI timings can differ.

The baseline copied the original app/keys/reporter/helpers/sandbox harness from
commit `455062a1f0a561fb9686433369055a047002c614` into a temporary test directory.
Production app code and resolved package versions were unchanged. The temporary
source directory was removed afterwards. The after-run used the final `app`
suite through `desktop_e2e_test.dart`. Its empty-folder case additionally proves
listing readiness and a nonempty-to-empty refresh; the added assertion was not
removed to improve timing.

The primary change is replacing multi-second pump intervals and repeated
global-idle waits with short animation settling and result polling. Screenshot
capture no longer waits for an entire video/spinner-heavy app to stop animating.
The real file-content and navigation assertions remain.

## Verification

- Full unit/widget run: **2,046 passed, 24 skipped**; the additional runner,
  semantics-identity and report-parser checks also passed in the focused tool suite.
- Full desktop gate: **71 passed, 1 skipped**, **462 s total** including build
  and startup in that run. The four accessibility cases are now included.
- After strengthening the empty-folder, delete-cancel, empty-rename, paste-empty
  and missing-path assertions, the complete app suite passed again: **34/34**.
  The final Navigation timings above come from that follow-up run.
- The skipped desktop case needs an explicitly configured real SMB URL
  (`CB_E2E_SMB_URL`); no SMB streaming success is claimed without it.
- Allure was checked against a real failed run as well as a real successful
  report. Reports distinguish fail/skip/incomplete, preserve event durations,
  associate indexed screenshots with exact test identities and remove stale
  generated result files.

Raw Navigation samples and verification counts are committed in
[`benchmarks/2026-11-07-desktop-test-performance.json`](benchmarks/2026-11-07-desktop-test-performance.json).
Local full event streams remain in `cb_file_manager/build/test-optimization/`
(`navigation-before.jsonl`, `app-final.jsonl`, `desktop-all-green.jsonl`). These
build artifacts are intentionally ignored by Git.

Use `just e2e-desktop` for the full gate, `just e2e-desktop-failed` for pending
failures and `just test-times <report.jsonl>` to inspect existing timings without
rerunning tests. [Full testing workflow](02-e2e-desktop-integration.md).

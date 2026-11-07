# Desktop testing: fast feedback and native coverage

Run Flutter/Dart commands from `cb_file_manager/`. Recipes below run from the
repository root. Use the pinned Flutter version in `build.config`. Agents must
follow the explicit E2E authorization policy in [AGENTS.md](../../AGENTS.md).

## Choose the layer that proves the behavior

| Layer | Use it for | Real dependencies |
| --- | --- | --- |
| Unit/service | Scheduling, cancellation, parsers, state transitions, errors | Inject dependencies; use completers/streams for async outcomes |
| Component/widget | Menus, keyboard/pointer actions, layout, captions, progress | Production widgets with controlled services and fake time |
| Service/native integration | SQLite cache, filesystem effects, Rust parity, worker protocol | Temporary DB/files and native implementation where available |
| Desktop E2E | App wiring, playback/decoding, native drag/drop, foreground IPC, Windows accessibility | Compiled Windows app and real plugins |

Keep detailed edge cases in the first three layers. Retain E2E assertions for
the actual cross-layer result: a copied file's bytes and source/destination,
decoded video pixels, seek position, real drag/drop effects or a valid native
accessibility tree. An app opening without an exception is insufficient.
UI screenshots made with authored fixtures illustrate layout; they do not
establish native behavior or model inference accuracy.

## Daily checks

```bash
just analyze                 # format, analysis, all unit/widget tests; no E2E
just e2e-affected             # preview affected suites; does not execute E2E
just e2e-affected main        # preview against a specific base
```

For a focused change, from `cb_file_manager/`:

```bash
flutter test --no-pub test/ui/components/video
flutter test --no-pub test/services/media
```

`scripts/check_quality.sh` resolves dependencies once; subsequent analysis and
tests use `--no-pub`. Reports/converters use `dart tool/...`, avoiding the native
build hooks that `dart run` would start for a reporting-only command.

## Full desktop E2E: one build and launch

```bash
just e2e-desktop
just e2e-desktop media_kit_playback,video_thumbnails
just e2e-desktop-failed
```

The same runner is used by Windows CI and the local release gate:

```bash
node scripts/ci/e2e_run.mjs --all
node scripts/ci/e2e_run.mjs --suites app,torrent_library
node scripts/ci/e2e_run.mjs --failed
```

The `just e2e-desktop` recipe prepares dependencies and bundled runtimes once.
Direct Node/Flutter commands assume `just deps`, `just fetch-llama` and
`just fetch-aria2` have already completed, as they do in CI/release preparation.

`integration_test/desktop_e2e_test.dart` registers the suites under scoped
groups. Their individual setup/teardown hooks stay scoped; one process-wide
temporary app-data sandbox is installed before services initialize. A single
entrypoint avoids repeatedly replacing Flutter's generated Windows listener
and rebuilding/launching a different target for every test file.

The runner selects exact group prefixes with `--name`, runs native/focus flows
sequentially and continues reporting assertion failures. It never duplicates
`smoke` when `app` already covers Navigation. Passes require completed,
non-skipped assertions and a terminal report; an empty filter, skipped-only
suite or crashed/truncated run cannot be recorded as a pass.

The suite catalog is authoritative in
[`e2e_impact.json`](../../cb_file_manager/integration_test/e2e_impact.json):

- `app` / `smoke`: all core file-manager flows / Navigation only.
- `video_thumbnails`, `media_kit_playback`, `ffmpeg_thumbnail`.
- `file_drag_drop`, `breadcrumb_address_bar_overflow`, `torrent_library`.
- `semantics_stability`, `tooltip_semantics`, `video_player_chrome_semantics`:
  actual desktop accessibility coverage, including real playback.

Marketing screenshot generators and temporary latency probes remain explicitly
outside the CI correctness gate. The real MP4 fixture lives in
`integration_test/samples/`; media assertions must not silently fall back to an
invalid stub or claim a pass when the fixture is missing.

## Focused/parallel debugging

```bash
just e2e Navigation
just e2e "rename"
just e2e-file media_kit_playback_e2e_test
just e2e-parallel "" 4
just e2e-failed
```

These existing debugging runners remain available. `--file` converts the report
it just produced; it does not invoke another test runner during dashboard
generation. Invalid files fail immediately. Failed-test reruns use an escaped
regex (`--name`), not a literal `--plain-name` containing pipe characters. If
there are no previous failures, rerun commands perform no build or tests.

Parallel defaults to half the CPU cores, clamped to 2–6. Windows builds with
different entrypoints and foreground-dependent torrent tests remain exclusive:
separate build directories do not isolate `generated_config.cmake`. More
workers are not automatically faster; use measured total wall time and memory.
The combined desktop runner is the full CI/release path.

## Waiting correctly

Use `waitForE2ECondition` or the file-row/menu helpers for observable async
results. They return immediately when ready and poll short frames up to a
deadline. The helper bounds real and fake time so widget regressions terminate
without consuming real seconds.

`settleE2EUi` is only for finite UI animations: 50 ms frame interval, bounded
timeout, and errors propagate. `pumpAndSettle(Duration(seconds: 5))` sets a
five-second **pump interval**, not a timeout. Do not use global settling for a
playing video, spinner, directory I/O or model inference. Do not catch a settle
timeout and silently treat it as success. A screenshot captures the asserted
state without waiting for the entire app to become idle.

Observation windows that are themselves under test (playback position changes,
tooltip delay, accessibility churn, debounce and SQLite busy timeout) remain
intentional; do not mechanically shorten them.

## Diagnostics and timing

- Full unit/widget events: `build/unit_test_report.jsonl`; failure-only console
  summary: `dart tool/unit_test_failures.dart <report>`.
- `just test-times` reads the existing unit report and prints the slowest ten
  executed tests. It also writes `<report>.timings.json`, excluding loading/build.
  Pass another report with `just test-times build/e2e-logs/desktop.jsonl`.
- Desktop E2E: `build/e2e-logs/desktop.jsonl`, `desktop.log`, per-suite `.log`
  and `summary.json`. The summary distinguishes per-suite executed test time
  from total build/startup/test wall time and time until the first test.
- Debugging runners: `build/e2e_workers/`, `build/e2e_report.jsonl` and the
  HTML dashboard at `build/e2e_dashboard/index.html`.

The desktop runner also updates `build/e2e_report.jsonl`; `just dashboard`
regenerates the HTML before opening it. Dashboard history merges partial reruns
without duplicating old unprefixed test identities. Allure consumes actual error,
skip and terminal events, uses event timestamps, and removes only its generated
result JSON files from the previous conversion. Skipped or incomplete cases are
never relabeled as passed. [Measured improvement](04-test-performance.md).

Keep the build cache. `flutter clean` / `just deep-clean` are recovery tools,
not routine test preparation. Enable full action screenshots or full production
startup only when those are the subject of the investigation (`--full-screenshots`,
`--full-startup` in debugging runners). Fast startup remains the default E2E mode.

## CI and release

CI selects suites from changed paths with ordered rules. `main` and explicit
full-run requests select the complete gate; other branches select affected
suites. Existing trusted pass records only apply to the same source fingerprint,
including both native packages, the pinned build configuration, test harness and runtime fetch scripts.

The release gate still requires a clean working tree and every suite to pass
before creating a version commit/tag. Pending suites run in one batch; completed
suite passes are retained when another suite fails. It does not silently skip
coverage to make releases faster. `just release-e2e --status` only displays the
record for the current source. No release command is needed to verify edits.

When adding a suite, update the combined entrypoint, suite/impact catalog,
parallel debugger mapping and selector/planner tests. Add assertions at the
lowest useful layer before expanding costly full-app scenarios.

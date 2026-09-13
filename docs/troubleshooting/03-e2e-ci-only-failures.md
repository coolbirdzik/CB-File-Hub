# E2E: Tests Pass Locally But Fail on GitHub Actions CI

## Symptoms

- `just e2e` / `flutter test integration_test/...` is green on a dev machine.
- The same test file fails on `windows-latest` in GitHub Actions — often a
  different subset of tests each run, or a UI assertion failing with
  `Expected: true / Actual: <false>` on a row/widget that "should" be there.
- The failure is not reproducible by re-running the same test locally.

## Why this happens

A GitHub-hosted Windows runner is not a smaller version of a dev machine —
it differs in ways that specifically defeat assumptions this test suite used
to make:

| Local dev machine | GitHub Actions `windows-latest` runner |
|---|---|
| Many CPU cores, dedicated, warm caches | ~2 shared vCPUs, cold start every run |
| Real audio hardware | **No audio device** |
| Short username (e.g. `ngtan`) | Long username (`RUNNER~1`), longer temp paths |
| Fast local NVMe | Virtualized disk I/O |

None of these are bugs in the CI setup — they are the actual conditions the
shipped app has to tolerate on some real users' machines too. Treat a
CI-only failure as a real bug report, not noise to route around.

Three concrete bug classes have hit this suite so far. All three passed
locally every time and only ever failed on CI:

### 1. Blind assertion right after an async operation

**Symptom:** `expectFileRowVisible(path)` (or `...Absent`) fails immediately
after a copy/paste/rename/delete/move, with `gridCount=0 listCount=0`.

**Cause:** `tester.pumpAndSettle(Duration(seconds: N))` returns once no more
*frames* are scheduled. It does **not** wait for real async I/O with no
frame in between — directory watcher callbacks, cache invalidation, a
filesystem scan. On a slower/busier CI runner, that I/O routinely takes
longer than it does locally, so the assertion runs before the UI has caught
up.

**Fix:** never assert visibility/absence immediately after an operation that
changes the filesystem. Poll instead, using the helpers in
`integration_test/e2e_keys.dart`:

```dart
// Wrong — races the directory watcher/cache refresh:
await et.tapContextMenuItem('paste', detail: 'paste');
expectFileRowVisible(pastedPath);

// Right — polls up to 10s, then asserts with the same failure message:
await et.tapContextMenuItem('paste', detail: 'paste');
await waitForFileRowVisible(tester, pastedPath);
```

Available helpers: `waitForFileRowVisible`, `waitForFolderRowVisible`,
`waitForFileRowAbsent`, and the generic `pumpUntilFound(tester, finder)` for
anything else (dialogs, submenus, text fields that mount asynchronously).
`expectFileRowVisible`/`expectFileRowAbsent` (no polling) are still fine for
a check that has nothing async to wait for — e.g. right after startup into a
directory that was never touched, or asserting a no-op stayed a no-op.

### 2. Text measured with the wrong font underestimates width

**Symptom:** `A RenderFlex overflowed by N pixels on the right` inside
`BreadcrumbAddressBar`, only on CI, only on deep paths. `N` scaled with path
depth (seen from <1px up to 32px).

**Cause:** [breadcrumb_address_bar.dart](../../cb_file_manager/lib/ui/components/common/breadcrumb_address_bar.dart)
decides whether to switch to a squeeze/`Flexible` layout by estimating the
natural width of the breadcrumb with a manual `TextPainter`. That painter's
`TextStyle` didn't set `fontFamily`, so it measured against Flutter's
built-in default font, while the real chips render with the app's actual
theme font (`Inter` by default, or any of 6 user-selectable fonts). The
under-count compounds per character and per segment. CI's `RUNNER~1`
username produces a longer temp path than a typical local username, so CI
was consistently the one to cross the threshold into an actual overflow.

**Fix:** any manual `TextPainter`/width-estimation code must measure with
the **same font the real widget will render with** — read it from
`DefaultTextStyle.of(context).style.fontFamily` (or the equivalent themed
style), never a bare `TextStyle(fontSize: ...)`. Add a small defensive
margin on top regardless — text shaping still varies a few px across
platforms even with a matched font, and an overflow here is a hard test/UI
failure, not a cosmetic nit.

Regression test:
[breadcrumb_address_bar_overflow_e2e_test.dart](../../cb_file_manager/integration_test/breadcrumb_address_bar_overflow_e2e_test.dart)
reproduces the exact CI path/width and must run as an **integration test**,
not a plain `flutter test` widget test — headless widget tests don't
actually differentiate font families during text layout, so a widget test
version of this same check silently passes even against the unfixed code.

### 3. Assuming hardware the CI runner doesn't have

**Symptom:** `media_kit_playback_e2e_test.dart` tests fail with `Could not
open/initialize audio device -> no sound.` reaching `player.stream.error`,
which then fails an `expect(errors, isEmpty)` — or, for tests that go
through the full `VideoPlayer` widget, the player silently switches to an
error screen and controls (sliders, `mk.Video`) disappear from the tree.

**Cause:** GitHub Actions Windows runners have no sound card. `libmpv` logs
this as a player error, but video decode/playback is completely unaffected
— confirmed by forcing the same error locally (`audio-device` set to a
nonexistent WASAPI device) and observing `playing=true` with position
advancing normally. The bug was
[video_player.dart](../../cb_file_manager/lib/ui/components/video/video_player/video_player.dart)
treating *any* player error as fatal and swapping in an error widget.

**Fix:** don't assume standard peripherals (audio device, a particular
display resolution/DPI, a GPU with hardware decode) are present. Classify
player errors before treating them as fatal — see `_isAudioDeviceError` next
to the existing `_isHardwareDecodeError` in `video_player.dart` for the
pattern. Tests that listen to `player.stream.error` directly (bypassing the
widget) need the same filter — see `isBenignAudioDeviceError` in
`media_kit_playback_e2e_test.dart`.

## Rules for writing new E2E tests

1. **Never assert on filesystem/UI state immediately after an operation
   that triggers async work** (copy, cut, paste, rename, delete, move,
   navigate, search, submenu open). Use `waitForFileRowVisible` /
   `waitForFolderRowVisible` / `waitForFileRowAbsent` / `pumpUntilFound`.
   A blind `expect*` is fine only when nothing async could still be
   in flight — e.g. checking a freshly-created, never-touched directory
   right after startup.
2. **Don't hardcode a `TextStyle`/`TextPainter` for width math.** Pull the
   font family from the real ambient style the widget renders with. Add a
   margin of safety on top.
3. **Don't assume the CI runner has real hardware.** No audio device, no
   guaranteed GPU acceleration path, a different default window size/DPI
   than a physical monitor. Player/decoder errors need to be classified
   (benign vs. fatal) rather than treated as uniformly fatal.
4. **A new `integration_test/*.dart` file is not covered by CI or `just
   e2e-parallel` until you wire it in.** Add it to: the `_kAllGroups` /
   `_testFileForGroup` map in `tool/e2e_parallel.dart`, the file list in
   `just e2e-list` (`justfile`), and a dedicated step (with `taskkill` before
   *and* after, matching the existing steps) in
   `.github/workflows/build-test.yml`. Flutter desktop `integration_test`
   cannot run multiple test files in one `flutter test integration_test`
   invocation — each file needs its own CI step.
5. **A width/layout/timing assumption that "obviously" holds locally is not
   verified until it has run on the actual CI runner at least once.** Prefer
   reproducing a suspected CI-only failure with a **precise, minimal repro**
   (exact width/path/error string from the CI log) over guessing — see the
   breadcrumb and audio fixes above for the pattern: force the exact
   condition locally, confirm the unfixed code fails the same way, confirm
   the fix passes, only then consider it resolved.
6. **When a test fails with `Test failed. See exception logs above.` and
   nothing else,** that's flutter_test's own placeholder for an uncaught
   `FlutterError` (e.g. a `RenderFlex` overflow) — it is not a
   `expect()` failure. `tool/e2e_summarize_failures.dart` recovers the real
   `EXCEPTION CAUGHT BY ...` text from the test's print stream automatically;
   if you're reading a raw log by hand, search for that string near the
   failing test's `testID` instead of trusting the "error" field.

## Verification Checklist

- `flutter analyze` and `dart format --output=none --set-exit-if-changed .`
  are clean.
- The specific test(s) pass locally with `flutter test
  integration_test/<file>.dart -d windows --plain-name "<test name>"`.
- For a suspected CI-only race/environment issue, reproduce the exact
  reported condition (error string, width, path) locally first — a fix that
  "should" work without a confirmed local repro of the failure is a guess.
- New `integration_test/*.dart` files are wired into `tool/e2e_parallel.dart`,
  `justfile`, and `.github/workflows/build-test.yml` (see rule 4).

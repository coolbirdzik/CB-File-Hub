# E2E desktop (integration_test)

End-to-end smoke tests for **cb_file_manager** on **Windows desktop** use Flutter's official [`integration_test`](https://docs.flutter.dev/testing/integration-tests) package. Tests run a **real** desktop build (`-d windows`), not a mocked widget tree.

## Prerequisites

- **Windows** + Flutter desktop enabled.
- Build must succeed (`flutter` can compile `windows/`).
- SQLite on Windows: `pubspec.yaml` configures `package:sqlite3` to use **system** `winsqlite3` via `hooks.user_defines` so `sqlite3.dll` does not need to sit next to the test executable (avoids load error 126 during Debug runs).

## How to run

### Quick start (parallel — recommended)

Runs all 11 test groups in parallel, then auto-opens the HTML dashboard:

```bash
cd cb_file_manager
dart run tool/e2e_parallel.dart
```

**Options:**

```bash
# Limit concurrency (default = CPU cores)
dart run tool/e2e_parallel.dart --max-parallel 2

# Run only one group
dart run tool/e2e_parallel.dart --plain-name "Navigation"

# Run a specific test file directly (bypasses parallel workers, runs file only)
dart run tool/e2e_parallel.dart --file video_thumbnails_e2e_test

# Run a specific test file + group filter inside that file
dart run tool/e2e_parallel.dart --file video_thumbnails_e2e_test --plain-name "Video Thumbnails"

# Skip dashboard generation
dart run tool/e2e_parallel.dart --no-generate

# Rerun only previously failed tests
dart run tool/e2e_parallel.dart --rerun-failed
```

### Using Makefile

From repo root:

```bash
# Run all E2E tests in parallel with HTML dashboard
make dev-test mode=e2e

# Rerun only previously failed tests
make dev-test mode=e2e RERUN=1

# Run only specific suite (by group name, e.g. Navigation, Video Thumbnails)
make dev-test mode=e2e TEST="Video Thumbnails"
make dev-test mode=e2e TEST=Navigation

# Run a specific test file directly (runs only tests in that file)
make dev-test mode=e2e TEST_FILE=video_thumbnails_e2e_test

# Clean build if CMake/MSBuild issues
make dev-test-e2e-clean
```

**Environment variables:**

- `E2E_DEVICE=linux` — Run on Linux desktop (default: windows)
- `TEST_REPORTER=json` — JSON output instead of expanded
- `RERUN=1` — Rerun failed tests only
- `TEST=GroupName` — Run specific test group

## Code layout

| Piece | Role |
|--------|------|
| `lib/e2e/cb_e2e_config.dart` | `kCbE2E` (`bool.fromEnvironment('CB_E2E')`), `CbE2EConfig.startupPayload` for opening a temp folder tab. |
| `lib/main.dart` → `runCbFileApp()` | Shared entry with production `main()`; when `CB_E2E` is true, skips theme onboarding noise, disables "remember workspace", skips maximize, applies startup payload. |
| `integration_test/*.dart` | Calls `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`, sets `CbE2EConfig`, `await runCbFileApp()`, then `find`/`expect`. |
| `integration_test/e2e_keys.dart` | Helpers that match **grid or list** row keys (desktop often restores **grid** from prefs: `file-grid-item-*` / `folder-grid-item-*` vs list `file-item-*` / `folder-item-*`). |

**You must pass** `--dart-define=CB_E2E=true` so startup payload and E2E-only behavior are honored.

## Reading the log (pass / fail / which case)

Flutter's test runner prints **one line per test** when using **`--reporter expanded`** (default in the repo Makefile via `TEST_REPORTER=expanded`).

| Output | Meaning |
|--------|---------|
| `+N` / `-M` in the progress prefix | **N** tests passed, **M** failed so far. |
| Test name string (from `testWidgets('…')`) | The **current** test / case name. |
| `[E]` after a name | That test **errored** (failure). |
| Final `All tests passed!` + exit code **0** | Full run **passed**. |
| `Some tests failed.` / non-zero exit | At least one test **failed**. |

### Which tests failed? (clear list)

`make dev-test-e2e` runs `dart run tool/run_e2e_with_log.dart`, which streams `flutter test` to the console **and** to `cb_file_manager/build/e2e_last_run.log`. On failure it runs `tool/e2e_summarize_failures.dart` and prints a **boxed list** of failed test descriptions (from expanded ` [E]` lines and/or JSON events). This path works on **Windows** (PowerShell/cmd) without bash.

Manual checks:

- **Grep**: search the log for ` [E]` (expanded reporter marks failures).
- **JSON artifact**: `make dev-test-e2e-json` writes `build/e2e_report.jsonl` (Flutter `--reporter json`) for `jq`, spreadsheets, or CI uploads.
- **IDE**: open `integration_test/app_e2e_test.dart` and use **Run / Debug** on a `testWidgets` — the Testing panel shows pass/fail per case.

There is **no built-in HTML dashboard** in Flutter's CLI; use JSON + your own viewer, or the IDE Testing UI.

### HTML Dashboard (parallel runner)

When using `dart run tool/e2e_parallel.dart`, an HTML dashboard is auto-generated at:

```
build/e2e_dashboard/index.html
```

Features:
- **Pass/fail summary** with pass rate bar
- **Filter buttons**: All / Passed / Failed
- **Collapsible groups** by test suite
- **Failure details** with screenshots
- **Auto-opens** in browser (use `--no-open` to skip)

Worker logs are saved to `build/e2e_workers/` for debugging individual group failures.

Verbose engine logs:

```bash
cd cb_file_manager
flutter test integration_test -d windows --dart-define=CB_E2E=true --reporter expanded -v
```

## CI

The root workflow runs **Windows E2E** after analysis:

`flutter test integration_test -d windows --dart-define=CB_E2E=true`

See `.github/workflows/build-test.yml` (job `e2e-windows`).

## Test groups

Tests are organized into **12 groups** (44 total). Run individual groups with `--plain-name "Group Name"`.

| Group | Tests | Description |
|-------|-------|-------------|
| **Navigation** | 4 | Sandbox listing, subfolder navigation, empty state, Backspace navigation |
| **File Operations** | 4 | Create folder, copy/paste, F2 rename, Delete key delete |
| **Cut & Move** | 2 | Cut via context menu, Cut via Ctrl+X |
| **Folder Operations** | 2 | Copy folder, Delete folder via keyboard |
| **Multi-Select** | 2 | Batch copy with Ctrl+click, Select all + batch delete |
| **Keyboard Shortcuts** | 3 | F5 refresh, Escape cancel, Enter key |
| **Search & Filter** | 2 | Search box, Clear search |
| **View Mode** | 3 | Grid/list toggle, File operations in grid view |
| **Tab Management** | 3 | Ctrl+T new tab, Ctrl+W close tab, Ctrl+Tab switch tabs |
| **Edge Cases & Error Handling** | 4 | Cancel delete dialog, Empty name rename, Paste nothing, Missing folder nav |
| **Extended File Operations** | 5 | Create new file, Context menu rename, Batch move, Deep copy folder, Rename folder |
| **Video Thumbnails** | 10 | Video file display, context menu, multi-format, refresh, rename, delete, play, row type, unsupported extension |

## Test files

E2E tests live in `cb_file_manager/integration_test/`. Each test file is a self-contained `main()` that can be run independently with `--file`.

| File | Groups | Description |
|------|--------|-------------|
| `app_e2e_test.dart` | 11 groups | Main test file — Navigation, File Operations, Cut & Move, Folder Operations, Multi-Select, Keyboard Shortcuts, Search & Filter, View Mode, Tab Management, Edge Cases, Extended File Operations |
| `video_thumbnails_e2e_test.dart` | 1 group | Video thumbnail tests — uses real sample at `integration_test/samples/file_example_MP4_1920_18MG.mp4` if available, falls back to stub files |
| `e2e_helpers.dart` | — | Shared helpers: `E2ETester`, `e2eTearDown`, screenshot capture, `et.enterText()` |
| `e2e_keys.dart` | — | Row matchers that work in **grid or list**: `expectFileRowVisible`, `tapFolderRow`, `rightClickFileRow`, `tapContextMenuItem`, `sendKeyboardShortcut`, `openBackgroundContextMenu`, etc. |
| `e2e_report.dart` | — | HTML report generator + `e2e_summarize_failures.dart` runner script |
| **Video Thumbnails** | 10 | Video file display, context menu, multi-format, refresh, rename, delete, play, row type, unsupported extension |

## Tests in `integration_test/app_e2e_test.dart`

### Navigation

| `testWidgets` name | What it checks |
|--------------------|----------------|
| `sandbox lists two files and a subfolder` | Temp dir with `a.txt`, `b.txt`, and one subfolder; asserts file/folder rows via grid **or** list keys (`expectFileRowVisible` / `expectFolderRowVisible`). |
| `open subfolder shows file inside` | Temp dir with `root.txt`, subfolder `innerdir/`, and `innerdir/nested.txt`; **double-taps** the folder row (desktop: single tap only selects), then expects the nested file row. |
| `empty sandbox has no file or folder rows` | Empty temp dir; expects no list **or** grid row widgets (`FileItem` / `FolderItem` / `FileGridItem` / `FolderGridItem`). |
| `navigate back to parent with Backspace after entering subfolder` | Navigate into subfolder, then press Backspace key to return to parent. |

### File Operations

| `testWidgets` name | What it checks |
|--------------------|----------------|
| `create new folder via right-click context menu` | Right-click background → New Folder → type name → expect folder row. |
| `copy file via right-click context menu and paste` | Copy file, navigate to dest folder, paste, expect file there. |
| `rename file via F2 keyboard shortcut` | Select file → F2 → type new name → expect renamed file row. |
| `delete file via keyboard shortcut` | Select file → Delete key → confirm dialog → expect file gone. |

### Cut & Move

| `testWidgets` name | What it checks |
|--------------------|----------------|
| `cut and move file via right-click context menu` | Cut via menu, navigate, paste, expect file moved (source deleted). |
| `cut and move file via Ctrl+X Ctrl+V keyboard shortcuts` | Same as above but with keyboard shortcuts. |

### Keyboard Shortcuts (extended)

| `testWidgets` name | What it checks |
|--------------------|----------------|
| `refresh folder listing with F5 after external change` | Create file externally → F5 → expect file appears in UI. |
| `cancel rename with Escape key after pressing F2` | F2 to start rename → Escape → expect original name unchanged. |
| `open file with Enter key when file is selected` | Select file → Enter key → verify no crash. |

### Extended File Operations

| `testWidgets` name | What it checks |
|--------------------|----------------|
| `batch move multiple files to destination folder` | Ctrl+select multiple files → Ctrl+X → navigate → Ctrl+V. |
| `copy folder with nested contents to another location` | Copy folder with nested subfolders, verify structure preserved. |
| `rename folder via F2 keyboard shortcut` | Select folder → F2 → rename → verify folder renamed. |

### Video Thumbnails

> **File:** `video_thumbnails_e2e_test.dart` — runs as a **separate test file** via `--file video_thumbnails_e2e_test`.

| `testWidgets` name | What it checks |
|--------------------|----------------|
| `video file row is visible and has correct file type` | `.mp4` row appears alongside text file; `assertFileRowExists`. |
| `video context menu shows Play video action (grid view)` | Right-click `.mp4` → "Play video" appears in context menu. |
| `video context menu shows Play video action (list view)` | Same as above, in list view mode. |
| `multiple video formats display correctly in same folder` | `.mp4`, `.avi`, `.mkv`, `.mov` all visible as rows. |
| `video files persist after folder refresh (F5)` | Video row stays visible after F5 refresh. |
| `deleting a video file removes it from the list` | Delete `.mp4` → row gone from UI, file deleted from disk. |
| `video file can be renamed via context menu` | Rename → new name visible, old name gone. |
| `opening a video via context menu does not crash app` | Tapping "Play video" → app does not crash, rows remain accessible. |
| `video file row is FileItem not FolderItem` | Video row is `FileItem`/`FileGridItem`, not folder type. |
| `unsupported video extension does not show Play video action` | `.abc` extension → "Play video" absent from context menu. |

**Sample video:** `integration_test/samples/file_example_MP4_1920_18MG.mp4` (18 MB). The test copies it into a temp sandbox for real thumbnail generation tests. If the sample is missing, it falls back to a minimal MP4 stub (sufficient for UI structure tests — app detects video by extension).

Between tests, `_e2eTearDown` pumps briefly, then `tearDownCbFileAppForNextE2ETest()` resets `DatabaseManager`'s singleton and `GetIt.reset(dispose: true)` (shared SQLite file stays open to avoid `database_closed` races), then deletes the temp sandbox directory after the app has dropped watchers on that path.

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| `make dev-test mode=e2e --file ...` fails | Use `TEST_FILE=filename` instead: `make dev-test mode=e2e TEST_FILE=video_thumbnails_e2e_test`. The `--file` flag is not a make argument. |
| MSB3073 / `cmake_install` / `INSTALL.vcxproj` | `make dev-test-e2e-clean`, or delete `cb_file_manager/build/windows` and rebuild. |
| `sqlite3.dll` / FFI load error 126 | Ensure `hooks.user_defines` for `sqlite3` (`source: system`, `name_windows: winsqlite3`) is present in `pubspec.yaml`; run `flutter pub get`. |
| Flaky `pumpAndSettle` | Timeouts are long on purpose; heavy first build can take minutes. |
| `Found 0 widgets` for `file-item-*` / `folder-item-*` | View may be **grid**; use `file-grid-item-*` / `folder-grid-item-*` or helpers in `integration_test/e2e_keys.dart`. |
| `DatabaseException(error database_closed)` between cases | Avoid closing the shared SQLite handle while the next `runCbFileApp` boots; E2E teardown resets `DatabaseManager` + `GetIt` only (see `lib/e2e/cb_e2e_config.dart`). |

## Related

- `docs/quality/01-testing-strategy.md` — high-level testing pyramid.
- `Makefile` — `help` lists `TEST_REPORTER`, `E2E_DEVICE`, and developer test targets.

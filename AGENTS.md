# AGENTS.md — CB File Hub

## Project layout

This is **not** a standard single-package Flutter app. The repo root is a workspace with three packages and a build system:

```
cb_file_manager/   ← main Flutter app (all flutter/dart commands run here)
mobile_smb_native/ ← local FFI plugin (SMB/CIFS via libsmb2, path dependency)
cb_native/         ← Rust helpers via a Dart build hook (path dependency, optional)
justfile           ← primary build orchestrator (uses `just` command runner, requires Git Bash on Windows)
scripts/           ← build, version, and CI helper scripts (bash)
installer/         ← Windows installer configs (Inno Setup, WiX)
```

The `cb_file_manager/windows/llama/` directory holds the bundled llama.cpp
runtime (Vulkan DLLs + `llama-server.exe`, ~69MB). These binaries are **not
committed to git** — they are downloaded at build time (see Local AI runtime
below).

**All `flutter` and `dart` commands must be run from `cb_file_manager/`**, not the repo root.

## Flutter version

Pinned to **3.47.8 stable** (`build.config`, CI workflows). Use this exact version.

## Developer commands

Run from repo root via `just` (requires Git Bash on Windows):

| Task                     | Command                                             |
| ------------------------ | --------------------------------------------------- |
| Show all recipes         | `just`                                              |
| Install deps             | `just deps`                                         |
| Fetch llama.cpp runtime  | `just fetch-llama`                                  |
| Fetch aria2 torrent runtime | `just fetch-aria2`                               |
| Run macOS dev build      | `just macos-dev` (own permissions + hot reload)     |
| Unit/widget tests        | `just test`                                         |
| E2E tests (parallel)     | `just e2e-parallel`                                 |
| E2E single suite         | `just e2e Navigation`                               |
| E2E single test by name  | `just e2e "navigate back to parent with Backspace"` |
| E2E single file          | `just e2e-file video_thumbnails_e2e_test`           |
| Rerun failed E2E only    | `just e2e-failed`                                   |
| E2E plain output (debug) | `just e2e-plain`                                    |
| E2E serial (debug order) | `just e2e-serial`                                   |
| List all E2E test names  | `just e2e-list`                                     |
| CI format, analysis, unit/widget tests | `just analyze`                            |
| Static analysis only     | `just lint`                                         |
| Format                   | `just format`                                       |
| Format + analyze         | `just verify`                                       |
| Clean                    | `just clean`                                        |
| Deep clean (rebuild)     | `just deep-clean` then `just deps`                  |
| Kill stray E2E processes | `just kill-e2e`                                     |
| Open dashboard           | `just dashboard`                                    |

### E2E execution policy

Do **not** run any E2E test command unless the user explicitly authorizes it in the current request. This includes `just e2e`, `just e2e-parallel`, `just e2e-serial`, `just e2e-plain`, `just e2e-failed`, `just e2e-file`, direct `flutter test integration_test ...` commands, and any equivalent E2E runner. Unit/widget tests, analysis, formatting, and builds may still be run when appropriate.

E2E parallel defaults to half the CPU cores (clamped 2..6). Override via:

- `just e2e-parallel "" 4` (positional arg)
- `CB_E2E_MAX_PARALLEL=4 just e2e-parallel` (env var)

Or run Flutter directly from `cb_file_manager/`:

```bash
flutter pub get
flutter test                           # unit/widget tests
flutter test --reporter expanded       # verbose test output
flutter analyze
dart format --output=none --set-exit-if-changed .   # format check (CI uses this)
flutter test integration_test -d windows --dart-define=CB_E2E=true  # E2E
```

## CI pipeline order

CI runs: **format check -> analyze -> unit tests -> E2E (Windows) -> build**.
Windows E2E is selective: `scripts/ci/e2e_select.mjs` maps changed paths to
suites via `cb_file_manager/integration_test/e2e_impact.json` (`main` always runs
every suite) and skips suites already passed on identical source. Preview with
`just e2e-affected`; keep `e2e_impact.json` in sync when adding E2E files or new
`lib/` areas (see `docs/quality/02-e2e-desktop-integration.md`).
Run `just analyze` before pushing to match the CI analyze job (including
unit/widget tests, excluding E2E). Both use `scripts/check_quality.sh` and stop
on the first failure. Their unit/widget step prints only failed tests (error,
stack and that test's own output, via `cb_file_manager/tool/unit_test_failures.dart`);
the full event stream is in `cb_file_manager/build/unit_test_report.jsonl`. Use
`just test` for the per-test expanded log. `just verify` runs only format check and static analysis;
`just lint` runs only static analysis. Local checks use the host OS; the CI
analyze job runs on Ubuntu, so platform-specific failures still need a Linux run.

## Architecture notes

- **State management:** BLoC (`flutter_bloc`) + Provider + GetIt (service locator in `lib/core/service_locator.dart`)
- **Design system:** Fluent UI on desktop, Material on mobile. Controlled by `DesignSystemConfig` feature flags. The app can run as either `FluentApp` or `MaterialApp`.
- **Localization:** Custom delegate-based (Vietnamese + English) in `lib/config/languages/`. Does **not** use Flutter's `gen-l10n` / ARB files.
- **Navigation:** Tab-based via `TabMainScreen` (`lib/ui/tab_manager/`), not standard Flutter routing.
- **Database:** SQLite via `sqflite` / `sqflite_common_ffi`. On Windows, uses system `winsqlite3.dll` (no bundled DLL).
- **Video:** shared media_kit backend (`lib/services/media/media_kit_playback.dart`), using `media_kit` 1.2.6, `media_kit_video` 2.0.1 and `media_kit_libs_video` 1.0.7. See `docs/technical/07-media-kit-playback.md`.
- **Streaming:** Built-in HTTP media server via `shelf` (`lib/services/streaming/`).
- **Network browsing:** SMB/CIFS via local `mobile_smb_native` FFI plugin, plus FTP support.
- **Windows native:** Uses `win32` FFI, acrylic backdrop, native tab drag-drop, PiP windowing.
- **Torrent library:** `lib/services/torrent/` indexes metainfo in the shared SQLite DB; `#torrents` supports index/copy/move storage modes and per-torrent payload destinations. aria2 runs as an authenticated loopback subprocess. Windows builds bundle its pinned runtime from `windows/aria2/` (git-ignored); run `just fetch-aria2` before direct Flutter Windows builds on a clean checkout. Other desktop platforms use an installed or user-selected aria2c. See `docs/features/10-torrent-library.md`.

## Feature flags (compile-time)

Passed via `--dart-define=FLAG=value`:

- `CB_E2E=true` — enables E2E test mode (required for integration tests)
- `CB_SHOW_DEV_OVERLAY=true` — shows developer debug overlay
- `CB_ENABLE_FLUENT_DESKTOP_SHELL` — Fluent UI shell toggle

Cloud Backup & Sync OAuth client ids come from a git-ignored `.env` in the repo
root (template: `.env.example`). `scripts/build.sh` loads it, and the `just`
recipes that call flutter directly pass `--dart-define-from-file`. Missing keys
just mark that provider unavailable — builds never fail over them. See
`docs/features/08-cloud-backup-sync.md`.

## Key conventions

- **`avoid_print` is disabled** in `analysis_options.yaml` — `print()` is intentionally used in dev/debug code.
- **`main.dart` is 900+ lines** — contains app initialization, window setup, service bootstrap, and the root widget. It is the real wiring diagram of the app.
- **No code generation** — `build_runner` is a dev dependency (for MSIX packaging) but there is no `build.yaml` and no generated Dart code to worry about.
- **Entry point for tests:** unit/widget tests in `cb_file_manager/test/`, E2E in `cb_file_manager/integration_test/`. E2E tooling (parallel runner, Allure adapter, dashboard) lives in `cb_file_manager/tool/`.

## Local AI runtime (llama.cpp)

CB Agent can run local GGUF models on-device via a bundled llama.cpp runtime.

- **Subprocess, not FFI:** the app launches the official `llama-server.exe` as a
  separate OS process and talks to it over HTTP (`lib/services/local_ai/gguf_llama_cpp_runtime.dart`).
  Calling llama.cpp through FFI inside a Dart isolate crashed during GPU tensor
  upload, so the subprocess model is used instead.
- **Binaries are not in git:** the runtime (Vulkan DLLs + `llama-server.exe`,
  ~69MB) lives in `cb_file_manager/windows/llama/`, which is git-ignored. It is
  downloaded at build time by `scripts/fetch_llama_runtime.sh` (pinned to
  llama.cpp release `b10809`, `win-vulkan-x64`). The script verifies SHA-256 and
  skips only when all files and the version marker match (`--force` to redownload).
- **Fetch before building:** every Windows build path runs the fetch script
  first — `scripts/build.sh` (release), the `build-windows` and `e2e-windows` CI
  jobs, and the `just windows` recipe (`just fetch-llama`). If you run
  `flutter build windows` or `flutter run -d windows` directly on a clean
  checkout, run `just fetch-llama` (or `bash scripts/fetch_llama_runtime.sh`)
  once first, or CMake's INSTALL step fails with a missing-file error.
- **Subfolder isolation (`vulkan-1.dll`):** CMake installs the runtime into a
  `llama/` subfolder next to the app exe, not the app root. The app bundle ships
  Flutter's own `vulkan-1.dll` (ANGLE/media_kit) whose ABI differs from the
  system Vulkan loader; since Windows prefers a DLL next to the launched exe,
  launching `llama-server.exe` from the app root loads that `vulkan-1.dll` and
  segfaults (`0xC0000005`) inside `ggml-vulkan`. The subfolder has no
  `vulkan-1.dll`, so the loader falls back to the real System32 loader.
- **Orphan protection:** the server is attached to a Windows Job Object with
  `KILL_ON_JOB_CLOSE` (`lib/services/local_ai/windows_process_reaper.dart`), so
  the OS reaps it if the app dies for any reason. `dispose()` handles the
  graceful path (model/context change).

## Rust native helpers (cb_native)

`cb_native/` holds a Rust crate (`rust/`) that `hook/build.dart` compiles with
`cargo build --release --locked` and bundles as a code asset on every
`flutter build`/`run`/`test`. Everything runs on Rust threads, never on the
calling isolate:

- the recursive file-name search (`FileNavigationBloc._nativeRecursiveSearch`);
- the Disk Cleaner's full-disk scan (`nativeScanInto` in
  `lib/services/disk_cleaner/full_disk_scan_isolate.dart`). Rust does the
  per-directory work of the Dart `scanInto` (sizes, junk rules, file folding,
  old-large files) and streams one record per directory; the scan isolate only
  builds `DiskTreeNode`s, so progress, previews, incremental refresh and final
  batching are unchanged. `useNativeScanner: false` forces the Dart walker;
  `test/services/disk_cleaner/native_full_disk_scan_test.dart` checks both
  produce the same result. Rust also reads paths longer than 260 characters,
  which the Dart walker reports as inaccessible, and returns each folder's
  NTFS file ID with the listing (`win_dir.rs`), so even cold scans can be
  refreshed from the USN Journal. A scan nobody polls for 15 s stops itself,
  because the Cleaner cancels by killing the isolate;
- **jobs** (`job.rs`, Dart `NativeJob`): everything else. A job posts its end
  state to a Dart port (dart_api_dl) so callers wake at once, and stops when
  that port's isolate is gone. Callers: folder sizes (`LazyPathSizeCalculator`,
  cache stats, Windows.old), the folder listing and tree view
  (`_scanDirectory`; `test/ui/screens/folder_list/native_directory_listing_test.dart`
  checks every sort against the Dart listing), filtered walks
  (`getAllImages`/`getAllVideos`, album scans, Downloads leftovers, Cleaner
  directory expansion), the junk-rule scan (`disk_cleaner_isolate.dart`),
  image thumbnails (photo, SMB/network; JPEGs decode at a reduced DCT scale),
  the editor's encode and inpaint (an exact port of `inpaint.dart`), SHA-256
  (`helpers/core/file_hash.dart`), and archives (`ArchiveService`: zip, tar,
  tar.gz/bz2/xz, gz, bz2 and 7z without 7-Zip; RAR still needs 7-Zip),
  and the CB Agent's `search_content`/`read_file` (`ContentSearch`,
  `content.rs` + `doctext.rs`: text, Office, EPUB, RTF and PDF through
  `pdf-extract`; cloud placeholders are never read).
  `test/services/local_ai/agent_content_search_test.dart` checks native and
  Dart return the same items and document text.
  Every caller keeps its Dart code as the fallback.

- Additional background jobs read image display dimensions from headers,
  transcode full-resolution images for crop/frame dialogs, validate batches of
  cached video paths, create ZIP backups/read selected ZIP members, parse
  torrent metainfo and hash its original `info` bytes, stream Recycle Bin
  metadata through four bounded readers, and read/deduplicate USN parent IDs
  before incremental refresh. `test/services/native_additional_jobs_test.dart`
  and `test/services/torrent/native_torrent_metainfo_test.dart` check the FFI
  paths against Dart. App storage attribution uses `PathRootSizeIndex` in Dart
  to avoid pairwise root comparisons without transferring the scan tree over
  FFI. Native jobs remain optional, and image/ZIP/torrent fallbacks run off the
  UI isolate too.

- Interactive jobs (`NativeUiJobs`, ABI 6) handle thumbnail cache eviction
  plans, prefix-limited directory suggestions, direct child counts and streamed
  Smart Album media scans. Regex album rules retain Dart's ECMAScript semantics
  in a cancellable isolate. Global tag searches and imports use batched native
  existence checks; imports commit bounded SQLite batches. Archive browsing
  caches a directory index for two archives, invalidated by file metadata, and
  returns only the requested children. Preview syntax is tokenized on Rust
  threads with pure-Rust syntect or a Dart isolate for unsupported grammars;
  bounded token caching lets theme changes reuse the result. Fallback/parity
  coverage lives in `test/services/native_ui_jobs_test.dart` and
  `test/models/database/tag_import_batch_test.dart`.

- **Optional by design:** if cargo, the rustup target or the build is missing,
  the hook prints `cb_native: ...` and bundles nothing; `CbNative.isAvailable`
  is then false and the Dart code runs. All crates are pure Rust, so cross
  builds need no C toolchain. Add a target with
  `rustup target add <triple>` (Android: `aarch64-linux-android`,
  `armv7-linux-androideabi`, `x86_64-linux-android`; CI Android jobs run
  `scripts/ci/setup_rust_android.sh` for this).
- **Matching must equal Dart:** the Rust port of `TextUtils.searchKey` uses
  tables generated from `package:diacritic` and Dart's `toLowerCase`
  (`cd cb_native && dart run tool/gen_fold_table.dart`, which also emits the
  upper-case table the junk rules use). Rerun it after a Dart
  SDK upgrade; `test/helpers/core/native_search_parity_test.dart` fails on drift.
- **Checks:** `cargo test --release` and `cargo clippy --release --all-targets`
  in `cb_native/rust/`, `dart test` in `cb_native/`. Compare speed with
  `dart run tool/bench_search.dart <root> <query>`.

## Windows build gotchas

- If Windows build fails with `MSB3073` / `cmake_install` / `INSTALL.vcxproj`: run `just e2e-clean` (or `just deep-clean` then `just deps`).
- If Windows build fails with a missing `windows/llama/*.dll` at the INSTALL step: run `just fetch-llama` (or `bash scripts/fetch_llama_runtime.sh`) to download the llama.cpp runtime.
- The `scripts/build.sh` auto-retries CMake race conditions and patches pdfx CMake compatibility.
- MSI builds require WiX Toolset. MSIX signing requires `MSIX_CERT_BASE64` and `MSIX_CERT_PASSWORD` secrets.

## Release workflow

- Version lives in `cb_file_manager/pubspec.yaml`. Use `just release-patch`, `just release-minor`, or `just release-major`.
- Tags matching `v*.*.*` trigger the release CI pipeline (GitHub Actions + GitLab CI).
- Build number is auto-incremented in CI.

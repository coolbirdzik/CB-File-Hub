# AGENTS.md — CB File Hub

## Project layout

This is **not** a standard single-package Flutter app. The repo root is a workspace with two packages and a build system:

```
cb_file_manager/   ← main Flutter app (all flutter/dart commands run here)
mobile_smb_native/ ← local FFI plugin (SMB/CIFS via libsmb2, path dependency)
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

Pinned to **3.41.5 stable** (`build.config`, CI workflows). Use this exact version.

## Developer commands

Run from repo root via `just` (requires Git Bash on Windows):

| Task | Command |
|------|---------|
| Show all recipes | `just` |
| Install deps | `just deps` |
| Fetch llama.cpp runtime | `just fetch-llama` |
| Unit/widget tests | `just test` |
| E2E tests (parallel) | `just e2e-parallel` |
| E2E single suite | `just e2e Navigation` |
| E2E single test by name | `just e2e "navigate back to parent with Backspace"` |
| E2E single file | `just e2e-file video_thumbnails_e2e_test` |
| Rerun failed E2E only | `just e2e-failed` |
| E2E plain output (debug) | `just e2e-plain` |
| E2E serial (debug order) | `just e2e-serial` |
| List all E2E test names | `just e2e-list` |
| Analyze | `just analyze` |
| Format | `just format` |
| Format + analyze | `just verify` |
| Clean | `just clean` |
| Deep clean (rebuild) | `just deep-clean` then `just deps` |
| Kill stray E2E processes | `just kill-e2e` |
| Open dashboard | `just dashboard` |

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

CI runs: **format check -> analyze -> unit tests -> E2E (Windows) -> build**. Match this locally with `just verify` before pushing.

## Architecture notes

- **State management:** BLoC (`flutter_bloc`) + Provider + GetIt (service locator in `lib/core/service_locator.dart`)
- **Design system:** Fluent UI on desktop, Material on mobile. Controlled by `DesignSystemConfig` feature flags. The app can run as either `FluentApp` or `MaterialApp`.
- **Localization:** Custom delegate-based (Vietnamese + English) in `lib/config/languages/`. Does **not** use Flutter's `gen-l10n` / ARB files.
- **Navigation:** Tab-based via `TabMainScreen` (`lib/ui/tab_manager/`), not standard Flutter routing.
- **Database:** SQLite via `sqflite` / `sqflite_common_ffi`. On Windows, uses system `winsqlite3.dll` (no bundled DLL).
- **Video:** `media_kit` (primary) + `flutter_vlc_player` (fallback).
- **Streaming:** Built-in HTTP media server via `shelf` (`lib/services/streaming/`).
- **Network browsing:** SMB/CIFS via local `mobile_smb_native` FFI plugin, plus FTP support.
- **Windows native:** Uses `win32` FFI, acrylic backdrop, native tab drag-drop, PiP windowing.

## Mandatory graph-first coding loop

For every source-code change, use the repository skill at
`.agents/skills/graph-first/SKILL.md`.

- Inspect the relevant graph and source read-only, then announce graph impact as
  `none` or `changed` before editing.
- For `changed`, present the graph delta and wait for explicit approval. After
  approval, update the canonical graph before source code.
- Implement and verify within the approved boundary. Ask again only if the graph
  boundary changes.
- Finish only when graph, code, and checks agree.

Analysis-only, review-only, diagnostics-only, and documentation-only tasks are
exempt from this loop.

## Feature flags (compile-time)

Passed via `--dart-define=FLAG=value`:

- `CB_E2E=true` — enables E2E test mode (required for integration tests)
- `CB_SHOW_DEV_OVERLAY=true` — shows developer debug overlay
- `CB_ENABLE_FLUENT_DESKTOP_SHELL` — Fluent UI shell toggle

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
  llama.cpp release `b9874`, `win-vulkan-x64`). The script is idempotent and
  skips the download when all files are already present (`--force` to redownload).
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

## Windows build gotchas

- If Windows build fails with `MSB3073` / `cmake_install` / `INSTALL.vcxproj`: run `just e2e-clean` (or `just deep-clean` then `just deps`).
- If Windows build fails with a missing `windows/llama/*.dll` at the INSTALL step: run `just fetch-llama` (or `bash scripts/fetch_llama_runtime.sh`) to download the llama.cpp runtime.
- The `scripts/build.sh` auto-retries CMake race conditions and patches pdfx CMake compatibility.
- MSI builds require WiX Toolset. MSIX signing requires `MSIX_CERT_BASE64` and `MSIX_CERT_PASSWORD` secrets.

## Release workflow

- Version lives in `cb_file_manager/pubspec.yaml`. Use `just release-patch`, `just release-minor`, or `just release-major`.
- Tags matching `v*.*.*` trigger the release CI pipeline (GitHub Actions + GitLab CI).
- Build number is auto-incremented in CI.

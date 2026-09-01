# Gotchas and Safe Extension

## Key gotchas

- **Startup source of truth:** verify active calls in `lib/main.dart`; do not
  assume similarly named helpers are wired into startup.
- **Tag systems:** `BatchTagManager`, `TagManager`, and the hierarchy cache must
  initialize after the database is ready.
- **Pane ownership:** menus and overlays outside a pane's widget subtree must
  receive the pane's BLoC explicitly.
- **Windows native contracts:** change Dart and C++ payloads together, register
  plugins in `flutter_window.cpp`, and include new sources in CMake.
- **Shell context menus:** native sessions and command IDs belong to the exact
  selected targets and Shift state; never cache them across targets or on disk.
- **Cleaner:** disk usage evidence is not deletion authorization. Preserve exact
  target selection and approval boundaries.
- **Local AI:** run `just fetch-llama` before a direct Windows build on a clean
  checkout. Keep `llama-server.exe` in its bundled subfolder and attached to the
  process reaper.
- **Windows build locks:** `LNK1168` commonly means a running executable owns
  the output. Do not terminate a user's application automatically; use a
  temporary target when practical.
- **Android VLC and SMB:** if playback starts without a rendered surface, check
  the Pigeon channel compatibility described in
  `docs/troubleshooting/02-android-smb-vlc-no-render.md`.

## Extending the application safely

- Update `docs/agent/feature-map.yaml` when a feature entry point, ownership
  boundary, native contract, or test boundary changes.
- Add localization keys to the abstract contract plus both English and
  Vietnamese implementations.
- Reuse the existing design system and operational UI for feature controls.
- Add or update focused tests, then verify in CI order in proportion to risk.
- Record architectural rationale as an ADR when the reason cannot be recovered
  from source alone.

_Last reviewed: 2026-08-08_

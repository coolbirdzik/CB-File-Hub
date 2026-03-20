# cb_file_manager

CB File Hub is a Flutter-based cross-platform file manager.

## Getting Started

```bash
flutter pub get
flutter run
```

## Developer Overlay

The floating developer overlay is opt-in and only available for non-release builds.

```bash
flutter run --dart-define=CB_SHOW_DEV_OVERLAY=true
```

- Without the flag, the overlay stays hidden.
- In production and release builds, the overlay never appears.
- Use a full restart after changing the flag.

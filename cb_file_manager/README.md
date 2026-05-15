# cb_file_manager

CB File Hub is a Flutter-based cross-platform file manager.

## AI File Agent

The app is positioned to support an AI-assisted file workflow for large libraries and messy folders.

- Search files and folders with natural-language requests.
- Create files and folders for repetitive setup tasks.
- Manage file operations such as rename, move, copy, delete, and batch cleanup.
- Find problematic files such as broken media, duplicates, missing thumbnails, or suspicious names.
- Sort and reorganize cluttered folders into a cleaner structure.

This keeps the AI feature focused on practical file management work instead of generic chat behavior.

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

## Screenshot Automation

From the repository root, generate showcase screenshots for the main app features on desktop and Android:

```powershell
./scripts/capture_screenshots.ps1 desktop
./scripts/capture_screenshots.ps1 android
./scripts/capture_screenshots.ps1 all
```

```bash
./scripts/capture_screenshots.sh desktop
./scripts/capture_screenshots.sh android
./scripts/capture_screenshots.sh all
```

# cb_file_manager

CB File Hub is an **ALL-IN-ONE file manager for Windows, macOS, Linux, and Android**, built with Flutter. Manage local and remote files, media, torrents, tags/albums, AI assistance, disk cleanup, and settings/tag backups in one app.

Full product descriptions and screenshots: [English](../README.md) · [Tiếng Việt](../README.vi.md).

## Feature Overview

- Manage a lazy-loaded torrent index with user-selected storage, client imports, duplicate merge confirmation, clipboard magnets, and destination/start controls for desktop downloads.
- Export settings/tag backups and connect available Google Drive, Dropbox, and OneDrive integrations.

- Browse local folders in tabs, pin common locations, manage tags and smart albums, and use dedicated image/video views.
- Connect to SMB, FTP, WebDAV, and SFTP locations; stream supported media and retain saved network credentials for quicker reconnects.
- Manage SSH hosts, keys, and trusted host fingerprints. Open a terminal for a saved host or browse it via SFTP, including in a new tab.
- Import OpenSSH / PEM private keys, generate keys, copy public keys, and discover eligible entries from the local `.ssh` directory.
- Browse supported archives as virtual folders and extract individual entries or the whole archive. ZIP/TAR-family formats are built in; 7z/RAR support on Windows uses an installed 7-Zip.
- Scan storage on Windows, macOS, and Android with Disk Cleaner and review cleanup candidates with CB Agent before removing them.
- Optionally use a compatible on-device model for local cleanup advice, with downloadable-model and context-window controls in Settings.

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

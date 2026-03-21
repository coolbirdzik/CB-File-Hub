# CB File Hub

[![Build and Test](https://github.com/coolbirdzik/cb-file-hub/actions/workflows/build-test.yml/badge.svg)](https://github.com/coolbirdzik/cb-file-hub/actions/workflows/build-test.yml)
[![Release](https://github.com/coolbirdzik/cb-file-hub/actions/workflows/release.yml/badge.svg)](https://github.com/coolbirdzik/cb-file-hub/actions/workflows/release.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

<p align="center">
  <img src="cb_file_manager/assets/images/logo_circle.png" alt="CB File Hub logo" width="180" />
</p>

CB File Hub is a cross-platform file manager focused on large personal media libraries. It is built for the situation where movies, photos, clips, and folders keep growing until finding the right thing to watch feels harder than watching it.

Instead of acting like a generic explorer, the app is designed to reduce browsing fatigue: faster visual scanning, tag-based organization, tabbed navigation on both desktop and mobile, network playback, and albums that can organize themselves with rules.

## Screenshots

<table>
  <tr>
    <td><img src="screenshots/window_main_light.png" alt="Windows library view" /></td>
    <td><img src="screenshots/window_add_tag.png" alt="Windows tag editor" /></td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/android_main.png" alt="Android home screen" width="260" /></td>
    <td align="center"><img src="screenshots/android_tab.png" alt="Android tabbed browsing" width="260" /></td>
  </tr>
</table>

## Why This App Exists

This project started from a very personal problem: a movie and photo collection that became too large to browse comfortably. File names were not enough, folder trees became noisy, and searching for something to watch or review took too much effort.

CB File Hub focuses on solving that workflow with a media-first file manager that helps you browse visually, organize flexibly, and jump back into your library without losing context.

## Highlights

- **Media-first file management**: Browse local folders with layouts that work better for photos, videos, and mixed libraries than a plain file list.
- **Tabbed browsing on desktop and mobile**: Open multiple locations at once, switch contexts quickly, and keep parallel browsing flows alive on both Windows and Android.
- **Tag files and search by tags**: Add tags to files, reuse popular tags, and search with single or multiple tags to narrow a large library fast.
- **Smart albums with dynamic rules**: Build albums that automatically collect matching files from selected source folders using filename-based rules.
- **Choose the video thumbnail frame**: Control the extraction position used for video thumbnails so previews represent the part of the clip that actually matters.
- **Watch videos over SMB and FTP**: Open and stream media from network locations without turning your workflow into manual copy-paste.
- **Fast thumbnails for local and network media**: Generate thumbnails for images, videos, folders, and supported network files with caching to keep browsing responsive.
- **Pinned places and workspace memory**: Pin important folders in the sidebar and restore the last tab workspace with per-tab drawer state.
- **Built-in galleries for photos and videos**: Move from raw folder browsing into image and video focused views when you want to scan a collection visually.
- **Cross-platform foundation**: Built with Flutter and currently targeting Windows, Android, Linux, and macOS.

## Main Features

### File management and browsing

- Browse local storage and network locations in a unified interface.
- Open directories in multiple tabs.
- Use the same tab-oriented workflow across desktop and mobile.
- Pin folders, drives, or favorite locations to the sidebar.
- Restore the last opened tab workspace when returning to the app.

### Tagging and discovery

- Add tags to files to create your own organization layer beyond folder names.
- Search by tag using direct tag paths and multi-tag filtering.
- Reuse recent and popular tags for faster tagging.
- Display tags directly in file and gallery views for quick visual context.

### Media workflow

- Generate image, video, and folder thumbnails.
- Tune video thumbnail extraction position from settings.
- Browse dedicated image and video gallery views.
- Use the built-in video player for local and supported network files.
- Support desktop-oriented media workflows such as external opening and focused playback.

### Network access

- Browse SMB shares.
- Connect to FTP servers.
- Generate thumbnails for supported network files.
- Stream supported media directly from network locations.
- Store network credentials locally for faster reconnects.

### Album automation

- Create albums for curated collections.
- Create smart albums driven by dynamic rules.
- Match files into albums automatically based on filename patterns.
- Scope rules to selected source folders so albums stay relevant instead of noisy.

## Platforms

- Windows
- Android
- Linux
- macOS

## Downloads

Latest packaged builds are published here:

[Download Latest Release](https://github.com/coolbirdzik/cb-file-hub/releases/latest)

Available package types include:

- Windows: portable ZIP, EXE installer, MSI installer
- Android: APK and AAB
- Linux: `tar.gz`
- macOS: ZIP

## Quick Start

### Windows

1. Download the latest Windows package from the releases page.
2. Install with the EXE or MSI package, or extract the portable ZIP.
3. Run `cb_file_manager.exe`.

### Android

1. Download the latest APK.
2. Allow installation from unknown sources if needed.
3. Install and launch the app.

### Linux

```bash
tar -xzf CBFileManager-<version>-linux.tar.gz
cd bundle
./cb_file_manager
```

### macOS

1. Download the macOS ZIP package.
2. Extract it and move the app into `Applications`.
3. Open it from Finder.

## Development

### Prerequisites

- Flutter SDK 3.41.5 or later
- Dart SDK 2.15.0 or later
- Visual Studio 2022 with C++ tools for Windows builds
- Android SDK and JDK 17+ for Android builds
- GTK3 development libraries for Linux builds
- Xcode and CocoaPods for macOS builds

### Local setup

```bash
git clone https://github.com/coolbirdzik/cb-file-hub.git
cd cb-file-hub/cb_file_manager
flutter pub get
flutter run
```

Enable the developer overlay only for local development:

```bash
flutter run --dart-define=CB_SHOW_DEV_OVERLAY=true
```

### Build commands

```bash
# Windows
flutter build windows --release

# Android APK
flutter build apk --release --split-per-abi

# Android AAB
flutter build appbundle --release

# Linux
flutter build linux --release

# macOS
flutter build macos --release
```

You can also use the helper scripts:

```bash
chmod +x scripts/build.sh
./scripts/build.sh
```

Or use `make` targets:

```bash
make help
make windows
make android
make linux
make all
```

## Testing

```bash
flutter test
flutter analyze
dart format --output=none --set-exit-if-changed .
```

## Project Structure

```text
cb_file_manager/
├── lib/
├── assets/
├── test/
└── pubspec.yaml
```

## Documentation

- [Quick Start Guide](QUICK_START.md)
- [Build Instructions](scripts/README.md)
- [Windows Setup Guide](WINDOWS_SETUP.md)
- [Windows Build Fix Notes](WINDOWS_BUILD_FIX.md)
- [Release Guide](RELEASE_GUIDE.md)
- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

## Contributing

Contributions are welcome. Open an issue for bugs or feature requests, or submit a pull request if you want to improve the app.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

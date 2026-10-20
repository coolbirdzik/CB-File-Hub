# Installation

CB File Hub is an **ALL-IN-ONE file manager for Windows, macOS, Linux, and Android**. Desktop and mobile share tabs, media browsing, and library organization, with platform-specific tools where available.

## Windows

Install from the [Microsoft Store](https://apps.microsoft.com/detail/9nchpzkc4m5c), or get the MSI installer or portable ZIP from [GitHub Releases](https://github.com/coolbirdzik/cb-file-hub/releases/latest). Extract the portable ZIP before launching the application.

## macOS

The universal DMG supports Apple Silicon and Intel on macOS 12 or later.

1. Download the DMG from [GitHub Releases](https://github.com/coolbirdzik/cb-file-hub/releases/latest), open it, and drag **CB File Hub** into **Applications**.
2. Open the app. If macOS cannot verify it, click **Done**, then open **System Settings → Privacy & Security → Open Anyway** and confirm.
3. When the app requests Full Disk Access, click **Grant Permission**. Drag the CB File Hub icon into the Full Disk Access list, approve the change, and choose **Quit & Reopen**.

Without Full Disk Access, macOS may request access to Desktop, Documents, Downloads, and drives separately; some folders remain inaccessible. The app is not notarized. See the [DMG installation notes](../../installer/macos/README.txt) for troubleshooting and the [signing guide](../technical/10-macos-code-signing.md) for how signing affects permission persistence.

## Linux

Build on Linux using the [development setup](../contributing/04-development-setup.md). Run from `cb_file_manager/`:

```bash
flutter pub get
flutter build linux --release
cd build/linux/x64/release/bundle
"./CB File Hub"
```

Keep the executable with its bundled libraries and data directory when moving or distributing the build.

## Android

Install from [Google Play](https://play.google.com/store/apps/details?id=com.cbv.filehub), or download an APK from [GitHub Releases](https://github.com/coolbirdzik/cb-file-hub/releases/latest). Allow installation from that download source if Android asks, then install the APK.

## First steps

Open a folder, choose a view, and pin frequently used locations. Use tags and albums to organize a library, or connect a network location through SMB, FTP, SFTP, or WebDAV.

Disk Cleaner supports Windows, macOS, and Android; torrent downloading runs on desktop. AI providers, cloud accounts, and local models may need additional configuration; see the [feature guides](../features/).

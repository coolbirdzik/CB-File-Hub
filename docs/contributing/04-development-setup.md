# Development setup

Use Flutter **3.47.8 stable**, as pinned in [`build.config`](../../build.config), and its bundled Dart SDK. Install `just`; Windows also needs Git Bash for the recipes.

| Target | Build requirements |
|--------|--------------------|
| Windows | Visual Studio 2022 with C++ tools |
| macOS | Xcode and CocoaPods; macOS 12 or later |
| Linux | Linux desktop toolchain and GTK3 development libraries |
| Android | Android SDK and JDK 17 or later |

## Workspace

```text
cb_file_manager/   main Flutter app
mobile_smb_native/ local SMB/CIFS FFI plugin
cb_native/         optional Rust helpers with a Dart fallback
scripts/           build, screenshot, version, and CI helpers
installer/         Windows installers and macOS DMG notes
justfile           primary developer command runner
```

Run `just` recipes from the repository root. Run direct `flutter` and `dart` commands from `cb_file_manager/`.

```bash
git clone https://github.com/coolbirdzik/cb-file-hub.git
cd cb-file-hub
just deps
cd cb_file_manager
flutter run
```

For macOS development, use `just macos-dev` from the repository root. It launches the app with its own privacy permissions and attaches for hot reload. Follow the [macOS signing guide](../technical/10-macos-code-signing.md) to keep Full Disk Access across rebuilds.

Optional cloud OAuth client IDs use a git-ignored root `.env`; start with [`.env.example`](../../.env.example). Missing keys leave the corresponding provider unavailable. See [cloud backup and sync](../features/08-cloud-backup-sync.md).

## Checks and builds

Run these recipes from the repository root:

```bash
just              # list recipes
just deps         # install dependencies
just verify       # format check and static analysis
just test         # unit and widget tests
just analyze      # CI checks: format, analysis, unit and widget tests
just clean
```

Build on the appropriate host with its platform toolchain installed:

```bash
just windows      # Windows portable ZIP
just windows-msi  # Windows MSI installer
just android      # Android APKs
just android-aab  # Android App Bundle
just macos        # macOS DMG
```

For Linux, run `flutter build linux --release` from `cb_file_manager/`; see [Linux setup](../guides/04-installation.md#linux) for the bundle location.

Direct Flutter commands belong inside `cb_file_manager/`:

```bash
flutter pub get
flutter test
flutter analyze
dart format --output=none --set-exit-if-changed .
```

Before a direct Windows build on a clean checkout, run `just fetch-llama` and `just fetch-aria2` from the root. The `just windows` recipe fetches both automatically.

E2E commands require explicit user authorization for the current task. See the [desktop E2E guide](../quality/02-e2e-desktop-integration.md) for runners, prerequisites, and reporting. Screenshot capture below uses E2E and follows the same authorization policy.

## Developer overlay

The floating overlay is opt-in for non-release builds. From `cb_file_manager/`:

```bash
flutter run --dart-define=CB_SHOW_DEV_OVERLAY=true
```

Restart the app after changing the flag. Release builds never show the overlay.

## Screenshot automation

Generate lightweight showcase screenshots for the main app features on desktop and Android:

```bash
# Windows desktop screenshots
./scripts/capture_screenshots.sh desktop

# Android screenshots, using first connected Android device or emulator
./scripts/capture_screenshots.sh android

# Both targets
./scripts/capture_screenshots.sh all
```

On Windows PowerShell, use the native script instead of the Bash wrapper:

```powershell
# Windows desktop screenshots
./scripts/capture_screenshots.ps1 desktop

# Android screenshots, using the first connected Android device or emulator
./scripts/capture_screenshots.ps1 android

# Both targets
./scripts/capture_screenshots.ps1 all
```

Output files are copied to:

```text
screenshots/auto/desktop/
screenshots/auto/android/
```

The screenshot scripts use a dedicated showcase E2E flow and export only the final hero frames for each featured scenario, not every intermediate test step. Desktop and Android run different scene lists, because the two shells look nothing alike: desktop captures the multi-pane workspace, file tag-assignment dialog, SSH workspace, SMB/WebDAV network catalog, and disk cleaner, while Android captures the home, file grid, tab manager, and tag screens that feed the four mobile promo slots.

Android requires a connected device or running emulator visible in `flutter devices`. The test process writes its frames inside the app sandbox, so the script pulls them off the device with `adb` before copying them into `screenshots/auto/android/`.

Generate promotional artwork from the captured screenshots:

```powershell
python scripts\make_promo_images.py
```

The generated artwork is written to `screenshots/promo/desktop/`, `screenshots/promo/mobile/`, `screenshots/promo/tablet7/`, the matching Vietnamese folders under `screenshots/promo/vi/`, Turkish and Chinese desktop promos under `screenshots/promo/tr/` and `screenshots/promo/zh/`, and the text-free Microsoft Store hero art in `screenshots/promo/store/`. Use `--desktop-only --languages tr,zh` to regenerate only some languages.

Render the English/Vietnamese Torrent dialog images with sample data from `cb_file_manager/`:

```bash
flutter test --no-pub tool/capture_torrent_screenshots_test.dart --dart-define=CB_CAPTURE_SCREENSHOTS=true
```

This opt-in widget capture writes `screenshots/features/torrents/en/` and `vi/`. It does not launch the desktop app or use the user's torrent library.

## Store listings

Both stores use the same concise descriptions in [`store/listings/`](../../store/listings/), one per app language (English, Vietnamese, Turkish, Simplified Chinese). Edit each language's `.txt` once; its bullet points also generate Microsoft Store features. The sibling `.json` holds the short description, Google Play language code and the Microsoft Store screenshots/hero art. CI checks text limits and image sizes and uploads a `store-listings` preview. MSIX submissions apply the text and images in Partner Center; AAB submissions include the text in the same Google Play edit as the app bundle. See the [content guide](../../store/README.md).


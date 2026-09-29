# App Updates

**Purpose**: Tell users when a newer version exists and install it, using the update path that matches how the app was installed.

## Layout

```
lib/services/app_update/
├── app_update_models.dart        # AppDistribution, AppUpdateInfo, phases, compareVersions
├── app_update_service.dart       # state machine (check → download → confirm → install)
├── github_release_source.dart    # latest release + asset per distribution
├── desktop_update_installer.dart # detached helper scripts for MSI / portable / DMG
└── release_notes.dart            # release notes → grouped change list for the UI
lib/ui/components/app_update/app_update_dialog.dart   # dialog + AppUpdateStatusCard
lib/ui/components/common/operation_progress_overlay.dart # Status Center (bell) hosts the card
windows/runner/store_update_plugin.{h,cpp}   # cb_file_manager/store_update channel
```

## Distribution → update path

| Build | Detected by | Check | Download | Install (after the user confirms) |
| --- | --- | --- | --- | --- |
| Microsoft Store (MSIX) | `GetCurrentPackageFullName` succeeds | `StoreContext.GetAppAndOptionalStorePackageUpdatesAsync` | `RequestDownloadStorePackageUpdatesAsync`, progress polled | `RequestDownloadAndInstallStorePackageUpdatesAsync`; Windows closes the app |
| Google Play | `installerStore == com.android.vending` | `in_app_update` `checkForUpdate` | Play flexible update (Play asks for consent and downloads) | `completeFlexibleUpdate`; Play restarts the app |
| Windows MSI | exe under `%ProgramFiles%` | GitHub `releases/latest` | `.msi` asset with % progress | `msiexec /i … /passive` (UAC), then relaunch |
| Windows portable | anything else on Windows | GitHub `releases/latest` | `-windows-portable.zip` asset with % progress | unzip, `robocopy` over the app folder, relaunch |
| macOS DMG | `.app` bundle not under `/Volumes` | GitHub `releases/latest` | `.dmg` asset with % progress | mount, `ditto` over the bundle (admin prompt if needed), relaunch |

Debug builds, E2E runs, sideloaded APKs, Linux and iOS resolve to `unsupported`, and the update UI stays hidden. To exercise the flow in a debug build, pass `--dart-define=CB_UPDATER_DEBUG=true`. A portable-style update then overwrites the build folder.

## Flow

1. The primary window checks once, 8 s after launch (`scheduleStartupCheck` in `main.dart`). Nothing pops up on desktop: the update appears as a card in the Status Center (toolbar bell), and the bell shows a badge until the Status Center or the dialog is opened (`hasUnseenUpdate` / `markUpdateSeen`). Mobile has no bell and shows a toast with an **Update** action. The sidebar footer and Settings → *Check for updates* open the dialog.
2. The card offers **Download** and **What's new**. The dialog shows the release notes grouped into new features, fixes and improvements (`parseReleaseChanges`: conventional-commit prefixes and hashes removed; `ci`/`build`/`chore`/`docs`/`test`/`style` commits hidden). Progress (percent and bytes) shows in both; the dialog can be closed while the download continues.
3. Downloads go to `%TEMP%/cbfilehub-update/`. They are checked against the asset size and GitHub's `sha256` digest. A complete earlier download is reused.
4. When the download finishes, the bell badges again and the card (or dialog) offers **Install and restart**. Nothing installs without that click.
5. Desktop installs run in a detached helper script. It waits for the app process to exit, closes the app's other window processes, installs, and relaunches. Errors go to `update.log` next to the package.

Release asset names come from `.github/workflows/release.yml`. If you rename them, update `GithubReleaseSource.assetMatches` too.

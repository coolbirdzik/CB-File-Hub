# Troubleshooting

- **Build reset** `flutter clean && flutter pub get`, verify SDK/toolchains per platform.
- **Android** Confirm `local.properties` `sdk.dir`, sync Gradle.
- **iOS** Run `pod install` under `ios/`, open `.xcworkspace`.
- **Desktop** Install required toolchains (CMake, platform SDKs).
- **Permissions** Recheck Android storage/all-files + iOS local network entitlements.
- **Networking** Validate SMB/WebDAV credentials and streaming config files.
- **Historical Android SMB VLC** For the removed backend only, see `docs/troubleshooting/02-android-smb-vlc-no-render.md`.
- **Logging** Use `flutter run -v`, sprinkle temporary logs in services/blocs while debugging.

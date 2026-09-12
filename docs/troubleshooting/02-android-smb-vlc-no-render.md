> Historical note: this describes the removed `flutter_vlc_player` fallback.
> Current builds use the shared media_kit backend; see [media_kit playback](../technical/07-media-kit-playback.md).

# Android: SMB VLC Plays Audio But Video Does Not Render

## Symptoms

- SMB video starts "playing" (network traffic / audio) but the Flutter UI shows a loading spinner forever.
- VLC controller never becomes ready:
  - `VlcPlayerValue.isInitialized == false`
  - `VlcPlayerValue.size == 0x0`
- Logs may contain:
  - `PlatformException(channel-error, Unable to establish connection on channel., null, null)`

## Root Cause

This can happen when the Dart Pigeon channels used by `flutter_vlc_player_platform_interface` do not match the Android channels implemented by `flutter_vlc_player`.

In the broken state:

- Dart side (platform interface) sends messages to channels like:
  - `dev.flutter.pigeon.VlcPlayerApi.create`
  - `dev.flutter.pigeon.VlcPlayerApi.initialize`
- Android side (plugin) listens on different channel names, so Dart receives `replyMap == null`
  and throws `PlatformException(channel-error, Unable to establish connection on channel.)`.

As a result, the controller never completes initialization, the platform view stays at `0x0`,
and the UI never transitions out of "loading".

## Fix

### 1) Pin a Known-Good `flutter_vlc_player` Version

Pin to `flutter_vlc_player: 7.4.3` in `cb_file_manager/pubspec.yaml`.

Why:
- `flutter_vlc_player 7.4.4` uses Android channel names prefixed with
  `flutter_vlc_player_platform_interface` (e.g.
  `dev.flutter.pigeon.flutter_vlc_player_platform_interface.VlcPlayerApi.create`),
  which does not match the channel names used by `flutter_vlc_player_platform_interface 2.0.5`.
- `flutter_vlc_player 7.4.3` matches the platform interface channel names:
  `dev.flutter.pigeon.VlcPlayerApi.*`.

Reference locations (pub cache):
- `flutter_vlc_player-7.4.4/android/src/main/java/software/solid/fluttervlcplayer/Messages.java`
- `flutter_vlc_player-7.4.3/android/src/main/java/software/solid/fluttervlcplayer/Messages.java`
- `flutter_vlc_player_platform_interface-2.0.5/lib/src/messages/messages.dart`

### 2) Do a Full Android Rebuild (Do Not Hot Reload)

After changing plugin versions, do a full rebuild so Gradle picks up the correct native code:

```bash
cd cb_file_manager
flutter clean
flutter pub get
flutter run
```

If you still see old behavior, uninstall the app from the device/emulator and run again.

### 3) Avoid Embedding SMB Credentials in the URL

libVLC SMB parsing can be sensitive to userinfo in the URL, especially when passwords contain
reserved characters like `@`.

Preferred:
- Use a clean URL: `smb://host/share/path/file.mkv`
- Pass credentials through VLC options:
  - `:smb-user=<user>`
  - `:smb-pwd=<password>`
  - `:smb-domain=<domain>` (optional)

Implementation lives in:
- `cb_file_manager/lib/ui/components/video/video_player/video_player.dart`

## Verification Checklist

- No `PlatformException(channel-error, Unable to establish connection on channel.)` in logs.
- VLC controller transitions to:
  - `isInitialized=true` (or `isPlaying=true`)
  - `size.width > 0` and `size.height > 0`
- Loading overlay is dismissed once VLC reports initialized/playing/has media info.


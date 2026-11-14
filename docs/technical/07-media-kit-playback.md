# media_kit playback

Local video, audio, HTTP streams, SMB, desktop PiP and frame picking share
`cb_file_manager/lib/services/media/media_kit_playback.dart`.

Desktop local-file players also expose [lossless cutting](../features/11-lossless-video-cut.md).
The player keeps its media_kit surface mounted while the editor selects ranges.
FFmpeg exports through stream copy; `cb_native` job 30 handles the subprocess,
bounded pipe parsing, progress and cancellation on Rust threads. The Dart
subprocess runner remains the fallback when that native job is unavailable.
Export results open in a fresh app tab through
`ui/utils/video_output_folder_navigation.dart`. The desktop window service
routes dedicated-player requests to a normal browser engine (including engines
in the same process), or starts a browser when none exists. In-window fullscreen
routes return to the browser after adding the result tab.
The result filename is passed as `highlightedFileName` through local `AddTab`,
validated `open_folders` IPC and `WindowTabPayload` startup. The existing folder
screen handles selection and scrolling after its listing/preferences finish
loading. Batch-result filename actions each reveal their own file; the general
open-output action reveals the first result.

Dependencies verified against pub.dev on 2026-09-12:

- `media_kit` 1.2.6
- `media_kit_video` 2.0.1
- `media_kit_libs_video` 1.0.7 (Windows native libraries 1.0.11)

The vendored VLC plugin and its runtime dependency have been removed.
Flutter generates native plugin registration and bundles media_kit's libraries.
`PlaybackPlayer` initializes MediaKit before creating a player, including when
launched directly by a PiP window or integration test.

The wrapper retains synchronous play/pause intent for rapid seek drags. Native
events drive position, duration, buffering, volume and dimensions. Screenshots
use media_kit's PNG capture. Paused opening renders the preview without briefly
playing audio. Looping maps to `PlaylistMode.single`.

Slider drags, held arrow keys and wheel seeks keep active playback running so
audio follows the seek. Explicitly paused playback stays paused. If playback
reaches EOF while scrubbing, seeking back resumes the latest requested play
state; a pause or disposal during an in-flight seek prevents that resume.

Keep the video texture mounted while buffering, seeking and hiding controls.
The overlay Stack must remain expanded. Default fit is `BoxFit.contain`, which
preserves the full frame and aspect ratio, including when enlarging a video.
The app supplies its existing controls rather than media_kit's default controls.

The Windows software decoding preference is retained. Initial video controller
configuration sets both rendering acceleration and `hwdec`. Changing the
decoding preference updates `hwdec` on the existing player without replacing
the texture; renderer acceleration is selected when the player is created.

SMB URLs preserve escaping and authentication. On Windows, playback uses native UNC paths; explicit credentials connect through
the same Win32 SMB service used by browsing. Shared OS sessions remain connected
when a decoder closes, so browser tabs and PiP keep working. Other platforms
use the existing loopback HTTP proxy backed by `mobile_smb_native`, with
byte ranges for seeking. Opaque temporary stream IDs keep SMB credentials out
of the URL passed to the decoder. PiP keeps the original source so it can
resolve its own playback connection. HTTP cancellation releases the SMB reader.

Run from `cb_file_manager/`:

```powershell
flutter test test/services/media/media_kit_playback_test.dart test/ui/components/video
flutter test integration_test/media_kit_playback_e2e_test.dart -d windows --dart-define=CB_E2E=true
```

The native suite covers paused preview, playback, seeking, volume, snapshots,
source reuse, disposal, drag/key seeking, and visible frames after controls
auto-hide. Pass `--dart-define=CB_E2E_SMB_URL=smb://host/share/sample.mp4` to
include a real accessible SMB share; otherwise the SMB case is skipped.

Folder thumbnails remain on the independent FFmpeg/native helper. Their
regression suite is `integration_test/ffmpeg_thumbnail_e2e_test.dart`.

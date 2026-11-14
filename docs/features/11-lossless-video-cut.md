# Lossless video cutting

Desktop local-file video players have a scissors button, including narrow
windows. The editor stays over the existing playback surface. HTTP/SMB proxy
streams and mobile players do not expose the editor; download the source first.
Files opened through a filesystem path (including an OS-mounted share) work.

1. Open a video and select the scissors button, **Advanced controls → Lossless
   cut**, or **right-click / long-press the video → Lossless cut**. Desktop
   scissors and menu buttons stay available in both compact and wide windows.
2. Seek to the desired start/end and press **I** / **O**, use the corresponding
   buttons, drag the range handles, or enter `HH:MM:SS.mmm` timecodes. Dragging
   either handle previews that boundary immediately; releasing keeps the player
   at the same boundary instead of jumping to the start.
3. The editor starts with one segment. Use **Add segment** to create each
   additional range, then select a segment row to edit it. Changes save to the
   selected segment automatically. Export always includes every listed segment
   in its displayed order, including the one currently being edited. Remove
   unwanted segments with X; at least one segment remains.
4. Choose separate files or joined segments, and source format, MKV or MP4.
   Open **Export options** in the footer to change these settings, embedded
   subtitles, or file dates. The footer summarizes the selected settings.
   The date selector defaults to **Export time**. Choose **Keep source file dates**
   to give every output the original file's modification date, plus its creation
   date on Windows. This helps the source and numbered clips stay together when
   sorting by date, especially with **Export here**. The choice also applies to
   joined outputs and exports to another folder.
5. Choose **Export losslessly** (one segment) or **Export N segments**, then
   choose **Export here** to save directly beside the source video, or
   **Choose another folder** to open the folder picker. The dialog shows the
   source folder before exporting. Other-folder exports keep the existing
   `CB-cuts-*` subfolder layout; in-place exports leave no result subfolder.
   For example, two segments from `holiday.mp4` produce `holiday_1.mp4` and
   `holiday_2.mp4`. The separate-files button shows the number of segments to
   export. Segment rows preview each filename. Completed results list every
   output filename, with its full path in the tooltip.

**Open output in new tab** opens the result folder in a fresh CB File Hub tab,
even if that folder already has a tab. An in-window fullscreen player returns
to the browser after adding the tab. A dedicated player sends the request to
an app file-browser window and keeps its own player window; when no browser
exists, the app creates one with that folder tab. This action uses app tab/IPC
routing and does not launch the OS file manager.
The new tab selects and scrolls to the first exported file. Each filename in
the completed result list also opens a new tab focused on that particular file.
The filename travels with the folder through local tab creation, peer IPC and
new-window startup, using the browser's existing highlighted-file behavior.

The editor uses a compact panel up to 960 px wide. Range editing and the segment
list sit side by side when space permits, and stack in narrow players. I/O
buttons sit inside their timecode fields, moving beside the range title in
narrow layouts so the complete timecodes remain readable. The segment list scrolls independently
and newly added segments scroll into view; export options expand only on request.
The header and action footer remain visible while the body scrolls in short
windows. Long filenames truncate in rows and retain their full accessible names.
Design review follows the taste skill's hierarchy, shared tokens, restrained
color, equal edges, keyboard and responsive principles in the existing Flutter
components. Its HTML/Chrome website gate does not apply to this native panel;
widget rendering at desktop and narrow sizes provides the visual checks instead.

In-place exports skip filenames that already exist. For example, if
`holiday_1.mp4` is present, two new segments use the next available numbers
without replacing it. Joined in-place exports use `holiday_merged.mp4`, then
`holiday_merged_1.mp4`, etc. when needed.

The source is never modified. Existing exports are never overwritten. Cancel,
closing the editor/player or changing source cancels the FFmpeg process and
removes the partial files belonging to that export. Controls stay visible and
automatic next-video playback is suspended while the editor is open.

The context menu also shares playback, seek, mute, fullscreen, screenshot,
audio/subtitle, speed, PiP, filters and settings actions with the three-dot
menu. **Shift+F10** or the keyboard Menu key opens it from the focused player.
Controls remain visible while the menu is open. Touch long-press opens this
menu; desktop held-arrow seeking remains available. Text fields and controls
above the video keep their own interactions.

## Processing and limitations

`LosslessCutService` uses FFmpeg input seeking (`-ss` before `-i`), `-t`,
`-map 0` and `-c copy`. Video/audio tracks and global metadata are copied;
embedded subtitles are excluded by default. Enable **Copy embedded subtitles**
to retain them (long cues may extend the exported duration and create gaps
when joining). Other embedded tracks are also retained;
source chapters are omitted because their timestamps reference the original
timeline. Generated AI/external subtitles, playback speed and video filters
are not baked into exports. Joining uses a concat demuxer manifest containing
only generated relative filenames, so user path quoting cannot alter it.
Separate exports use generated ASCII staging names internally and are renamed
to `<source basename>_1.<ext>`, `_2`, etc. after processing. This keeps Unicode,
apostrophes and other source-name characters out of the concat manifest.
In-place export also uses a fresh staging directory on the destination volume.
After all segments finish, it exclusively reserves free final filenames and
renames completed files over those owned reservations. Existing files, folders
and links are skipped. Normal failure/cancellation removes only this export's
staging directory and reserved/published files; cleanup errors are reported.

Source dates are captured before FFmpeg starts and applied after every final
rename, including in-place filename reservations. Windows uses native file
attribute operations on a background isolate and retains FILETIME precision;
other platforms retain the modification date only (inode change time is never
treated as creation time). File systems may round timestamps to their supported
precision. If copying the dates fails, export reports the error and removes its
own outputs through the normal cleanup path. The source dates are never written.
These small attribute operations use the same path with and without Rust;
subprocess work remains on Rust threads when available.

Stream copying preserves encoded media packets, but cuts are **keyframe based**,
not frame exact. The actual start and duration can differ from the selected
range. Subtitle cues overlapping a cut boundary and some codecs/containers may
need special handling. Unsupported tracks fail with FFmpeg diagnostics; try
the source format or MKV instead of MP4. The app never silently re-encodes.

Windows packages install `ffmpeg/ffmpeg.exe`, its shared DLLs and license from
the existing pinned FFmpeg download. macOS/Linux search PATH and common
Homebrew locations; the panel also permits choosing an installed executable.
No FFmpeg CLI is bundled for mobile.

## Rust acceleration and fallback

`LosslessCutService` prefers `NativeMediaProcess` in `cb_native` (job kind 30).
The Rust worker starts FFmpeg without a shell, drains stdout and stderr on two
threads, parses `out_time_us`, and exposes monotonic progress counters. Progress
is read by Dart at most once per 100 ms while running; native port notification
wakes it immediately at completion. The diagnostic tail is bounded to 16,000
bytes and progress lines to 1,024 bytes, so verbose/malformed output cannot grow
the buffers without limit.

Cancellation and abandoned-owner detection kill and reap the child. The native
result waits for process exit and both readers before Dart removes partial
files, avoiding Windows file-lock races. On Windows the process starts hidden
at below-normal priority; a per-child kill-on-close Job Object also protects
against an application crash when the OS permits job assignment.

FFmpeg still performs all demuxing, stream copying and muxing. Media packets
never cross FFI. Rust reduces work on the UI isolate; it does not make a claim
of faster media copying, which is usually limited by storage throughput.
Timecode fields, segment selection, export naming and file validation stay in
Dart because they are lightweight and already asynchronous where they do I/O.
The cut-range slider shares the player's seek-preview pipeline: seek requests
are coalesced every 150 ms while dragging and finish with an exact seek on
release. Paused playback stays paused; active playback keeps its intent.

When Rust is unavailable, or an older native library does not support job 30,
the service uses the original asynchronous Dart subprocess runner.
`LosslessCutService(useNativeProcess: false)` explicitly selects that fallback.
A native job that already started is never retried through Dart on failure;
its error reaches the caller and its partial outputs are cleaned up.

## Validation

From `cb_file_manager/`:

```powershell
flutter test test/services/media/lossless_cut_service_test.dart test/ui/components/video/video_cut_panel_test.dart
```

The service tests use the checkout's Windows FFmpeg/ffprobe binaries when
available. Set `CB_TEST_FFMPEG` to a full FFmpeg path (with ffprobe beside it)
on other hosts. Without those executables, the real-media group is explicitly
skipped. Fixtures check separate/joined exports, unchanged encoded video packet
hashes, tracks and metadata, decoding, progress, cancellation, source integrity,
unique result folders, and cleanup after container/startup failures. These are
unit/service tests; they do not launch the application or run the desktop E2E
runner.
In-place fixtures cover source-folder output, existing filename/folder
collisions, merged naming, cancellation, and concurrent exports; dialog widget
tests cover choosing either destination and cancelling.
Date-mode fixtures check fresh dates by default, original modification/Windows
creation dates for separate and joined exports in both destination layouts,
and unchanged source dates. A widget check covers switching date modes.

The full real-media fixture group runs once through Dart and once through Rust
when the native library is available; an explicit capability test prevents an
unsupported native job from silently falling back in the Rust group. Rust unit
tests also cover bounded/malformed progress, diagnostics, startup errors and
process cancellation. From `cb_native/rust/`, run `cargo test --release --locked`
and `cargo clippy --release --all-targets --locked`.

Concept reference: [LosslessCut](https://github.com/mifi/lossless-cut), including
its [keyframe cutting limitations](https://losslesscut.app/docs/troubleshooting#cutting-times-are-not-accurate).
This implementation uses FFmpeg directly and does not embed LosslessCut code.

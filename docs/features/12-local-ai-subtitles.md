# Desktop local AI subtitles and shared models

## Use

Open **Settings → AI models · CB Agent & subtitles**, or **video player → ⋮ →
Subtitles**. Enable local AI subtitles, choose a speech model, and download its
weights. Download the translation model too when the audio and output languages
differ. Choose the audio language manually or leave it on Auto detect.

Language names use English and sort A–Z in both selectors. Audio offers the full
Whisper language list: 99 for Base/Small and 100 for Large v3 Turbo, which adds
Cantonese. Translation targets use their own model's list. Auto detect and
Follow app language remain at the top.

Japanese (`ja`) is available as an audio language with every speech model and as
a subtitle target. Use the search icon beside either language selector and type
`Japanese` or `ja`. For Japanese audio with Vietnamese subtitles, choose
**Audio language → Japanese** and **Subtitle language → Vietnamese**; both speech
and translation models must be installed. Keeping Japanese subtitles only needs
the speech model. Model descriptions state their audio language count and Japanese
support explicitly.

Audio track and embedded subtitle choices also use English language names,
including ISO 639-2 metadata such as `jpn` → Japanese. Unknown metadata (`und`)
is shown as **Unknown language**, rather than a raw code or untranslated title.
Track choices sort by their English labels while retaining their original stream
IDs. The subtitle HUD shows the recognized audio/output language pair in English.

Auto recognition decodes up to 30 seconds of context for language identification
while emitting only the requested eight-second chunk. This improves Japanese
detection when short windows contain too little speech; music and silent intros
can still be ambiguous. Choose **Japanese** explicitly when the audio language
is known. Silence detection only measures the requested chunk, so later speech
does not create subtitles in an earlier silent interval. Earlier Auto cache keys
are invalidated by this pipeline change; explicit-language cache remains reusable.

The subtitle target defaults to **Follow app language**. An explicit target
persists independently; bilingual display optionally retains the recognized text.
Windows, macOS and Linux expose these controls. Mobile keeps the existing chat
model manager and does not run the subtitle pipeline.

The common manager covers background downloads, byte progress, cancellation,
retry, installed files, removal and moving the storage folder. Its catalog can
be filtered by CB Agent, speech recognition and subtitle translation. Subtitle
weights never become CB Agent's selected chat model. Existing installed-model
metadata without a purpose field remains a chat model.

Initial subtitle catalog:

| Task | Models | Download |
| --- | --- | --- |
| Speech | Whisper Base / Small / Large v3 Turbo | 148 MB / 488 MB / 1.62 GB |
| Translation | Hy-MT2 1.8B Q4_K_M | 1.13 GB |

These are artifact sizes, not RAM requirements. The current native integration
uses Whisper. Qwen3-ASR, Cohere and other candidates in the
[research](../technical/15-local-live-subtitles-research.md) remain future
backends rather than advertised working choices.

Downloaded subtitle artifacts are checked against publisher LFS SHA-256 values
and expected lengths before installation. Model downloads use a per-artifact OS
lock; registry updates merge changed IDs under a common OS lock. Another desktop
process cannot overwrite a concurrent installation's registry entry. Main/video
windows refresh stored model and subtitle preferences periodically. A failed
file deletion retains its metadata and presents an error, allowing a retry.

## Runtime

`native/subtitles/worker.cpp` is a persistent JSON-lines process. FFmpeg demuxes
the resolved local, UNC or HTTP/proxy source and selected audio stream. It
resamples to 16 kHz mono, keeps original media timestamps and runs whisper.cpp.
Mute, player volume and playback rate do not change recognition input.

`LocalSubtitleSession` schedules eight-second chunks with an 800 ms context
overlap and adaptive twelve-to-forty-second look-ahead. Repeated overlap text is
trimmed while retaining the next cue's new portion. Small cue messages cross
into Dart; PCM and inference remain in C++. Pause/rate changes display cues
against media time, and seek, source/track/settings changes cancel stale work.
The player keeps a rolling window of cues in memory. Completed chunks, including
silence, are committed atomically to the application's shared SQLite database
after recognition and translation succeed. Reopening or seeking restores saved
cues before loading either model and only processes missing intervals. SRT export
is not yet implemented.

Recognition can prepare one chunk while translation processes the preceding
chunk. Translation tokens appear provisionally in the subtitle area; completed
cues replace them, and only successfully completed chunks reach the cache.
Idle models stay loaded across seeks. Scrubbing cancels stale work and coalesces
restarts; changing bilingual display does not reload models. When the source
language is known, translation and speech model preparation overlap.

Auto detection uses a supported audio-track language hint when available.
Otherwise two confident, contiguous detections allow reuse for up to thirty
seconds of media before checking again. A seek or track change resets this
memory. See [performance validation](../technical/16-local-subtitle-performance.md).

## Subtitle cache

The player explains whether it is checking, reusing or saving subtitles. Its
**Clear and regenerate** button deletes the current video/settings version and
restarts processing from the current playback position. **Settings → AI models ·
CB Agent & subtitles → Subtitle cache** shows saved version counts and subtitle
text size and can clear every version. The same bucket appears under **Cache
management**, including **Clear all cache**. Downloaded model weights remain
installed. Size is logical text payload, not the physical SQLite file size;
deleted pages are available for database reuse.

Cache keys include file identity (path, size and modification time), duration,
resolved audio track, speech/translation model artifact versions and audio/output
languages. Bilingual display and app theme reuse the same text. Paths, source
URLs and credentials are hashed rather than stored in cache rows. HTTP sources
need ETag or Last-Modified validators; unversioned HTTP/proxy sources continue
generating subtitles but explicitly report that persistent caching is unavailable.
Only the requested cue window is loaded from SQLite. Completed intervals remain
separate from visible cues so silent chunks and seek gaps stay accurate.

Clearing increments a database revision in the deletion transaction. Late results
from another window cannot repopulate the cleared revision; active windows
refresh and regenerate as needed. Concurrent players reuse the first committed
overlapping interval. Database/cache failures leave playback and subtitle
generation available and display the cache failure.

Translation uses a separate llama-server runtime and conversation. It does not
switch or dispose CB Agent's chat model. Model management releases local users
before moving/removing their weights. Windows child processes use the existing
kill-on-close Job Object. A file held by another process can still require that
window to close before deletion succeeds.

Inference sends no audio or transcript to a cloud API. Hugging Face downloads
require connectivity; decoding a network video still reads its original source.

## Build and platform requirements

A rebuild is required; hot reload cannot install the helper executable.

- **Windows:** the app CMake build compiles and installs the helper with its
  FFmpeg DLLs and the real Vulkan loader under `subtitles/`, isolated from Flutter
  and llama DLLs. Vulkan acceleration is enabled by default; CMake downloads and
  verifies pinned build tools into the ignored build cache without installing
  an SDK or changing drivers. Python 3.9+ is required for this build step.
  `CB_SUBTITLE_VULKAN=OFF` produces a CPU-only build. Runtime GPU failures retry
  in a fresh CPU worker. Base/Small can produce CPU results while the GPU warms
  up, switching to the ready GPU without waiting for a losing CPU operation.
  Translation uses the existing bundled llama.cpp runtime with one slot and a
  bounded CPU thread budget, and can retry on CPU. Subtitle child processes run
  below normal priority. The baseline x64 build uses AVX2.
- **macOS:** `scripts/bundle_macos_subtitle_runtime.sh` builds each Xcode target
  architecture and combines helpers with `lipo`. It builds pinned static FFmpeg
  sources to avoid Homebrew dylib and architecture dependencies, enables the
  upstream Metal backend, and signs the helper. Build tools: Xcode, CMake and
  pkg-config (`brew install cmake pkg-config`). Translation retains the existing
  bundled llama runtime's macOS 13.3 minimum.
- **Linux:** build dependencies include libavformat/libavcodec/libavutil/
  libswresample development packages. Debian packaging includes the helper in
  dependency resolution and library smoke checks. Translation resolves bundled
  `llama/llama-server`, then a `llama-server` installed on PATH.

This version handles **seekable video**, including suitable network VOD. Live
sources without a seekable timeline report a limitation. Initial subtitles can
arrive after playback begins; processing speed depends on hardware, model and
translation cost. The player shows loading, missing models, processing lag,
errors and retry instead of delaying video playback automatically.

Desktop playback controls include a small **CC** button. Its tooltip and menu
show model loading, recognition, translation, the language pair, processed time
and cache state. Settings, retry and clear/regenerate are available from that
menu. A two-pixel AI rail immediately below the existing seek track paints
finished intervals in teal and the current unfinished chunk in amber. The
playback thumb, keyboard seeking and drag behavior retain their normal role.
No separate AI status panel covers the picture; hiding controls leaves only
caption text visible and keeps recognition running. Local files and network
video share one subtitle session for captions, the CC button and the seek rail.
Only completed recognition and translation advance the processed time, including
silence. A seek restores saved intervals without painting an unprocessed prefix
as complete. Model warm-up uses an indeterminate indicator in the CC button;
the UI does not invent a model-loading percentage.

## Validation

Unit/widget coverage checks shared model storage and migration, checksum/length
rejection, concurrent installs, cancellation, language defaults, overlap,
seek/target races, cache reopen/invalidation, clearing during translation,
cross-repository stale writes and releasing model users. The existing CB Agent and player
unit/widget suites are also used for regression checks.

`native/subtitles/test_worker.py` checks the worker independently of Flutter:
resampling, seek offsets, Unicode paths, multiple audio tracks, protocol errors
and optional real-model recognition/timestamps. Example, from the repo root:

```powershell
python native/subtitles/test_worker.py --worker <worker.exe> --model <ggml-base.bin> --speech-sample <jfk.wav> --ffmpeg <ffmpeg.exe> -v
```

Windows checks include real Whisper recognition and real Hy-MT2 translation
with the app's pinned llama runtime. macOS/Linux build and runtime validation
requires those hosts. Project E2E commands were not run; AGENTS.md requires
explicit authorization for them.

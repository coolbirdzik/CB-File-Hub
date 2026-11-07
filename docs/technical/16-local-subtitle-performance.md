# Local subtitle scheduling and performance

The desktop pipeline uses a persistent C++ FFmpeg/whisper.cpp worker and a
separate llama-server for translation. PCM, model tensors and inference never
cross the Flutter UI isolate. The implementation and UI are described in
[local AI subtitles](../features/12-local-ai-subtitles.md).

## Scheduling

- Recognize eight seconds of media with 800 ms overlap, then prepare at most
  one additional recognition request while translation finishes. Look-ahead
  adapts from twelve to forty media seconds using recent processing time and
  playback rate. This bounds speculative work and memory.
- Publish translated tokens provisionally, then complete each cue. Commit
  recognition and translation together to SQLite only when the chunk succeeds;
  unfinished text cannot become persistent cache data.
- Keep idle models across seeks. Debounce scrubbing for 200 ms, cancel busy
  work, reject stale generations and resume at the current playback position
  if processing falls behind. Display-only settings reuse model state.
- Prepare speech and translation models concurrently when the source language
  is already known. Auto detection uses supported track metadata or a longer
  language-only context; two confident contiguous detections permit brief reuse.
- Windows uses Vulkan by default and retries a failed GPU worker on CPU.
  Base/Small prepare a temporary CPU context before asynchronous GPU warm-up.
  The first ready CPU/GPU result wins; an outstanding CPU loser is cancelled
  and cannot delay publication or mutate the selected language state. At most
  one CPU job survives a handoff. Large models avoid this extra model allocation.
- Subtitle processes run below normal priority, with at most six CPU inference
  threads. Translation uses one parallel slot, batch/ubatch 128 and no idle
  prompt-cache RAM allocation. CB Agent's defaults remain independent.
- Load cached cues before loading any model. Subtitle refreshes are coalesced;
  partial text updates have a 100 ms cadence and timeline progress a one-second
  cadence when the visible text has not changed.

## Repeatable checks

Windows builds download pinned Vulkan tools with `scripts/fetch_subtitle_vulkan.py`
and verify both archive SHA-256 hashes before extraction. The tools stay in the
ignored `cb_file_manager/windows/subtitle-vulkan/` directory so `flutter clean`
does not discard them. Windows CI jobs cache the extracted tools, without the
large SDK installer. The download URLs use [LunarG's documented](https://vulkan.lunarg.com/content/view/latest-sdk-version-api) `?Human=true`
parameter for shared-IP download limits, with bounded retries for transient
HTTP/network failures. The SDK installer is never executed.

Run all Flutter commands in `cb_file_manager/`. These are opt-in component
benchmarks; they do not launch or control the application and are not E2E runners.

`native/subtitles/bench_worker.py` measures persistent native-worker load,
decode, language detection and recognition timings. Give it local `--worker`,
`--model`, `--source`, `--output`, optionally `--gpu`, `--language ja` or `auto`,
and `--start-ms`. Output contains timing/count metadata, never transcript text.

`tool/bench_subtitles_test.dart` runs the production subtitle session, native
worker and translation runtime against a synthetic media clock at 1x, real
models and a temporary SQLite cache. Run with `flutter test --no-pub` and these
`--dart-define` values:

```text
CB_SUBTITLE_BENCH_SOURCE=<local video>
CB_SUBTITLE_BENCH_SPEECH=<ggml-small.bin>
CB_SUBTITLE_BENCH_TRANSLATION=<Hy-MT2-1.8B-Q4_K_M.gguf>
CB_SUBTITLE_BENCH_WORKER=<cb-subtitle-worker.exe>
CB_SUBTITLE_BENCH_LLAMA=<llama-server.exe>
CB_SUBTITLE_BENCH_OUTPUT=build/subtitle-performance-session.json
```

The test requires visible translated text, keeps loaded models on an idle
uncached seek, then closes both runtimes and verifies cached reopen without
starting a new model. Its 16 ms event-loop probe measures service-isolate
scheduling; it is not a Flutter frame-time measurement.

`native/subtitles/bench_video_contention.py` compares hardware decoding to a
null sink before and during continuous recognition. It currently selects an
NVIDIA D3D11VA decoder on Windows. This is decoder throughput, not application
FPS, and warm filesystem/driver caches can affect the comparison.

Native regression coverage includes Japanese explicit/Auto recognition,
timestamp boundaries, silence, language-memory invalidation and a controlled
CPU-to-GPU startup handoff. The controlled delay requires a helper built with
`CB_SUBTITLE_TEST_HOOKS=ON`; production builds leave it OFF.

## Windows measurement, 2026-11-07

Host: Core i5-14600K, RTX 5070 Ti, 64 GB RAM. Input: local Japanese H.264
3840×2160 video at 29.97 fps, AAC stereo. Models: Whisper Small and
Hy-MT2 1.8B Q4_K_M, bundled production Release helpers. Tests use portions of
the source, not an exhaustive run of the entire video. Driver/filesystem caches
were warm; these numbers are not cold-start guarantees or cross-device targets.

| Component measurement | Result |
| --- | --- |
| Auto ASR, eight successive 8 s increments plus overlap | 124.43 ms median; 341.47 ms maximum |
| ASR aggregate real-time factor, excluding model load | 0.0212 |
| ASR model initialization | 1,030 ms |
| Auto detection on those eight requests | Japanese on every request |
| Japanese → Vietnamese first visible subtitle | 3,002 ms |
| Idle uncached seek, first visible translated subtitle | 559 ms |
| Cached reopen, first visible subtitle | 102 ms; cue data restored in 11 ms |
| Processing runway after five seconds at playback 1x | 11.85–19.65 s; no lagging samples in the 15 s run |
| Service event-loop 16 ms probe | 0.976 ms p95 lateness; 51.072 ms maximum |

The service test retained one speech and one translation runtime across the
uncached seek, then stopped both and reopened from SQLite without another
model. Reports are in ignored `cb_file_manager/build/` files
`subtitle-performance-native-final.json` and
`subtitle-performance-session-final.json`.

An earlier decoder contention test reached 412.64 fps alone and 473.63 fps
during continuous GPU ASR. Both exceed the input frame rate by a wide margin;
cache/order effects prevent treating the difference as an improvement due to
ASR. This does not measure presentation, audio/video sync or Flutter rendering.

Validation: 194 related Dart tests passed (eight existing opt-in tests skipped),
nine GPU native tests passed, and eight CPU native tests passed (the GPU-only
handoff test skipped). Full Flutter analysis and the shared format check passed.
The full Windows Release build succeeded with Vulkan ON and test hooks OFF.

## Limits

Startup varies with driver shader caches, disk caches, other workloads, model
size and hardware. The CPU bridge reduces cold-GPU stalls but does not promise
zero startup delay. Processing seekable VOD ahead of playback differs from
streaming microphone ASR; non-seekable live sources remain unsupported.

Windows component measurements and release builds do not establish whole-app
rendering smoothness or macOS/Linux performance. A visual player smoke test and
project E2E require their own validation; no project E2E was run for this change.

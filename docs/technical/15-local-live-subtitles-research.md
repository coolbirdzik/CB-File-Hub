# Local live subtitles on desktop — research and proposal

Research date: **2026-11-07**. This records the research before implementation;
see [desktop local subtitles](../features/12-local-ai-subtitles.md) for the
implemented baseline, validation and remaining limits. Scope: Windows, macOS and Linux;
mobile is excluded from the first implementation.

## Recommendation

Build a replaceable two-stage pipeline: **speech recognition in the source
language, then text translation into the selected subtitle language**. Skip
translation when source and target match. Model quality, streaming support,
timestamps and native runtime support must be evaluated separately.

Start the proof of concept with **Whisper large-v3-turbo / whisper.cpp** as the
portable, timestamp-capable baseline. Benchmark **Qwen3-ASR 0.6B and 1.7B** as
multilingual alternatives and **Cohere Transcribe 03-2026** as an accuracy
candidate. For translation, try **Hy-MT2-1.8B GGUF / llama.cpp** first, with
Hy-MT2-7B and TranslateGemma-4B as comparison options. These are proposed
profiles, not validated defaults or a claim that one model wins every language.

## Speech model shortlist

| Model | Relevant strengths | Native/local deployment and limitations | Proposed role |
| --- | --- | --- | --- |
| Whisper large-v3-turbo; large-v3 | Multilingual recognition; large-v3 is the quality comparison to the faster turbo variant | Mature C/C++ implementation with CPU, CUDA, Vulkan and Metal paths. Whisper requires overlapping chunks for incremental captions; it is not a native streaming decoder. | Initial integration baseline; large-v3 optional quality profile |
| Qwen3-ASR 0.6B / 1.7B | 30 languages plus 22 Chinese dialects; includes Vietnamese, English, Turkish and Chinese; automatic language detection | Official streaming uses vLLM and returns no streaming timestamps. The transcribe.cpp C++ port currently supports offline chunks, without streaming or timestamps. | Priority challenger for multilingual recognition |
| Cohere Transcribe 03-2026, 2B | Strong published multilingual results; includes Vietnamese among 14 languages | Official model lacks automatic language detection, timestamps and diarization; code switching is a limitation. C++ port exists, but is offline. Turkish is outside its supported list. | Quality comparison with explicit source language |
| Voxtral Mini 4B Realtime 2602 | Native streaming; publisher recommends a 480 ms transcription delay | Open weights and C++ streaming port exist. Its 13-language list excludes Vietnamese and Turkish. ASR delay is not translated-caption end-to-end latency. | Optional low-latency source-language profile |
| Parakeet TDT 0.6B v3 | Efficient recognition with automatic language detection and timestamps | Covers 25 European languages; excludes Vietnamese, Chinese and Japanese. This restriction concerns v3, not every model named Parakeet. | Optional European-language performance comparison |
| Granite Speech 5.0 2B | Recent multilingual ASR and speech translation model | Published ASR/translation scope covers English, French, German, Spanish, Portuguese and Japanese; unsuitable as the universal Vietnamese-oriented default. | Watchlist / selected-language comparison |
| Meta Omnilingual ASR v2 | Breadth across 1,600+ languages; multiple model sizes | Evaluate if uncommon source languages become a requirement. Coverage alone does not establish desktop subtitle latency or timing quality. | Future language-coverage option |

Sources: [Whisper models](https://github.com/openai/whisper),
[whisper.cpp](https://github.com/ggml-org/whisper.cpp),
[Whisper streaming example](https://github.com/ggml-org/whisper.cpp/blob/master/examples/stream/README.md),
[Qwen official runtime](https://github.com/QwenLM/Qwen3-ASR),
[Qwen C++ capability limits](https://github.com/handy-computer/transcribe.cpp/blob/main/docs/models/qwen3-asr.md),
[Cohere model card](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026),
[Cohere C++ port](https://github.com/handy-computer/transcribe.cpp/blob/main/docs/models/cohere-transcribe-03-2026.md),
[Voxtral model card](https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602),
[Voxtral C++ port](https://github.com/handy-computer/transcribe.cpp/blob/main/docs/models/voxtral-realtime.md),
[Parakeet model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3),
[Granite 5.0 model card](https://huggingface.co/ibm-granite/granite-speech-5.0-2b),
[Omnilingual ASR](https://github.com/facebookresearch/omnilingual-asr).

New announcements must not be confused with downloadable desktop weights:
[Qwen-Audio-3.1-ASR](https://qwenaudio.github.io/qwen-audio-3.1-asr/)
(report dated October 20) documents newer capabilities, but the checked project
page routes integration to service APIs; this research did not establish public
local weights and a native runtime. Likewise,
[Voxtral Realtime 3](https://docs.mistral.ai/models/voxtral-mini-transcribe-realtime-3-0)
is listed as Premier, and should not inherit the open-weight status of 2602.

## Translation shortlist

| Model | Fit for this feature | Distribution/runtime considerations |
| --- | --- | --- |
| Hy-MT2-1.8B | First compact translation candidate; Vietnamese, English, Turkish and Chinese are in the published list | Apache-2.0; official GGUF and llama.cpp deployment instructions. Verify compatibility with the app's pinned runtime. |
| Hy-MT2-7B | Optional quality comparison for stronger desktops | More compute and memory; measure caption latency with ASR and video active. |
| TranslateGemma-4B; 12B/27B | Strong specialist comparison, with 55-language coverage | Gemma terms and access conditions; requires its specific source/target translation template. Larger variants are benchmark options rather than proposed defaults. |
| SeamlessM4T-v2-large | Direct speech translation comparison | Model card declares CC-BY-NC-4.0. Exclude from the default distributable model catalog under this proposal. |

Sources: [Hy-MT2 model card and supported languages](https://huggingface.co/tencent/Hy-MT2-1.8B),
[official Hy-MT2 GGUF](https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF),
[TranslateGemma model card](https://huggingface.co/google/translategemma-4b-it),
[SeamlessM4T model card](https://huggingface.co/facebook/seamless-m4t-v2-large).

Whisper's translation task targets English; turbo is not trained for that task.
It cannot implement arbitrary user-selected output languages by changing an
ASR language parameter. Preserve the original transcript and translate it once
into the requested target instead of routing every language through English.

## Download size and hardware interpretation

Example artifact sizes published by the C++ runtime maintainers: Qwen3-ASR
0.6B Q8_0 **850 MB**, 1.7B Q8_0 **2.19 GB**; Cohere Q5_K_M **1.77 GB**;
Voxtral Realtime 2602 Q4_K_M **2.83 GB**. These are weights on disk, not total
RAM/VRAM or a promise of real-time speed. Their reported English test-clean
results do not establish Vietnamese movie-caption accuracy.

Sources: [Qwen artifact table](https://github.com/handy-computer/transcribe.cpp/blob/main/docs/models/qwen3-asr.md),
[Cohere artifact table](https://github.com/handy-computer/transcribe.cpp/blob/main/docs/models/cohere-transcribe-03-2026.md),
[Voxtral artifact table](https://github.com/handy-computer/transcribe.cpp/blob/main/docs/models/voxtral-realtime.md).

Use Q4/Q5/Q8 variants only after checking native-port parity on the target
languages. Hy-MT2's advertised 440 MB extreme-quantization variant is a separate
artifact/runtime choice; do not assume the ordinary bundled llama-server can
load it. CPU-only operation must be supported where feasible, with an honest
slower-processing state. Hardware tiers remain unmeasured.

## Repository integration points before implementation

- `lib/services/media/media_kit_playback.dart`: shared `PlaybackPlayer` for
  main playback, PiP and frame picking. Exposes player state/streams; there is
  no decoded PCM subscription in this wrapper.
- `lib/ui/components/video/video_player/video_player.dart`: subtitle state is
  an empty track list and selection ID; audio-track dialog displays a stub.
- `video_player.settings.dart`: subtitle selection currently changes widget
  state; `video_player_advanced_menu.dart` disables subtitles for an empty list.
  AI subtitles must be available even when the video has no embedded subtitles.
- `lib/config/language_controller.dart`: current app locale and supported
  app languages are `en`, `vi`, `tr`, `zh`.
- `lib/services/local_ai/gguf_llama_cpp_runtime.dart`: existing out-of-process
  llama-server lifecycle. GPU inference is deliberately isolated from Flutter.
  `scripts/fetch_llama_runtime.sh` pins b10809; model compatibility is untested.
- `windows/runner/ffmpeg_thumbnail_helper.cpp` and runner CMake already use
  libavformat/libavcodec. CMake copies swresample DLLs but does not currently
  link swresample to the runner. Audio extraction still needs new code.
- `cb_native/rust/Cargo.toml`: existing optional native crate keeps pure-Rust
  dependencies for cross builds. Desktop ASR/C++ dependencies belong in a
  separate helper target rather than making this shared hook require C++/GPU.

Paths above are relative to `cb_file_manager/` unless explicitly prefixed.
These observations describe the source snapshot at the time of research.

## Proposed native architecture

```text
Selected media source + audio stream + media clock
  -> native demux/decode/resample -> 16 kHz mono PCM with source timestamps
  -> voice activity detection -> bounded overlapping speech chunks
  -> native ASR -> stable source cues -> optional native translation
  -> small timestamped cue events -> Flutter subtitle overlay
```

**C++:** FFmpeg/libav audio decode and resampling, whisper.cpp or transcribe.cpp
inference, and llama.cpp translation. **Rust:** bounded scheduling, cancellation,
overlap deduplication, cue/cache management and process supervision where useful.
**Dart:** controls, settings, lifecycle commands, playback clock and rendering.
Keep PCM, inference and per-sample processing outside the UI isolate.

Prefer a persistent desktop helper process for GPU inference, with a versioned
IPC contract. It can host Rust orchestration and C/C++ libraries or communicate
with a separately managed llama-server. Reuse lifecycle/download infrastructure
without replacing the CB Agent's active chat model or sharing its conversation.
Define a memory budget for video decoding, ASR and translation together.

On Windows, isolate helper DLL directories as the existing llama runtime does.
On macOS, package/sign helpers and dependent dylibs for each architecture.
Linux needs an explicit bundled or resolved runtime and its minimum libc/GPU
requirements; current Windows wiring does not prove Linux/macOS compatibility.

For seekable files, begin with an independent audio decoder reading a bounded
window ahead of playback. Reuse the resolved UNC/proxy source and correct audio
stream mapping; retain separate proxy leases and avoid logging credentials.
This costs a second demux/audio decode and possibly network reads. Use the
existing libav libraries where practical; no ffmpeg CLI installation is assumed.

For non-seekable/live sources, prove that a second connection yields the same
audio timeline, or implement a native player audio tap. That tap is an open
integration task, not an existing media_kit wrapper API. Consume the video's
audio rather than microphone/system loopback, so mute and volume do not disable
recognition and other apps' audio does not enter captions.

[Silero VAD](https://github.com/snakers4/silero-vad) is a suitable small native
VAD candidate. It detects speech activity, not speakers or linguistic content.
Silence/music gating, maximum chunk length and repeated-text suppression need
movie-specific evaluation.

## Subtitle timing and language behavior

- Settings: AI subtitles on/off; recognition model; translation model;
  source language Auto/manual where supported; target language; original/bilingual
  display; optional subtitle timing offset.
- Default target setting is the sentinel **Follow app language**, resolved from
  `LanguageController.currentLocale`, rather than a one-time copied locale.
  An explicit user selection persists and overrides app-language changes.
- Offer supported translation targets beyond the four app UI languages.
  Maintain separate ASR-input and translation-output capability lists. If a
  target is unavailable, explain it and offer a model download or another
  language; never silently substitute English.
- Track cues in original media time using decoded PTS/sample offsets, not wall
  time. Pause, 0.5x/2x playback and buffering must not shift cached cue times.
- For seekable video, try **5–15 seconds of bounded look-ahead** as a tuning
  starting point. For live sources, **2–5 seconds to stable translated text**
  is an initial engineering target, not a measured guarantee. Separate model
  warm-up, first partial, final source cue and final translated-cue latency.
- Qwen's published forced aligner supports 11 languages, excluding Vietnamese
  and Turkish. Its streaming runtime and checked C++ port do not supply the
  timestamps this feature needs. VAD/chunk bounds can produce coarse cue timing;
  precise timing needs a validated aligner or a timestamp-capable ASR backend.
- Emit replaceable partial text separately from finalized cues. Translate stable
  clauses with bounded prior context; preserve cue IDs/timing in native code,
  so a model cannot rewrite timestamps or duplicate an entire overlap window.
- Every open/seek/audio-track/model/source-language change advances a session
  generation and cancels stale work. Target changes invalidate translations,
  while retaining compatible source transcripts. Bound queues, memory and cache.
- When work falls behind, show the lag and prioritize current playback. Offer a
  smaller model or pre-generation; do not let queued inference grow indefinitely.
- Cache by media identity, selected audio stream, ASR model/version, source
  settings, translator/version and target language. Export only finalized cues
  as SRT/VTT when requested; share sessions across main/PiP where possible.

## Benchmark gate before choosing shipping defaults

1. Compare turbo, large-v3, Qwen 0.6B/1.7B and Cohere using the same decoded
   audio, chunking settings, quantization records and reference subtitles.
   Cover Vietnamese accents, English, Japanese, Korean, Chinese, Turkish,
   code switching, film music, overlapping speakers and long silence.
2. Score ASR WER/CER with a documented per-language normalization policy; score
   subtitle boundaries and duplicate/hallucinated cues separately. Evaluate
   translation adequacy, names, pronouns, negation and reading speed with human
   review, especially EN/JA/KO/ZH -> VI. Translation cannot repair missing ASR.
3. Measure p50/p95 first-partial and stable-caption latency, processing time per
   audio second, warm-up, peak RAM/VRAM, video dropped frames and contention with
   CB Agent. Sustained processing must beat the selected playback speed with
   headroom; batch throughput on H100 is not a desktop latency measurement.
4. Test CPU-only Windows, NVIDIA, AMD/Intel Vulkan and Apple Silicon; add Linux
   and Intel Mac validation for supported builds. Choose profiles from measured
   results rather than assigning GPU requirements from parameter count.
5. Verify seek/cancel, track changes, loop, pause/resume, rate changes, PiP,
   SMB/HTTP source lifetime, missing/corrupt models, offline restart, helper
   crash and GPU out-of-memory recovery. Pin runtime/model revisions and hashes.

No E2E command was run for this research. Executing project E2E tests requires
explicit authorization in the request under AGENTS.md. Implementation should
begin with audio/timestamp and native-model parity proofs before adding the full
desktop settings flow.

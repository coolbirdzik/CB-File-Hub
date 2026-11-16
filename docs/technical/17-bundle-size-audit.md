# Bundle size audit — 2026-11-16

Implementation and measured after-build results are recorded in
[Smaller native bundles](18-bundle-packaging.md). The findings below retain
the original investigation baseline.

Scope: Windows, macOS, Android and Linux. Source reviewed at `ea99caef`.
This is an investigation, not an implemented size reduction. No new app builds,
E2E runs or releases were performed. Sizes below are MiB (1,048,576 bytes),
counted from file lengths, not allocated disk space.

## Measurements and limits

| Platform | Available evidence | Size |
| --- | --- | --- |
| Windows x64 | Existing `build/windows/x64/runner/Release`, 119 files, latest file dated November 15 | 945.54 MiB unpacked |
| Linux x64 / Debian 13 | Existing November 8 artifacts, version 1.1.31 | 161.50 MiB unpacked; 58.46 MiB tar.gz; 41.49 MiB deb |
| macOS | Current build scripts and Xcode/Pods configuration | No local release artifact; savings not measured |
| Android | Current Gradle/CMake, release CI and resolved native package hooks | No local release APK/AAB; savings not measured |

These artifacts are not a same-commit cross-platform comparison. The Windows
directory may contain incremental-build residue; the major duplicate groups
also have explicit producers in the current build configuration. Rebuild clean
before accepting any shipping baseline.

The measured inventories, SHA-256 hashes and duplicate groups are saved locally
in `cb_file_manager/build/bundle-size-audit/2026-11-16.json` (ignored build
output, removed by a clean). GitNexus was bound to `coolbirdfm-flutter` and
refreshed to `ea99caef` during the audit. Its Windows FTS extension could not
load, so keyword search remained degraded. Source reads and binary hashes,
rather than absence of graph results, establish these findings.

## Windows: largest immediate opportunities

| Component | Unpacked size | Finding |
| --- | ---: | --- |
| Root directory | 498.22 MiB | Includes FFmpeg, LiteRT/OpenVINO, graphics runtimes and Flutter |
| `ffmpeg/` | 169.46 MiB | Full shared FFmpeg CLI runtime |
| `subtitles/` | 163.83 MiB | Worker, Vulkan loader and another FFmpeg copy |
| `llama/` | 76.07 MiB | Includes 53.00 MiB `ggml-vulkan.dll` |
| `data/` | 32.51 MiB | Includes 28.92 MiB Dart AOT `app.so` |
| `aria2/` | 5.45 MiB | Small relative to the other runtimes |

### 1. Share the FFmpeg DLLs: 249.83 MiB duplicate payload

SHA-256 confirms identical bytes in these locations:

| DLL | Copies | Redundant bytes in MiB |
| --- | ---: | ---: |
| `avcodec-62.dll` | root, ffmpeg, subtitles | 188.02 |
| `avformat-62.dll` | root, ffmpeg, subtitles | 42.66 |
| `avutil-60.dll` | root, ffmpeg, subtitles | 5.60 |
| `swresample-6.dll` | root, ffmpeg, subtitles | 1.38 |
| `swscale-9.dll` | root, ffmpeg | 12.17 |

Producers: `cb_file_manager/windows/runner/CMakeLists.txt` copies thumbnail
dependencies beside the runner, `windows/CMakeLists.txt` installs the CLI's DLLs
into `ffmpeg/`, and `native/subtitles/CMakeLists.txt` installs decoder DLLs into
`subtitles/`.

Keep one canonical FFmpeg runtime and change subprocess DLL discovery to use
it, including the native lossless-export launcher. Preserve subprocess
isolation and the subtitle worker's real Vulkan loader; Flutter's root
`vulkan-1.dll` is incompatible with the inference helpers. Moving the subtitle
or llama executable into the root directory is not a safe deduplication fix.
Validate imported DLLs and actual thumbnail, subtitle and export operations on
a machine without a developer FFmpeg installation.

### 2. Fix LiteRT filename aliases: 62.18 MiB duplicate payload

Five byte-identical pairs use names with and without a `lib` prefix:
`LiteRt`, `LiteRtWebGpuAccelerator`, `LiteRtTopKWebGpuSampler`,
`GemmaModelConstraintProvider` and `webgpu_dawn`.

The resolved `flutter_edge_ai_litertlm` 1.17.0 hook explicitly registers both
names: Dart Native Assets uses one naming convention, while the binaries' PE
imports require the original names. This is not proof the files are unused.
Fix the hook/FFI asset mapping in a maintained patch or upstream change so one
physical filename serves the required identities. Deleting aliases without
updating the loader can break `.litertlm` inference.

FFmpeg deduplication plus canonical LiteRT filenames has a file-counting
potential of about **312 MiB**, taking this directory from 945.54 to roughly
633.5 MiB. This is a candidate outcome, not a validated build result or ZIP/MSIX
download-size prediction. The complete duplicate inventory also includes tiny
shader/license duplicates.

### 3. Make expensive AI backends optional

The measured LiteRT family, including aliases, DXC, OpenVINO and TBB, occupies
283.49 MiB at the root. Its Intel NPU stack alone occupies 121.82 MiB; the
resolved plugin ships that stack on every Windows x64 build. The app has no
Intel-NPU packaging toggle today. A plugin-hook change would be required.

Possible products are CPU/GPU by default with an optional Intel NPU component,
or desktop runtimes installed when their model family is first selected.
These preserve capability only after adding runtime acquisition, integrity
checks, versioning, offline/error handling and correct loader paths. Both GGUF
and LiteRT are offered by the app, so removing either outright changes the
supported model set. Do not add the 62.18 MiB alias saving again when counting
removal of the entire 283.49 MiB family.

The 76.07 MiB llama runtime and the 43.34 MiB subtitle worker are additional
desktop component candidates. AI model weights are already acquired separately;
they are not the cause of this bundle size.

## macOS

1. Offer separate arm64 and x86_64 releases if smaller downloads are preferred
   over one Universal DMG. Both `fetch_macos_llama_runtime.sh` and
   `bundle_macos_llama_runtime.sh` unconditionally process both architectures.
   A thin Flutter build alone will still carry both llama runtimes unless
   those scripts also follow the selected architecture. Check every framework,
   native asset and helper slice, then sign the final staged app.
2. `bundle_macos_subtitle_runtime.sh` builds static FFmpeg for each requested
   architecture. It already disables encoders, muxers, filters and programs,
   but still builds the default decoders/demuxers. The worker selects only
   `AVMEDIA_TYPE_AUDIO`; evaluate an audio-decoder allowlist with the containers
   and network protocols the product supports. Measure before promising a gain.
3. Consider optional desktop AI components as above. Keep universal delivery
   if supporting both architectures in a single package is a requirement.
4. Inspect helper symbols before adding a strip step. The Xcode project already
   enables dead-code stripping; `COPY_PHASE_STRIP = NO` alone does not prove
   shipped code contains removable debug information. Any strip/thin operation
   must happen before final code signing.

## Android

1. Release APK production already uses `--split-per-abi`; Play releases already
   build AAB. Flutter's installed Gradle plugin enables release R8 and resource
   shrinking. Enabling those again is not a new saving. The generic build-test
   workflow still creates a fat APK, which should not be used as the release
   download-size baseline.
2. Measure arm64 separately. The external llama build targets arm64-v8a and
   x86_64; Gradle excludes armeabi-v7a libraries, while the release command uses
   Flutter's default ABI target list. Align the release targets with the actual
   supported set to avoid unsupported/irrelevant outputs. Removing x86_64 from
   an AAB mainly changes upload size when Play already serves per-device splits.
3. The app ships two AI engines: LiteRT-LM and a static `libcb_llama_server.so`
   executable, including mtmd. Profile these and libmpv before reducing Dart
   packages or assets. A LiteRT-only flavor would remove Android GGUF support;
   a text-only llama build would remove multimodal support.
4. `useLegacyPackaging = true` is deliberate: the OS must extract the llama
   executable into `nativeLibraryDir` for `Process.start`. Turning it off can
   break inference. An alternative requires changing how inference is launched
   or delivered, not just changing a compression setting. A desktop-style
   downloaded executable in writable app storage is blocked on Android 10+.
   Evaluate Play-delivered feature modules for optional native code separately.
5. Native PiP currently uses Media3 ExoPlayer alongside media_kit. Consolidating
   playback is a possible secondary investigation, with PiP lifecycle and codec
   parity work; no saving is quantified without a release APK.

## Linux

The older Debian 13 bundle spends **102.54 of 161.50 MiB** on LiteRT libraries,
about 63.5%. The largest are `libLiteRtLm.so` (34.68), model constraints (21.59),
the WebGPU sampler (13.84) and Dawn (13.19). Its subtitle worker is only 2.69 MiB.
System libmpv/FFmpeg dependencies keep those libraries outside the application
bundle; package size excludes dependencies that may need to be installed.

Prioritize optional LiteRT/GPU components and inspect upstream exported symbols
before attempting additional stripping. The `.deb` already uses xz;
`scripts/build.sh` produces a gzip portable archive. An additional tar.xz
artifact could reduce download size without reducing the installed footprint.
Keep per-distro builds and dependency checks because FFmpeg/libmpv ABIs differ.

## Shared priorities and verification

Fonts, icons and images are secondary: Windows has only about 3.6 MiB of data
outside Dart AOT, including ICU and notices. Rust already uses thin LTO,
one codegen unit and symbol stripping. Test size-oriented Rust optimization
against current search, image and archive performance before adopting it.

Recommended order:

1. Establish clean Release baselines, file inventories and compressed package
   sizes on each host; save artifact version, architecture and commit.
2. Deduplicate Windows FFmpeg while retaining the Vulkan isolation.
3. Fix LiteRT aliases and introduce explicit backend packaging controls.
4. Add macOS architecture-specific packaging and profile Android native libs.
5. Evaluate optional desktop AI components and smaller download formats.

Use Flutter 3.47.8 from `cb_file_manager/`. For Dart/native attribution,
`flutter build <windows|macos|linux> --release --analyze-size` and
`flutter build apk --release --analyze-size --target-platform=android-arm64`
produce reports. Save separate debug symbols and inspect native libraries too:
Dart tree shaking does not remove DLLs explicitly registered by build hooks.
Compare Android download/install sizes using a device-specific bundletool/Play
report, not the total AAB size. Run representative runtime checks after actual
loader or packaging changes; E2E requires the user's explicit authorization.

References: [Flutter app size measurement](https://docs.flutter.dev/perf/app-size),
[Flutter Android release and R8](https://docs.flutter.dev/deployment/android),
[Android 10 executable restrictions](https://developer.android.com/about/versions/10/behavior-changes-10#execute-permission).

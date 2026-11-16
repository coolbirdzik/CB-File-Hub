# Smaller native bundles

Implemented after the [2026-11-16 size audit](17-bundle-size-audit.md).
All sizes below use MiB (1,048,576 bytes). Runtime caches and previous local
builds are not part of the distributed application.

## Windows

The app, thumbnail helper, FFmpeg CLI and subtitle worker share one FFmpeg
installation at the application root. `ffmpeg.exe` and `LICENSE-FFmpeg.txt`
are beside `cb_file_hub.exe`. The existing lossless-export resolver supports
this location for both Dart and Rust process launchers.

The subtitle executable remains in `subtitles/`, together with the real
Vulkan loader. Its child environment prepends the app root to `PATH`, so
Windows finds the shared FFmpeg imports without moving the executable beside
Flutter/ANGLE's incompatible `vulkan-1.dll`. The llama server remains isolated
under `llama/`. Incremental installs remove the known legacy FFmpeg copies.

The local `flutter_edge_ai_litertlm` 1.17.0 patch preserves upstream Native
Assets IDs and maps them to the filenames actually named by the PE imports:

| Asset | Physical DLL |
| --- | --- |
| LiteRt | libLiteRt.dll |
| GemmaModelConstraintProvider | libGemmaModelConstraintProvider.dll |
| LiteRtTopKWebGpuSampler | libLiteRtTopKWebGpuSampler.dll |
| LiteRtWebGpuAccelerator | libLiteRtWebGpuAccelerator.dll |
| webgpu_dawn | webgpu_dawn.dll |

Dawn deliberately has no `lib` prefix: both WebGPU companions import
`webgpu_dawn.dll`. The explicit Dart library loader uses the same mapping.
No native binaries are rewritten and no symlinks or hardlinks are required.
The original archive checksums and runtime versions remain pinned upstream.

Intel NPU is an optional distribution component. CPU/GPU and both model
formats remain available in the default Windows build. To ship the Intel
OpenVINO/TBB stack, set this in `cb_file_manager/pubspec.yaml` and rebuild:

```yaml
hooks:
  user_defines:
    flutter_edge_ai_litertlm:
      intel_npu: true
```

The default is `false`, saving 121.82 MiB in the measured bundle. The runtime's
existing Native Assets manifest gate detects whether that backend is bundled.
Use a clean Release output when changing bundled backend options.
This is a build option, not an on-demand downloader. Core desktop AI remains
bundled, including Linux's LiteRT runtime; removing it would remove the local
model backend there. Signed runtime updates and an offline component installer
are separate work, not silently substituted for existing offline support.

Measured Windows results on 2026-11-16:

| Artifact | Size |
| --- | ---: |
| Previous local Release directory | 945.54 MiB |
| New Release, built into an empty directory | 511.71 MiB |
| Reduction | 433.83 MiB / 45.88% |
| New portable ZIP, deflate level 9 | 194.07 MiB |
| Remaining byte-identical duplicate payload | 0.02 MiB |

The baseline is the existing November 15 build, not a fresh build of identical
source with the old packaging. File hashes establish the FFmpeg/alias groups;
there are also normal Dart/source differences between builds. The savings are
installed-bundle bytes; there is no before/after ZIP percentage claim.

Verification: a second Release build, canonical DLL loads in a separate native
process, FFmpeg generation and stream-copy export of audio, subtitle-worker
decoding from its isolated directory, and 61 focused Flutter tests (including
real Dart/Rust exports). The Intel-NPU-enabled hook was also executed and its
asset list checked. These checks do not establish inference on an Intel NPU or
GPU/model compatibility on every driver.

### Further Windows reduction: purpose-built FFmpeg and solid archives

The follow-up Windows build is **366.99 MiB**, another **144.72 MiB / 28.28%**
below the 511.71 MiB intermediate bundle. The source-built FFmpeg runtime keeps
the native decoders, demuxers, muxers, bitstream filters, networking, Schannel
HTTPS, software AV1 through dav1d, and DXVA2/D3D11/D3D12 acceleration. The app's
thumbnail path uses D3D11. Only the basic CLI filters and two small utility
encoders (`pcm_s16le`, `wrapped_avframe`) remain; lossless exports use stream copy.
Capture devices and general-purpose transcoding encoders are excluded.

This is a runtime for the app's media operations, not the full FFmpeg CLI.
Compared with the previous full distribution, decoder implementations decrease
from 551 to 513. Alternative QSV/CUVID/AMF wrappers and optional external
decoders are absent. In particular AVS2/AVS3/JPEG XL and external caption
decoders do not have coverage parity with the old runtime. AAC, Opus, Vorbis,
MP3, FLAC, H.264, HEVC, VP9 and AV1 are exercised by the component checks.
`media_kit`'s self-contained libmpv remains unchanged and does not import the
app-root FFmpeg DLLs. A full development runtime can still be selected explicitly
with CMake's `FFMPEG_DIR` when those extra CLI/thumbnail codecs are required.

Build the smaller runtime from the repository root with
`just build-windows-ffmpeg`. It uses Linux's MinGW cross compiler (WSL on
Windows); required Debian/Ubuntu packages are listed at the top of
`scripts/build_windows_ffmpeg.sh`. The script pins and checks SHA-256 for FFmpeg
8.1.2, dav1d 1.5.3 and zlib 1.3.1. It stages headers, MSVC-compatible import
libraries, DLLs, licenses and the recipe into the ignored
`cb_file_manager/windows/ffmpeg-slim/` directory, outside `flutter clean`'s
output. MinGW's C11 thread DLL is included beside the shared FFmpeg DLLs.

CMake validates the recipe marker and required files before selecting the slim
runtime. A stale/incomplete marked runtime fails with a rebuild instruction.
Without a staged slim runtime, direct Windows development builds retain the
pinned full-download fallback. GitHub and GitLab CI always build/cache the slim
runtime on Linux and transfer it to their Windows jobs. Recipe changes invalidate
the cache. Incremental installs remove obsolete avdevice and legacy subfolder
DLLs using the resolved per-configuration bundle directory.

Windows portable builds now create **both ZIP and solid 7z**. The packaging
helper finds 7-Zip on PATH or under Program Files, creates a fresh temporary
archive, verifies it and atomically replaces the destination. This avoids
retaining deleted DLLs when an archive is updated. Missing/broken 7-Zip fails the
build; GitLab installs it if necessary. Release names, artifact upload paths,
release notes and website metadata recognize `.7z`.

The earlier 511.71 MiB bundle compressed to 106.44 MiB with solid 7z, versus
194.07 MiB with ZIP. The final FFmpeg bundle is **75.13 MiB** as solid 7z and
**138.71 MiB** as ZIP (deflate level 9). Both archives were read back and the
relative paths and SHA-256 of all **97 files** matched the Release bundle.
Archive compression reduces downloads, not installed bytes.

Validation on Windows with Flutter 3.47.8:

- Release build and final native install succeeded; full Dart analysis and
  source formatting passed.
- The complete repeated unit/widget run passed **2,337 visible tests**, with
  26 conditional skips. A macOS fixture expectation now uses the host path
  separator when simulated on Windows. A transient access-time sort failure
  passed in isolation and in the repeated full run; production sort code was
  not changed.
- Native component checks exercise actual stream copy, decoding, GDI+ thumbnail
  images and subtitle audio decoding across H.264/HEVC/VP9/AV1 with AAC/Opus,
  plus MP3/FLAC/Vorbis. Bundled libmpv decodes/plays the same clips with null
  video/audio outputs. Canonical LiteRT DLLs load and llama starts in its
  isolated directory.
- The subtitle worker passed English/Japanese recognition, timestamps, track
  selection and silence tests with a real base model, on CPU and GPU (8 passed
  per mode; the test-hook-only warmup test was skipped).
- The tested Rust size profile was rejected: its 3.68 MiB DLL saving slowed
  search-key normalization roughly 2–3x. Production Rust settings are unchanged.

CI generates its own synthetic clips and runs
`scripts/check_windows_media.ps1` after the Windows build. In release CI,
fixtures are downloaded **after** the build script's clean step. These are
component checks, not Flutter E2E; no E2E was run for this follow-up. macOS,
Android and Linux have no additional runtime changes in this step.


## macOS

`just macos` builds the app once, then stages and signs two copies:

- `CBFileHub-<version>-macos-arm64.dmg` for Apple Silicon.
- `CBFileHub-<version>-macos-x64.dmg` for Intel.

`stage_macos_arch_bundle.sh` removes the unused llama helper, thins Mach-O files
to the target architecture and fails if a required binary lacks that slice.
The staged helpers/frameworks and outer app are signed **after** thinning,
with the same signing identity used across updates. Release CI checks for both
DMGs. Fetch/bundle scripts follow Xcode's `ARCHS` for direct thin builds too.

The pinned LiteRT release has no Intel macOS artifact. The Intel copy omits
only its known arm-only optional frameworks, and the app defaults to the
bundled GGUF backend with a GGUF catalog there. Apple Silicon retains LiteRT
and GGUF. The existing macOS 13.3 minimum for the downloaded llama binaries
still applies; the file manager itself retains its existing deployment target.

Windows-hosted shell fixtures verify architecture pruning, source/license
preservation, missing-slice failures and overwrite protection. Native Mach-O
thinning/signing tests run on macOS CI; they are skipped on Windows. No macOS
DMG or Metal/Intel inference was validated locally during this change.

## Android

Release commands explicitly target `android-arm64,android-x64`, matching the
existing JNI support/exclusions. They no longer request or advertise a 32-bit
APK whose native runtime was already excluded. APK releases remain split by
ABI, and Play releases remain AAB. R8/resource shrinking were already enabled.

Keep `useLegacyPackaging = true`: Android must extract the llama executable
into `nativeLibraryDir`. Turning it off is not a compatible size optimization.
The Media3 PiP backend and both native AI engines remain present.

The native CMake target list and JNI packaging exclusions now follow Flutter's
`target-platform` property too. The first arm64 measurement still contained
25.61 MiB of x86_64 plugin/runtime libraries despite having only arm64 Dart and
engine code. Explicit JNI exclusions prevent those unrelated libraries from
entering single-ABI APKs, including on incremental builds with old JNI files.

Measured with Flutter 3.47.8, Release, arm64 target, on 2026-11-16:

| APK | Download/file size | Uncompressed entries |
| --- | ---: | ---: |
| Before target-specific JNI exclusions | 56.26 MiB | 135.31 MiB |
| After exclusions; verified arm64-v8a only | 45.99 MiB | 109.70 MiB |

The APK reduction is 18.26%. Native arm64 libraries occupy 101.07 MiB
uncompressed. Largest entries are LiteRT-LM (23.44 MiB), Dart AOT (22.75 MiB),
libmpv (11.80 MiB), Flutter (11.22 MiB), llama server (9.15 MiB), and cb_native
(8.79 MiB). These measurements retain both AI backends and Media3 PiP.
CI now verifies the native ABI set inside built APKs, not only their names.

Measure a single ABI from `cb_file_manager/` with the pinned Flutter SDK:

```sh
flutter build apk --release --analyze-size --target-platform=android-arm64
```

Allow the normal pub/tooling preparation when switching from tests/debug to a
Release build. Reusing `--no-pub` with a stale Android registrant can retain
dev-only plugin references even though Gradle excludes those plugins in Release.
The local measurement also used Kotlin's per-process `kotlin.incremental=false`
and `kotlin.compiler.execution.strategy=in-process` properties to avoid a
Windows cache error between the C: pub cache and the L: checkout. Project/CI
incremental compilation defaults are unchanged.

Then inventory the resulting APK from the repository root:

```sh
python scripts/audit_bundle_size.py cb_file_manager/build/app/outputs/flutter-apk/app-release.apk --expect-abis arm64-v8a --json cb_file_manager/build/bundle-size-audit/android-arm64.json
```

The report separates ZIP/compressed bytes, uncompressed entries and native
bytes per ABI. A total AAB size does not represent a device's Play download.

## Linux

Portable releases now include `.tar.xz` alongside the existing `.tar.gz` and
`.deb` packages. Release checks, GitHub/GitLab upload paths and download labels
include the new format. The installed files, system dependencies and per-distro
FFmpeg ABI rules are unchanged; the `.deb` already uses xz.

Recompressing the existing Debian 13 / 1.1.31 tar stream gave **58.46 MiB gzip
versus 41.35 MiB xz**, a **29.28%** download reduction. SHA-256 of both
decompressed tar streams is identical. This is a compression comparison on an
older artifact, not a fresh Linux build or a reduction in installed size.

## Repeatable checks

From the repository root:

```sh
node --test scripts/tests/macos_arch_bundle.test.mjs scripts/tests/macos_subtitle_bundle.test.mjs scripts/tests/windows_build.test.mjs
python -m unittest discover -s scripts/tests -p test_audit_bundle_size.py -v
python scripts/audit_bundle_size.py cb_file_manager/build/windows/x64/runner/Release --json cb_file_manager/build/bundle-size-audit/windows-after.json
```

For native Windows component checks, set `CB_BUNDLE_DIR` to the full Release
directory, then run `python -m unittest discover -s scripts/tests -p
test_windows_bundle_runtime.py -v`. CI runs this after its Windows build.
This launches native helper components, not the Flutter application or E2E
runner. E2E remains subject to explicit user authorization.

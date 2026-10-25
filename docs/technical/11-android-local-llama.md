# Android local GGUF runtime

GGUF models use llama.cpp's HTTP server on Windows and Android. LiteRT-LM
models continue to use Flutter Gemma. Android previously dispatched GGUF
requests to the Windows executable resolver without shipping an Android server.

## Build and packaging

`cb_file_manager/android/app/src/main/cpp/CMakeLists.txt` fetches llama.cpp
**b10809**, verifies the source archive SHA-256, and builds a CPU server with
the Android NDK. Gradle runs this build automatically for `arm64-v8a` and
`x86_64`; no manual runtime download is needed. The first build needs network
access to GitHub. The native build disables OpenMP, OpenSSL, GPU backends,
dynamic backend loading and the embedded web UI. C++ dependencies link
statically into the server. ELF load segments use 16 KB alignment.

The PIE executable is named `libcb_llama_server.so` so Android packages it as
a native library. Variant-specific generated `jniLibs` folders feed APK/AAB
packaging, and the merge tasks depend on the native build. Keep
`jniLibs.useLegacyPackaging = true`: the installer must extract native files
into `ApplicationInfo.nativeLibraryDir`. A binary downloaded/copied into the
writable app home cannot be executed by apps targeting Android 10+.
See [Android's execution restrictions](https://developer.android.com/about/versions/10/behavior-changes-10#execute-permission).

`MainActivity` exposes the installed executable path through
`cb_file_manager/local_ai` / `getLlamaServerPath`. Dart launches that path
directly, with a loopback HTTP listener. Models stay in the existing model
storage directory. An APK rebuild and reinstall is required; hot reload
cannot install the native executable or MethodChannel handler.

## Runtime behavior

Android forces CPU inference, one chat slot, 128-token logical/micro batches
and no RAM prompt cache. The configured context window is preserved. Large
models still require enough device memory for weights, context and temporary
buffers. The existing Windows Vulkan settings and isolated `llama/` folder
remain in use on Windows.

The Android entry point watches its parent process and kills the server within
one second if Flutter dies. It watches the process PID because
[`PR_SET_PDEATHSIG` follows the spawning thread's lifetime](https://man7.org/linux/man-pages/man2/PR_SET_PDEATHSIG.2const.html#CAVEATS),
which may be shorter than the Dart app's lifetime. Normal disposal and model/context changes terminate the server
through the existing Dart lifecycle. Startup failures retain the last 8 KB of
stderr in the application log and error instead of discarding loader/model
diagnostics.

## Verification

Run Flutter/Dart commands from `cb_file_manager/` with Flutter 3.47.8:

```sh
flutter test test/services/local_ai/llama_cpp_server_launch_test.dart test/services/local_ai/llama_cpp_chat_client_test.dart test/14_local_ai_advisor_service_test.dart
flutter build apk --debug --target-platform android-arm64
```

Check the resulting APK contains
`lib/arm64-v8a/libcb_llama_server.so`, and run the repository's
`scripts/check_android_page_sizes.mjs` against it. Device verification needs
an installed APK and a downloaded GGUF: select the model, send a chat message,
then switch models/context and confirm the server restarts. Unit tests verify
platform resolution and launch settings; they do not establish device
inference performance or memory requirements.

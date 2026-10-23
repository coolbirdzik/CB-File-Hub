# macOS local GGUF runtime

GGUF inference uses the official llama.cpp **b10809** server. An Xcode Runner
build phase runs `scripts/bundle_macos_llama_runtime.sh`, so direct Flutter
builds, `just macos-dev` and release DMG builds all include the runtime.

`scripts/fetch_macos_llama_runtime.sh` downloads the arm64 and Intel archives,
verifies their pinned SHA-256 values, and copies the server and its exact
`@rpath` dylib dependencies. Downloads live in the ignored
`cb_file_manager/build/llama-runtime/macos/` cache. Extracted files are restored
from the verified archives on each build. The helpers are placed under
`Contents/Helpers/llama/{arm64,x86_64}/`; keeping dependencies next to each
server preserves the upstream `@loader_path` search path. Xcode signs each
helper and dylib before signing the app. Release tooling re-signs them with
the final app identity before its existing deep signature verification.

`LocalAiRuntimeChannel.swift` returns the correct helper for the running app's
architecture, including an Intel slice running under Rosetta. Dart keeps GPU
offload enabled: the arm64 archive includes Metal, while the Intel archive
uses CPU/Accelerate. The existing Windows and Android launch settings remain.

**The official b10809 macOS binaries require macOS 13.3 or later.** Their
Mach-O `LC_BUILD_VERSION` sets that minimum. The app's existing macOS 12
deployment target remains; on earlier systems this GGUF backend reports its
OS requirement instead of attempting to launch incompatible code. Model
downloads and the other AI providers remain separate from this backend.

A rebuild and reinstall is required to add the Swift channel and helper files.
Hot reload cannot install them. Validation on a Mac should include
`flutter build macos --release` from `cb_file_manager/`,
`codesign --verify --deep --strict <app-path>`, and a chat with a downloaded
GGUF model. Windows-hosted checks cover channel resolution, archive hashes,
dependency closure and bundle/signing command wiring; they do not establish
Mac startup, Metal inference or successful code signing.

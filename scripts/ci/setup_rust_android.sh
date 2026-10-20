#!/usr/bin/env bash
# Prepares Rust for cb_native's Android build (cb_native/hook/build.dart).
#
# Without these targets the hook still succeeds but bundles nothing, and the
# APK silently falls back to the slower Dart search. Installs a minimal rustup
# toolchain when the runner image has none (e.g. ghcr.io/cirruslabs/flutter).
set -euo pipefail

targets=(aarch64-linux-android armv7-linux-androideabi x86_64-linux-android)

if ! command -v rustup >/dev/null 2>&1; then
  if [ -x "$HOME/.cargo/bin/rustup" ]; then
    export PATH="$HOME/.cargo/bin:$PATH"
  else
    echo '==> Installing rustup (minimal profile)'
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs |
      sh -s -- -y --profile minimal --default-toolchain stable
    export PATH="$HOME/.cargo/bin:$PATH"
  fi
fi

echo "==> Adding Rust targets: ${targets[*]}"
rustup target add "${targets[@]}"

# Later CI steps run in fresh shells; expose cargo to them too.
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$HOME/.cargo/bin" >>"$GITHUB_PATH"
fi

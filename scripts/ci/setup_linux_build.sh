#!/usr/bin/env bash
# Installs what `scripts/build.sh linux` needs on a Debian or Ubuntu image
# (CI containers run as root; elsewhere sudo is used).
#
# - Flutter Linux toolchain: clang, cmake, ninja, pkg-config, GTK 3.
# - Plugin libraries: libmpv + epoxy (media_kit_video), libsecret
#   (flutter_secure_storage_linux).
# - dpkg-dev for dpkg-shlibdeps, which derives the .deb Depends.
# - jq/curl/unzip/xz for subosito/flutter-action, and a minimal rustup so
#   cb_native's build hook bundles the Rust helpers (it is optional; without
#   cargo the app falls back to Dart).
set -euo pipefail

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update
$SUDO apt-get install -y --no-install-recommends \
  ca-certificates curl git jq unzip xz-utils zip file \
  build-essential clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev \
  libmpv-dev libepoxy-dev libsecret-1-dev \
  libavformat-dev libavcodec-dev libavutil-dev libswresample-dev \
  dpkg-dev

# Flutter runs git inside its SDK and the checkout, which belong to another
# uid in containers.
git config --global --add safe.directory '*'

if ! command -v cargo >/dev/null 2>&1 && [ ! -x "$HOME/.cargo/bin/cargo" ]; then
  echo '==> Installing rustup (minimal profile)'
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs |
    sh -s -- -y --profile minimal --default-toolchain stable
fi

# Later CI steps run in fresh shells; expose cargo to them too.
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$HOME/.cargo/bin" >>"$GITHUB_PATH"
fi

echo "==> libmpv: $(pkg-config --modversion mpv)  glibc: $(ldd --version | head -n1)"

#!/usr/bin/env bash

# Fetch the bundled llama.cpp Windows runtime (Vulkan build) used by the
# Local AI feature. These DLLs + llama-server.exe are large binaries (~69MB)
# and are NOT committed to git; they are downloaded here at build time and
# extracted into cb_file_manager/windows/llama/.
#
# Usage:
#   scripts/fetch_llama_runtime.sh          # download if missing
#   scripts/fetch_llama_runtime.sh --force  # re-download even if present
#
# The Windows CMakeLists.txt installs everything in windows/llama/ into a
# "llama" subfolder next to the app exe at build time.

set -euo pipefail

# llama.cpp release to bundle. Keep in sync with the ABI the Dart HTTP client
# talks to (the server is launched as a subprocess, so only the HTTP contract
# matters, but pinning avoids surprise behavior changes).
LLAMA_RELEASE_TAG="b10809"
LLAMA_SHA256="97e50b3ef0cdd2cb4d5afd446a9006b3496bee6c0d0ba7083d32f36075771870"
LLAMA_ASSET="llama-${LLAMA_RELEASE_TAG}-bin-win-vulkan-x64.zip"
LLAMA_URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_RELEASE_TAG}/${LLAMA_ASSET}"

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
DEST_DIR="$REPO_DIR/cb_file_manager/windows/llama"

# The exact set of files the app bundles. The Vulkan zip contains many extra
# tools (llama-cli.exe, llama-tts.exe, etc.) we do not ship.
REQUIRED_FILES=(
  "ggml-base.dll"
  "ggml-cpu-x64.dll"
  "ggml-vulkan.dll"
  "ggml.dll"
  "libomp.dll"
  "LICENSE-LLVM-OpenMP"
  "llama-common.dll"
  "llama.dll"
  "llama-server-impl.dll"
  "mtmd.dll"
  "llama-server.exe"
)

FORCE=0
if [ "${1:-}" = "--force" ]; then
  FORCE=1
fi

all_present() {
  [ -f "$DEST_DIR/.runtime-version" ] || return 1
  [ "$(cat "$DEST_DIR/.runtime-version")" = "$LLAMA_RELEASE_TAG $LLAMA_SHA256" ] || return 1
  for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$DEST_DIR/$f" ]; then
      return 1
    fi
  done
  return 0
}

if [ "$FORCE" -eq 0 ] && all_present; then
  echo "[fetch_llama_runtime] All runtime files already present in $DEST_DIR; skipping download."
  echo "[fetch_llama_runtime] Use --force to re-download."
  exit 0
fi

mkdir -p "$DEST_DIR"

TMP_DIR="$(mktemp -d)"
TMP_DIR="$(cd -- "$TMP_DIR" && pwd)"
cleanup() {
  # Only remove the exact temporary directory created by this invocation.
  case "$TMP_DIR" in
    /tmp/tmp.*|/c/Users/*/AppData/Local/Temp/tmp.*) rm -rf -- "$TMP_DIR" ;;
  esac
}
trap cleanup EXIT

ZIP_PATH="$TMP_DIR/$LLAMA_ASSET"
EXTRACT_DIR="$TMP_DIR/extracted"
mkdir -p "$EXTRACT_DIR"

echo "[fetch_llama_runtime] Downloading $LLAMA_URL"
if command -v curl >/dev/null 2>&1; then
  curl -fL --retry 3 -o "$ZIP_PATH" "$LLAMA_URL"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$ZIP_PATH" "$LLAMA_URL"
else
  echo "[fetch_llama_runtime] ERROR: neither curl nor wget is available." >&2
  exit 1
fi

echo "$LLAMA_SHA256  $ZIP_PATH" | sha256sum --check --status || {
  echo "[fetch_llama_runtime] ERROR: archive checksum mismatch." >&2
  exit 1
}

echo "[fetch_llama_runtime] Extracting..."
if command -v unzip >/dev/null 2>&1; then
  unzip -q -o "$ZIP_PATH" -d "$EXTRACT_DIR"
elif command -v 7z >/dev/null 2>&1; then
  7z x -y -o"$EXTRACT_DIR" "$ZIP_PATH" >/dev/null
elif command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -Command "Expand-Archive -Force -Path '$ZIP_PATH' -DestinationPath '$EXTRACT_DIR'"
else
  echo "[fetch_llama_runtime] ERROR: no unzip tool (unzip/7z/powershell) available." >&2
  exit 1
fi

# Validate the complete archive before replacing any installed runtime file.
missing=0
for f in "${REQUIRED_FILES[@]}"; do
  src="$(find "$EXTRACT_DIR" -type f -name "$f" -print -quit 2>/dev/null || true)"
  if [ -z "$src" ]; then
    echo "[fetch_llama_runtime] ERROR: '$f' not found in the downloaded archive." >&2
    missing=1
    continue
  fi
done

if [ "$missing" -ne 0 ]; then
  echo "[fetch_llama_runtime] ERROR: one or more required files were missing." >&2
  exit 1
fi

echo "[fetch_llama_runtime] Copying required files to $DEST_DIR"
rm -f -- "$DEST_DIR/.runtime-version"
for f in "${REQUIRED_FILES[@]}"; do
  src="$(find "$EXTRACT_DIR" -type f -name "$f" -print -quit)"
  cp -f "$src" "$DEST_DIR/$f"
done
printf '%s %s\n' "$LLAMA_RELEASE_TAG" "$LLAMA_SHA256" > "$DEST_DIR/.runtime-version"

echo "[fetch_llama_runtime] Done. Runtime ready in $DEST_DIR"

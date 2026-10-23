#!/usr/bin/env bash
# Pinned official runtimes. Metal on Apple Silicon, CPU/Accelerate on Intel.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="${CB_LLAMA_MACOS_CACHE:-$SCRIPT_DIR/../cb_file_manager/build/llama-runtime/macos}"
TAG=b10809
mkdir -p "$CACHE"

hash_file() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

for arch in arm64 x86_64; do
    if [ "$arch" = arm64 ]; then
        asset_arch=arm64
        expected=7d692df9e1e386e62f1c12b843903218041e6cd74c9415aa39a7ed3176f9eaa2
    else
        asset_arch=x64
        expected=13b34aa8a5d87341a21065a83f54a8167e1aaa6fe0d66065de01632a1ed64be6
    fi
    asset="llama-$TAG-bin-macos-$asset_arch.tar.gz"
    archive="$CACHE/$asset"
    if [ ! -f "$archive" ] || [ "$(hash_file "$archive")" != "$expected" ]; then
        echo "[llama macOS] Downloading $asset"
        curl --fail --location --retry 3 --silent --show-error \
            "https://github.com/ggml-org/llama.cpp/releases/download/$TAG/$asset" \
            --output "$archive"
    fi
    if [ "$(hash_file "$archive")" != "$expected" ]; then
        echo "error: Checksum mismatch for $asset" >&2
        exit 1
    fi
    files=(llama-server libllama-server-impl.dylib libllama-common.0.dylib
        libmtmd.0.dylib libllama.0.dylib libggml.0.dylib libggml-cpu.0.dylib
        libggml-blas.0.dylib libggml-rpc.0.dylib libggml-base.0.dylib LICENSE)
    if [ "$arch" = arm64 ]; then files+=(libggml-metal.0.dylib); fi
    # Extract regular files only, renaming versioned dylibs to their install
    # names. This avoids duplicate aliases and does not require symlink support.
    sources=()
    members=()
    for file in "${files[@]}"; do
        case "$file" in
            libggml*.0.dylib) source_file="${file%.0.dylib}.0.23.0.dylib" ;;
            libllama-common.0.dylib|libllama.0.dylib|libmtmd.0.dylib)
                source_file="${file%.0.dylib}.0.4.0.dylib" ;;
            *) source_file="$file" ;;
        esac
        sources+=("$source_file")
        members+=("llama-$TAG/$source_file")
    done
    # Re-extract verified archives so damaged extracted caches repair themselves.
    mkdir -p "$CACHE/extracted/$arch" "$CACHE/runtime/$arch"
    tar -xzf "$archive" -C "$CACHE/extracted/$arch" "${members[@]}"
    src="$CACHE/extracted/$arch/llama-$TAG"
    dest="$CACHE/runtime/$arch"
    for i in "${!files[@]}"; do
        cp "$src/${sources[$i]}" "$dest/${files[$i]}"
    done
    chmod 755 "$dest/llama-server"
    echo "[llama macOS] Verified $TAG $arch"
done

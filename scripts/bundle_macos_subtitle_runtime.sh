#!/usr/bin/env bash
# Universal, self-contained helper: static FFmpeg avoids Homebrew architecture
# and dylib-path dependencies in an Apple Silicon + Intel app bundle.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
: "${TARGET_BUILD_DIR:?Xcode TARGET_BUILD_DIR is required}"
: "${CONTENTS_FOLDER_PATH:?Xcode CONTENTS_FOLDER_PATH is required}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v cmake >/dev/null || ! command -v pkg-config >/dev/null; then
    echo 'error: Local subtitles require cmake and pkg-config (brew install cmake pkg-config).'
    exit 1
fi
cache="$REPO_DIR/cb_file_manager/build/subtitle-runtime/macos"
mkdir -p "$cache"
archive="$cache/ffmpeg-n8.1.2.tar.gz"
sha=9fd092511605bbebafe095ea6d38d9e40f34d12f7386e1258372df8be0576eb7
if [ ! -f "$archive" ] || [ "$(shasum -a 256 "$archive" | awk '{print $1}')" != "$sha" ]; then
    curl --fail --location --retry 3 --connect-timeout 15 --max-time 300 \
        https://codeload.github.com/FFmpeg/FFmpeg/tar.gz/refs/tags/n8.1.2 -o "$archive"
fi
if [ "$(shasum -a 256 "$archive" | awk '{print $1}')" != "$sha" ]; then
    echo 'error: FFmpeg source checksum mismatch'; exit 1
fi
source_dir="$cache/FFmpeg-n8.1.2"
if [ ! -f "$source_dir/configure" ]; then tar -xzf "$archive" -C "$cache"; fi
sdk="$(xcrun --sdk macosx --show-sdk-path)"
minimum="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
helpers=()
for arch in ${ARCHS:-$(uname -m)}; do
    case "$arch" in arm64|x86_64) ;; *) echo "error: Unsupported subtitle architecture $arch"; exit 1 ;; esac
    prefix="$cache/ffmpeg/$arch"
    work="$cache/ffmpeg-build/$arch"
    marker="$sha-$arch-$minimum"
    if [ ! -f "$prefix/.ready" ] || [ "$(cat "$prefix/.ready")" != "$marker" ]; then
        mkdir -p "$work"
        (cd "$work" && bash "$source_dir/configure" \
            --prefix="$prefix" --arch="$arch" --target-os=darwin --enable-cross-compile \
            --cc="$(xcrun -f clang)" --enable-static --disable-shared --enable-pic \
            --disable-autodetect --enable-securetransport --disable-x86asm \
            --disable-programs --disable-doc --disable-avdevice --disable-avfilter \
            --disable-swscale --disable-encoders --disable-muxers \
            --extra-cflags="-arch $arch -isysroot $sdk -mmacosx-version-min=$minimum" \
            --extra-ldflags="-arch $arch -isysroot $sdk -mmacosx-version-min=$minimum" && \
            make -j4 && make install)
        printf '%s' "$marker" > "$prefix/.ready"
    fi
    build="$cache/helper/$arch"
    PKG_CONFIG_PATH="$prefix/lib/pkgconfig" cmake -S "$REPO_DIR/native/subtitles" -B "$build" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$minimum" -DPKG_CONFIG_ARGN=--static
    cmake --build "$build" --config Release --target cb-subtitle-worker --parallel 4
    helpers+=("$build/bin/cb-subtitle-worker")
done
dest="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/subtitles"
mkdir -p "$dest"
lipo -create "${helpers[@]}" -output "$dest/cb-subtitle-worker"
# The shipped helper must not depend on the build machine's package manager.
if otool -L "$dest/cb-subtitle-worker" | grep -Eq '/(opt/homebrew|usr/local)/'; then
    echo 'error: Subtitle helper has an unbundled package-manager dependency'; exit 1
fi
if [ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --timestamp=none "$dest/cb-subtitle-worker"
fi
cp "$build/_deps/whisper-src/LICENSE" "$dest/LICENSE-whisper"
cp "$source_dir/COPYING.LGPLv2.1" "$dest/LICENSE-FFmpeg"
cp "$REPO_DIR/native/subtitles/THIRD_PARTY_NOTICES.md" "$dest/"

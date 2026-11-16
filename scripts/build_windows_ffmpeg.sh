#!/usr/bin/env bash
# Cross-build the shared Windows runtime on Linux (including WSL Debian).
# apt-get install gcc libc6-dev gcc-mingw-w64-x86-64-posix g++-mingw-w64-x86-64-posix \
#   make nasm pkg-config meson ninja-build curl ca-certificates xz-utils
set -euo pipefail
script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
cache="${CB_FFMPEG_BUILD_CACHE:-${HOME:?}/.cache/cb-file-hub/windows-ffmpeg}"
destination="${1:-$repo_dir/cb_file_manager/windows/ffmpeg-slim}"
recipe=$(sha256sum "$0" | awk '{print $1}')
prefix="$cache/$recipe/runtime"
work="$cache/$recipe/work"
mkdir -p "$cache/sources" "$work"
for tool in gcc x86_64-w64-mingw32-gcc x86_64-w64-mingw32-g++ make nasm pkg-config meson ninja curl; do
    command -v "$tool" >/dev/null || { echo "Missing build tool: $tool" >&2; exit 1; }
done
fetch() {
    local name=$1 sha=$2 url=$3
    if ! [ -f "$cache/sources/$name" ] || ! echo "$sha  $cache/sources/$name" | sha256sum --status -c; then
        curl --fail --location --retry 3 --connect-timeout 20 "$url" -o "$cache/sources/$name"
    fi
    echo "$sha  $cache/sources/$name" | sha256sum -c
}
if ! [ -f "$prefix/.runtime-version" ]; then
    fetch ffmpeg-8.1.2.tar.xz 464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c \
        https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz
    fetch dav1d-1.5.3.tar.xz 732010aa5ef461fa93355ed2c6c5fedb48ddc4b74e697eaabe8907eaeb943011 \
        https://downloads.videolan.org/pub/videolan/dav1d/1.5.3/dav1d-1.5.3.tar.xz
    fetch zlib-1.3.1.tar.gz 9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23 \
        https://zlib.net/fossils/zlib-1.3.1.tar.gz
    tar -xf "$cache/sources/ffmpeg-8.1.2.tar.xz" -C "$work"
    tar -xf "$cache/sources/dav1d-1.5.3.tar.xz" -C "$work"
    tar -xf "$cache/sources/zlib-1.3.1.tar.gz" -C "$work"
    jobs="${CB_FFMPEG_BUILD_JOBS:-4}"
    (cd "$work/zlib-1.3.1" && CHOST=x86_64-w64-mingw32 ./configure --static --prefix="$prefix" && make -j"$jobs" && make install)
    cat > "$work/mingw.ini" <<'EOF'
[binaries]
c = 'x86_64-w64-mingw32-gcc'
cpp = 'x86_64-w64-mingw32-g++'
ar = 'x86_64-w64-mingw32-ar'
strip = 'x86_64-w64-mingw32-strip'
windres = 'x86_64-w64-mingw32-windres'
pkg-config = 'pkg-config'
[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF
    meson setup "$work/dav1d-build" "$work/dav1d-1.5.3" --cross-file "$work/mingw.ini" \
        --prefix "$prefix" --buildtype release --default-library static \
        -Denable_tools=false -Denable_tests=false
    ninja -C "$work/dav1d-build" -j"$jobs" install
    mkdir -p "$work/ffmpeg-build"
    (cd "$work/ffmpeg-build" && PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" \
        "$work/ffmpeg-8.1.2/configure" --prefix="$prefix" \
        --arch=x86_64 --target-os=mingw32 --cross-prefix=x86_64-w64-mingw32- \
        --enable-cross-compile --enable-shared --disable-static --disable-debug --disable-doc \
        --disable-autodetect --enable-gpl --enable-version3 --disable-ffplay \
        --disable-avdevice --disable-filters --enable-filter=aresample,scale \
        --disable-encoders --enable-encoder=pcm_s16le,wrapped_avframe \
        --enable-libdav1d --enable-zlib --enable-schannel \
        --enable-dxva2 --enable-d3d11va --enable-d3d12va --disable-pthreads --enable-w32threads \
        --extra-cflags="-I$prefix/include" --extra-ldflags="-L$prefix/lib -static-libgcc -static-libstdc++" \
        --pkg-config=pkg-config --pkg-config-flags=--static && make -j"$jobs" && make install)
    mkdir -p "$prefix/licenses"
    cp "$work/ffmpeg-8.1.2/COPYING.GPLv3" "$prefix/LICENSE.txt"
    cp "$work/dav1d-1.5.3/COPYING" "$prefix/licenses/LICENSE-dav1d.txt"
    cp "$work/zlib-1.3.1/LICENSE" "$prefix/licenses/LICENSE-zlib.txt"
    # MinGW installs the MSVC-compatible import libraries beside the DLLs.
    # Our CMake consumers intentionally use the usual development lib/ layout.
    cp "$prefix"/bin/*.lib "$prefix/lib/"
    # C11 thread support in avutil uses MinGW's small runtime even though the
    # FFmpeg worker pool itself uses native Win32 threads.
    cp /usr/x86_64-w64-mingw32/lib/libwinpthread-1.dll "$prefix/bin/"
    cp /usr/share/doc/mingw-w64-common/copyright "$prefix/licenses/LICENSE-MinGW.txt"
    cp "$0" "$prefix/licenses/build_windows_ffmpeg.sh"
    printf '%s\n' "$recipe" > "$prefix/.runtime-version"
fi
mkdir -p "$destination"
cp -a "$prefix/." "$destination/"
echo "Windows FFmpeg runtime staged at $destination (recipe $recipe)"

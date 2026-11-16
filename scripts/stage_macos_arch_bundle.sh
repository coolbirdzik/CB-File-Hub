#!/usr/bin/env bash
# Copy a Universal app, retain one architecture, then let the caller sign it.
set -euo pipefail
die() { echo "stage_macos_arch_bundle: $*" >&2; exit 1; }
[ "$#" -eq 3 ] || die 'usage: <source.app> <new-destination.app> <arm64|x86_64>'
source_app=$1
dest=$2
arch=$3
case "$arch" in arm64) other=x86_64 ;; x86_64) other=arm64 ;; *) die "unsupported architecture $arch" ;; esac
[ -d "$source_app/Contents" ] || die 'source is not an app bundle'
[ ! -e "$dest" ] || die 'destination already exists'
mkdir -p "$(dirname "$dest")"
dest="$(cd "$(dirname "$dest")" && pwd)/$(basename "$dest")"
ditto "$source_app" "$dest"

# This is exclusively the copied app's unused llama architecture, not the
# source app or runtime cache. Keep licenses in Contents/Resources.
unused="$dest/Contents/Helpers/llama/$other"
case "$unused" in "$dest"/Contents/Helpers/llama/arm64|"$dest"/Contents/Helpers/llama/x86_64) ;; *) die 'unsafe helper path' ;; esac
rm -rf -- "$unused"

# LiteRT-LM 1.17 ships Apple Silicon assets only. Flutter's x64 native-assets
# map has no entries for them. Remove just these arm-only optional frameworks
# from the Intel copy; its local AI uses the bundled x86_64 llama server.
if [ "$arch" = x86_64 ]; then
    for base in LiteRtLm StreamProxy GemmaModelConstraintProvider LiteRtLmMetalAccelerator LiteRtTopKMetalSampler; do
        framework="$dest/Contents/Frameworks/$base.framework"
        binary="$framework/$base"
        if [ -f "$binary" ]; then
            slices="$(lipo -archs "$binary")"
            case " $slices " in *" x86_64 "*) ;; *) rm -rf -- "$framework" ;; esac
        fi
    done
fi

count=0
while IFS= read -r -d '' item; do
    case "$(file -b "$item")" in *Mach-O*) ;; *) continue ;; esac
    slices="$(lipo -archs "$item")"
    case " $slices " in *" $arch "*) ;; *) die "$item has no $arch slice ($slices)" ;; esac
    if [ "$slices" != "$arch" ]; then
        # Write beside the original, preserving permissions and framework links.
        lipo "$item" -thin "$arch" -output "$item.cb-thin"
        chmod "$(stat -f '%Lp' "$item")" "$item.cb-thin"
        mv -f "$item.cb-thin" "$item"
    fi
    count=$((count + 1))
done < <(find "$dest/Contents" -type f -print0)
[ "$count" -gt 0 ] || die 'no Mach-O binaries found'
echo "Staged $arch app ($count Mach-O files); sign before distribution."

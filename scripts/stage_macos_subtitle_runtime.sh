#!/usr/bin/env bash
# Stage an already-built helper. Data files belong in Resources, never Helpers:
# https://developer.apple.com/library/archive/technotes/tn2206/
set -euo pipefail

if [ "$#" -lt 4 ]; then
    echo 'usage: stage_macos_subtitle_runtime.sh <Contents> <whisper-license> <ffmpeg-license> <helper> [...]' >&2
    exit 1
fi
contents=$1
whisper_license=$2
ffmpeg_license=$3
shift 3
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="$contents/Helpers/subtitles"
resources="$contents/Resources/subtitles"
mkdir -p "$dest" "$resources"
# Repair incremental builds containing the old, unsigned files in Helpers.
rm -f "$dest/LICENSE-whisper" "$dest/LICENSE-FFmpeg" "$dest/THIRD_PARTY_NOTICES.md"
lipo -create "$@" -output "$dest/cb-subtitle-worker"
# The shipped helper must not depend on the build machine's package manager.
if otool -L "$dest/cb-subtitle-worker" | grep -Eq '/(opt/homebrew|usr/local)/'; then
    echo 'error: Subtitle helper has an unbundled package-manager dependency' >&2
    exit 1
fi
cp "$whisper_license" "$resources/LICENSE-whisper"
cp "$ffmpeg_license" "$resources/LICENSE-FFmpeg"
cp "$SCRIPT_DIR/../native/subtitles/THIRD_PARTY_NOTICES.md" "$resources/"
if [ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --timestamp=none "$dest/cb-subtitle-worker"
fi

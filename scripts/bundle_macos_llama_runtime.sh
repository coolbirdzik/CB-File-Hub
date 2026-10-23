#!/usr/bin/env bash
# Xcode Runner build phase: runs for direct Flutter builds and packaged releases.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="${CB_LLAMA_MACOS_CACHE:-$SCRIPT_DIR/../cb_file_manager/build/llama-runtime/macos}"
: "${TARGET_BUILD_DIR:?Xcode TARGET_BUILD_DIR is required}"
: "${CONTENTS_FOLDER_PATH:?Xcode CONTENTS_FOLDER_PATH is required}"

bash "$SCRIPT_DIR/fetch_macos_llama_runtime.sh"
for arch in arm64 x86_64; do
    dest="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/llama/$arch"
    mkdir -p "$dest"
    cp "$CACHE/runtime/$arch/llama-server" "$dest/llama-server"
    cp "$CACHE/runtime/$arch/"*.dylib "$dest/"
    chmod 755 "$dest/llama-server"
    # Re-sign downloaded code before Xcode signs the outer app. Release tooling
    # re-signs these helpers with its final distribution identity as well.
    if [ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]; then
        for code in "$dest/"*.dylib "$dest/llama-server"; do
            codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --timestamp=none "$code"
        done
    fi
done
mkdir -p "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Resources"
cp "$CACHE/runtime/arm64/LICENSE" \
    "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Resources/llama-runtime-LICENSE.txt"

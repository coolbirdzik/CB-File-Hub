#!/usr/bin/env bash
# Official aria2 release; unmodified subprocess runtime, isolated from Flutter.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
DEST_DIR="$REPO_DIR/cb_file_manager/windows/aria2"
VERSION="1.37.0"
SHA256="67d015301eef0b612191212d564c5bb0a14b5b9c4796b76454276a4d28d9b288"
ASSET="aria2-${VERSION}-win-64bit-build1"
URL="https://github.com/aria2/aria2/releases/download/release-${VERSION}/${ASSET}.zip"
FILES=(aria2c.exe COPYING LICENSE.OpenSSL README.mingw README.html AUTHORS)

all_present() {
  [ -f "$DEST_DIR/.runtime-version" ] || return 1
  [ "$(cat "$DEST_DIR/.runtime-version")" = "$VERSION $SHA256" ] || return 1
  for file in "${FILES[@]}"; do
    [ -s "$DEST_DIR/$file" ] || return 1
  done
}
if [ "${1:-}" != "--force" ] && all_present; then
  echo "[fetch_aria2_runtime] Runtime already present."
  exit 0
fi
mkdir -p "$DEST_DIR"
ZIP_PATH="$(mktemp)"
trap 'rm -f -- "$ZIP_PATH"' EXIT
curl -fL --retry 3 -o "$ZIP_PATH" "$URL"
echo "$SHA256  $ZIP_PATH" | sha256sum --check --status || {
  echo "[fetch_aria2_runtime] Archive checksum mismatch." >&2
  exit 1
}
# Copy only explicitly named archive entries. No arbitrary archive paths are
# extracted, and licences accompany the executable in every Windows bundle.
for file in "${FILES[@]}"; do
  unzip -p "$ZIP_PATH" "$ASSET/$file" > "$DEST_DIR/$file"
done
cat > "$DEST_DIR/SOURCE.txt" <<EOF
aria2 $VERSION (unmodified official Windows x64 build)
Binary: $URL
Corresponding source: https://github.com/aria2/aria2/releases/download/release-$VERSION/aria2-$VERSION.tar.xz
Build instructions and linked dependencies: README.mingw
Licences: COPYING, LICENSE.OpenSSL, README.html
EOF
echo "$VERSION $SHA256" > "$DEST_DIR/.runtime-version"
echo "[fetch_aria2_runtime] Ready: $DEST_DIR"

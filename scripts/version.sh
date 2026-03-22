#!/usr/bin/env bash
# Cross-platform version helper for Makefile
# Usage: source scripts/version.sh (sets VERSION, BUILD_NUMBER, VERSION_FULL)
#   or: ./scripts/version.sh full|name|build

set -euo pipefail

PUBSPEC="${PUBSPEC:-cb_file_manager/pubspec.yaml}"

VERSION_FULL=$(awk '/^version:/{print $2}' "$PUBSPEC")
VERSION="${VERSION_FULL%%+*}"
BUILD_NUMBER="${VERSION_FULL##*+}"

case "${1:-}" in
  full)       echo "$VERSION_FULL" ;;
  name)       echo "$VERSION" ;;
  build)      echo "$BUILD_NUMBER" ;;
  bump)       # Bump build number in pubspec and echo new value
    NEW_BUILD=$((BUILD_NUMBER + 1))
    # Cross-platform sed -i
    if sed -i '' /dev/null 2>/dev/null; then
      SED_I=''
    else
      SED_I=''
    fi
    sed -i '' "s/^version:.*/version: $VERSION+$NEW_BUILD/" "$PUBSPEC" 2>/dev/null || \
    sed -i    "s/^version:.*/version: $VERSION+$NEW_BUILD/" "$PUBSPEC"
    echo "$NEW_BUILD"
    ;;
  set-version)
    # set-version NEW_VERSION
    NEW_VER="$2"
    sed -i '' "s/^version:.*/version: $NEW_VER+1/" "$PUBSPEC" 2>/dev/null || \
    sed -i    "s/^version:.*/version: $NEW_VER+1/" "$PUBSPEC"
    echo "Updated to $NEW_VER+1"
    ;;
  *)  echo "Usage: version.sh full|name|build|bump|set-version <version>" ;;
esac

#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
PUBSPEC="$REPO_DIR/cb_file_manager/pubspec.yaml"
OUTPUT_DIR_INPUT="${1:-ci/release}"
if [[ "$OUTPUT_DIR_INPUT" = /* ]]; then
    OUTPUT_DIR="$OUTPUT_DIR_INPUT"
else
    OUTPUT_DIR="$REPO_DIR/$OUTPUT_DIR_INPUT"
fi
mkdir -p "$OUTPUT_DIR"

VERSION_LINE="$(sed -n 's/^version: //p' "$PUBSPEC" | head -n 1 | tr -d '\r')"
if [[ -z "$VERSION_LINE" ]]; then
    echo "Unable to read version from $PUBSPEC" >&2
    exit 1
fi

VERSION_NAME="${VERSION_LINE%%+*}"
VERSION_CODE="0"
if [[ "$VERSION_LINE" == *"+"* ]]; then
    VERSION_CODE="${VERSION_LINE##*+}"
fi

EXPECTED_TAG="v$VERSION_NAME"
RELEASE_TAG="${CI_COMMIT_TAG:-$EXPECTED_TAG}"
RELEASE_SHA="${CI_COMMIT_SHA:-HEAD}"

if [[ -n "${CI_COMMIT_TAG:-}" && "$CI_COMMIT_TAG" != "$EXPECTED_TAG" ]]; then
    echo "Tag $CI_COMMIT_TAG does not match pubspec version $EXPECTED_TAG" >&2
    exit 1
fi

git -C "$REPO_DIR" fetch --tags --force >/dev/null 2>&1 || true

# Resolve the commit pointed to by the current release tag. CI jobs may create
# extra commits during the build, so release notes must not use a later HEAD.
if git -C "$REPO_DIR" rev-parse -q --verify "refs/tags/$RELEASE_TAG" >/dev/null; then
    RELEASE_REF="$(git -C "$REPO_DIR" rev-list -n 1 "$RELEASE_TAG")"
else
    RELEASE_REF="$(git -C "$REPO_DIR" rev-parse "$RELEASE_SHA")"
fi

# Find the nearest previous tag by walking back from the tagged release commit.
PREVIOUS_TAG=""
if git -C "$REPO_DIR" rev-parse "${RELEASE_REF}^" >/dev/null 2>&1; then
    PREVIOUS_TAG="$(git -C "$REPO_DIR" describe --tags --abbrev=0 "${RELEASE_REF}^" 2>/dev/null || true)"
fi

# Fallback: if describe failed, try sorted reachable tags excluding current tag.
if [ -z "$PREVIOUS_TAG" ]; then
    PREVIOUS_TAG="$(git -C "$REPO_DIR" tag --merged "$RELEASE_REF" --sort=-version:refname | grep -v "^${RELEASE_TAG}$" | head -n 1 || true)"
fi

RELEASE_NOTES_FILE="$OUTPUT_DIR/release_notes.md"

# CI housekeeping (e.g. "ci: auto bump build number") and release version bumps
# ("chore: bump version to x.y.z") mean nothing to users: leave them out.
# `|| true` keeps pipefail happy when every commit in the range is filtered out.
drop_ci_commits() {
    grep -vE '^- (ci(\([^)]*\))?!?:|chore(\([^)]*\))?!?: bump version to )' || true
}

{
    echo "# CB File Hub $VERSION_NAME"
    echo
    if [[ -n "$PREVIOUS_TAG" ]]; then
        echo "Changes from \`$PREVIOUS_TAG\` to \`$RELEASE_TAG\`."
        echo
        git -C "$REPO_DIR" log --reverse --pretty=format:'- %s (%h)' "$PREVIOUS_TAG..$RELEASE_REF" | drop_ci_commits
    else
        echo "Changes included in the first tagged release."
        echo
        git -C "$REPO_DIR" log --reverse --pretty=format:'- %s (%h)' "$RELEASE_REF" | drop_ci_commits
    fi
    echo
} >"$RELEASE_NOTES_FILE"

cat >"$OUTPUT_DIR/release.env" <<EOF
RELEASE_VERSION=$VERSION_NAME
RELEASE_VERSION_CODE=$VERSION_CODE
RELEASE_TAG=$RELEASE_TAG
PREVIOUS_TAG=$PREVIOUS_TAG
RELEASE_REF=$RELEASE_REF
RELEASE_NOTES_FILE=$RELEASE_NOTES_FILE
EOF

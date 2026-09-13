#!/bin/bash
# Bump version, commit, create annotated tag, then push branch + tag
# Usage: bash scripts/release.sh patch|minor|major
#
# When run interactively (TTY), lists available git remotes and lets you pick
# (Enter = default), then pushes right away.
# Non-interactive: skips the push and prints the commands to run.

set -e

PUBSPEC="${PUBSPEC:-cb_file_manager/pubspec.yaml}"

case "$1" in
    patch) BUMP='{print $1"."$2"."$3+1}' ;;
    minor) BUMP='{print $1"."$2+1".0"}' ;;
    major) BUMP='{print $1+1".0.0"}' ;;
    *)
        echo "Usage: bash scripts/release.sh patch|minor|major"
        exit 1
        ;;
esac

BRANCH=$(git branch --show-current)
if [ -z "$BRANCH" ]; then
    echo "Error: detached HEAD, checkout a branch first"
    exit 1
fi

NEW_VER=$(bash scripts/version.sh name | awk -F. "$BUMP")
TAG="v$NEW_VER"

echo "Creating $1 release: $NEW_VER"
bash scripts/version.sh set-version "$NEW_VER"
git add "$PUBSPEC"
git commit -m "chore: bump version to $NEW_VER"
git tag -a "$TAG" -m "Release $TAG"
echo "Created tag $TAG"

# Collect remotes
mapfile -t REMOTES < <(git remote)
if [ "${#REMOTES[@]}" -eq 0 ]; then
    echo "Error: no git remote configured"
    exit 1
fi

DEFAULT="origin"
if ! printf '%s\n' "${REMOTES[@]}" | grep -qx "origin"; then
    DEFAULT="${REMOTES[0]}"
fi

if ! { [ -t 0 ] && [ -t 1 ]; }; then
    echo "Non-interactive shell, skipping push. Push with:"
    echo "  git push $DEFAULT $BRANCH && git push $DEFAULT $TAG"
    exit 0
fi

# Pick remote
echo ""
echo "Available remotes:"
for i in "${!REMOTES[@]}"; do
    echo "  $((i+1))) ${REMOTES[$i]}"
done
printf "Choose remote [default: %s]: " "$DEFAULT"
read -r CHOICE
if [[ "$CHOICE" =~ ^[0-9]+$ ]] && (( CHOICE >= 1 && CHOICE <= ${#REMOTES[@]} )); then
    REMOTE="${REMOTES[$((CHOICE-1))]}"
elif [ -n "$CHOICE" ]; then
    if printf '%s\n' "${REMOTES[@]}" | grep -qx "$CHOICE"; then
        REMOTE="$CHOICE"
    else
        echo "Error: remote '$CHOICE' not found. Push with:"
        echo "  git push <remote> $BRANCH && git push <remote> $TAG"
        exit 1
    fi
else
    REMOTE="$DEFAULT"
fi

echo ""
echo "Branch: $BRANCH"
echo "Tag:    $TAG"
echo "Remote: $REMOTE"
echo "Pushing branch..."
git push "$REMOTE" "$BRANCH"
echo "Pushing tag..."
git push "$REMOTE" "$TAG"
echo "Done."

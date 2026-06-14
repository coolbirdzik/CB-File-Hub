#!/bin/bash
# Recreate annotated tag and force-push to trigger CI rebuild
# Usage: bash scripts/retag.sh v1.2.3
#        bash scripts/retag.sh            (interactive, detects latest tag)
#
# When run interactively (TTY), lists available git remotes and lets you pick.
# Non-interactive: prefers 'origin', falls back to first remote.

set -e

if [ -z "$1" ]; then
    echo "Usage: bash scripts/retag.sh <tag>"
    echo "  e.g.  bash scripts/retag.sh v1.2.3"
    echo ""
    echo "Detecting latest tag..."
    TAG=$(git describe --tags --abbrev=0 HEAD 2>/dev/null)
    if [ -z "$TAG" ]; then
        echo "Error: no tags found"
        exit 1
    fi
else
    TAG="$1"
fi

# Collect remotes
mapfile -t REMOTES < <(git remote)
if [ "${#REMOTES[@]}" -eq 0 ]; then
    echo "Error: no git remote configured"
    exit 1
fi

# Pick remote
REMOTE=""
if [ -t 0 ] && [ -t 1 ]; then
    echo ""
    echo "Available remotes:"
    for i in "${!REMOTES[@]}"; do
        echo "  $((i+1))) ${REMOTES[$i]}"
    done
    DEFAULT="origin"
    if ! printf '%s\n' "${REMOTES[@]}" | grep -qx "origin"; then
        DEFAULT="${REMOTES[0]}"
    fi
    printf "Choose remote [default: %s]: " "$DEFAULT"
    read -r CHOICE
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && (( CHOICE >= 1 && CHOICE <= ${#REMOTES[@]} )); then
        REMOTE="${REMOTES[$((CHOICE-1))]}"
    elif [ -n "$CHOICE" ]; then
        if printf '%s\n' "${REMOTES[@]}" | grep -qx "$CHOICE"; then
            REMOTE="$CHOICE"
        else
            echo "Error: remote '$CHOICE' not found"
            exit 1
        fi
    else
        REMOTE="$DEFAULT"
    fi
else
    REMOTE=$(printf '%s\n' "${REMOTES[@]}" | grep -m1 '^origin$' || printf '%s\n' "${REMOTES[@]}" | head -1)
fi

echo ""
echo "Tag:    $TAG"
echo "Remote: $REMOTE"
echo "Recreating annotated tag..."
git tag -f -a "$TAG" -m "Rebuild $TAG - auto-incremented build number"

echo "Force-pushing tag to $REMOTE..."
git push "$REMOTE" "$TAG" -f
echo "Done. CI will auto-increment build_number on each build."

#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <release-notes-file> <asset> [asset...]" >&2
    exit 1
fi

RELEASE_NOTES_FILE="$1"
shift

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${GITHUB_REPO:?GITHUB_REPO is required}"
: "${RELEASE_TAG:?RELEASE_TAG is required}"

GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"
RELEASE_NAME="CB File Hub ${RELEASE_TAG}"

if [[ ! -f "$RELEASE_NOTES_FILE" ]]; then
    echo "Release notes file not found: $RELEASE_NOTES_FILE" >&2
    exit 1
fi

RELEASE_BODY="$(cat "$RELEASE_NOTES_FILE")"
AUTH_HEADER="Authorization: Bearer $GITHUB_TOKEN"
API_HEADER="Accept: application/vnd.github+json"
VERSION_HEADER="X-GitHub-Api-Version: 2022-11-28"

release_response="$(curl -fsS \
    -H "$AUTH_HEADER" \
    -H "$API_HEADER" \
    -H "$VERSION_HEADER" \
    "$GITHUB_API_URL/repos/$GITHUB_REPO/releases/tags/$RELEASE_TAG" || true)"

if [[ -n "$release_response" ]]; then
    release_id="$(jq -r '.id' <<<"$release_response")"
    upload_url="$(jq -r '.upload_url' <<<"$release_response" | sed 's/{?name,label}//')"
    curl -fsS -X PATCH \
        -H "$AUTH_HEADER" \
        -H "$API_HEADER" \
        -H "$VERSION_HEADER" \
        "$GITHUB_API_URL/repos/$GITHUB_REPO/releases/$release_id" \
        -d "$(jq -n --arg name "$RELEASE_NAME" --arg body "$RELEASE_BODY" '{name: $name, body: $body, draft: false, prerelease: false}')" \
        >/dev/null
else
    release_response="$(curl -fsS -X POST \
        -H "$AUTH_HEADER" \
        -H "$API_HEADER" \
        -H "$VERSION_HEADER" \
        "$GITHUB_API_URL/repos/$GITHUB_REPO/releases" \
        -d "$(jq -n --arg tag_name "$RELEASE_TAG" --arg name "$RELEASE_NAME" --arg body "$RELEASE_BODY" '{tag_name: $tag_name, name: $name, body: $body, draft: false, prerelease: false}')" )"
    release_id="$(jq -r '.id' <<<"$release_response")"
    upload_url="$(jq -r '.upload_url' <<<"$release_response" | sed 's/{?name,label}//')"
fi

assets_response="$(curl -fsS \
    -H "$AUTH_HEADER" \
    -H "$API_HEADER" \
    -H "$VERSION_HEADER" \
    "$GITHUB_API_URL/repos/$GITHUB_REPO/releases/$release_id/assets")"

for asset in "$@"; do
    if [[ ! -f "$asset" ]]; then
        echo "Skipping missing asset: $asset" >&2
        continue
    fi

    asset_name="$(basename "$asset")"
    existing_asset_id="$(jq -r --arg name "$asset_name" '.[] | select(.name == $name) | .id' <<<"$assets_response" | head -n 1)"

    if [[ -n "$existing_asset_id" ]]; then
        curl -fsS -X DELETE \
            -H "$AUTH_HEADER" \
            -H "$API_HEADER" \
            -H "$VERSION_HEADER" \
            "$GITHUB_API_URL/repos/$GITHUB_REPO/releases/assets/$existing_asset_id" \
            >/dev/null
    fi

    curl -fsS -X POST \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/octet-stream" \
        "$upload_url?name=$(printf '%s' "$asset_name" | jq -sRr @uri)" \
        --data-binary @"$asset" \
        >/dev/null
done

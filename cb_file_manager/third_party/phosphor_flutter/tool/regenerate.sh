#!/usr/bin/env bash
# Rebuild the vendored, trimmed phosphor_flutter from the pub cache.
#
# Re-run after bumping VERSION, or after adding a style to STYLES. Requires the
# upstream package to be present in the pub cache; `flutter pub get` in a
# scratch project that depends on it will place it there.
set -euo pipefail

VERSION="2.1.0"
STYLES="Light Fill Bold"

DST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${PUB_CACHE:-$LOCALAPPDATA/Pub/Cache}/hosted/pub.dev/phosphor_flutter-$VERSION"

if [ ! -d "$SRC" ]; then
  echo "upstream not in pub cache: $SRC" >&2
  exit 1
fi

rm -f "$DST"/lib/src/*.dart "$DST"/lib/fonts/*.ttf
mkdir -p "$DST/lib/src" "$DST/lib/fonts"
cp "$SRC/LICENSE" "$DST/LICENSE"

for style in $STYLES; do
  lower="$(echo "$style" | tr 'A-Z' 'a-z')"
  font="Phosphor-$style.ttf"
  # Upstream names the regular font Phosphor.ttf, not Phosphor-Regular.ttf.
  [ "$style" = "Regular" ] && font="Phosphor.ttf"

  cp "$SRC/lib/fonts/$font" "$DST/lib/fonts/"
  cp "$SRC/lib/src/phosphor_icons_$lower.dart" "$DST/lib/src/"

  target="$DST/lib/src/phosphor_icons_$lower.dart"
  # IconData is final and can no longer be subclassed; construct it directly.
  sed -i -E "s/PhosphorFlatIconData\((0x[0-9a-fA-F]+), '$style'\)/IconData(\1, fontFamily: 'Phosphor$style', fontPackage: 'phosphor_flutter', matchTextDirection: true)/g" "$target"
  sed -i "/import 'package:phosphor_flutter\/src\/phosphor_icon_data.dart';/d" "$target"

  if grep -q "PhosphorIconData" "$target"; then
    echo "unconverted subclass reference left in $target" >&2
    exit 1
  fi
done

echo "regenerated $DST from phosphor_flutter $VERSION (styles: $STYLES)"
echo "update lib/phosphor_flutter.dart and pubspec.yaml if the style set changed"

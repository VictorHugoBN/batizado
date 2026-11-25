#!/bin/bash
#
# Regenerate assets/AppIcon.icns from assets/AppIcon.svg. Called by `make icon`.
# Uses only AppKit's SVG renderer (through the Swift interpreter) and iconutil.

set -euo pipefail

SRC="${SRC:-assets/AppIcon.svg}"
OUT="${OUT:-assets/AppIcon.icns}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"

# Render the SVG once per pixel size, then copy each into the names iconutil expects. The 16 and 32 point
# sizes are left out on purpose: with them, macOS 27 put the small icon on a gray plate; without them it
# scales the 128 one down inside its own squircle.
for px in 128 256 512 1024; do
  swift scripts/render-svg.swift "$SRC" "$work/$px.png" "$px"
done
for pt in 128 256 512; do
  cp "$work/$pt.png" "$iconset/icon_${pt}x${pt}.png"
  cp "$work/$((pt * 2)).png" "$iconset/icon_${pt}x${pt}@2x.png"
done

iconutil --convert icns --output "$OUT" "$iconset"
echo "icon: $OUT"

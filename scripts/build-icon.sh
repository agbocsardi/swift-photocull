#!/usr/bin/env bash
# Render the Dock icon and monochrome menu-bar template.
# Usage: scripts/build-icon.sh [icon-name]     (default: icon-a)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NAME="${1:-icon-a}"
SVG="icon/${NAME}.svg"
[ -f "$SVG" ] || { echo "missing $SVG"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Build the SVG rasterizer once (uses the OS renderer, no third-party deps).
BIN="$WORK/svgrender"
swiftc -O -o "$BIN" scripts/svgrender.swift

ICONSET="$WORK/PhotoCull.iconset"
mkdir -p "$ICONSET"
for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
            "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
            "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
  px="${spec%%:*}"; out="${spec##*:}"
  "$BIN" "$SVG" "$ICONSET/$out.png" "$px" >/dev/null
done

mkdir -p resources
iconutil -c icns "$ICONSET" -o resources/PhotoCull.icns
echo "==> resources/PhotoCull.icns from $SVG"

# Template images use alpha as a mask; a 36px raster maps to 18pt on Retina.
MENU_SVG="icon/menubar-outline.svg"
[ -f "$MENU_SVG" ] || { echo "missing $MENU_SVG"; exit 1; }
"$BIN" "$MENU_SVG" resources/PhotoCullMenuBar.png 36 >/dev/null
echo "==> resources/PhotoCullMenuBar.png from $MENU_SVG"
ls -la resources/PhotoCull.icns resources/PhotoCullMenuBar.png

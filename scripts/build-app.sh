#!/usr/bin/env bash
# Build PhotoCull.app — a real macOS app bundle assembled from the SwiftPM product.
# Usage: scripts/build-app.sh [debug|release]
set -euo pipefail

CONF="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> swift build -c $CONF --product PhotoCull"
swift build -c "$CONF" --product PhotoCull

BIN="$(swift build -c "$CONF" --show-bin-path)"
APP="$ROOT/dist/PhotoCull.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PhotoCull" "$APP/Contents/MacOS/PhotoCull"
cp "$ROOT/resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/PhotoCull"

# Ad-hoc signature so macOS treats it as a normal app.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "note: ad-hoc codesign skipped"

echo "==> built $APP"

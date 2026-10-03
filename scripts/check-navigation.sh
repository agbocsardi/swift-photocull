#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
OUT=${OUT:-/tmp/photocull-luna-wave-2026-10-03/navigation}
mkdir -p "$OUT"
OUT=$(CDPATH= cd -- "$OUT" && pwd -P)
mkdir -p "$OUT/build" "$OUT/cache" "$OUT/config" "$OUT/security" \
  "$OUT/module-cache" "$OUT/clang-module-cache"

CLANG_MODULE_CACHE_PATH="$OUT/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$OUT/module-cache" \
swift build --package-path "$ROOT" --scratch-path "$OUT/build" --cache-path "$OUT/cache" \
  --config-path "$OUT/config" --security-path "$OUT/security" -c release

CORE_SOURCES=$(printf '%s\n' "$ROOT"/Sources/PhotoCullCore/*.swift)
# shellcheck disable=SC2086
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
  -package-name PhotoCull -module-cache-path "$OUT/module-cache" -emit-library -emit-module \
  -module-name PhotoCullCore -emit-module-path "$OUT/build/PhotoCullCore.swiftmodule" \
  $CORE_SOURCES -o "$OUT/build/libPhotoCullCore.dylib"

APP_SOURCES=$(find "$ROOT/Sources/PhotoCullApp" -maxdepth 1 -name '*.swift' ! -name PhotoCullApp.swift -print | sort)
# shellcheck disable=SC2086
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
  -package-name PhotoCull -module-cache-path "$OUT/module-cache" -I "$OUT/build" -L "$OUT/build" \
  -lPhotoCullCore $APP_SOURCES "$ROOT/Tests/App/NavigationChecks.swift" \
  -o "$OUT/build/navigation-checks"
PC_NAVIGATION_OUT="$OUT" \
DYLD_LIBRARY_PATH="$OUT/build${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
  "$OUT/build/navigation-checks"

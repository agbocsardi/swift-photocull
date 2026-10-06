#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
OUT=${OUT:-/tmp/photocull-luna-wave-2026-10-03/render}
mkdir -p "$OUT/build" "$OUT/cache" "$OUT/config" "$OUT/security" \
  "$OUT/module-cache" "$OUT/clang-module-cache"
CLANG_MODULE_CACHE_PATH="$OUT/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$OUT/module-cache" \
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path "$OUT/module-cache" -package-name PhotoCull \
  -emit-library -emit-module -module-name PhotoCullCore \
  "$ROOT"/Sources/PhotoCullCore/*.swift \
  -emit-module-path "$OUT/build/PhotoCullCore.swiftmodule" \
  -o "$OUT/build/libPhotoCullCore.dylib"
CLANG_MODULE_CACHE_PATH="$OUT/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$OUT/module-cache" \
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path "$OUT/module-cache" -I "$OUT/build" -L "$OUT/build" \
  -Xlinker -rpath -Xlinker "$OUT/build" -lPhotoCullCore \
  "$ROOT"/Sources/PhotoCullApp/EditRenderer.swift \
  "$ROOT"/Tests/App/EditRenderingChecks.swift \
  -o "$OUT/build/EditRenderingChecks"
"$OUT/build/EditRenderingChecks"

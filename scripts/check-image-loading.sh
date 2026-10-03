#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
OUT="${OUT:-/tmp/photocull-luna-wave-2026-10-03/loading}"
if [[ "$OUT" != /* ]]; then OUT="$ROOT/$OUT"; fi
export OUT
mkdir -p "$OUT"/{build,cache,config,security,module-cache,clang-module-cache,runner}
CLANG_MODULE_CACHE_PATH="$OUT/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$OUT/module-cache" \
swift build --package-path "$ROOT" --scratch-path "$OUT/build" --cache-path "$OUT/cache" \
  --config-path "$OUT/config" --security-path "$OUT/security" -c release

SDK="$(xcrun --sdk macosx --show-sdk-path)"
PRODUCTS="$OUT/build/out/Products/Release"
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" -I "$PRODUCTS" \
  -L "$PRODUCTS" -lPhotoCullCore -Xlinker -rpath -Xlinker "$PRODUCTS" \
  -F "$SDK/System/Library/Frameworks" -framework SwiftUI -framework AppKit \
  "$ROOT/Sources/PhotoCullApp/ImageLoader.swift" \
  "$ROOT/Tests/App/ImageLoadingChecks.swift" \
  -o "$OUT/runner/image-loading-checks"
"$OUT/runner/image-loading-checks"

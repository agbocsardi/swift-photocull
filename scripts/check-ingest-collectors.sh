#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OUT=${OUT:-/tmp/photocull-luna-wave-2026-10-03/reliability}
mkdir -p "$OUT/build" "$OUT/cache" "$OUT/config" "$OUT/security" \
  "$OUT/module-cache" "$OUT/clang-module-cache"
CLANG_MODULE_CACHE_PATH="$OUT/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$OUT/module-cache" \
swift build --package-path "$ROOT" --scratch-path "$OUT/build" --cache-path "$OUT/cache" \
  --config-path "$OUT/config" --security-path "$OUT/security" -c release

PRODUCTS="$OUT/build/out/Products/Release"
MODULES="$OUT/build/out/Intermediates.noindex/PhotoCull.build/Release/PhotoCullCore-t.build/Objects-normal/arm64"
BIN="$PRODUCTS/PhotoCullTests"
PC_TEST_ROOT="$OUT" "$BIN" --suite IngestConcurrent
"$BIN" --finalize-safety-only
for args in '--suite' '--suite MissingSuite' '--bogus'; do
  if "$BIN" $args >"$OUT/invalid-selection.log" 2>&1; then
    echo "Expected invalid selection to fail: $args" >&2
    exit 1
  fi
  if grep -q 'Selected .*suite' "$OUT/invalid-selection.log"; then
    echo "Invalid selection executed a suite: $args" >&2
    exit 1
  fi
done
printf '%s\n' 'PASS — three invalid CLI selections rejected before suite execution'

cp "$ROOT/Tests/Core/IngestCollectorChecks.swift" "$OUT/main.swift"
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path "$OUT/module-cache" \
  -I "$MODULES" \
  "$ROOT/Sources/PhotoCullTests/Harness.swift" "$OUT/main.swift" \
  -L "$PRODUCTS" -lPhotoCullCore \
  -o "$OUT/IngestCollectorChecks"
"$OUT/IngestCollectorChecks" "$OUT"

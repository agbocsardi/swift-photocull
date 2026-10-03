#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${OUT:-/tmp/photocull-luna-wave-2026-10-03/finalize}
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
mkdir -p "$OUT/build" "$OUT/cache" "$OUT/config" "$OUT/security" \
  "$OUT/module-cache" "$OUT/clang-module-cache" "$OUT/synthetic"
CLANG_MODULE_CACHE_PATH="$OUT/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$OUT/module-cache" \
swift build --package-path "$ROOT" --scratch-path "$OUT/build" \
  --cache-path "$OUT/cache" --config-path "$OUT/config" \
  --security-path "$OUT/security" -c release
cat > "$OUT/FinalizePlanningMain.swift" <<'SWIFT'
import Foundation
@main struct Main {
    static func main() throws { try suiteFinalizePlanningChecks() }
}
SWIFT
BIN="$OUT/build/release"
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path "$OUT/module-cache" -I "$BIN" \
  "$ROOT/Tests/Core/FinalizePlanningChecks.swift" "$OUT/FinalizePlanningMain.swift" \
  "$BIN/libPhotoCullCore.a" -o "$OUT/FinalizePlanningChecks"
PC_FINALIZE_TEST_OUT="$OUT" "$OUT/FinalizePlanningChecks"
"$BIN/PhotoCullTests" --finalize-safety-only

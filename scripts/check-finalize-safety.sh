#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${OUT:?OUT must be an absolute dedicated output directory}
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd -P)
case "$OUT" in /private/tmp/photocull-finalize-safety-2026-10-03/worker/*) ;; *)
  echo "OUT must be beneath the assigned worker root: $OUT" >&2; exit 2;;
esac
mkdir -p "$OUT/scratch" "$OUT/cache" "$OUT/config" "$OUT/security" \
  "$OUT/swift-module-cache" "$OUT/clang-module-cache" \
  "$OUT/standalone-swift-module-cache" "$OUT/standalone-clang-module-cache" "$OUT/synthetic"
CLANG_MODULE_CACHE_PATH="$OUT/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$OUT/swift-module-cache" \
swift build --package-path "$ROOT" --scratch-path "$OUT/scratch" \
  --cache-path "$OUT/cache" --config-path "$OUT/config" \
  --security-path "$OUT/security" -c release
PC_FINALIZE_SAFETY_OUT="$OUT" \
  "$OUT/scratch/release/PhotoCullTests" --finalize-safety-only
BIN="$OUT/scratch/release"
cat > "$OUT/FinalizePlanningMain.swift" <<'SWIFT'
import Foundation
@main struct Main { static func main() throws { try suiteFinalizePlanningChecks() } }
SWIFT
CLANG_MODULE_CACHE_PATH="$OUT/standalone-clang-module-cache" \
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  -module-cache-path "$OUT/standalone-swift-module-cache" -I "$BIN" \
  "$ROOT/Tests/Core/FinalizePlanningChecks.swift" "$OUT/FinalizePlanningMain.swift" \
  "$BIN/libPhotoCullCore.a" -o "$OUT/FinalizePlanningChecks"
PC_FINALIZE_TEST_OUT="$OUT" "$OUT/FinalizePlanningChecks"

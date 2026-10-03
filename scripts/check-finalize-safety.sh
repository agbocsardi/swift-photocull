#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
OUT=${OUT:?OUT must be an absolute dedicated output directory}
case "$OUT" in /*) ;; *) echo 'OUT must be absolute' >&2; exit 2;; esac
mkdir -p "$OUT"
OUT=$(CDPATH= cd -- "$OUT" && pwd -P)
case "$OUT" in /|/tmp|/private/tmp|/Users|/Users/*/|"$HOME"|"$ROOT"|"$ROOT"/*)
  echo "Refusing unbounded/source output root: $OUT" >&2; exit 2;;
esac
# Fresh products/caches only. Existing caller logs are fine; never delete caller-owned output.
for dir in scratch cache config security pm-swift pm-clang core-swift core-clang app-swift app-clang; do
  if [ -e "$OUT/$dir" ]; then echo "Output already used: $OUT/$dir" >&2; exit 2; fi
  mkdir -p "$OUT/$dir"
done
mkdir -p "$OUT/synthetic"
CLANG_MODULE_CACHE_PATH="$OUT/pm-clang" SWIFTPM_MODULECACHE_OVERRIDE="$OUT/pm-swift" \
swift build --package-path "$ROOT" --scratch-path "$OUT/scratch" \
  --cache-path "$OUT/cache" --config-path "$OUT/config" --security-path "$OUT/security" -c release
PC_FINALIZE_SAFETY_OUT="$OUT" "$OUT/scratch/release/PhotoCullTests" --finalize-safety-only
BIN="$OUT/scratch/release"
# SwiftPM uses the checkout's normalized package identity, not Package(name:).
PACKAGE=$(basename "$ROOT" | tr '[:upper:]-' '[:lower:]_')
cat > "$OUT/FinalizeCoreMain.swift" <<'SWIFT'
import Foundation
@main struct Main {
    static func main() throws {
        try suiteFinalizePlanningChecks()
        try suiteFinalizeFailureChecks()
    }
}
SWIFT
CLANG_MODULE_CACHE_PATH="$OUT/core-clang" \
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 -package-name "$PACKAGE" \
  -module-cache-path "$OUT/core-swift" -I "$BIN" \
  "$ROOT/Tests/Core/FinalizePlanningChecks.swift" "$ROOT/Tests/Core/FinalizeFailureChecks.swift" \
  "$OUT/FinalizeCoreMain.swift" "$BIN/libPhotoCullCore.a" -o "$OUT/FinalizeCoreChecks"
PC_FINALIZE_TEST_OUT="$OUT" "$OUT/FinalizeCoreChecks"
# App runner is added with the app ownership checkpoint; no GUI application is launched.
if [ -f "$ROOT/Tests/App/FinalizeOperationChecks.swift" ]; then
  APP_SOURCES=$(find "$ROOT/Sources/PhotoCullApp" -maxdepth 1 -name '*.swift' ! -name PhotoCullApp.swift -print | sort)
  # shellcheck disable=SC2086
  CLANG_MODULE_CACHE_PATH="$OUT/app-clang" \
  swiftc -O -swift-version 5 -target arm64-apple-macos14.0 -package-name "$PACKAGE" \
    -module-cache-path "$OUT/app-swift" -I "$BIN" $APP_SOURCES \
    "$ROOT/Tests/App/FinalizeOperationChecks.swift" "$BIN/libPhotoCullCore.a" -o "$OUT/FinalizeOperationChecks"
  PC_FINALIZE_TEST_OUT="$OUT" "$OUT/FinalizeOperationChecks"
fi

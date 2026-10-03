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
for dir in scratch cache config security pm-swift pm-clang core-swift core-clang fd-swift fd-clang app-swift app-clang nav-swift nav-clang; do
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
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--flock-probe" {
            finalizeLockProbe(CommandLine.arguments[2]); return
        }
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
# Actual constructors plus test-local syscall forwarding/reuse, not substitute implementations.
CLANG_MODULE_CACHE_PATH="$OUT/fd-clang" \
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 -package-name "$PACKAGE" \
  -D FINALIZE_DESCRIPTOR_CHECKS -module-cache-path "$OUT/fd-swift" \
  "$ROOT/Sources/PhotoCullCore/Session.swift" "$ROOT/Sources/PhotoCullCore/FinalizeSafety.swift" \
  "$ROOT/Tests/Core/FinalizeFailureChecks.swift" -o "$OUT/FinalizeDescriptorChecks"
PC_FINALIZE_TEST_OUT="$OUT" "$OUT/FinalizeDescriptorChecks"
# Real AppState runners; neither launches an application nor initializes appearance/preferences.
test -f "$ROOT/Tests/App/FinalizeOperationChecks.swift"
  APP_SOURCES=$(find "$ROOT/Sources/PhotoCullApp" -maxdepth 1 -name '*.swift' ! -name PhotoCullApp.swift -print | sort)
  # shellcheck disable=SC2086
  CLANG_MODULE_CACHE_PATH="$OUT/app-clang" \
  swiftc -O -swift-version 5 -target arm64-apple-macos14.0 -package-name "$PACKAGE" \
    -module-cache-path "$OUT/app-swift" -I "$BIN" $APP_SOURCES \
    "$ROOT/Tests/App/FinalizeOperationChecks.swift" "$BIN/libPhotoCullCore.a" -o "$OUT/FinalizeOperationChecks"
  PC_FINALIZE_TEST_OUT="$OUT" "$OUT/FinalizeOperationChecks"
  # Existing navigation runner, but with its own caches instead of the old script's shared PM caches.
  CLANG_MODULE_CACHE_PATH="$OUT/nav-clang" \
  swiftc -O -swift-version 5 -target arm64-apple-macos14.0 -package-name "$PACKAGE" \
    -module-cache-path "$OUT/nav-swift" -I "$BIN" $APP_SOURCES \
    "$ROOT/Tests/App/NavigationChecks.swift" "$BIN/libPhotoCullCore.a" -o "$OUT/NavigationChecks"
  PC_NAVIGATION_OUT="$OUT" "$OUT/NavigationChecks"

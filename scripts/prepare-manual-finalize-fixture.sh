#!/bin/bash
# Preparation only: never launches PhotoCull or calls Finalize.run/Trash.
set -euo pipefail
umask 077
if [[ $# != 0 ]]; then echo 'Usage: scripts/prepare-manual-finalize-fixture.sh (always creates a fresh root)' >&2; exit 2; fi
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
OUT=$(mktemp -d /private/tmp/photocull-manual-fixture-XXXXXXXX)
printf 'Fixture root: %s\n' "$OUT"
mkdir -p "$OUT/tool/sources" "$OUT/tool/module-cache" "$OUT/tool/clang-module-cache" \
  "$OUT/tool/cache" "$OUT/tool/config" "$OUT/tool/security" "$OUT/tool/tmp"
export TMPDIR="$OUT/tool/tmp/" CLANG_MODULE_CACHE_PATH="$OUT/tool/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$OUT/tool/module-cache" XDG_CACHE_HOME="$OUT/tool/cache"
CORE=(Config Session FilePair Library Exif ImagePipeline FinalizeSafety Finalize)
for name in "${CORE[@]}"; do cp "$REPO/Sources/PhotoCullCore/$name.swift" "$OUT/tool/sources/"; done
# Keep the exact inspected startup/CLI/ingest evidence alongside the compiled subset.
for name in PhotoCullApp AppState HeadlessCheck Snapshot Overlays ContentView MenuBarView; do
  cp "$REPO/Sources/PhotoCullApp/$name.swift" "$OUT/tool/sources/"
done
cp "$REPO/Sources/PhotoCullCore/"{Ingest,PairRepair}.swift "$OUT/tool/sources/"
cp "$REPO/Tests/Manual/ManualFinalizeFixture.swift" "$OUT/tool/sources/"
cp "$REPO/Tests/Manual/README.md" "$OUT/CHECKLIST.md"
git -C "$REPO" rev-parse HEAD > "$OUT/tool/source-commit.txt"
git -C "$REPO" branch --show-current > "$OUT/tool/source-branch.txt"
shasum -a 256 "$OUT/tool/sources/"*.swift > "$OUT/tool/source-sha256.txt"
SOURCES=()
for name in "${CORE[@]}"; do SOURCES+=("$OUT/tool/sources/$name.swift"); done
swiftc --version > "$OUT/tool/compiler-version.txt" 2>&1
swiftc -O -swift-version 5 -package-name PhotoCullManualFixture -parse-as-library \
  -module-cache-path "$OUT/tool/module-cache" \
  -Xcc "-fmodules-cache-path=$OUT/tool/clang-module-cache" \
  "${SOURCES[@]}" "$OUT/tool/sources/ManualFinalizeFixture.swift" \
  -o "$OUT/tool/fixture" > "$OUT/tool/build.log" 2>&1
"$OUT/tool/fixture" generate "$OUT" > "$OUT/preparation.log" 2>&1
"$OUT/tool/fixture" validate "$OUT" > "$OUT/validation.log" 2>&1
printf 'Prepared, not launch-cleared. See %s/CHECKLIST.md and validation.log\n' "$OUT"
printf 'Read-only validation: "%s/tool/fixture" validate "%s"\n' "$OUT" "$OUT"

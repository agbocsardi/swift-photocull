#!/bin/bash
# Native checks and disposable candidate preparation ONLY; never execute PhotoCull.
set -euo pipefail
umask 077
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
OUT=${OUT:-$(mktemp -d /private/tmp/photocull-manual-launch-XXXXXXXX)}
case "$OUT" in /private/tmp/photocull-manual-launch-*) ;; *) echo 'Dedicated canonical launch OUT required' >&2; exit 2;; esac
[[ "$OUT" == "$(CDPATH= cd -- "$OUT" && pwd -P)" && "$(dirname "$OUT")" == /private/tmp ]]
for name in scratch cache config security pm-swift pm-clang tmp generator check-core startup operation navigation bundle evidence negative-format negative-identity negative-guard negative-preferences; do
  [[ ! -e "$OUT/$name" ]]; mkdir "$OUT/$name"
done
printf 'Artifacts: %s\n' "$OUT"
export TMPDIR="$OUT/tmp/" XDG_CACHE_HOME="$OUT/cache"
PACKAGE=$(basename "$REPO" | tr '[:upper:]-' '[:lower:]_')
CHECK="$REPO/Tests/App/FixtureStartupChecks.swift"
# Shared fixtures are read-only evidence, never test targets or launch targets.
SHARED=(/private/tmp/photocull-manual-fixture-W57RS7B8 /private/tmp/photocull-manual-fixture-Uf2OLjUt)
for root in "${SHARED[@]}"; do
  if [[ -d "$root" ]]; then find "$root" -type f -exec shasum -a 256 {} \;; fi
done | LC_ALL=C sort > "$OUT/evidence/shared-before.sha256"
CLANG_MODULE_CACHE_PATH="$OUT/pm-clang" SWIFTPM_MODULECACHE_OVERRIDE="$OUT/pm-swift" \
  swift build --package-path "$REPO" --scratch-path "$OUT/scratch" --cache-path "$OUT/cache" \
  --config-path "$OUT/config" --security-path "$OUT/security" -c release > "$OUT/release.log" 2>&1
BIN="$OUT/scratch/release"
for group in generator check-core startup operation navigation negative-format negative-identity negative-guard negative-preferences; do
  mkdir -p "$OUT/$group/swift-cache" "$OUT/$group/clang-cache"
done
CORE=(Config Session FilePair Library Exif ImagePipeline FinalizeSafety Finalize)
SOURCES=(); for name in "${CORE[@]}"; do SOURCES+=("$REPO/Sources/PhotoCullCore/$name.swift"); done
CLANG_MODULE_CACHE_PATH="$OUT/generator/clang-cache" \
  swiftc -O -swift-version 5 -package-name "$PACKAGE" -parse-as-library \
  -module-cache-path "$OUT/generator/swift-cache" "${SOURCES[@]}" \
  "$REPO/Tests/Manual/ManualFinalizeFixture.swift" -o "$OUT/generator/fixture" > "$OUT/generator/build.log" 2>&1
FIXTURE=$(mktemp -d /private/tmp/photocull-manual-launch-XXXXXXXX)
printf '%s\n' "$FIXTURE" > "$OUT/fixture-root.txt"
"$OUT/generator/fixture" generate "$FIXTURE" > "$OUT/generator/generate.log" 2>&1
mkdir "$FIXTURE/tool"
cp "$OUT/generator/fixture" "$FIXTURE/tool/fixture"
cp "$REPO/Tests/Manual/README.md" "$FIXTURE/CHECKLIST.md"
"$FIXTURE/tool/fixture" validate "$FIXTURE" > "$OUT/generator/validate-before.log" 2>&1
# Compile actual Core plus a test-local lstat forwarding seam (only ownership spoofing).
CLANG_MODULE_CACHE_PATH="$OUT/check-core/clang-cache" \
  swiftc -O -swift-version 5 -package-name "$PACKAGE" -D FIXTURE_CORE_CHECKS \
  -module-cache-path "$OUT/check-core/swift-cache" -emit-library -static -emit-module \
  -module-name PhotoCullCore -emit-module-path "$OUT/check-core/PhotoCullCore.swiftmodule" \
  "$REPO"/Sources/PhotoCullCore/*.swift "$CHECK" -o "$OUT/check-core/libPhotoCullCore.a" > "$OUT/check-core/build.log" 2>&1
compile_checks() {
  local dest=$1 core=$2 apps=$3
  local app_sources=()
  while IFS= read -r path; do app_sources+=("$path"); done < <(find "$apps" -maxdepth 1 -name '*.swift' ! -name PhotoCullApp.swift -print | sort)
  CLANG_MODULE_CACHE_PATH="$dest/clang-cache" \
    swiftc -O -swift-version 5 -package-name "$PACKAGE" -module-cache-path "$dest/swift-cache" \
    -I "$core" "${app_sources[@]}" "$CHECK" "$core/libPhotoCullCore.a" -o "$dest/checks" > "$dest/build.log" 2>&1
}
compile_checks "$OUT/startup" "$OUT/check-core" "$REPO/Sources/PhotoCullApp"
PC_FIXTURE_STARTUP_OUT="$FIXTURE" "$OUT/startup/checks" > "$OUT/startup/checks.log" 2>&1
"$FIXTURE/tool/fixture" validate "$FIXTURE" > "$OUT/generator/validate-after.log" 2>&1
# Effective negative controls on copied sources; all forbidden APIs remain safely shadowed.
for kind in format identity guard preferences; do
  DEST="$OUT/negative-$kind"
  mkdir "$DEST/core" "$DEST/app"
  cp "$REPO"/Sources/PhotoCullCore/*.swift "$DEST/core/"
  cp "$REPO"/Sources/PhotoCullApp/*.swift "$DEST/app/"
  case "$kind" in
    format) perl -0777 -pi -e 's/text == cfg\.toTOML\(\),/true,/ or die "format seam missing"' "$DEST/core/Config.swift" ;;
    identity) perl -0777 -pi -e 's/UUID\(uuidString: String\(id\.dropFirst\(fixtureIdentifierPrefix\.count\)\)\) != nil/true/ or die "identity seam missing"' "$DEST/app/StartupConfiguration.swift" ;;
    guard) perl -0777 -pi -e 's/guard !fixtureMode else \{ toastMessage\("Unavailable in disposable fixture mode"\); return false \}/\/\/ Negative control: ordinary I\/O guard removed/ or die "guard seam missing"' "$DEST/app/AppState.swift" ;;
    preferences) perl -0777 -pi -e 's/if initializeAppearance && !fixtureMode \{/if initializeAppearance {/ or die "preference seam missing"' "$DEST/app/AppState.swift" ;;
  esac
  if [[ "$kind" == format ]]; then
    mkdir "$DEST/core-swift" "$DEST/core-clang"
    CLANG_MODULE_CACHE_PATH="$DEST/core-clang" \
      swiftc -O -swift-version 5 -package-name "$PACKAGE" -D FIXTURE_CORE_CHECKS \
      -module-cache-path "$DEST/core-swift" -emit-library -static -emit-module -module-name PhotoCullCore \
      -emit-module-path "$DEST/core/PhotoCullCore.swiftmodule" "$DEST"/core/*.swift "$CHECK" \
      -o "$DEST/core/libPhotoCullCore.a" > "$DEST/core-build.log" 2>&1
    CHECK_CORE="$DEST/core"
  else CHECK_CORE="$OUT/check-core"; fi
  compile_checks "$DEST" "$CHECK_CORE" "$DEST/app"
  NEG_FIXTURE=$(mktemp -d /private/tmp/photocull-manual-launch-XXXXXXXX)
  printf '%s\n' "$NEG_FIXTURE" > "$DEST/fixture-root.txt"
  "$OUT/generator/fixture" generate "$NEG_FIXTURE" > "$DEST/generate.log" 2>&1
  if PC_FIXTURE_STARTUP_OUT="$NEG_FIXTURE" "$DEST/checks" > "$DEST/checks.log" 2>&1; then
    echo "Negative control unexpectedly passed: $kind" >&2; exit 1
  else [[ $? == 1 ]]; fi
  printf 'PASS effective negative control: %s\n' "$kind" >> "$OUT/evidence/negative-controls.log"
done
# Existing focused real AppState operation and navigation checks, normal production Core.
APP_SOURCES=(); while IFS= read -r path; do APP_SOURCES+=("$path"); done < <(find "$REPO/Sources/PhotoCullApp" -maxdepth 1 -name '*.swift' ! -name PhotoCullApp.swift -print | sort)
for name in operation navigation; do
  if [[ "$name" == operation ]]; then TEST=FinalizeOperationChecks; else TEST=NavigationChecks; fi
  CLANG_MODULE_CACHE_PATH="$OUT/$name/clang-cache" \
    swiftc -O -swift-version 5 -package-name "$PACKAGE" -module-cache-path "$OUT/$name/swift-cache" \
    -I "$BIN" "${APP_SOURCES[@]}" "$REPO/Tests/App/$TEST.swift" "$BIN/libPhotoCullCore.a" \
    -o "$OUT/$name/checks" > "$OUT/$name/build.log" 2>&1
  if [[ "$name" == operation ]]; then
    PC_FINALIZE_TEST_OUT="$OUT/operation" "$OUT/operation/checks" > "$OUT/operation/checks.log" 2>&1
  else PC_NAVIGATION_OUT="$OUT/navigation" "$OUT/navigation/checks" > "$OUT/navigation/checks.log" 2>&1; fi
done
# Separate unique bundle identity is required by production fixture startup.
ID="local.photocull.fixture.$(uuidgen | tr '[:upper:]' '[:lower:]')"
APP="$OUT/bundle/PhotoCullFixture.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PhotoCull" "$APP/Contents/MacOS/PhotoCull"
cp "$REPO/resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName PhotoCull Fixture' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName PhotoCull Fixture' "$APP/Contents/Info.plist"
for name in PhotoCull.icns PhotoCullMenuBar.png; do
  if [[ -f "$REPO/resources/$name" ]]; then cp "$REPO/resources/$name" "$APP/Contents/Resources/"; fi
done
plutil -lint "$APP/Contents/Info.plist" > "$OUT/bundle/plist.log"
codesign --force --sign - "$APP" > "$OUT/bundle/sign.log" 2>&1
codesign --verify --deep --strict "$APP" > "$OUT/bundle/verify.log" 2>&1
codesign --display --verbose=4 "$APP" > "$OUT/bundle/identity.log" 2>&1
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == "$ID" ]]
grep -Fx "Identifier=$ID" "$OUT/bundle/identity.log" > "$OUT/bundle/identity-match.log"
printf '%s\n' "$ID" > "$OUT/bundle/identifier.txt"
shasum -a 256 "$APP/Contents/MacOS/PhotoCull" > "$OUT/bundle/executable.sha256"
git -C "$REPO" rev-parse HEAD > "$OUT/source-commit.txt"
shasum -a 256 "$REPO"/Sources/PhotoCullCore/*.swift "$REPO"/Sources/PhotoCullApp/*.swift > "$OUT/evidence/source-sha256.txt"
for root in "${SHARED[@]}"; do
  if [[ -d "$root" ]]; then find "$root" -type f -exec shasum -a 256 {} \;; fi
done | LC_ALL=C sort > "$OUT/evidence/shared-after.sha256"
cmp "$OUT/evidence/shared-before.sha256" "$OUT/evidence/shared-after.sha256"
printf 'PASS shared fixtures byte-unchanged; never launched candidate or ordinary app.\n' > "$OUT/evidence/shared-preservation.log"
printf 'PASS preparation/checks. Candidate (NOT launch-cleared): %s\nFixture: %s\n' "$APP" "$FIXTURE"
printf 'Proposed ONLY after parent review + user GUI authorization:\n"%s/Contents/MacOS/PhotoCull" --fixture-config "%s/config/config.toml"\n' "$APP" "$FIXTURE" > "$OUT/proposed-launch.txt"

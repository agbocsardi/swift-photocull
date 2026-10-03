#!/bin/bash
set -euo pipefail
OUT=/tmp/photocull-luna-wave-2026-10-03/loading
export OUT
mkdir -p "$OUT"/{build,cache,config,security,module-cache,clang-module-cache,runner}
CLANG_MODULE_CACHE_PATH="$OUT/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$OUT/module-cache" \
swift build --scratch-path "$OUT/build" --cache-path "$OUT/cache" \
  --config-path "$OUT/config" --security-path "$OUT/security" -c release --target PhotoCullCore

cat > "$OUT/runner/SwiftUI.swift" <<'SWIFT'
@_exported import AppKit
import Foundation
@propertyWrapper public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
public protocol ObservableObject: AnyObject {}
SWIFT
swiftc -emit-module -emit-library -module-name SwiftUI -target arm64-apple-macosx14.0 \
  -swift-version 5 -module-cache-path "$OUT/module-cache" \
  "$OUT/runner/SwiftUI.swift" -o "$OUT/runner/libSwiftUI.dylib"
PRODUCTS="$OUT/build/out/Products/Release"
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path "$OUT/module-cache" -I "$PRODUCTS" -I "$OUT/runner" \
  -L "$OUT/runner" -lSwiftUI -Xlinker -rpath -Xlinker "$OUT/runner" \
  -L "$PRODUCTS" -lPhotoCullCore -Xlinker -rpath -Xlinker "$PRODUCTS" \
  Sources/PhotoCullApp/ImageLoader.swift Tests/App/ImageLoadingChecks.swift \
  -o "$OUT/runner/image-loading-checks"
"$OUT/runner/image-loading-checks"

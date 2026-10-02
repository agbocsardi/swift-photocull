import Foundation
import CoreGraphics
import PhotoCullCore

// Tests_ImagePipeline.swift — spec section 8: decode, thumbnail, orient, crop, encode, cache.

// MARK: - Image helpers

private func srgbContext(width: Int, height: Int) -> CGContext? {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
              bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
}

/// Solid-color test image: left half red, right half blue.
private func makeTestImage(width: Int, height: Int) -> CGImage {
    let ctx = srgbContext(width: width, height: height)!
    ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
    ctx.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
    return ctx.makeImage()!
}

/// Grayscale test image built from a matrix given in display space (row 0 = top).
private func grayImage(_ rows: [[UInt8]]) -> CGImage {
    let h = rows.count, w = rows[0].count
    let ctx = srgbContext(width: w, height: h)!
    let buf = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            buf[i] = rows[y][x]; buf[i + 1] = rows[y][x]; buf[i + 2] = rows[y][x]; buf[i + 3] = 255
        }
    }
    return ctx.makeImage()!
}

/// Read the R channel of an image as a display-space matrix (row 0 = top).
private func grayPixels(_ image: CGImage) -> [[UInt8]] {
    let w = image.width, h = image.height
    let ctx = srgbContext(width: w, height: h)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let buf = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
    return (0..<h).map { y in (0..<w).map { x in buf[(y * w + x) * 4] } }
}

private func pixelRGBA(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    let w = image.width, h = image.height
    let ctx = srgbContext(width: w, height: h)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let buf = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
    let i = (y * w + x) * 4
    return (buf[i], buf[i + 1], buf[i + 2], buf[i + 3])
}

// MARK: - Suite

func suiteImagePipeline() throws {
    let tmp = try makeTempDir("pipeline")

    // Source image: bundled fixture when present, else a generated JPEG.
    let fixture = fixtureURL("20240503-DSCF2771.jpeg")
    let srcURL: URL
    if let fixture {
        srcURL = fixture
    } else {
        srcURL = tmp.appendingPathComponent("generated-source.jpg")
        try ImagePipeline.writeJPEG(makeTestImage(width: 320, height: 200), to: srcURL, quality: 0.9)
        check(FileManager.default.fileExists(atPath: srcURL.path), "generated fallback source JPEG written")
    }

    // --- load: full-size decode + orientedPixelSize agreement ---
    let full = ImagePipeline.load(url: srcURL, maxPixel: 10000)
    check(full != nil, "load returns non-nil for source image")
    let oriented = ImagePipeline.orientedPixelSize(url: srcURL)
    check(oriented != nil, "orientedPixelSize returns non-nil")
    if let full, let oriented {
        checkEqual(full.width, oriented.width, "loaded width matches orientedPixelSize")
        checkEqual(full.height, oriented.height, "loaded height matches orientedPixelSize")
    }

    // --- load: downsample + aspect ---
    let maxPixel = 640
    let small = ImagePipeline.load(url: srcURL, maxPixel: maxPixel)
    check(small != nil, "downsampled load returns non-nil")
    if let small {
        check(max(small.width, small.height) <= maxPixel,
              "longest edge <= maxPixel (got \(small.width)x\(small.height))")
    }
    if let small, let oriented {
        let got = Double(small.width) / Double(small.height)
        let want = Double(oriented.width) / Double(oriented.height)
        check(abs(got - want) / want < 0.02, "aspect ratio preserved when downsampled")
    }

    // --- thumbnail ---
    let thumb = ImagePipeline.thumbnail(url: srcURL, maxPixel: 256)
    check(thumb != nil, "thumbnail returns non-nil")
    if let thumb {
        check(max(thumb.width, thumb.height) <= 256, "thumbnail respects maxPixel")
    }

    // --- crop: center half + full frame ---
    if let full {
        let half = ImagePipeline.crop(full, to: CropRect(x: 0.25, y: 0.25, w: 0.5, h: 0.5))
        check(half != nil, "center crop returns non-nil")
        if let half {
            check(abs(Double(half.width) - Double(full.width) / 2) <= 1,
                  "crop width ~half (got \(half.width) of \(full.width))")
            check(abs(Double(half.height) - Double(full.height) / 2) <= 1,
                  "crop height ~half (got \(half.height) of \(full.height))")
        }
        if let ff = ImagePipeline.crop(full, to: .full) {
            check(ff.width == full.width && ff.height == full.height,
                  "full-frame crop keeps dimensions")
        } else {
            check(false, "full-frame crop returns non-nil")
        }
    }

    // --- crop: pixel content (right half of a red/blue image is blue) ---
    let blocks = makeTestImage(width: 100, height: 50)
    if let right = ImagePipeline.crop(blocks, to: CropRect(x: 0.5, y: 0, w: 0.5, h: 1)) {
        checkEqual(right.width, 50, "right-half crop width")
        let px = pixelRGBA(right, x: 5, y: 5)
        check(px.b > 200 && px.r < 50, "cropped right half is blue")
        if let left = ImagePipeline.crop(blocks, to: CropRect(x: 0, y: 0, w: 0.5, h: 1)) {
            let pl = pixelRGBA(left, x: 5, y: 5)
            check(pl.r > 200 && pl.b < 50, "cropped left half is red")
        }
    } else {
        check(false, "right-half crop returns non-nil")
    }

    // --- writeJPEG: file exists, non-empty, decodes again ---
    let out = tmp.appendingPathComponent("out.jpg")
    try ImagePipeline.writeJPEG(blocks, to: out, quality: 0.9)
    check(FileManager.default.fileExists(atPath: out.path), "writeJPEG created a file")
    let attrs = try FileManager.default.attributesOfItem(atPath: out.path)
    check((attrs[.size] as? Int ?? 0) > 0, "written JPEG is non-empty")
    check(ImagePipeline.load(url: out, maxPixel: 100) != nil, "written JPEG decodes again")

    // --- export: nil crop → byte-identical copy ---
    let copy1 = tmp.appendingPathComponent("copy-nil.jpg")
    try ImagePipeline.export(src: srcURL, crop: nil, to: copy1, quality: 0.9)
    checkEqual(try Data(contentsOf: srcURL), try Data(contentsOf: copy1),
               "export with nil crop copies bytes exactly")

    // --- export: full-frame crop → byte-identical copy ---
    let copy2 = tmp.appendingPathComponent("copy-full.jpg")
    try ImagePipeline.export(src: srcURL, crop: .full, to: copy2, quality: 0.9)
    checkEqual(try Data(contentsOf: srcURL), try Data(contentsOf: copy2),
               "export with full-frame crop copies bytes exactly")

    // --- export: center crop → smaller, re-encoded image ---
    let cropped = tmp.appendingPathComponent("cropped.jpg")
    try ImagePipeline.export(src: srcURL,
                             crop: CropRect(x: 0.25, y: 0.25, w: 0.5, h: 0.5),
                             to: cropped, quality: 0.9)
    check(FileManager.default.fileExists(atPath: cropped.path), "cropped export written")
    if let croppedImg = ImagePipeline.load(url: cropped, maxPixel: 10000), let oriented {
        check(croppedImg.width < oriented.width && croppedImg.height < oriented.height,
              "cropped export is smaller than the source")
        check(abs(Double(croppedImg.width) - Double(oriented.width) / 2) <= 1,
              "cropped export ~half width (got \(croppedImg.width) of \(oriented.width))")
        check(abs(Double(croppedImg.height) - Double(oriented.height) / 2) <= 1,
              "cropped export ~half height (got \(croppedImg.height) of \(oriented.height))")
    } else {
        check(false, "cropped export decodes")
    }

    // --- applyOrientation: all 8 EXIF cases on a 3x2 gray pattern ---
    let pattern: [[UInt8]] = [[10, 20, 30], [40, 50, 60]]
    let expected: [Int: [[UInt8]]] = [
        1: [[10, 20, 30], [40, 50, 60]],            // none
        2: [[30, 20, 10], [60, 50, 40]],            // flip horizontal
        3: [[60, 50, 40], [30, 20, 10]],            // rotate 180
        4: [[40, 50, 60], [10, 20, 30]],            // flip vertical
        5: [[10, 40], [20, 50], [30, 60]],          // transpose
        6: [[40, 10], [50, 20], [60, 30]],          // rotate 90 CW
        7: [[60, 30], [50, 20], [40, 10]],          // transverse
        8: [[30, 60], [20, 50], [10, 40]],          // rotate 90 CCW
    ]
    for (o, want) in expected.sorted(by: { $0.key < $1.key }) {
        let out = ImagePipeline.applyOrientation(grayImage(pattern), orientation: o)
        let wantW = (5...8).contains(o) ? 2 : 3
        let wantH = (5...8).contains(o) ? 3 : 2
        check(out.width == wantW && out.height == wantH, "orientation \(o) swaps dimensions")
        checkEqual(grayPixels(out), want, "orientation \(o) pixel layout")
    }

    // --- ImageCache: store/return, LRU eviction, clear ---
    let cache = ImageCache(capacity: 2)
    let imgs = (0..<4).map { j in grayImage([[UInt8(j * 10)]]) }
    cache.store(imgs[0], for: "a")
    cache.store(imgs[1], for: "b")
    // Note: image(for:) touches LRU order, so "a" is only looked up after eviction.
    check(cache.image(for: "nope") == nil, "cache returns nil for unknown key")
    cache.store(imgs[2], for: "c")
    check(cache.image(for: "a") == nil, "cache evicts oldest past capacity")
    check(cache.image(for: "b") === imgs[1], "cache keeps entry b")
    check(cache.image(for: "c") === imgs[2], "cache keeps entry c")

    let lru = ImageCache(capacity: 2)
    lru.store(imgs[0], for: "a")
    lru.store(imgs[1], for: "b")
    _ = lru.image(for: "a")           // touch a
    lru.store(imgs[2], for: "c")
    check(lru.image(for: "a") === imgs[0], "LRU keeps recently used entry")
    check(lru.image(for: "b") == nil, "LRU evicts least recently used entry")
    lru.clear()
    check(lru.image(for: "a") == nil && lru.image(for: "c") == nil, "clear empties the cache")
    checkEqual(ImageCache.key(url: URL(fileURLWithPath: "/x/y.jpg"), maxPixel: 512),
               "/x/y.jpg|512", "cache key format")

    // --- ImageCache: concurrent access safety ---
    let conc = ImageCache(capacity: 8)
    var mismatches: [String] = []
    let mlock = NSLock()
    DispatchQueue.concurrentPerform(iterations: 64) { i in
        let j = i % 16
        let k = "k\(j)"
        conc.store(imgs[j % imgs.count], for: k)
        if let got = conc.image(for: k), got !== imgs[j % imgs.count] {
            mlock.lock()
            mismatches.append("wrong image returned for \(k)")
            mlock.unlock()
        }
        if i % 8 == 0 { conc.clear() }
    }
    check(mismatches.isEmpty, "cache never returns a wrong image under concurrent access")
    let present = (0..<16).filter { conc.image(for: "k\($0)") != nil }
    check(present.count <= 8, "capacity respected after concurrent stores (got \(present.count))")

    // --- coverScale: shared by CPU rotateToFill and the GPU live-tilt preview ---
    checkEqual(ImagePipeline.coverScale(width: 100, height: 100, degrees: 0), 1.0,
               "coverScale at 0° is 1")
    checkClose(ImagePipeline.coverScale(width: 100, height: 100, degrees: 45),
               2.0.squareRoot(), 1e-9, "coverScale square at 45° is √2")
    checkClose(ImagePipeline.coverScale(width: 300, height: 200, degrees: 90),
               1.5, 1e-9, "coverScale 300x200 at 90° is 1.5")

    // --- rotateToFill: same-size output contract on a non-square input ---
    let nonsquare = makeTestImage(width: 120, height: 80)
    let tilted = ImagePipeline.rotateToFill(nonsquare, degrees: 10)
    checkEqual(tilted.width, nonsquare.width, "rotateToFill keeps width at 10°")
    checkEqual(tilted.height, nonsquare.height, "rotateToFill keeps height at 10°")

    // --- ImageCache: byte budget evicts LRU-first, never the newest entry ---
    // blocks is 100x50 RGBA = 20,000 bytes.
    let budgeted = ImageCache(capacity: 8, byteBudget: 30_000)
    budgeted.store(blocks, for: "big-a")
    budgeted.store(blocks, for: "big-b")
    check(budgeted.image(for: "big-a") == nil, "byte budget evicts LRU entry past budget")
    check(budgeted.image(for: "big-b") === blocks, "byte budget keeps the newest entry")
    let solo = ImageCache(capacity: 4, byteBudget: 1)
    solo.store(blocks, for: "one")
    check(solo.image(for: "one") === blocks,
          "single entry survives even when it alone exceeds the byte budget")
}

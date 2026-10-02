import Foundation
import CoreGraphics
import ImageIO
import PhotoCullCore

// Tests_Rotation.swift — quarter turns and fine tilt: signs, round-trips, export.
// Screen-space convention under test: positive angle / one quarter turn rotate
// the photo CLOCKWISE on screen. CG contexts are y-up while displays are
// y-down, so every sign here is verified against pixel positions, not trust.

func suiteRotation() throws {
    let fm = FileManager.default
    let tmp = try makeTempDir("rotation")

    // ── helpers ───────────────────────────────────────────────────────────
    /// 100×100 white image with a red top-left quadrant (screen coordinates).
    func markerImage(_ w: Int = 100, _ h: Int = 100) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        // y-up context: the top-left screen quadrant is (0, h/2, w/2, h/2).
        ctx.fill(CGRect(x: 0, y: h / 2, width: w / 2, height: h / 2))
        return ctx.makeImage()!
    }

    /// Centroid (screen coords, top-left origin) of the red pixels, or nil.
    func redCentroid(_ image: CGImage) -> (x: Double, y: Double)? {
        let w = image.width, h = image.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let stride = ctx.bytesPerRow  // padded — NOT w*4
        let px = data.bindMemory(to: UInt8.self, capacity: stride * h)
        var sx = 0.0, sy = 0.0, n = 0.0
        for row in 0..<h {
            for col in 0..<w {
                let i = (row * stride) + col * 4
                // Red, and not white: the marker quadrant.
                if px[i] > 200, px[i + 1] < 100, px[i + 2] < 100 {
                    sx += Double(col); sy += Double(row); n += 1
                }
            }
        }
        guard n > 0 else { return nil }
        return (sx / n, sy / n)
    }

    // ── quarter turns ─────────────────────────────────────────────────────
    let marker = markerImage()
    let c0 = redCentroid(marker)!
    checkClose(c0.x, 25, 0.5, "marker starts in the top-left quadrant (x)")
    checkClose(c0.y, 25, 0.5, "marker starts in the top-left quadrant (y)")

    let cw = ImagePipeline.rotateQuarter(marker, turns: 1)
    checkEqual(cw.width, 100, "quarter turn keeps width")
    let c1 = redCentroid(cw)!
    check(c1.x > 60 && c1.x < 90, "one quarter turn moves the marker clockwise (x=\(c1.x))")
    check(c1.y < 40, "one quarter turn keeps the marker near the top (y=\(c1.y))")

    let ccw = ImagePipeline.rotateQuarter(marker, turns: -1)
    let cm1 = redCentroid(ccw)!
    check(cm1.x < 40, "minus one quarter turn moves the marker left (x=\(cm1.x))")
    check(cm1.y > 60, "minus one quarter turn moves the marker to the bottom (y=\(cm1.y))")

    check(ImagePipeline.rotateQuarter(markerImage(40, 20), turns: 1).width == 20,
          "quarter turn swaps a landscape image's dimensions")

    // ── fine tilt ─────────────────────────────────────────────────────────
    let tilted = ImagePipeline.rotateToFill(marker, degrees: 10)
    checkEqual(tilted.width, 100, "tilt keeps the canvas width")
    checkEqual(tilted.height, 100, "tilt keeps the canvas height")
    let ct = redCentroid(tilted)!
    check(ct.x > 26.5, "positive tilt rotates clockwise on screen (x=\(ct.x) > 25)")
    let ntilt = ImagePipeline.rotateToFill(marker, degrees: -10)
    let cn = redCentroid(ntilt)!
    check(cn.x < 23.5, "negative tilt rotates counter-clockwise on screen (x=\(cn.x) < 25)")

    // ── sidecar round-trip ────────────────────────────────────────────────
    let folder = tmp.appendingPathComponent("2024-06-01")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let s = Session.fresh()
    s.setTilt("A0001", 1.5)
    s.setTilt("B0002", 0.01)   // below the 0.05° noise floor → dropped
    s.setQuarter("A0001", 1)
    s.setQuarter("C0003", 4)   // full revolution → dropped
    s.setQuarter("D0004", -1)  // normalizes to 3
    try s.save(folder: folder)
    let json = try String(contentsOf: folder.appendingPathComponent(Session.fileName), encoding: .utf8)
    check(json.contains("\"tilts\""), "sidecar has a tilts key")
    check(json.contains("\"rotations\""), "sidecar has a rotations key")

    let r = try Session.load(folder: folder)
    checkClose(r.tilt(for: "a0001"), 1.5, 0.0001, "tilt survives a save/load round-trip")
    checkClose(r.tilt(for: "B0002"), 0, 0.0001, "sub-noise tilt is not persisted")
    checkEqual(r.quarterTurns(for: "A0001"), 1, "quarter turn survives the round-trip")
    checkEqual(r.quarterTurns(for: "C0003"), 0, "full revolution is not persisted")
    checkEqual(r.quarterTurns(for: "D0004"), 3, "negative turns normalize to 3")

    // ── export ────────────────────────────────────────────────────────────
    let src = tmp.appendingPathComponent("R.JPG")
    try ImagePipeline.writeJPEG(markerImage(40, 20), to: src, quality: 0.9)

    func dims(_ url: URL) -> (Int, Int) {
        let s = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as! [CFString: Any]
        return (p[kCGImagePropertyPixelWidth] as! Int, p[kCGImagePropertyPixelHeight] as! Int)
    }

    let outQ = tmp.appendingPathComponent("outQ.JPG")
    try ImagePipeline.export(src: src, crop: nil, to: outQ, quality: 0.9, quarterTurns: 1)
    check(dims(outQ) == (20, 40), "exported quarter turn swaps dimensions, got \(dims(outQ))")

    let outT = tmp.appendingPathComponent("outT.JPG")
    try ImagePipeline.export(src: src, crop: nil, to: outT, quality: 0.9, tilt: 5)
    check(dims(outT) == (40, 20), "exported tilt keeps dimensions, got \(dims(outT))")

    let outNone = tmp.appendingPathComponent("outNone.JPG")
    try ImagePipeline.export(src: src, crop: nil, to: outNone, quality: 0.9)
    check(fm.contentsEqual(atPath: src.path, andPath: outNone.path),
          "no edits → bytes copied unchanged")
}

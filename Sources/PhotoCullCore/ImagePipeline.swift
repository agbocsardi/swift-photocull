import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// ImagePipeline.swift — decode, downsample, orient, crop, encode.

public enum ImagePipeline {
    /// Decode `url` downsampled so the longest edge is <= `maxPixel`,
    /// with EXIF orientation already applied.
    public static func load(url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Fast thumbnail (ImageIO thumbnail path, orientation applied).
    public static func thumbnail(url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Pixel size of the file with EXIF orientation applied.
    public static func orientedPixelSize(url: URL) -> (width: Int, height: Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        guard let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        if (5...8).contains(orientation) {
            return (width: h, height: w)
        }
        return (width: w, height: h)
    }

    /// Crop an already orientation-corrected image using a normalized rect.
    public static func crop(_ image: CGImage, to rect: CropRect) -> CGImage? {
        if rect.isFullFrame { return image }
        // Clamp the normalized rect into the frame.
        let x = min(max(rect.x, 0), 1)
        let y = min(max(rect.y, 0), 1)
        let w = min(max(rect.w, 0), 1 - x)
        let h = min(max(rect.h, 0), 1 - y)
        if w <= 0 || h <= 0 { return nil }
        let pw = CGFloat(image.width)
        let ph = CGFloat(image.height)
        // CGImage cropping uses top-left origin pixel space, same as the
        // oriented display space, so the conversion is a direct scale.
        var px = Int((x * pw).rounded(.down))
        var py = Int((y * ph).rounded(.down))
        var pwid = Int((w * pw).rounded())
        var phei = Int((h * ph).rounded())
        px = min(max(px, 0), image.width - 1)
        py = min(max(py, 0), image.height - 1)
        pwid = min(max(pwid, 1), image.width - px)
        phei = min(max(phei, 1), image.height - py)
        return image.cropping(to: CGRect(x: px, y: py, width: pwid, height: phei))
    }

    /// Write a CGImage as JPEG.
    public static func writeJPEG(_ image: CGImage, to url: URL, quality: Double) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw pipelineError("could not create JPEG destination at \(url.path)") }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw pipelineError("could not finalize JPEG at \(url.path)")
        }
    }

    /// Read `src`, apply `crop` (if any), write JPEG to `dst`.
    /// When `crop` is nil or full-frame, copies the file bytes unchanged.
    public static func export(src: URL, crop: CropRect?, to dst: URL, quality: Double) throws {
        if let crop, !crop.isFullFrame {
            guard let size = orientedPixelSize(url: src) else {
                throw pipelineError("could not read dimensions of \(src.path)")
            }
            let maxPixel = max(size.width, size.height)
            guard let image = load(url: src, maxPixel: maxPixel) else {
                throw pipelineError("could not decode \(src.path)")
            }
            guard let cropped = ImagePipeline.crop(image, to: crop) else {
                throw pipelineError("invalid crop rect \(crop)")
            }
            try writeJPEG(cropped, to: dst, quality: quality)
        } else {
            try FileManager.default.copyItem(at: src, to: dst)
        }
    }

    /// Rotate/flip `image` according to EXIF orientation 1...8.
    public static func applyOrientation(_ image: CGImage, orientation: Int) -> CGImage {
        guard (2...8).contains(orientation) else { return image }
        let w = image.width
        let h = image.height
        let swapped = (5...8).contains(orientation)
        let outW = swapped ? h : w
        let outH = swapped ? w : h

        // CGContext space has a bottom-left origin, so the flips/rotations
        // below are expressed in that space (verified against EXIF matrices).
        var t = CGAffineTransform.identity
        switch orientation {
        case 2: // flip horizontal
            t = CGAffineTransform(translationX: CGFloat(w), y: 0).scaledBy(x: -1, y: 1)
        case 3: // rotate 180
            t = CGAffineTransform(translationX: CGFloat(w), y: CGFloat(h)).rotated(by: .pi)
        case 4: // flip vertical
            t = CGAffineTransform(translationX: 0, y: CGFloat(h)).scaledBy(x: 1, y: -1)
        case 5: // transpose: display (x, y) -> (y, x)
            t = CGAffineTransform(translationX: CGFloat(h), y: CGFloat(w))
                .rotated(by: .pi / 2).scaledBy(x: -1, y: 1)
        case 6: // rotate 90 CW: display (x, y) -> (H - y, x)
            t = CGAffineTransform(translationX: 0, y: CGFloat(w)).rotated(by: -.pi / 2)
        case 7: // transverse: display (x, y) -> (H - y, W - x)
            t = CGAffineTransform.identity.rotated(by: -.pi / 2).scaledBy(x: -1, y: 1)
        case 8: // rotate 90 CCW: display (x, y) -> (y, W - x)
            t = CGAffineTransform(translationX: CGFloat(h), y: 0).rotated(by: .pi / 2)
        default:
            return image
        }

        guard let cs = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else { return image }
        guard let ctx = CGContext(data: nil, width: outW, height: outH,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.concatenate(t)
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return ctx.makeImage() ?? image
    }

    static func pipelineError(_ msg: String) -> NSError {
        NSError(domain: "PhotoCullCore.ImagePipeline", code: 1,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }
}

/// Thread-safe LRU cache for decoded images, keyed by (path, maxPixel).
public final class ImageCache: @unchecked Sendable {
    private let capacity: Int
    private var lock = NSLock()
    /// Oldest first.
    private var order: [String] = []
    private var images: [String: CGImage] = [:]

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
    }

    public func image(for key: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let img = images[key] else { return nil }
        // Touch: move to the most-recently-used end.
        order.removeAll { $0 == key }
        order.append(key)
        return img
    }

    public func store(_ image: CGImage, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        guard capacity > 0 else { return }
        images[key] = image
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity {
            let evicted = order.removeFirst()
            images.removeValue(forKey: evicted)
        }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        images.removeAll()
        order.removeAll()
    }

    /// Cache key helper: "<path>|<maxPixel>".
    public static func key(url: URL, maxPixel: Int) -> String { "\(url.path)|\(maxPixel)" }
}

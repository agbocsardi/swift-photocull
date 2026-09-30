import Foundation
import CoreGraphics

// ImagePipeline.swift — decode, downsample, orient, crop, encode.

public enum ImagePipeline {
    /// Decode `url` downsampled so the longest edge is <= `maxPixel`,
    /// with EXIF orientation already applied.
    public static func load(url: URL, maxPixel: Int) -> CGImage? { fatalError("TODO: ImagePipeline.load") }

    /// Fast thumbnail (ImageIO thumbnail path, orientation applied).
    public static func thumbnail(url: URL, maxPixel: Int) -> CGImage? { fatalError("TODO: ImagePipeline.thumbnail") }

    /// Pixel size of the file with EXIF orientation applied.
    public static func orientedPixelSize(url: URL) -> (width: Int, height: Int)? {
        fatalError("TODO: ImagePipeline.orientedPixelSize")
    }

    /// Crop an already orientation-corrected image using a normalized rect.
    public static func crop(_ image: CGImage, to rect: CropRect) -> CGImage? {
        fatalError("TODO: ImagePipeline.crop")
    }

    /// Write a CGImage as JPEG.
    public static func writeJPEG(_ image: CGImage, to url: URL, quality: Double) throws {
        fatalError("TODO: ImagePipeline.writeJPEG")
    }

    /// Read `src`, apply `crop` (if any), write JPEG to `dst`.
    /// When `crop` is nil or full-frame, copies the file bytes unchanged.
    public static func export(src: URL, crop: CropRect?, to dst: URL, quality: Double) throws {
        fatalError("TODO: ImagePipeline.export")
    }

    /// Rotate/flip `image` according to EXIF orientation 1...8.
    public static func applyOrientation(_ image: CGImage, orientation: Int) -> CGImage {
        fatalError("TODO: ImagePipeline.applyOrientation")
    }
}

/// Thread-safe LRU cache for decoded images, keyed by (path, maxPixel).
public final class ImageCache: @unchecked Sendable {
    public init(capacity: Int) { fatalError("TODO: ImageCache.init") }
    public func image(for key: String) -> CGImage? { fatalError("TODO: ImageCache.image") }
    public func store(_ image: CGImage, for key: String) { fatalError("TODO: ImageCache.store") }
    public func clear() { fatalError("TODO: ImageCache.clear") }
    /// Cache key helper: "<path>|<maxPixel>".
    public static func key(url: URL, maxPixel: Int) -> String { "\(url.path)|\(maxPixel)" }
}

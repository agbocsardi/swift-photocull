import Foundation

// Exif.swift — metadata via ImageIO (CGImageSource).

public struct PhotoInfo: Sendable, Equatable {
    public var camera: String?
    public var lens: String?
    public var iso: String?
    public var shutter: String?
    public var aperture: String?
    /// Pixel dimensions as text, e.g. "6240×4160". Falls back to "1.2 MB".
    public var size: String?
    /// "YYYY-MM-DD HH:MM:SS" when EXIF DateTimeOriginal is present.
    public var dateTimeOriginal: String?
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// EXIF orientation 1...8 (1 = normal).
    public var orientation: Int
    public var fileSizeBytes: Int64
    public init() {
        camera = nil; lens = nil; iso = nil; shutter = nil; aperture = nil
        size = nil; dateTimeOriginal = nil; pixelWidth = 0; pixelHeight = 0
        orientation = 1; fileSizeBytes = 0
    }
}

public enum ExifReader {
    /// Read metadata from a JPG or RAW file. Never throws; missing fields stay nil.
    public static func read(url: URL) -> PhotoInfo { fatalError("TODO: ExifReader.read") }

    /// EXIF DateTimeOriginal as "YYYY-MM-DD", else file modification date,
    /// else "undated". Used by ingest for date folder naming.
    public static func captureDate(url: URL) -> String { fatalError("TODO: ExifReader.captureDate") }

    /// Raw EXIF orientation (1...8) without reading pixel data. Defaults to 1.
    public static func orientation(url: URL) -> Int { fatalError("TODO: ExifReader.orientation") }
}

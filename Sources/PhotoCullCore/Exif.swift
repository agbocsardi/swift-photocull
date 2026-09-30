import Foundation
import ImageIO
import CoreGraphics

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
    public static func read(url: URL) -> PhotoInfo {
        var info = PhotoInfo()
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let bytes = attrs[.size] as? Int64 {
            info.fileSizeBytes = bytes
        }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            // No readable metadata: Go still stats the file for a size line.
            if info.fileSizeBytes > 0 {
                info.size = String(format: "%.1f MB", Double(info.fileSizeBytes) / 1e6)
            }
            return info
        }

        // Camera: "{Make} {Model}", either part alone when the other is missing.
        // ImageIO reports Make/Model in the TIFF dictionary.
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let make = (tiff?[kCGImagePropertyTIFFMake] as? String)
            ?? (props["Make" as CFString] as? String) ?? ""
        let model = (tiff?[kCGImagePropertyTIFFModel] as? String)
            ?? (props["Model" as CFString] as? String) ?? ""
        switch (make.isEmpty, model.isEmpty) {
        case (false, false): info.camera = make + " " + model
        case (false, true): info.camera = make
        case (true, false): info.camera = model
        case (true, true): info.camera = nil
        }

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let exifAux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any]

        // Lens: ExifAux LensModel, else EXIF LensModel.
        if let lens = exifAux?[kCGImagePropertyExifAuxLensModel] as? String, !lens.isEmpty {
            info.lens = lens
        } else if let lens = exif?[kCGImagePropertyExifLensModel] as? String, !lens.isEmpty {
            info.lens = lens
        }

        // ISO: first element of ISOSpeedRatings.
        if let vals = exif?[kCGImagePropertyExifISOSpeedRatings] as? [Any], let first = vals.first {
            info.iso = String(describing: numeric(first))
        }

        // Shutter: ExposureTime as "1/250s" or "n/ds".
        if let t = exif?[kCGImagePropertyExifExposureTime] as? Double, t > 0 {
            if t >= 1.0 {
                info.shutter = String(format: "%gs", t)
            } else {
                let den = (1.0 / t).rounded()
                if den > 0 {
                    let num = (t * den).rounded()
                    if num == 1 {
                        info.shutter = "1/\(Int(den))s"
                    } else {
                        info.shutter = "\(Int(num))/\(Int(den))s"
                    }
                }
            }
        }

        // Aperture: FNumber as "f/2.8".
        if let f = exif?[kCGImagePropertyExifFNumber] as? Double, f > 0 {
            info.aperture = String(format: "f/%.1f", f)
        }

        // Pixel dimensions.
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        if w > 0 && h > 0 {
            info.pixelWidth = w
            info.pixelHeight = h
            info.size = "\(w)\u{00D7}\(h)"
        } else if info.fileSizeBytes > 0 {
            info.size = String(format: "%.1f MB", Double(info.fileSizeBytes) / 1e6)
        }

        // DateTimeOriginal: "2024:05:03 14:22:31" → "2024-05-03 14:22:31".
        if let dto = exif?[kCGImagePropertyExifDateTimeOriginal] as? String {
            info.dateTimeOriginal = Self.normalizeDateTime(dto)
        }

        if let o = props[kCGImagePropertyOrientation] as? Int, o >= 1 && o <= 8 {
            info.orientation = o
        }

        return info
    }

    /// EXIF DateTimeOriginal as "YYYY-MM-DD", else file modification date,
    /// else "undated". Used by ingest for date folder naming.
    public static func captureDate(url: URL) -> String {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let dto = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
           let date = normalizedDate(dto) {
            return date
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let mod = attrs[.modificationDate] as? Date {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            return f.string(from: mod)
        }
        return "undated"
    }

    /// Raw EXIF orientation (1...8) without reading pixel data. Defaults to 1.
    public static func orientation(url: URL) -> Int {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let o = props[kCGImagePropertyOrientation] as? Int, o >= 1 && o <= 8 else {
            return 1
        }
        return o
    }

    /// "2024:05:03 14:22:31" → "2024-05-03 14:22:31" (best effort).
    static func normalizeDateTime(_ raw: String) -> String {
        let parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let datePart = parts.count > 0 ? String(parts[0]) : ""
        let timePart = parts.count > 1 ? String(parts[1]) : ""
        let comps = datePart.split(separator: ":")
        var date = datePart
        if comps.count == 3 {
            date = "\(comps[0])-\(comps[1])-\(comps[2])"
        }
        if timePart.isEmpty { return date }
        return date + " " + timePart
    }

    /// "2024:05:03 14:22:31" → "2024-05-03", nil when unparseable.
    static func normalizedDate(_ raw: String) -> String? {
        guard let datePart = raw.split(separator: " ").first else { return nil }
        let comps = datePart.split(separator: ":")
        guard comps.count == 3 else { return nil }
        return "\(comps[0])-\(comps[1])-\(comps[2])"
    }

    /// Force a value into a decimal string (ISO entries arrive as NSNumber).
    static func numeric(_ v: Any) -> CustomStringConvertible {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String, let n = Int(s) { return n }
        return String(describing: v)
    }
}

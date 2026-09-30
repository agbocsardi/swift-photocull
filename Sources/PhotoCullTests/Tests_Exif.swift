import Foundation
import PhotoCullCore

func suiteExif() throws {
    // ── Fixture JPEG: real EXIF via ImageIO ──────────────────────────────
    if let fx = fixtureURL("20240503-DSCF2771.jpeg") {
        let info = ExifReader.read(url: fx)
        check(info.camera != nil, "camera is non-nil for fixture JPEG")
        if let cam = info.camera {
            check(cam.lowercased().contains("x-s20"), "camera includes model (got \(cam))")
        }
        check(info.pixelWidth > 0, "pixelWidth > 0 (got \(info.pixelWidth))")
        checkEqual(info.pixelWidth, 2048, "fixture pixelWidth")
        checkEqual(info.pixelHeight, 1365, "fixture pixelHeight")
        if let size = info.size {
            check(size.contains("\u{00D7}"), "size uses U+00D7 multiplication sign (got \(size))")
        } else {
            check(false, "size is non-nil for fixture")
        }
        if let ap = info.aperture {
            check(ap.hasPrefix("f/"), "aperture formatted f/x.x (got \(ap))")
        } else {
            check(false, "aperture is non-nil for fixture")
        }
        check(info.iso != nil, "iso is non-nil for fixture (got \(info.iso ?? "nil"))")
        if let sh = info.shutter {
            check(sh.hasSuffix("s") && sh.contains("/"), "shutter is rational with s suffix (got \(sh))")
        } else {
            check(false, "shutter is non-nil for fixture")
        }
        if let dto = info.dateTimeOriginal {
            let ok = dto.range(of: "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}$",
                               options: .regularExpression) != nil
            check(ok, "dateTimeOriginal formatted YYYY-MM-DD HH:MM:SS (got \(dto))")
        }
        let cd = ExifReader.captureDate(url: fx)
        check(cd.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil,
              "captureDate matches YYYY-MM-DD (got \(cd))")
        checkEqual(ExifReader.orientation(url: fx), 1, "fixture orientation is 1")

        if let attrs = try? FileManager.default.attributesOfItem(atPath: fx.path),
           let bytes = attrs[.size] as? Int64 {
            checkEqual(info.fileSizeBytes, bytes, "fileSizeBytes matches file size")
        }
    } else {
        print("  (skip: fixture 20240503-DSCF2771.jpeg not present)")
    }

    // ── Junk JPEG: no EXIF → size-only info, mod-date captureDate ────────
    let tmp = try makeTempDir("exif")
    let plain = tmp.appendingPathComponent("plain.jpg")
    let payload = Data(repeating: 0x42, count: 1024)
    try payload.write(to: plain)

    let junk = ExifReader.read(url: plain)
    checkEqual(junk.fileSizeBytes, Int64(1024), "junk JPEG: fileSizeBytes set")
    check(junk.camera == nil, "junk JPEG: camera nil")
    check(junk.iso == nil && junk.shutter == nil && junk.aperture == nil,
          "junk JPEG: no EXIF fields")
    checkEqual(junk.size, "0.0 MB", "junk JPEG: size falls back to MB text")
    checkEqual(junk.pixelWidth, 0, "junk JPEG: pixelWidth 0")
    checkEqual(junk.orientation, 1, "junk JPEG: orientation defaults to 1")
    checkEqual(ExifReader.orientation(url: plain), 1, "orientation() defaults to 1")

    // captureDate falls back to the file modification date
    var comps = DateComponents()
    comps.year = 2023; comps.month = 1; comps.day = 15; comps.hour = 12
    let when = Calendar.current.date(from: comps)  // noon local → no TZ day-shift
    try FileManager.default.setAttributes([.modificationDate: when as Any], ofItemAtPath: plain.path)
    checkEqual(ExifReader.captureDate(url: plain), "2023-01-15", "captureDate uses mod date")

    // ── Garbage RAW: never throws, size only ────────────────────────────
    let raf = tmp.appendingPathComponent("DSCF9999.RAF")
    try Data(repeating: 0x00, count: 4096).write(to: raf)
    let rawInfo = ExifReader.read(url: raf)
    checkEqual(rawInfo.fileSizeBytes, Int64(4096), "garbage RAW: fileSizeBytes set")
    check(rawInfo.camera == nil, "garbage RAW: camera nil")
    check(rawInfo.size == nil || rawInfo.size == "0.0 MB",
          "garbage RAW: no pixel dims (got \(rawInfo.size ?? "nil"))")
    checkEqual(rawInfo.orientation, 1, "garbage RAW: orientation default 1")
}

import Foundation
import CoreGraphics
import ImageIO
import PhotoCullCore

private var finalizePlanningChecks = 0
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    finalizePlanningChecks += 1
    if !condition() { fatalError("CHECK \(finalizePlanningChecks) failed: \(message)") }
}

private func centerPixel(_ url: URL) -> (UInt8, UInt8, UInt8)? {
    guard let image = ImagePipeline.load(url: url, maxPixel: 16) else { return nil }
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let info = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
    guard let context = CGContext(data: &pixels, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info.rawValue) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let offset = ((image.height / 2) * image.width + image.width / 2) * 4
    return (pixels[offset], pixels[offset + 1], pixels[offset + 2])
}

private func makeJPEG(_ url: URL, color: (UInt8, UInt8, UInt8)) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: CGFloat(color.0) / 255, green: CGFloat(color.1) / 255,
                         blue: CGFloat(color.2) / 255, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    try ImagePipeline.writeJPEG(context.makeImage()!, to: url, quality: 1)
}

/// Synthetic-only Finalize regressions: never reject, Trash, or read user data.
func suiteFinalizePlanningChecks() throws {
    let fm = FileManager.default
    guard let outPath = ProcessInfo.processInfo.environment["PC_FINALIZE_TEST_OUT"] else {
        fatalError("PC_FINALIZE_TEST_OUT must name the dedicated output root")
    }
    let outRoot = URL(fileURLWithPath: outPath)
    let confinementPrefix = outRoot.path.hasSuffix("/") ? outRoot.path : outRoot.path + "/"
    let root = outRoot.appendingPathComponent("synthetic/test-\(UUID().uuidString)", isDirectory: true)
    guard root.path.hasPrefix(confinementPrefix) else { fatalError("synthetic root escaped OUT") }
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        if root.path.hasPrefix(confinementPrefix) {
            try? fm.removeItem(at: root)
        }
    }
    var dateIndex = 0
    func setup() throws -> (URL, URL, URL, PCConfig) {
        dateIndex += 1
        let date = String(format: "2026-10-%02d", dateIndex)
        let inbox = root.appendingPathComponent("inbox/\(date)")
        let archive = root.appendingPathComponent("archive/\(date)")
        let dump = root.appendingPathComponent("dump/\(date)")
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        let cfg = PCConfig(paths: PathsConfig(inbox: root.appendingPathComponent("inbox").path,
                                              archive: root.appendingPathComponent("archive").path,
                                              dump: root.appendingPathComponent("dump").path),
                           files: FilesConfig(rawExtensions: ["RAF"], jpgExtensions: ["JPG", "JPEG"]))
        return (inbox, archive, dump, cfg)
    }
    func bytes(_ url: URL, _ data: Data) throws { try data.write(to: url) }
    func run(_ cfg: PCConfig, date: String, dump: Bool = false) throws -> FinalizeResult {
        try Finalize.run(cfg: cfg, date: date, dump: dump, cropMode: .original, dumpOverride: nil)
    }
    func assertBytes(_ url: URL, _ data: Data, _ message: String) throws {
        let actual = try Data(contentsOf: url)
        expect(actual == data, message)
    }

    // In-run archive reservations include source names and preserve markers.
    do {
        let (inbox, archive, _, cfg) = try setup()
        let a = Data([1, 2, 3]), a2 = Data([4, 5, 6])
        try bytes(inbox.appendingPathComponent("A.JPG"), a)
        try bytes(inbox.appendingPathComponent("A_2.JPG"), a2)
        let outsider = Data([90, 91])
        try bytes(archive.appendingPathComponent("a.jpg"), outsider)
        _ = try run(cfg, date: inbox.lastPathComponent)
        try assertBytes(archive.appendingPathComponent("A_2.JPG"), a, "case-folded collision suffix")
        try assertBytes(archive.appendingPathComponent("A_2_2.JPG"), a2, "reserved suffix avoids next source")
        try assertBytes(archive.appendingPathComponent("a.jpg"), outsider, "preexisting archive bytes preserved")
    }

    // Either existing member forces a common suffix for a paired JPG+RAW.
    for existingName in ["A.JPG", "A.RAF"] {
        let (inbox, archive, _, cfg) = try setup()
        let jpg = Data([11, 12]), raw = Data([13, 14]), outsider = Data([99])
        try bytes(inbox.appendingPathComponent("A.JPG"), jpg)
        try bytes(inbox.appendingPathComponent("A.RAF"), raw)
        try bytes(archive.appendingPathComponent(existingName), outsider)
        _ = try run(cfg, date: inbox.lastPathComponent)
        try assertBytes(archive.appendingPathComponent("A_2.JPG"), jpg, "paired JPG uses common suffix")
        try assertBytes(archive.appendingPathComponent("A_2.RAF"), raw, "paired RAW uses common suffix")
        try assertBytes(archive.appendingPathComponent(existingName), outsider, "pair collision preserves outsider")
    }

    // Orphan reservations account for already-planned pair destinations.
    do {
        let (inbox, archive, _, cfg) = try setup()
        let jpg = Data([21]), raw = Data([22]), orphan = Data([23]), outsider = Data([24])
        try bytes(inbox.appendingPathComponent("A.JPG"), jpg)
        try bytes(inbox.appendingPathComponent("A.RAF"), raw)
        try bytes(inbox.appendingPathComponent("A_2.RAF"), orphan)
        try bytes(archive.appendingPathComponent("A.JPG"), outsider)
        _ = try run(cfg, date: inbox.lastPathComponent)
        try assertBytes(archive.appendingPathComponent("A.JPG"), outsider, "existing pair JPG marker preserved")
        try assertBytes(archive.appendingPathComponent("A_2.JPG"), jpg, "pair JPG receives common suffix")
        try assertBytes(archive.appendingPathComponent("A_2.RAF"), raw, "pair RAW reserves orphan's original name")
        try assertBytes(archive.appendingPathComponent("A_2_2.RAF"), orphan, "orphan avoids planned pair RAW")
    }

    // Dump paths are reserved independently; unrelated legacy .tmp is untouched.
    do {
        let (inbox, _, dump, cfg) = try setup()
        try fm.createDirectory(at: dump, withIntermediateDirectories: true)
        let one = Data([31]), two = Data([32]), sentinel = Data([33, 34])
        try bytes(inbox.appendingPathComponent("A.JPG"), one)
        try bytes(inbox.appendingPathComponent("A_2.JPG"), two)
        try bytes(dump.appendingPathComponent("A.JPG"), Data([35]))
        try bytes(dump.appendingPathComponent("legacy.tmp"), sentinel)
        _ = try Finalize.run(cfg: cfg, date: inbox.lastPathComponent, dump: true,
                             cropMode: .original, dumpOverride: dump)
        try assertBytes(dump.appendingPathComponent("A_2.JPG"), one, "dump reserves first suffix")
        try assertBytes(dump.appendingPathComponent("A_2_2.JPG"), two, "dump reservations are per-run")
        try assertBytes(dump.appendingPathComponent("legacy.tmp"), sentinel, "unrelated tmp survives")
    }

    // Edited jobs make valid output and leave no private stage directory/files.
    do {
        let (inbox, archive, dump, cfg) = try setup()
        try fm.createDirectory(at: dump, withIntermediateDirectories: true)
        let images = [("A", (255, 0, 0)), ("B", (0, 255, 0))] as [(String, (UInt8, UInt8, UInt8))]
        let session = Session.fresh()
        for (stem, color) in images {
            try makeJPEG(inbox.appendingPathComponent("\(stem).JPG"), color: color)
            session.setCrop(stem, CropRect(x: 0.1, y: 0.1, w: 0.8, h: 0.8))
        }
        try session.save(folder: inbox)
        let result = try Finalize.run(cfg: cfg, date: inbox.lastPathComponent, dump: true,
                                      cropMode: .applyCrop, dumpOverride: dump)
        expect(result.cropped == 2, "two edited exports counted")
        for (stem, _) in images {
            let output = dump.appendingPathComponent("\(stem).JPG")
            expect(ImagePipeline.orientedPixelSize(url: output)?.width == 6, "edited output has expected crop")
            let pixel = centerPixel(output)
            if stem == "A" {
                expect(Int(pixel?.0 ?? 0) > Int(pixel?.1 ?? 255) * 2, "red marker survives edited export")
            } else {
                expect(Int(pixel?.1 ?? 0) > Int(pixel?.0 ?? 255) * 2, "green marker survives edited export")
            }
            expect(fm.fileExists(atPath: archive.appendingPathComponent("\(stem).JPG").path), "original archived")
        }
        let entries = try fm.contentsOfDirectory(atPath: dump.path)
        expect(!entries.contains(where: { $0.hasPrefix(".photocull-stage-") }), "owned stage directory removed")
    }

    // Middle encode failure preserves completed prefix and leaves later source.
    do {
        let (inbox, archive, dump, cfg) = try setup()
        try fm.createDirectory(at: dump, withIntermediateDirectories: true)
        try makeJPEG(inbox.appendingPathComponent("A.JPG"), color: (1, 2, 3))
        try bytes(inbox.appendingPathComponent("B.JPG"), Data("not a jpeg".utf8))
        try bytes(inbox.appendingPathComponent("C.JPG"), Data("later".utf8))
        let session = Session.fresh()
        for stem in ["A", "B", "C"] { session.setCrop(stem, CropRect(x: 0.1, y: 0.1, w: 0.8, h: 0.8)) }
        try session.save(folder: inbox)
        do {
            _ = try Finalize.run(cfg: cfg, date: inbox.lastPathComponent, dump: true,
                                 cropMode: .applyCrop, dumpOverride: dump)
            fatalError("expected invalid-image encode failure")
        } catch { expect(true, "invalid middle export throws") }
        expect(fm.fileExists(atPath: archive.appendingPathComponent("A.JPG").path), "completed prefix archived")
        expect(fm.fileExists(atPath: dump.appendingPathComponent("A.JPG").path), "completed prefix dump remains")
        expect(fm.fileExists(atPath: inbox.appendingPathComponent("B.JPG").path), "failing source retained")
        expect(fm.fileExists(atPath: inbox.appendingPathComponent("C.JPG").path), "later source retained")
        let dumpEntries = try fm.contentsOfDirectory(atPath: dump.path)
        expect(!dumpEntries.contains(where: { $0.hasPrefix(".photocull-stage-") }), "failure cleans owned stage directory")
    }

    // Phase-3 archive failure occurs after every export is staged; permissions
    // are always restored, and unrelated destination markers are never removed.
    do {
        let (inbox, archive, dump, cfg) = try setup()
        try fm.createDirectory(at: dump, withIntermediateDirectories: true)
        for stem in ["A", "B"] {
            try makeJPEG(inbox.appendingPathComponent("\(stem).JPG"), color: (9, 8, 7))
        }
        let session = Session.fresh()
        for stem in ["A", "B"] { session.setCrop(stem, CropRect(x: 0.1, y: 0.1, w: 0.8, h: 0.8)) }
        try session.save(folder: inbox)
        let unrelated = Data([70, 71])
        try bytes(archive.appendingPathComponent("unrelated.tmp"), unrelated)
        let originalMode = try fm.attributesOfItem(atPath: archive.path)[.posixPermissions] as! NSNumber
        try fm.setAttributes([.posixPermissions: NSNumber(value: 0o500)], ofItemAtPath: archive.path)
        defer { try? fm.setAttributes([.posixPermissions: originalMode], ofItemAtPath: archive.path) }
        do {
            _ = try Finalize.run(cfg: cfg, date: inbox.lastPathComponent, dump: true,
                                 cropMode: .applyCrop, dumpOverride: dump)
            fatalError("expected archive move failure in read-only directory")
        } catch { expect(true, "archive failure is surfaced") }
        try fm.setAttributes([.posixPermissions: originalMode], ofItemAtPath: archive.path)
        try assertBytes(archive.appendingPathComponent("unrelated.tmp"), unrelated, "unrelated archive tmp preserved")
        expect(fm.fileExists(atPath: dump.appendingPathComponent("A.JPG").path), "already-promoted prefix remains")
        expect(fm.fileExists(atPath: inbox.appendingPathComponent("B.JPG").path), "later original not moved")
        let dumpEntries = try fm.contentsOfDirectory(atPath: dump.path)
        expect(!dumpEntries.contains(where: { $0.hasPrefix(".photocull-stage-") }), "later owned stage cleaned after archive failure")
    }

    print("FinalizePlanningChecks: \(finalizePlanningChecks) checks passed")
}

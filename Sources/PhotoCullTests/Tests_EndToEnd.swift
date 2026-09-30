import Foundation
import CoreGraphics
import ImageIO
import PhotoCullCore

/// Drives the exact workflow the SwiftUI app performs:
/// ingest a card -> cull -> crop -> finalize -> verify the archive, Trash and dump.
func suiteEndToEnd() throws {
    guard let fixture = fixtureURL("20240503-DSCF2771.jpeg") else {
        check(false, "fixture JPEG unavailable — set PC_FIXTURES or run from the repo")
        return
    }

    // ---- 1. Build a fake SD card -------------------------------------------
    let card = try makeTempDir("card")
    let dcim = card.appendingPathComponent("DCIM/100_FUJI")
    try FileManager.default.createDirectory(at: dcim, withIntermediateDirectories: true)

    let jpgA = dcim.appendingPathComponent("DSCF0001.JPG")
    let rawA = dcim.appendingPathComponent("DSCF0001.RAF")
    let jpgB = dcim.appendingPathComponent("DSCF0002.JPG")
    try FileManager.default.copyItem(at: fixture, to: jpgA)
    try FileManager.default.copyItem(at: fixture, to: jpgB)
    try touch(rawA, bytes: 4096)

    // The fake RAW has no EXIF, so pin its modification date to the JPG's capture
    // date to keep the pair in one date folder (real RAF/RW2 files carry EXIF).
    let captureDate = ExifReader.captureDate(url: jpgA)
    check(captureDate.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
          "card JPG reports a capture date (\(captureDate))")
    let noon = ISO8601DateFormatter().date(from: "\(captureDate)T12:00:00Z")!
    try FileManager.default.setAttributes([.modificationDate: noon], ofItemAtPath: rawA.path)
    try FileManager.default.setAttributes([.modificationDate: noon], ofItemAtPath: jpgB.path)

    checkEqual(Ingest.detectSDCards().contains(dcim), false,
               "detectSDCards only scans /Volumes, not an arbitrary temp card")

    // ---- 2. Ingest ---------------------------------------------------------
    let root = try makeTempDir("e2e")
    let inbox = root.appendingPathComponent("inbox")
    let archive = root.appendingPathComponent("archive")
    let dump = root.appendingPathComponent("dump")
    let cfg = PCConfig(
        paths: PathsConfig(inbox: inbox.path, archive: archive.path, dump: dump.path),
        files: FilesConfig(rawExtensions: ["RAF", "RW2"], jpgExtensions: ["JPG", "JPEG"]))

    var lastProgress = IngestProgress()
    let result = try Ingest.run(cfg: cfg, source: dcim) { p in lastProgress = p }
    checkEqual(result.copied, 3, "ingest copied all three files")
    checkEqual(result.folders, [captureDate], "ingest produced one date folder")
    check(lastProgress.done, "final progress callback reports done")

    let inboxFolder = inbox.appendingPathComponent(captureDate)
    let ingested = try FilePairs.pairs(folder: inboxFolder,
                                       jpgExts: cfg.jpgExtSet, rawExts: cfg.rawExtSet)
    checkEqual(ingested.count, 2, "two pairs in the inbox")
    checkEqual(ingested.first(where: { $0.stem == "DSCF0001" })?.hasRAW, true,
               "DSCF0001 kept its paired RAW")

    // Re-ingest must be a no-op (same size => skip).
    let second = try Ingest.run(cfg: cfg, source: dcim, onProgress: nil)
    checkEqual(second.copied, 0, "re-ingest copies nothing")
    checkEqual(second.skipped, 3, "re-ingest skips all three")

    // ---- 3. Library rollup -------------------------------------------------
    let rows = Library.loadSessions(cfg: cfg)
    checkEqual(rows.count, 1, "one session row")
    checkEqual(rows.first?.date, captureDate, "session row uses the capture date")
    checkEqual(rows.first?.total, 2, "session row counts pairs")
    checkEqual(rows.first?.status, .unstarted, "fresh session is unstarted")

    // ---- 4. Cull + crop (what the UI does) ---------------------------------
    let session = try Session.load(folder: inboxFolder)
    session.set("DSCF0001", .keep)
    session.setCrop("DSCF0001", CropRect(x: 0.25, y: 0.25, w: 0.5, h: 0.5))
    session.set("DSCF0002", .reject)
    session.lastIndex = 1
    try session.save(folder: inboxFolder)

    let reread = try Session.load(folder: inboxFolder)
    checkEqual(reread.get("DSCF0001"), .keep, "keep decision persisted")
    checkEqual(reread.get("DSCF0002"), .reject, "reject decision persisted")
    checkEqual(reread.lastIndex, 1, "last_index persisted")
    checkClose(reread.crop(for: "DSCF0001")?.w ?? 0, 0.5, 0.001, "crop persisted")

    let sidecar = try String(contentsOf: inboxFolder.appendingPathComponent(".photocull.json"),
                             encoding: .utf8)
    check(sidecar.contains("\"crops\""), "sidecar contains a crops key")
    check(sidecar.contains("\"last_index\""), "sidecar uses the Go key name last_index")

    let stats = try Finalize.summary(cfg: cfg, date: captureDate)
    checkEqual(stats.keep, 1, "summary keep count")
    checkEqual(stats.reject, 1, "summary reject count")
    checkEqual(stats.undecided, 0, "summary undecided count")
    checkEqual(stats.keepRAW, 1, "summary keep RAW count")

    // ---- 5. Finalize -------------------------------------------------------
    let fin = try Finalize.run(cfg: cfg, date: captureDate, dump: true,
                               cropMode: .applyCrop, dumpOverride: dump)
    checkEqual(fin.sessions, 1, "one session finalized")
    checkEqual(fin.archived, 2, "keeper JPG + its RAW archived")
    checkEqual(fin.trashed, 1, "rejected JPG trashed (DSCF0002 has no RAW)")
    checkEqual(fin.cropped, 1, "one cropped JPEG written")
    check(!FileManager.default.fileExists(atPath: inboxFolder.path),
          "inbox date folder removed after finalize")

    let archivedFiles = try FileManager.default.contentsOfDirectory(atPath:
        archive.appendingPathComponent(captureDate).path).sorted()
    checkEqual(archivedFiles, ["DSCF0001.JPG", "DSCF0001.RAF"],
               "archive holds exactly the keeper pair")

    let dumped = try FileManager.default.contentsOfDirectory(atPath: dump.path).sorted()
    checkEqual(dumped, ["DSCF0001.JPG"], "dump holds only the keeper JPG")
    checkEqual(Library.loadSessions(cfg: cfg).count, 0, "inbox is empty after finalize")

    // The dumped copy must actually be cropped.
    let dumpJPG = dump.appendingPathComponent("DSCF0001.JPG")
    let src = CGImageSourceCreateWithURL(dumpJPG as CFURL, nil)
    let props = src.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
    let dw = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
    let dh = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
    let orig = ImagePipeline.orientedPixelSize(url: fixture)
    checkEqual(dw, (orig?.width ?? 0) / 2, "dumped JPEG is half the original width")
    check(abs(dh - (orig?.height ?? 0) / 2) <= 1,
          "dumped JPEG is half the original height (±1 for rounding, got \(dh))")

    // ---- 6. Multi-session finalize ----------------------------------------
    let inbox2 = root.appendingPathComponent("inbox2")
    let archive2 = root.appendingPathComponent("archive2")
    let dump2 = root.appendingPathComponent("dump2")
    let cfg2 = PCConfig(
        paths: PathsConfig(inbox: inbox2.path, archive: archive2.path, dump: dump2.path),
        files: FilesConfig(rawExtensions: ["RAF"], jpgExtensions: ["JPG"]))

    for date in ["2025-03-07", "2025-03-10"] {
        let f = inbox2.appendingPathComponent(date)
        try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: f.appendingPathComponent("IMG_1.JPG"))
        let s = Session.fresh()
        s.set("IMG_1", .keep)
        try s.save(folder: f)
    }

    let multi = try Finalize.runMulti(cfg: cfg2, dates: ["2025-03-10", "2025-03-07"],
                                      dump: true, cropMode: .original)
    checkEqual(multi.sessions, 2, "multi finalize processed two sessions")
    checkEqual(URL(fileURLWithPath: multi.dumpFolder).lastPathComponent,
               "2025-03-07 to 2025-03-10", "date-range dump folder name")
    check(FileManager.default.fileExists(atPath:
        dump2.appendingPathComponent("2025-03-07 to 2025-03-10/IMG_1.JPG").path),
        "range dump folder holds the keeper JPG")
    checkEqual(Library.loadSessions(cfg: cfg2).count, 0, "both inboxes emptied")
}

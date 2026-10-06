import Foundation
import PhotoCullCore
import ImageIO

// Perf wave 3 tests: parallel finalize exports (B1), concurrent ingest copies
// (B2), and the temp-file hygiene that comes with them. Exercise the new
// multi-worker paths and pin the fail-fast prefix contract.

/// All "*.tmp" paths anywhere under `dir` (recursive).
private func tmpFiles(in dir: URL) -> [String] {
    guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else {
        return []
    }
    return en.compactMap { ($0 as? URL)?.path }.filter { $0.hasSuffix(".tmp") }
}

func suiteFinalizeParallel() throws {
    let fm = FileManager.default
    guard let fx = fixtureURL("20240503-DSCF2771.jpeg") else {
        print("  (skip: fixture JPEG not present for parallel finalize tests)")
        return
    }
    let tmp = try makeTempDir("finalize-par")
    let cfg = PCConfig(
        paths: PathsConfig(inbox: tmp.appendingPathComponent("inbox").path,
                           archive: tmp.appendingPathComponent("archive").path,
                           dump: tmp.appendingPathComponent("dump").path),
        files: FilesConfig(rawExtensions: ["RAF", "RW2"], jpgExtensions: ["JPG", "JPEG"]))

    func writeSidecar(_ folder: URL, _ json: String) throws {
        try json.write(to: folder.appendingPathComponent(".photocull.json"),
                       atomically: true, encoding: .utf8)
    }

    // ── Multiple cropped keepers: all dumps land, edits correct, archive
    //    completes, names deterministic, no *.tmp leftovers ────────────────
    let date = "2024-08-01"
    let folder = tmp.appendingPathComponent("inbox").appendingPathComponent(date)
    for stem in ["Q0001", "Q0002", "Q0003", "Q0004", "Q0005", "R0001"] {
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.copyItem(at: fx, to: folder.appendingPathComponent("\(stem).JPG"))
    }
    // Four cropped/tilted/turned jobs run through the parallel phase-2 group;
    // Q0005 keeps no edits (serial clone path); R0001 is trashed in phase 1.
    try writeSidecar(folder,
                     #"{"version":1,"decisions":{"Q0001":"keep","Q0002":"keep","Q0003":"keep","Q0004":"keep","Q0005":"keep","R0001":"reject"},"crops":{"Q0001":{"x":0,"y":0,"w":0.5,"h":0.5},"Q0002":{"x":0.25,"y":0.25,"w":0.5,"h":0.5}},"tilts":{"Q0003":4},"rotations":{"Q0004":1},"last_index":6}"#)

    let dump = tmp.appendingPathComponent("dump").appendingPathComponent(date)
    let arch = tmp.appendingPathComponent("archive").appendingPathComponent(date)
    let res = try Finalize.run(cfg: cfg, date: date, dump: true,
                               cropMode: .applyCrop, dumpOverride: nil)
    checkEqual(res.dumped, 5, "parallel run dumps all five keepers")
    checkEqual(res.cropped, 4, "parallel run counts four edited exports")
    checkEqual(res.archived, 5, "parallel run archives all five keepers")
    checkEqual(res.trashed, 1, "reject trashed before the parallel phase")

    let dumpNames = try Set(fm.contentsOfDirectory(atPath: dump.path))
    checkEqual(dumpNames, Set(["Q0001.JPG", "Q0002.JPG", "Q0003.JPG", "Q0004.JPG", "Q0005.JPG"]),
               "dump holds exactly the keeper names, no collision suffixes")
    for stem in ["Q0001", "Q0002", "Q0003", "Q0004", "Q0005"] {
        check(fm.fileExists(atPath: arch.appendingPathComponent("\(stem).JPG").path),
              "archived \(stem).JPG")
    }
    check(!fm.fileExists(atPath: arch.appendingPathComponent("R0001.JPG").path),
          "reject not archived")
    check(!fm.fileExists(atPath: folder.path), "inbox date folder removed after parallel run")

    func pixelSize(_ url: URL) -> (w: Int, h: Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int,
              let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }
    let fxSize = ImagePipeline.orientedPixelSize(url: fx)

    if let cropOut = pixelSize(dump.appendingPathComponent("Q0001.JPG")), let fxSize {
        check(abs(cropOut.w - fxSize.width / 2) <= 2,
              "cropped dump is half the width (\(cropOut.w) vs \(fxSize.width / 2))")
    } else {
        check(false, "cropped dump decodes")
    }
    if let tiltOut = pixelSize(dump.appendingPathComponent("Q0003.JPG")), let fxSize {
        check(tiltOut.w == fxSize.width && tiltOut.h == fxSize.height,
              "tilt-only dump keeps the oriented canvas size")
    } else {
        check(false, "tilt-only dump decodes")
    }
    if let turnOut = pixelSize(dump.appendingPathComponent("Q0004.JPG")), let fxSize {
        check(turnOut.w == fxSize.height && turnOut.h == fxSize.width,
              "quarter-turn dump swaps width and height")
    } else {
        check(false, "quarter-turn dump decodes")
    }
    if let plainBytes = try? Data(contentsOf: dump.appendingPathComponent("Q0005.JPG")).count {
        checkEqual(plainBytes, try Data(contentsOf: fx).count,
                   "unedited keeper dump is a byte copy")
    } else {
        check(false, "unedited keeper dump exists")
    }
    check(tmpFiles(in: dump).isEmpty && tmpFiles(in: arch).isEmpty,
          "no .tmp files remain after a successful parallel run")

    // ── Middle export fails: prefix contract ─────────────────────────────
    // Pairs before the failure are fully dumped + archived; the failing pair
    // and every later pair — keepers AND rejects — stay untouched in the
    // inbox with no dump files; the first error is thrown.
    let date2 = "2024-08-02"
    let folder2 = tmp.appendingPathComponent("inbox").appendingPathComponent(date2)
    try fm.createDirectory(at: folder2, withIntermediateDirectories: true)
    try fm.copyItem(at: fx, to: folder2.appendingPathComponent("S0001.JPG"))
    try Data(repeating: 0x41, count: 500).write(to: folder2.appendingPathComponent("S0002.JPG"))  // undecodable
    try fm.copyItem(at: fx, to: folder2.appendingPathComponent("S0003.JPG"))
    try fm.copyItem(at: fx, to: folder2.appendingPathComponent("S0004.JPG"))
    try writeSidecar(folder2,
                     #"{"version":1,"decisions":{"S0001":"keep","S0002":"keep","S0003":"keep","S0004":"reject"},"crops":{"S0001":{"x":0,"y":0,"w":0.5,"h":0.5},"S0002":{"x":0,"y":0,"w":0.5,"h":0.5},"S0003":{"x":0,"y":0,"w":0.25,"h":0.25}},"last_index":4}"#)

    let arch2 = tmp.appendingPathComponent("archive").appendingPathComponent(date2)
    let dump2 = tmp.appendingPathComponent("dump").appendingPathComponent(date2)
    var threw = false
    do {
        _ = try Finalize.run(cfg: cfg, date: date2, dump: true,
                             cropMode: .applyCrop, dumpOverride: nil)
    } catch {
        threw = true
    }
    check(threw, "failing middle export throws")
    check(fm.fileExists(atPath: arch2.appendingPathComponent("S0001.JPG").path),
          "pair before the failure is archived")
    check(fm.fileExists(atPath: dump2.appendingPathComponent("S0001.JPG").path),
          "pair before the failure is dumped")
    checkEqual(try Set(fm.contentsOfDirectory(atPath: dump2.path)), Set(["S0001.JPG"]),
               "dump after failure holds only the processed prefix")
    for stem in ["S0002", "S0003", "S0004"] {
        check(fm.fileExists(atPath: folder2.appendingPathComponent("\(stem).JPG").path),
              "\(stem) stays in the inbox")
        check(!fm.fileExists(atPath: arch2.appendingPathComponent("\(stem).JPG").path),
              "\(stem) is not archived")
        check(!fm.fileExists(atPath: dump2.appendingPathComponent("\(stem).JPG").path),
              "\(stem) has no dump file")
    }
    check(fm.fileExists(atPath: folder2.path) &&
          fm.fileExists(atPath: folder2.appendingPathComponent(".photocull.json").path),
          "inbox folder and sidecar survive the failure")
    check(tmpFiles(in: dump2).isEmpty && tmpFiles(in: folder2).isEmpty,
          "no .tmp files remain after a failed run")

    // ── Re-run after fixing the bad file: clean names, no _2 duplicates ──
    try fm.removeItem(at: folder2.appendingPathComponent("S0002.JPG"))
    try fm.copyItem(at: fx, to: folder2.appendingPathComponent("S0002.JPG"))
    let res2 = try Finalize.run(cfg: cfg, date: date2, dump: true,
                                cropMode: .applyCrop, dumpOverride: nil)
    checkEqual(res2.dumped, 2, "re-run dumps the two remaining keepers")
    checkEqual(res2.archived, 2, "re-run archives the two remaining keepers")
    checkEqual(res2.trashed, 1, "re-run trashes the reject that stayed in the inbox")
    checkEqual(try Set(fm.contentsOfDirectory(atPath: dump2.path)),
               Set(["S0001.JPG", "S0002.JPG", "S0003.JPG"]),
               "re-run dump holds exactly the clean names, no _2 suffixes")
    check(!fm.fileExists(atPath: folder2.path), "re-run removes the inbox folder")
    check(tmpFiles(in: dump2).isEmpty, "no .tmp files after the successful re-run")
}

func suiteIngestConcurrent() throws {
    let fm = FileManager.default
    let tmp = try makeTempDir("ingest-par")
    defer { try? fm.removeItem(at: tmp) }

    // Fake card: two subfolders, seven matching files so the width-4 copy
    // workers actually overlap. Includes a sameFile skip target and a
    // same-filename collision across folders.
    let card = tmp.appendingPathComponent("card/DCIM")
    let aDir = card.appendingPathComponent("100A")
    let bDir = card.appendingPathComponent("101B")

    func localDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12  // noon local → no TZ day-shift
        return Calendar.current.date(from: c)!
    }
    func mkfile(_ name: String, bytes: Int, in dir: URL, mod: Date) throws {
        let u = dir.appendingPathComponent(name)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: u)
        try fm.setAttributes([.modificationDate: mod], ofItemAtPath: u.path)
    }

    let day = localDate(2024, 9, 12)
    try mkfile("N0001.JPG", bytes: 100, in: aDir, mod: day)
    try mkfile("N0002.JPG", bytes: 120, in: aDir, mod: day)
    try mkfile("N0003.JPG", bytes: 140, in: aDir, mod: day)
    try mkfile("N0001.RAF", bytes: 300, in: aDir, mod: day)
    try mkfile("N0001.JPG", bytes: 555, in: bDir, mod: day)  // filename collision with 100A
    try mkfile("N0004.JPG", bytes: 160, in: bDir, mod: day)
    try mkfile("N0002.RAF", bytes: 310, in: bDir, mod: day)

    let cfg = PCConfig(
        paths: PathsConfig(inbox: tmp.appendingPathComponent("inbox").path,
                           archive: tmp.appendingPathComponent("archive").path,
                           dump: tmp.appendingPathComponent("dump").path),
        files: FilesConfig(rawExtensions: ["RAF", "RW2"], jpgExtensions: ["JPG", "JPEG"]))

    // Pre-existing identical copy of N0002.JPG → sameFile skip in phase 1.
    let inboxDate = tmp.appendingPathComponent("inbox").appendingPathComponent("2024-09-12")
    try mkfile("N0002.JPG", bytes: 120, in: inboxDate, mod: day)

    let box = LockedBox<[IngestProgress]>([])
    let res = try Ingest.run(cfg: cfg, source: card) { progress in
        box.update { $0.append(progress) }
    }
    let events = box.snapshot()

    checkEqual(res.copied, 6, "concurrent run copies 6 files")
    checkEqual(res.skipped, 1, "concurrent run skips the size-identical duplicate")
    checkEqual(res.folders, ["2024-09-12"], "folders from mod dates, sorted")

    // Names and byte counts must match the serial safeDestName semantics
    // exactly: the 100A N0001.JPG wins the plain name, the 101B one gets _2,
    // and the RAWs keep their unsuffixed pair names.
    func size(_ name: String) -> Int? {
        guard let d = try? Data(contentsOf: inboxDate.appendingPathComponent(name)) else {
            return nil
        }
        return d.count
    }
    checkEqual(size("N0001.JPG"), 100, "N0001.JPG holds the 100A copy")
    checkEqual(size("N0001_2.JPG"), 555, "colliding N0001.JPG gets _2 with its own bytes")
    checkEqual(size("N0002.JPG"), 120, "pre-existing N0002.JPG untouched")
    checkEqual(size("N0003.JPG"), 140, "N0003.JPG copied")
    checkEqual(size("N0004.JPG"), 160, "N0004.JPG copied")
    checkEqual(size("N0001.RAF"), 300, "N0001.RAF keeps its pair name")
    checkEqual(size("N0002.RAF"), 310, "N0002.RAF keeps its pair name")
    checkEqual(try Set(fm.contentsOfDirectory(atPath: inboxDate.path)).count, 7,
               "inbox holds exactly the seven expected files")

    // Progress: total up front, per-copy updates reach the final counts.
    check(events.first?.total == 7 && events.first?.running == true,
          "progress reports total 7 up front")
    check(events.last?.copied == 6 && events.last?.skipped == 1,
          "final progress has copied=6, skipped=1")
    check(events.last?.done == true && events.last?.running == false,
          "progress ends with done=true")
    check(events.last?.error == nil, "no error on success")
    check(!(events.last?.current.isEmpty ?? true), "current holds the last completed copy")

    // Second run: everything is now size-identical → all skipped.
    let res2 = try Ingest.run(cfg: cfg, source: card, onProgress: nil)
    checkEqual(res2.copied, 0, "re-run copies nothing")
    checkEqual(res2.skipped, 7, "re-run skips all seven files")

    check(tmpFiles(in: inboxDate).isEmpty, "no .tmp files in the inbox after ingest")
}

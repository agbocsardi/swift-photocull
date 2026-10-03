import Foundation
import PhotoCullCore

func suiteIngest() throws {
    let fm = FileManager.default
    let tmp = try makeTempDir("ingest")

    // Fake card: DCIM/100FUJI + DCIM/101RAW with known mod dates.
    let card = tmp.appendingPathComponent("card/DCIM")
    let jpgDir = card.appendingPathComponent("100FUJI")
    let rawDir = card.appendingPathComponent("101RAW")

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

    let may3 = localDate(2024, 5, 3)
    try mkfile("DSCF1001.JPG", bytes: 100, in: jpgDir, mod: may3)
    try mkfile("DSCF1002.JPG", bytes: 120, in: jpgDir, mod: may3)
    try mkfile("DSCF1001.RAF", bytes: 300, in: rawDir, mod: may3)
    try mkfile("NOTES.TXT", bytes: 10, in: jpgDir, mod: may3)  // wrong extension

    let cfg = PCConfig(
        paths: PathsConfig(inbox: tmp.appendingPathComponent("inbox").path,
                           archive: tmp.appendingPathComponent("archive").path,
                           dump: tmp.appendingPathComponent("dump").path),
        files: FilesConfig(rawExtensions: ["RAF", "RW2"], jpgExtensions: ["JPG", "JPEG"]))

    // ── First ingest: 3 copies into a date folder ────────────────────────
    let box = LockedBox<[IngestProgress]>([])
    let res = try Ingest.run(cfg: cfg, source: card) { progress in
        box.update { $0.append(progress) }
    }
    let events = box.snapshot()
    checkEqual(res.copied, 3, "first run copies 3 matching files")
    checkEqual(res.skipped, 0, "first run skips nothing")
    checkEqual(res.folders, ["2024-05-03"], "folders = mod-date folders, sorted")

    let inboxDate = tmp.appendingPathComponent("inbox/2024-05-03")
    for n in ["DSCF1001.JPG", "DSCF1002.JPG"] {
        check(fm.fileExists(atPath: inboxDate.appendingPathComponent(n).path),
              "\(n) landed in inbox/2024-05-03")
    }
    // Deliberate divergence from the Go app: collisions key on the FULL uppercased
    // filename, so a JPG and its RAW keep matching names and stay paired.
    check(fm.fileExists(atPath: inboxDate.appendingPathComponent("DSCF1001.RAF").path),
          "same-stem RAW keeps its name so the JPG+RAW pair survives")
    check(!fm.fileExists(atPath: inboxDate.appendingPathComponent("DSCF1001_2.RAF").path),
          "same-stem RAW is not renamed to _2")
    var collide: [String: Int] = ["DSCF1001.JPG": 1]
    let renamed = Ingest.safeDestName(URL(fileURLWithPath: "/cam2/DSCF1001.JPG"), seen: &collide)
    checkEqual(renamed, "DSCF1001_2.JPG",
               "a genuine same-filename collision from another folder still gets _2")
    check(!fm.fileExists(atPath: inboxDate.appendingPathComponent("NOTES.TXT").path),
          "non-matching extension is not ingested")

    // Copy preserves the modification date.
    if let attrs = try? fm.attributesOfItem(atPath: inboxDate.appendingPathComponent("DSCF1001.JPG").path),
       let mod = attrs[.modificationDate] as? Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        checkEqual(f.string(from: mod), "2024-05-03", "copy preserves modification date")
    } else {
        check(false, "copied file has a modification date")
    }

    // ── Second ingest: all duplicates skipped (name + size match) ────────
    let res2 = try Ingest.run(cfg: cfg, source: card, onProgress: nil)
    checkEqual(res2.copied, 0, "second run copies nothing")
    checkEqual(res2.skipped, 3, "second run skips 3 duplicates")

    // ── Progress callbacks: total once, per-file updates, done flag ─────
    check(events.first?.total == 3, "progress reports total 3 up front")
    check(events.first?.running == true, "progress is running after start")
    check(events.count >= 5, "progress reported per file plus start/end (got \(events.count))")
    check(events.last?.copied == 3, "progress copied count reaches 3")
    check(events.last?.done == true && events.last?.running == false,
          "progress ends with done=true, running=false")
    check(events.last?.error == nil, "progress has no error on success")

    // ── Same filename in another subdirectory → next counter ────────────
    let dupDir = card.appendingPathComponent("200DUP")
    try mkfile("DSCF1001.JPG", bytes: 555, in: dupDir, mod: may3)
    let res3 = try Ingest.run(cfg: cfg, source: card, onProgress: nil)
    checkEqual(res3.copied, 1, "same-filename file copied once")
    checkEqual(res3.skipped, 3, "existing files still skipped on later runs")
    check(fm.fileExists(atPath: inboxDate.appendingPathComponent("DSCF1001_2.JPG").path),
          "second DSCF1001.JPG gets the _2 suffix")
    check(fm.fileExists(atPath: inboxDate.appendingPathComponent("DSCF1001.RAF").path),
          "the RAW still keeps its unsuffixed name alongside both JPGs")

    // ── detectSDCards: DCIM paths, sorted case-insensitively ────────────
    let cards = Ingest.detectSDCards()
    check(cards.allSatisfy { $0.lastPathComponent == "DCIM" },
          "detected cards are .../DCIM paths")
    check(zip(cards, cards.dropFirst()).allSatisfy {
        $0.path.localizedCaseInsensitiveCompare($1.path) != .orderedDescending
    }, "detected cards are sorted case-insensitively")

    // ── Auto-detect with no card mounted → noSourceFound ─────────────────
    if cards.isEmpty {
        var threw = false
        do {
            _ = try Ingest.run(cfg: cfg, source: nil, onProgress: nil)
        } catch {
            threw = true
            check(String(describing: error).contains("noSourceFound"),
                  "auto-detect throws noSourceFound (got \(error))")
        }
        check(threw, "run(source: nil) throws when no card is mounted")
    }

    // ── Missing source directory → scanFailed ────────────────────────────
    var scanThrew = false
    do {
        _ = try Ingest.run(cfg: cfg, source: tmp.appendingPathComponent("nope"), onProgress: nil)
    } catch {
        scanThrew = true
        check(String(describing: error).contains("scanFailed"),
              "missing source throws scanFailed (got \(error))")
    }
    check(scanThrew, "run throws for a missing source directory")
}

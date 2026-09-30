import Foundation
import PhotoCullCore
import ImageIO

func suiteFinalize() throws {
    let fm = FileManager.default
    let tmp = try makeTempDir("finalize")
    let cfg = PCConfig(
        paths: PathsConfig(inbox: tmp.appendingPathComponent("inbox").path,
                           archive: tmp.appendingPathComponent("archive").path,
                           dump: tmp.appendingPathComponent("dump").path),
        files: FilesConfig(rawExtensions: ["RAF", "RW2"], jpgExtensions: ["JPG", "JPEG"]))

    func exists(_ u: URL) -> Bool { fm.fileExists(atPath: u.path) }
    func writeSidecar(_ folder: URL, _ json: String) throws {
        try json.write(to: folder.appendingPathComponent(".photocull.json"),
                       atomically: true, encoding: .utf8)
    }

    // ── Session 2024-05-03: keep A, reject B, undecided C, orphan RAW ───
    let date = "2024-05-03"
    let folder = tmp.appendingPathComponent("inbox").appendingPathComponent(date)
    let ajpg = folder.appendingPathComponent("A0001.JPG")
    let araf = folder.appendingPathComponent("A0001.RAF")
    let bjpg = folder.appendingPathComponent("B0001.JPG")
    let cjpg = folder.appendingPathComponent("C0001.JPG")
    let craf = folder.appendingPathComponent("C0001.RAF")
    let orphan = folder.appendingPathComponent("D0002.RAF")
    try touch(ajpg, bytes: 100)
    try touch(araf, bytes: 200)
    try touch(bjpg, bytes: 300)
    try touch(cjpg, bytes: 400)
    try touch(craf, bytes: 500)
    try touch(orphan, bytes: 600)
    try writeSidecar(folder,
                     #"{"version":1,"decisions":{"A0001":"keep","B0001":"reject"},"last_index":2}"#)

    // summary counts by decision over pairs
    let stats = try Finalize.summary(cfg: cfg, date: date)
    checkEqual(stats.date, date, "summary date")
    checkEqual(stats.keep, 1, "summary keep count")
    checkEqual(stats.reject, 1, "summary reject count")
    checkEqual(stats.undecided, 1, "summary undecided count")
    checkEqual(stats.keepRAW, 1, "summary keepRAW count")
    checkEqual(stats.rejectRAW, 0, "summary rejectRAW count (reject has no RAW)")
    checkEqual(stats.total, 3, "summary total")

    // ── run: dump original via override ──────────────────────────────────
    let dumpOverride = tmp.appendingPathComponent("mydump")
    let res = try Finalize.run(cfg: cfg, date: date, dump: true,
                               cropMode: .original, dumpOverride: dumpOverride)
    checkEqual(res.sessions, 1, "run sessions count")
    checkEqual(res.archived, 5, "run archives 5 files (2+2 pair files + orphan)")
    checkEqual(res.trashed, 1, "run trashes 1 file (reject JPG only)")
    checkEqual(res.dumped, 2, "run dumps keep+undecided JPGs (2)")
    checkEqual(res.cropped, 0, "no crops in .original mode")
    checkEqual(res.dumpFolder, dumpOverride.path, "result reports the dump folder")

    let arch = tmp.appendingPathComponent("archive").appendingPathComponent(date)
    for n in ["A0001.JPG", "A0001.RAF", "C0001.JPG", "C0001.RAF", "D0002.RAF"] {
        check(exists(arch.appendingPathComponent(n)), "archived \(n)")
    }
    check(!exists(arch.appendingPathComponent("B0001.JPG")), "rejected JPG is not archived")
    for n in ["A0001.JPG", "C0001.JPG"] {
        check(exists(dumpOverride.appendingPathComponent(n)), "dumped \(n)")
    }
    check(!exists(dumpOverride.appendingPathComponent("B0001.JPG")),
          "rejected JPG is not dumped")
    checkEqual((try Data(contentsOf: dumpOverride.appendingPathComponent("A0001.JPG"))).count, 100,
               ".original dump is a byte copy")
    // Inbox date folder (and its sidecar) removed; rejects left the inbox (trashed).
    check(!exists(folder), "inbox date folder removed")
    check(!exists(folder.appendingPathComponent(".photocull.json")), "sidecar removed with folder")

    // ── run without dump: no dump folder created; archive collision → _2 ─
    let date2 = "2024-06-01"
    let folder2 = tmp.appendingPathComponent("inbox").appendingPathComponent(date2)
    try touch(folder2.appendingPathComponent("E0001.JPG"), bytes: 700)
    try touch(folder2.appendingPathComponent("E0001.RAF"), bytes: 800)
    try writeSidecar(folder2, #"{"version":1,"decisions":{"E0001":"keep"},"last_index":1}"#)
    // Pre-existing archive file forces a _2 suffix on the archived JPG.
    try touch(tmp.appendingPathComponent("archive").appendingPathComponent(date2)
        .appendingPathComponent("E0001.JPG"), bytes: 999)

    let arch2 = tmp.appendingPathComponent("archive").appendingPathComponent(date2)
    let res2 = try Finalize.run(cfg: cfg, date: date2, dump: false,
                                cropMode: .original, dumpOverride: nil)
    checkEqual(res2.archived, 2, "second session archives jpg+raw")
    checkEqual(res2.dumped, 0, "nothing dumped when dump=false")
    check(!exists(tmp.appendingPathComponent("dump")), "dump root not created when dump=false")
    check(exists(arch2.appendingPathComponent("E0001_2.JPG")),
          "archive name collision gets _2 suffix")
    check(exists(arch2.appendingPathComponent("E0001.RAF")), "RAW archived next to collided JPG")
    checkEqual((try? Data(contentsOf: arch2.appendingPathComponent("E0001_2.JPG")))?.count, 700,
               "collided archive copy holds the new file's bytes")
    check(!exists(folder2), "second inbox date folder removed")

    // ── runMulti: two dates → one dump folder "first to last" ────────────
    let dA = "2025-03-07"
    let dB = "2025-03-10"
    for (d, n) in [(dA, "F0001.JPG"), (dB, "G0001.JPG")] {
        let f = tmp.appendingPathComponent("inbox").appendingPathComponent(d)
        try touch(f.appendingPathComponent(n), bytes: 111)
    }
    let resM = try Finalize.runMulti(cfg: cfg, dates: [dB, dA], dump: true, cropMode: .original)
    checkEqual(resM.sessions, 2, "runMulti session count")
    checkEqual(resM.archived, 2, "runMulti archived count")
    checkEqual(resM.dumped, 2, "runMulti dumped count")
    let multiDump = tmp.appendingPathComponent("dump").appendingPathComponent("2025-03-07 to 2025-03-10")
    check(exists(multiDump), "multi dump folder named '<first> to <last>'")
    checkEqual(resM.dumpFolder, multiDump.path, "runMulti reports shared dump folder")
    check(exists(multiDump.appendingPathComponent("F0001.JPG")), "first date dumped into shared folder")
    check(exists(multiDump.appendingPathComponent("G0001.JPG")), "second date dumped into shared folder")
    check(!exists(tmp.appendingPathComponent("inbox").appendingPathComponent(dA)),
          "runMulti removes first inbox folder")
    check(!exists(tmp.appendingPathComponent("inbox").appendingPathComponent(dB)),
          "runMulti removes second inbox folder")

    // ── applyCrop: re-encoded dump from a non-full-frame crop ───────────
    if let fx = fixtureURL("20240503-DSCF2771.jpeg") {
        let date3 = "2024-07-04"
        let folder3 = tmp.appendingPathComponent("inbox").appendingPathComponent(date3)
        try fm.createDirectory(at: folder3, withIntermediateDirectories: true)
        try fm.copyItem(at: fx, to: folder3.appendingPathComponent("H0001.JPG"))
        try writeSidecar(folder3,
                         #"{"version":1,"decisions":{"H0001":"keep"},"crops":{"H0001":{"x":0,"y":0,"w":0.5,"h":0.5}},"last_index":1}"#)
        let dump3 = tmp.appendingPathComponent("cropdump")
        let res3 = try Finalize.run(cfg: cfg, date: date3, dump: true,
                                    cropMode: .applyCrop, dumpOverride: dump3)
        checkEqual(res3.dumped, 1, "applyCrop dumps one JPG")
        checkEqual(res3.cropped, 1, "applyCrop counts the re-encoded crop")
        checkEqual(res3.archived, 1, "applyCrop still archives the original")

        let out = dump3.appendingPathComponent("H0001.JPG")
        check(exists(out), "cropped dump written")
        if let src = CGImageSourceCreateWithURL(fx as CFURL, nil),
           let outSrc = CGImageSourceCreateWithURL(out as CFURL, nil),
           let sp = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let op = CGImageSourceCopyPropertiesAtIndex(outSrc, 0, nil) as? [CFString: Any] {
            let sw = sp[kCGImagePropertyPixelWidth] as? Int ?? 0
            let ow = op[kCGImagePropertyPixelWidth] as? Int ?? 0
            check(ow > 0 && ow < sw, "cropped output narrower than source (\(ow) < \(sw))")
            check(abs(ow - sw / 2) <= 2, "crop keeps about half the width (\(ow) vs \(sw / 2))")
        } else {
            check(false, "cropped output is a readable image")
        }
        check(!exists(tmp.appendingPathComponent("inbox").appendingPathComponent(date3)),
              "crop session inbox folder removed")
    } else {
        print("  (skip: fixture JPEG not present for applyCrop test)")
    }
}

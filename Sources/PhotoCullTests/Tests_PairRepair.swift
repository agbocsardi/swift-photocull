import Foundation
import PhotoCullCore

func suitePairRepair() throws {
    let tmp = try makeTempDir("repair")
    let inbox = tmp.appendingPathComponent("inbox")
    let archive = tmp.appendingPathComponent("archive")
    let fm = FileManager.default

    // A date folder damaged by the Go app's stem-keyed collision rule.
    let d1 = inbox.appendingPathComponent("2026-08-18")
    try fm.createDirectory(at: d1, withIntermediateDirectories: true)
    try touch(d1.appendingPathComponent("DSCF0677.JPG"), bytes: 100)
    try touch(d1.appendingPathComponent("DSCF0677_2.RAF"), bytes: 200)   // should be repaired
    try touch(d1.appendingPathComponent("DSCF0678.JPG"), bytes: 100)
    try touch(d1.appendingPathComponent("DSCF0678.RAF"), bytes: 200)     // already fine
    try touch(d1.appendingPathComponent("ORPHAN_2.RAF"), bytes: 200)     // no JPG -> untouched
    try touch(d1.appendingPathComponent("DSCF0679.JPG"), bytes: 100)
    try touch(d1.appendingPathComponent("DSCF0679.RAF"), bytes: 200)
    try touch(d1.appendingPathComponent("DSCF0679_2.RAF"), bytes: 300)   // target taken -> ambiguous
    // A suffixed RAW whose own suffixed JPG exists is a genuine pair, not damage.
    try touch(d1.appendingPathComponent("DSCF0680_2.JPG"), bytes: 100)
    try touch(d1.appendingPathComponent("DSCF0680_2.RAF"), bytes: 200)

    // Archive folder with the same damage.
    let d2 = archive.appendingPathComponent("2026-05-16")
    try fm.createDirectory(at: d2, withIntermediateDirectories: true)
    try touch(d2.appendingPathComponent("P1200321.JPG"), bytes: 100)
    try touch(d2.appendingPathComponent("P1200321_2.RW2"), bytes: 200)

    let cfg = PCConfig(
        paths: PathsConfig(inbox: inbox.path, archive: archive.path, dump: tmp.appendingPathComponent("dump").path),
        files: FilesConfig(rawExtensions: ["RAF", "RW2"], jpgExtensions: ["JPG", "JPEG"]))

    // ---- plan (must not touch the filesystem) ------------------------------
    let plan = PairRepair.plan(cfg: cfg)
    checkEqual(plan.renamed, 2, "two RAW files are repairable")
    checkEqual(plan.unpaired, 1, "one orphan RAW reported")
    checkEqual(plan.ambiguous, 1, "one ambiguous RAW reported")
    check(plan.actions.contains { $0.from.lastPathComponent == "DSCF0680_2.RAF" && $0.kind == .alreadyPaired },
          "a suffixed RAW with its own suffixed JPG is treated as paired")
    check(fm.fileExists(atPath: d1.appendingPathComponent("DSCF0677_2.RAF").path),
          "plan does not rename anything")
    check(!plan.applied, "plan is not marked applied")

    // ---- apply -------------------------------------------------------------
    let applied = try PairRepair.apply(cfg: cfg)
    checkEqual(applied.renamed, 2, "apply renamed both candidates")
    check(applied.applied, "result marked applied")
    check(fm.fileExists(atPath: d1.appendingPathComponent("DSCF0677.RAF").path),
          "DSCF0677_2.RAF became DSCF0677.RAF")
    check(!fm.fileExists(atPath: d1.appendingPathComponent("DSCF0677_2.RAF").path),
          "old suffixed name is gone")
    check(fm.fileExists(atPath: d2.appendingPathComponent("P1200321.RW2").path),
          "archive RAW repaired too")
    check(fm.fileExists(atPath: d1.appendingPathComponent("ORPHAN_2.RAF").path),
          "orphan RAW left untouched")
    check(fm.fileExists(atPath: d1.appendingPathComponent("DSCF0679_2.RAF").path),
          "ambiguous RAW left untouched")

    // ---- pairs now match ---------------------------------------------------
    let pairs = try FilePairs.pairs(folder: d1, jpgExts: cfg.jpgExtSet, rawExts: cfg.rawExtSet)
    let repaired = pairs.first { $0.stem == "DSCF0677" }
    checkEqual(repaired?.hasRAW, true, "repaired JPG now has its RAW back")
    checkEqual(pairs.first { $0.stem == "DSCF0678" }?.hasRAW, true, "undamaged pair still intact")

    // ---- idempotent --------------------------------------------------------
    let again = try PairRepair.apply(cfg: cfg)
    checkEqual(again.renamed, 0, "second run is a no-op")

    // ---- suffix parsing ----------------------------------------------------
    checkEqual(PairRepair.splitSuffix("DSCF0001_2")?.base, "DSCF0001", "suffix base parsed")
    checkEqual(PairRepair.splitSuffix("DSCF0001_2")?.index, 2, "suffix index parsed")
    check(PairRepair.splitSuffix("DSCF0001") == nil, "no suffix -> nil")
    check(PairRepair.splitSuffix("DSCF_0001") == nil, "non-numeric suffix -> nil")
    check(PairRepair.splitSuffix("DSCF0001_1") == nil, "_1 is not a collision suffix")
}

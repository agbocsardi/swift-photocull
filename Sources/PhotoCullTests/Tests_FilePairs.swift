import Foundation
import PhotoCullCore

func suiteFilePairs() throws {
    let dir = try makeTempDir("filepairs")
    let jpgExts: Set<String> = ["JPG", "JPEG"]
    let rawExts: Set<String> = ["RAF", "RW2"]

    // Mixed-case pair + jpg-only + orphan RAW + noise + dotfile + subdirectory
    try touch(dir.appendingPathComponent("DSCF1234.JPG"))
    try touch(dir.appendingPathComponent("dscf1234.RaF"))
    try touch(dir.appendingPathComponent("P100.JPG"), bytes: 40)
    try touch(dir.appendingPathComponent("orphan.RW2"), bytes: 99)
    try touch(dir.appendingPathComponent("ignored.txt"))
    try touch(dir.appendingPathComponent("noprefix.jpeg"))
    try touch(dir.appendingPathComponent(".hidden.jpg"))
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("subdir.JPG"),
                                            withIntermediateDirectories: true)

    let result = try FilePairs.scan(folder: dir, jpgExts: jpgExts, rawExts: rawExts)

    // Sorted stems, plain lexicographic
    checkEqual(FilePairs.stems(result.pairs), ["DSCF1234", "NOPREFIX", "P100"], "pairs sorted by uppercased stem")
    checkEqual(result.pairs.count, 3, "pair count")
    checkEqual(result.orphanRAWs.count, 1, "one orphan RAW")

    // Mixed-case extension matching, uppercased stem
    let pair0 = result.pairs[0]
    checkEqual(pair0.stem, "DSCF1234", "stem uppercased")
    checkEqual(pair0.jpg.lastPathComponent, "DSCF1234.JPG", "jpg path")
    checkEqual(pair0.raw?.lastPathComponent, "dscf1234.RaF", "raw path case-insensitive ext")
    check(pair0.hasRAW, "pair has RAW")
    checkEqual(pair0.rawExt, "RAF", "rawExt uppercased without dot")

    // JPG-only pair
    let pair1 = result.pairs[1]
    checkEqual(pair1.stem, "NOPREFIX", "jpg-only stem")
    check(!pair1.hasRAW, "jpg-only pair has no RAW")
    check(pair1.rawExt == nil, "rawExt nil without RAW")

    // Orphan RAW
    checkEqual(result.orphanRAWs[0].lastPathComponent, "orphan.RW2", "orphan RAW path")
    check(!result.pairs.contains { $0.stem == "ORPHAN" }, "orphan RAW not in pairs")

    // Dotfile, subdirectory and unknown extension skipped
    check(!result.pairs.contains { $0.stem == "HIDDEN" }, "dotfile skipped")
    check(!result.pairs.contains { $0.stem == "SUBDIR" }, "subdirectory skipped")
    check(!result.pairs.contains { $0.stem == "IGNORED" }, "unknown extension skipped")

    // Multiple JPGs sharing a stem: alphabetically last one wins (Go ReadDir order)
    let dup = try makeTempDir("filepairs-dup")
    try touch(dup.appendingPathComponent("stem.JPEG"), bytes: 1)
    try touch(dup.appendingPathComponent("stem.JPG"), bytes: 2)
    let dupPairs = try FilePairs.pairs(folder: dup, jpgExts: jpgExts, rawExts: rawExts)
    checkEqual(dupPairs.count, 1, "shared stem → single pair")
    checkEqual(dupPairs[0].jpg.lastPathComponent, "stem.JPG", "last (alphabetical) JPG wins")

    // Missing folder throws
    var threw = false
    do {
        _ = try FilePairs.scan(folder: dir.appendingPathComponent("nonexistent"),
                               jpgExts: jpgExts, rawExts: rawExts)
    } catch { threw = true }
    check(threw, "scan missing folder throws")

    // Empty folder → empty result
    let empty = try makeTempDir("filepairs-empty")
    let emptyResult = try FilePairs.scan(folder: empty, jpgExts: jpgExts, rawExts: rawExts)
    check(emptyResult.pairs.isEmpty && emptyResult.orphanRAWs.isEmpty, "empty folder → no pairs")
}

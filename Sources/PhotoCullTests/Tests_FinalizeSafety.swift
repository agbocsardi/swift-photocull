import Foundation
import PhotoCullCore

/// Synthetic originals only: no fixture reads, image decoding, dumps or rejects.
func suiteFinalizeSafety() throws {
    let fm = FileManager.default
    let output = ProcessInfo.processInfo.environment["PC_FINALIZE_SAFETY_OUT"]
        ?? "/tmp/finalize-safety-impl"
    let root = URL(fileURLWithPath: output, isDirectory: true)
        .appendingPathComponent("synthetic/regression-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) } // Only this suite's synthetic files.
    let cfg = PCConfig(
        paths: PathsConfig(inbox: root.appendingPathComponent("inbox").path,
                           archive: root.appendingPathComponent("archive").path,
                           dump: root.appendingPathComponent("dump").path),
        files: FilesConfig(rawExtensions: ["RAF", "RW2"], jpgExtensions: ["JPG", "JPEG"]))
    let sidecar = Data(#"{"version":1,"decisions":{"A":"keep"},"last_index":0}"#.utf8)

    func folder(_ date: String) throws -> URL {
        let url = URL(fileURLWithPath: cfg.paths.inbox).appendingPathComponent(date)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try sidecar.write(to: url.appendingPathComponent(Session.fileName))
        return url
    }
    func write(_ folder: URL, _ name: String, _ byte: UInt8) throws -> Data {
        let data = Data([0, byte, 255, byte, 10])
        try data.write(to: folder.appendingPathComponent(name))
        return data
    }
    func unchanged(_ url: URL, _ data: Data, _ message: String) {
        checkEqual(try? Data(contentsOf: url), Optional(data), message)
    }
    func archive(_ folder: URL, _ name: String) -> URL {
        URL(fileURLWithPath: cfg.paths.archive).appendingPathComponent(folder.lastPathComponent)
            .appendingPathComponent(name)
    }
    func finalize(_ folder: URL) throws -> FinalizeResult {
        try Finalize.run(cfg: cfg, date: folder.lastPathComponent, dump: false,
                         cropMode: .original, dumpOverride: nil)
    }
    func retained(_ folder: URL) {
        check(fm.fileExists(atPath: folder.path), "residual folder retained")
        unchanged(folder.appendingPathComponent(Session.fileName), sidecar,
                  "residual sidecar preserved byte-for-byte")
    }

    // Each alternate-extension case alone must preserve the omitted original.
    let jpgFolder = try folder("2025-01-01")
    let jpeg = try write(jpgFolder, "A.JPEG", 11)
    let jpg = try write(jpgFolder, "A.JPG", 12)
    let jpgResult = try finalize(jpgFolder)
    checkEqual(jpgResult.archived, 1, "only selected JPG archived")
    checkEqual(jpgResult.trashed, 0, "no rejects or Trash calls")
    unchanged(jpgFolder.appendingPathComponent("A.JPEG"), jpeg, "alternate JPEG untouched")
    unchanged(archive(jpgFolder, "A.JPG"), jpg, "selected JPG archived unchanged")
    retained(jpgFolder)

    let rawFolder = try folder("2025-01-02")
    let rawJPG = try write(rawFolder, "A.JPG", 21)
    let raf = try write(rawFolder, "A.RAF", 22)
    let rw2 = try write(rawFolder, "A.RW2", 23)
    let rawResult = try finalize(rawFolder)
    checkEqual(rawResult.archived, 2, "only selected JPG and RAW archived")
    unchanged(rawFolder.appendingPathComponent("A.RAF"), raf, "alternate RAW untouched")
    unchanged(archive(rawFolder, "A.JPG"), rawJPG, "RAW-pair JPG archived unchanged")
    unchanged(archive(rawFolder, "A.RW2"), rw2, "selected RAW archived unchanged")
    retained(rawFolder)

    // Hidden/unrecognized entries, nested originals and links are not owned
    // by Finalize. Check each as the sole remaining non-sidecar entry.
    for (index, name) in [".hidden", "notes.txt", "nested", "link", "dangling-link"].enumerated() {
        let extras = try folder("2025-02-0\(index + 1)")
        let original = try write(extras, "A.JPG", 31)
        let entry = extras.appendingPathComponent(name)
        let bytes: Data
        if name == "nested" {
            try fm.createDirectory(at: entry, withIntermediateDirectories: false)
            bytes = try write(entry, "unprocessed.RAF", 32)
        } else if name == "link" || name == "dangling-link" {
            let target = root.appendingPathComponent("target-\(index)")
            bytes = Data([0, 33, 255])
            if name == "link" { try bytes.write(to: target) }
            try fm.createSymbolicLink(at: entry, withDestinationURL: target)
        } else {
            bytes = try write(extras, name, 34)
        }
        let result = try finalize(extras)
        checkEqual(result.archived, 1, "only JPG processed with residual \(name)")
        unchanged(archive(extras, "A.JPG"), original, "archived bytes with residual \(name)")
        if name == "nested" {
            unchanged(entry.appendingPathComponent("unprocessed.RAF"), bytes, "nested original untouched")
        } else if name == "link" || name == "dangling-link" {
            let target = root.appendingPathComponent("target-\(index)")
            checkEqual(try? fm.destinationOfSymbolicLink(atPath: entry.path), Optional(target.path),
                       "residual \(name) itself retained")
            if name == "link" { unchanged(target, bytes, "symlink target untouched") }
        } else {
            unchanged(entry, bytes, "residual \(name) untouched")
        }
        retained(extras)
    }

    // Deterministic post-scan arrival: invoke the exact final cleanup helper
    // after adding an original that was not in the scan (no timing sleeps).
    let late = try folder("2025-03-01")
    let scanned = try FilePairs.scan(folder: late, jpgExts: cfg.jpgExtSet, rawExts: cfg.rawExtSet)
    check(scanned.pairs.isEmpty && scanned.orphanRAWs.isEmpty, "scan precedes late original")
    let lateBytes = try write(late, "ARRIVED.JPG", 41)
    Finalize.cleanupSessionFolder(late)
    unchanged(late.appendingPathComponent("ARRIVED.JPG"), lateBytes, "post-scan original untouched")
    retained(late)

    // Pin the kernel guarantee separately: a directory observed empty can
    // receive a file before rmdir; failure must not recursively remove it.
    let race = root.appendingPathComponent("empty-then-arrival")
    try fm.createDirectory(at: race, withIntermediateDirectories: false)
    checkEqual(try fm.contentsOfDirectory(atPath: race.path), [], "directory initially empty")
    let arrival = try write(race, "new.RAF", 51)
    check(!Finalize.removeEmptyDirectory(race), "empty-only primitive refuses new/nonempty directory")
    unchanged(race.appendingPathComponent("new.RAF"), arrival, "kernel refusal preserves arrival bytes")
    try fm.removeItem(at: race.appendingPathComponent("new.RAF")) // Own synthetic file only.
    check(Finalize.removeEmptyDirectory(race), "empty-only primitive removes genuinely empty directory")
    check(!fm.fileExists(atPath: race.path), "empty directory gone")

    // Even a sidecar path replaced by a directory must never be recursed into.
    let replaced = try folder("2025-03-02")
    let sidecarPath = replaced.appendingPathComponent(Session.fileName)
    try fm.removeItem(at: sidecarPath)
    try fm.createDirectory(at: sidecarPath, withIntermediateDirectories: false)
    let nestedSidecarBytes = try write(sidecarPath, "original.JPG", 61)
    Finalize.cleanupSessionFolder(replaced)
    unchanged(sidecarPath.appendingPathComponent("original.JPG"), nestedSidecarBytes,
              "sidecar-directory replacement cannot be recursively deleted")

    // Ordinary processing still removes the now-empty folder and sidecar.
    let complete = try folder("2025-04-01")
    let completeJPG = try write(complete, "A.JPG", 71)
    let completeRAW = try write(complete, "A.RAF", 72)
    let orphan = try write(complete, "ORPHAN.RW2", 73)
    let result = try finalize(complete)
    checkEqual(result.archived, 3, "normal session archives pair and orphan RAW")
    checkEqual(result.trashed, 0, "normal session has no rejects")
    checkEqual(result.dumped, 0, "dump=false writes no exports")
    unchanged(archive(complete, "A.JPG"), completeJPG, "normal JPG bytes unchanged")
    unchanged(archive(complete, "A.RAF"), completeRAW, "normal RAW bytes unchanged")
    unchanged(archive(complete, "ORPHAN.RW2"), orphan, "orphan RAW bytes unchanged")
    check(fm.fileExists(atPath: complete.path), "sidecar-only folder retained")
    unchanged(complete.appendingPathComponent(Session.fileName), sidecar,
              "ordinary success retains sidecar byte-for-byte")
    check(result.retainedFolders.contains(complete.path), "retained folder reported")
    check(!fm.fileExists(atPath: cfg.paths.dump), "safety suite never creates dump root")

    let corrupt = try folder("2025-04-02")
    let corruptSidecar = corrupt.appendingPathComponent(Session.fileName)
    let corruptBytes = Data("{".utf8)
    try corruptBytes.write(to: corruptSidecar)
    let untouched = try write(corrupt, "A.JPG", 81)
    do {
        _ = try finalize(corrupt)
        check(false, "corrupt sidecar rejected")
    } catch { check(true, "corrupt sidecar rejected before effects") }
    unchanged(corruptSidecar, corruptBytes, "corrupt sidecar preserved")
    unchanged(corrupt.appendingPathComponent("A.JPG"), untouched, "corrupt sidecar original untouched")

    do {
        _ = try Finalize.summary(cfg: cfg, date: "../escape")
        check(false, "traversal date rejected")
    } catch { check(true, "traversal date rejected") }

    let empty = root.appendingPathComponent("no-sidecar")
    try fm.createDirectory(at: empty, withIntermediateDirectories: false)
    Finalize.cleanupSessionFolder(empty)
    check(!fm.fileExists(atPath: empty.path), "already-empty folder without sidecar removed")
}

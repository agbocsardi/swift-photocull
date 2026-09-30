import Foundation

// Finalize.swift — Phase 3: trash rejects, archive keepers, dump JPGs.

public struct FinalizeStats: Sendable, Equatable {
    public var date: String
    public var keep: Int
    public var reject: Int
    public var undecided: Int
    public var keepRAW: Int
    public var rejectRAW: Int
    public init(date: String, keep: Int, reject: Int, undecided: Int, keepRAW: Int, rejectRAW: Int) {
        self.date = date; self.keep = keep; self.reject = reject
        self.undecided = undecided; self.keepRAW = keepRAW; self.rejectRAW = rejectRAW
    }
    public var total: Int { keep + reject + undecided }
}

/// What to do with crops when writing JPGs to the dump folder.
public enum CropExportMode: String, Sendable, CaseIterable {
    /// Copy the original JPG untouched.
    case original
    /// Write a cropped copy when a crop is set, else copy the original.
    case applyCrop
}

public struct FinalizeResult: Sendable, Equatable {
    public var sessions: Int
    public var archived: Int
    public var trashed: Int
    public var dumped: Int
    public var cropped: Int
    public var dumpFolder: String
    public init(sessions: Int, archived: Int, trashed: Int, dumped: Int, cropped: Int, dumpFolder: String) {
        self.sessions = sessions; self.archived = archived; self.trashed = trashed
        self.dumped = dumped; self.cropped = cropped; self.dumpFolder = dumpFolder
    }
}

public enum Finalize {
    /// Counts for the confirmation sheet.
    public static func summary(cfg: PCConfig, date: String) throws -> FinalizeStats {
        let folder = try inboxFolder(cfg: cfg, date: date)
        let (pairs, _) = try FilePairs.scan(folder: folder,
                                            jpgExts: cfg.jpgExtSet, rawExts: cfg.rawExtSet)
        let session = try Session.load(folder: folder)
        var keep = 0, reject = 0, undecided = 0, keepRAW = 0, rejectRAW = 0
        for pair in pairs {
            switch session.get(pair.stem) {
            case .keep:
                keep += 1
                if pair.hasRAW { keepRAW += 1 }
            case .reject:
                reject += 1
                if pair.hasRAW { rejectRAW += 1 }
            case .undecided:
                undecided += 1
            }
        }
        return FinalizeStats(date: date, keep: keep, reject: reject, undecided: undecided,
                             keepRAW: keepRAW, rejectRAW: rejectRAW)
    }

    /// Finalize one inbox date folder. `dump` writes keep+undecided JPGs into
    /// `cfg.paths.dump/{date}/` (or `dumpOverride` when given).
    @discardableResult
    public static func run(cfg: PCConfig, date: String, dump: Bool,
                           cropMode: CropExportMode,
                           dumpOverride: URL?) throws -> FinalizeResult {
        let fm = FileManager.default
        let folder = try inboxFolder(cfg: cfg, date: date)
        let archiveFolder = URL(fileURLWithPath: PCConfig.expandHome(cfg.paths.archive))
            .appendingPathComponent(date)
        let dumpFolder = dumpOverride
            ?? URL(fileURLWithPath: PCConfig.expandHome(cfg.paths.dump)).appendingPathComponent(date)

        let (pairs, orphanRAWs) = try FilePairs.scan(folder: folder,
                                                     jpgExts: cfg.jpgExtSet,
                                                     rawExts: cfg.rawExtSet)
        let session = try Session.load(folder: folder)

        if dump {
            try fm.createDirectory(at: dumpFolder, withIntermediateDirectories: true)
        }
        try fm.createDirectory(at: archiveFolder, withIntermediateDirectories: true)

        var archived = 0, trashed = 0, dumped = 0, cropped = 0

        for pair in pairs {
            switch session.get(pair.stem) {
            case .reject:
                try trash(pair.jpg)
                trashed += 1
                if let raw = pair.raw {
                    try trash(raw)
                    trashed += 1
                }
            default:  // keep and undecided are treated the same
                if dump {
                    let dst = collisionFreeDestination(for: pair.jpg, in: dumpFolder)
                    let crop = cropMode == .applyCrop ? session.crop(for: pair.stem) : nil
                    if let crop, !crop.isFullFrame {
                        try ImagePipeline.export(src: pair.jpg, crop: crop, to: dst, quality: 0.9)
                        cropped += 1
                    } else {
                        try fm.copyItem(at: pair.jpg, to: dst)
                    }
                    dumped += 1
                }
                let jpgDst = collisionFreeDestination(for: pair.jpg, in: archiveFolder)
                try fm.moveItem(at: pair.jpg, to: jpgDst)
                archived += 1
                if let raw = pair.raw {
                    let rawDst = collisionFreeDestination(for: raw, in: archiveFolder)
                    try fm.moveItem(at: raw, to: rawDst)
                    archived += 1
                }
            }
        }

        for raw in orphanRAWs {
            let dst = collisionFreeDestination(for: raw, in: archiveFolder)
            try fm.moveItem(at: raw, to: dst)
            archived += 1
        }

        // Remove the sidecar, then the (now hopefully empty) inbox date folder.
        try? fm.removeItem(at: folder.appendingPathComponent(Session.fileName))
        if fm.fileExists(atPath: folder.path) {
            try? fm.removeItem(at: folder)
        }

        return FinalizeResult(sessions: 1, archived: archived, trashed: trashed,
                              dumped: dumped, cropped: cropped, dumpFolder: dumpFolder.path)
    }

    /// Finalize several sessions into one dump folder named
    /// `"2025-03-07 to 2025-03-10"` (single date when there is only one).
    @discardableResult
    public static func runMulti(cfg: PCConfig, dates: [String], dump: Bool,
                                cropMode: CropExportMode) throws -> FinalizeResult {
        var total = FinalizeResult(sessions: 0, archived: 0, trashed: 0,
                                   dumped: 0, cropped: 0, dumpFolder: "")
        guard !dates.isEmpty else { return total }

        let dumpFolder = URL(fileURLWithPath: PCConfig.expandHome(cfg.paths.dump))
            .appendingPathComponent(dumpFolderName(dates: dates))
        for date in dates {
            let r = try run(cfg: cfg, date: date, dump: dump, cropMode: cropMode,
                            dumpOverride: dump ? dumpFolder : nil)
            total.sessions += 1
            total.archived += r.archived
            total.trashed += r.trashed
            total.dumped += r.dumped
            total.cropped += r.cropped
        }
        total.dumpFolder = dumpFolder.path
        return total
    }

    /// Dump folder name for a set of dates, matching Go `GenerateDumpFolderName`.
    static func dumpFolderName(dates: [String]) -> String {
        let sorted = dates.sorted()
        guard let first = sorted.first else { return "" }
        guard sorted.count > 1, let last = sorted.last else { return first }
        return first + " to " + last
    }

    /// Move a file to the macOS Trash (timestamp-suffixed fallback on name collision).
    static func trash(_ url: URL) throws {
        let fm = FileManager.default
        do {
            var resulting: NSURL?
            try fm.trashItem(at: url, resultingItemURL: &resulting)
        } catch {
            // Fallback: move into ~/.Trash directly, with a timestamp suffix on collision.
            let trashDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
            try? fm.createDirectory(at: trashDir, withIntermediateDirectories: true)
            var dest = trashDir.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                let ext = url.pathExtension
                let base = url.lastPathComponent
                let stem = ext.isEmpty ? base : String(base.dropLast(ext.count + 1))
                let suffix = Int(Date().timeIntervalSince1970 * 1_000_000)  // microseconds
                let name = ext.isEmpty ? "\(stem)_\(suffix)" : "\(stem)_\(suffix).\(ext)"
                dest = trashDir.appendingPathComponent(name)
            }
            try fm.moveItem(at: url, to: dest)
        }
    }

    /// Absolute inbox folder URL for a date.
    static func inboxFolder(cfg: PCConfig, date: String) throws -> URL {
        URL(fileURLWithPath: PCConfig.expandHome(cfg.paths.inbox)).appendingPathComponent(date)
    }

    /// A destination inside `dir` that does not exist yet: `name`, then
    /// `name_2`, `name_3`, … preserving the original stem/extension case.
    static func collisionFreeDestination(for src: URL, in dir: URL) -> URL {
        let fm = FileManager.default
        let base = src.lastPathComponent
        var dest = dir.appendingPathComponent(base)
        guard fm.fileExists(atPath: dest.path) else { return dest }
        let ext = src.pathExtension
        let stem = ext.isEmpty ? base : String(base.dropLast(ext.count + 1))
        var i = 2
        while true {
            let name = ext.isEmpty ? "\(stem)_\(i)" : "\(stem)_\(i).\(ext)"
            dest = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: dest.path) { return dest }
            i += 1
        }
    }
}

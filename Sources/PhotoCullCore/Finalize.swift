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
        fatalError("TODO: Finalize.summary")
    }

    /// Finalize one inbox date folder. `dump` writes keep+undecided JPGs into
    /// `cfg.paths.dump/{date}/` (or `dumpOverride` when given).
    @discardableResult
    public static func run(cfg: PCConfig, date: String, dump: Bool,
                           cropMode: CropExportMode,
                           dumpOverride: URL?) throws -> FinalizeResult {
        fatalError("TODO: Finalize.run")
    }

    /// Finalize several sessions into one dump folder named
    /// `"2025-03-07 to 2025-03-10"` (single date when there is only one).
    @discardableResult
    public static func runMulti(cfg: PCConfig, dates: [String], dump: Bool,
                                cropMode: CropExportMode) throws -> FinalizeResult {
        fatalError("TODO: Finalize.runMulti")
    }

    /// Dump folder name for a set of dates, matching Go `GenerateDumpFolderName`.
    static func dumpFolderName(dates: [String]) -> String { fatalError("TODO: Finalize.dumpFolderName") }

    /// Move a file to the macOS Trash (timestamp-suffixed on name collision).
    static func trash(_ url: URL) throws { fatalError("TODO: Finalize.trash") }
}

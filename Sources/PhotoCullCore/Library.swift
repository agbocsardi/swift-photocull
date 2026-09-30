import Foundation

// Library.swift — app-facing rollups over the inbox.

public struct SessionRow: Identifiable, Sendable, Equatable {
    public var date: String
    public var total: Int
    public var keep: Int
    public var reject: Int
    public var undecided: Int
    public var status: FolderStatus
    public var cropped: Int
    public var id: String { date }
    public init(date: String, total: Int, keep: Int, reject: Int,
                undecided: Int, status: FolderStatus, cropped: Int) {
        self.date = date; self.total = total; self.keep = keep
        self.reject = reject; self.undecided = undecided
        self.status = status; self.cropped = cropped
    }
    /// 0...1 completion fraction.
    public var progress: Double { total == 0 ? 0 : Double(keep + reject) / Double(total) }
}

public enum Library {
    /// All inbox date folders, newest first.
    public static func loadSessions(cfg: PCConfig) -> [SessionRow] { fatalError("TODO: Library.loadSessions") }

    /// Pairs for one date folder.
    public static func pairs(cfg: PCConfig, date: String) throws -> [FilePair] { fatalError("TODO: Library.pairs") }

    /// Absolute inbox folder URL for a date.
    public static func inboxFolder(cfg: PCConfig, date: String) -> URL { fatalError("TODO: Library.inboxFolder") }
}

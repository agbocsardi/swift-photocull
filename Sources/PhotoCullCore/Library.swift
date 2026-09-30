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
    /// All inbox date folders, newest first (descending date string compare).
    /// Skips unreadable folders; returns [] when the inbox is missing.
    public static func loadSessions(cfg: PCConfig) -> [SessionRow] {
        let inbox = inboxFolder(cfg: cfg, date: "")
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: inbox, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }

        var rows: [SessionRow] = []
        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            let date = entry.lastPathComponent

            guard let pairs = try? FilePairs.pairs(folder: entry,
                                                   jpgExts: cfg.jpgExtSet,
                                                   rawExts: cfg.rawExtSet) else { continue }

            // Corrupt session file behaves like a fresh one (Go ignores the error).
            let session = (try? Session.load(folder: entry)) ?? Session.fresh()
            let stems = FilePairs.stems(pairs)
            let counts = session.statusCounts(stems: stems)
            rows.append(SessionRow(date: date,
                                   total: pairs.count,
                                   keep: counts.keep,
                                   reject: counts.reject,
                                   undecided: counts.undecided,
                                   status: session.folderStatus(stems: stems),
                                   cropped: session.crops.count))
        }

        rows.sort { $0.date > $1.date }
        return rows
    }

    /// Pairs for one date folder.
    public static func pairs(cfg: PCConfig, date: String) throws -> [FilePair] {
        try FilePairs.pairs(folder: inboxFolder(cfg: cfg, date: date),
                            jpgExts: cfg.jpgExtSet, rawExts: cfg.rawExtSet)
    }

    /// Absolute inbox folder URL for a date (empty date → the inbox itself).
    public static func inboxFolder(cfg: PCConfig, date: String) -> URL {
        let inbox = URL(fileURLWithPath: PCConfig.expandHome(cfg.paths.inbox))
        return date.isEmpty ? inbox : inbox.appendingPathComponent(date)
    }
}

import Foundation

// Ingest.swift — Phase 1: scan source, read EXIF dates, copy into inbox.

public struct IngestProgress: Sendable, Equatable {
    public var running: Bool
    public var done: Bool
    public var total: Int
    public var copied: Int
    public var skipped: Int
    public var current: String
    public var error: String?
    public init() {
        running = false; done = false; total = 0; copied = 0
        skipped = 0; current = ""; error = nil
    }
}

public struct IngestResult: Sendable, Equatable {
    public var copied: Int
    public var skipped: Int
    /// Date folders created or added to, sorted.
    public var folders: [String]
    public init(copied: Int, skipped: Int, folders: [String]) {
        self.copied = copied; self.skipped = skipped; self.folders = folders
    }
}

public enum IngestError: Error, LocalizedError {
    case noSourceFound
    case scanFailed(String)
    public var errorDescription: String? {
        switch self {
        case .noSourceFound:
            return "No SD card found under /Volumes/ with a DCIM directory."
        case .scanFailed(let m):
            return "Could not scan source: \(m)"
        }
    }
}

public enum Ingest {
    /// `DCIM` paths under `/Volumes/*`, sorted.
    public static func detectSDCards() -> [URL] { fatalError("TODO: Ingest.detectSDCards") }

    /// Scan `source` (or auto-detect) and copy matching files into `cfg.paths.inbox/{date}/`.
    /// `onProgress` is called from a background queue.
    @discardableResult
    public static func run(cfg: PCConfig,
                           source: URL?,
                           onProgress: (@Sendable (IngestProgress) -> Void)?) throws -> IngestResult {
        fatalError("TODO: Ingest.run")
    }

    /// All regular files under `source` whose uppercase extension is in `exts`, sorted by path.
    static func scanSource(_ source: URL, exts: Set<String>) -> [URL] { fatalError("TODO: Ingest.scanSource") }

    /// Collision-safe destination filename, mutating `seen` (uppercased stem -> count).
    static func safeDestName(_ src: URL, seen: inout [String: Int]) -> String {
        fatalError("TODO: Ingest.safeDestName")
    }

    /// True when `dest` exists with the same byte size as `src`.
    static func sameFile(dest: URL, src: URL) -> Bool { fatalError("TODO: Ingest.sameFile") }
}

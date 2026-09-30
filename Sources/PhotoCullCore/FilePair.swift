import Foundation

// FilePair.swift — pair JPG + RAW files by filename stem.

public struct FilePair: Sendable, Hashable, Identifiable {
    /// UPPERCASED filename stem, e.g. "DSCF1234".
    public var stem: String
    /// Always present.
    public var jpg: URL
    /// Paired RAW, or nil.
    public var raw: URL?
    public var id: String { stem }
    public var hasRAW: Bool { raw != nil }
    /// Uppercase extension of the RAW file without the dot, e.g. "RAF".
    public var rawExt: String? {
        guard let raw else { return nil }
        return raw.pathExtension.uppercased()
    }
    public init(stem: String, jpg: URL, raw: URL?) {
        self.stem = stem; self.jpg = jpg; self.raw = raw
    }
}

public enum FilePairs {
    /// Scan `folder` for JPG/RAW files and pair them by uppercased stem.
    /// Pairs are sorted by stem. RAW files with no JPG are returned separately.
    public static func scan(folder: URL, jpgExts: Set<String>, rawExts: Set<String>) throws
        -> (pairs: [FilePair], orphanRAWs: [URL]) {
        fatalError("TODO: FilePairs.scan")
    }

    /// Convenience: just the pair list.
    public static func pairs(folder: URL, jpgExts: Set<String>, rawExts: Set<String>) throws -> [FilePair] {
        fatalError("TODO: FilePairs.pairs")
    }

    /// Uppercased stems of the given pairs.
    public static func stems(_ pairs: [FilePair]) -> [String] { pairs.map(\.stem) }
}

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
    /// Subdirectories and dotfiles are skipped. When several JPGs share a stem,
    /// the alphabetically last one wins (matches Go's sorted ReadDir order).
    public static func scan(folder: URL, jpgExts: Set<String>, rawExts: Set<String>) throws
        -> (pairs: [FilePair], orphanRAWs: [URL]) {
        let entries = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey])

        struct Entry { var jpg: URL?; var raw: URL? }
        var byKey: [String: Entry] = [:]

        // Go's os.ReadDir enumerates in sorted filename order; match it so
        // "last one wins" is deterministic.
        let names = entries.map { $0.lastPathComponent }.sorted()
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.lastPathComponent, $0) })

        for name in names {
            guard let url = byName[name] else { continue }
            if name.hasPrefix(".") { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }
            let ext = url.pathExtension.uppercased()
            let stem = url.deletingPathExtension().lastPathComponent.uppercased()
            var e = byKey[stem] ?? Entry(jpg: nil, raw: nil)
            if jpgExts.contains(ext) {
                e.jpg = url
            } else if rawExts.contains(ext) {
                e.raw = url
            }
            byKey[stem] = e
        }

        var pairs: [FilePair] = []
        var orphanRAWs: [URL] = []
        for stem in byKey.keys.sorted() {
            guard let e = byKey[stem] else { continue }
            switch (e.jpg, e.raw) {
            case let (jpg?, raw?):
                pairs.append(FilePair(stem: stem, jpg: jpg, raw: raw))
            case let (jpg?, nil):
                pairs.append(FilePair(stem: stem, jpg: jpg, raw: nil))
            case let (nil, raw?):
                orphanRAWs.append(raw)
            default:
                break
            }
        }
        return (pairs, orphanRAWs)
    }

    /// Convenience: just the pair list.
    public static func pairs(folder: URL, jpgExts: Set<String>, rawExts: Set<String>) throws -> [FilePair] {
        try scan(folder: folder, jpgExts: jpgExts, rawExts: rawExts).pairs
    }

    /// Uppercased stems of the given pairs.
    public static func stems(_ pairs: [FilePair]) -> [String] { pairs.map(\.stem) }
}

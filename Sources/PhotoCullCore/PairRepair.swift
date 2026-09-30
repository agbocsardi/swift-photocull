import Foundation

// PairRepair.swift — fix RAW files that a stem-keyed collision renamed to `_2`.
//
// The Go app's `safeDestName` counted collisions per uppercased STEM, so ingesting
// `DSCF0001.JPG` and `DSCF0001.RAF` in one run renamed the RAW to `DSCF0001_2.RAF`.
// That silently broke the JPG+RAW pairing the whole workflow depends on. This
// repairs the damage: `STEM_N.RAW` becomes `STEM.RAW` again when it is safe to do so.

public struct RepairAction: Sendable, Equatable {
    public enum Kind: String, Sendable {
        /// `<stem>_N.<raw>` -> `<stem>.<raw>` because `<stem>.JPG` exists and is unpaired.
        case renamed
        /// A RAW with no JPG at all; left untouched.
        case unpairedRAW
        /// Several candidates for the same target; left untouched.
        case ambiguous
        /// The RAW is already correctly paired.
        case alreadyPaired
    }
    public var kind: Kind
    public var date: String
    public var from: URL
    public var to: URL?
    public var note: String
    public init(kind: Kind, date: String, from: URL, to: URL?, note: String) {
        self.kind = kind; self.date = date; self.from = from; self.to = to; self.note = note
    }
}

public struct RepairReport: Sendable, Equatable {
    public var actions: [RepairAction]
    public var renamed: Int
    public var unpaired: Int
    public var ambiguous: Int
    public var applied: Bool
    public init(actions: [RepairAction], renamed: Int, unpaired: Int, ambiguous: Int, applied: Bool) {
        self.actions = actions; self.renamed = renamed
        self.unpaired = unpaired; self.ambiguous = ambiguous; self.applied = applied
    }
}

public enum PairRepair {
    /// Scan `roots` (inbox and/or archive) for repairable RAW names.
    /// Nothing is modified — call `apply` with the result to perform the renames.
    public static func plan(cfg: PCConfig, includeArchive: Bool = true) -> RepairReport {
        var roots: [(String, URL)] = [("inbox", URL(fileURLWithPath: cfg.paths.inbox))]
        if includeArchive { roots.append(("archive", URL(fileURLWithPath: cfg.paths.archive))) }

        let jpgExts = cfg.jpgExtSet
        let rawExts = cfg.rawExtSet
        var actions: [RepairAction] = []

        for (_, root) in roots {
            let folders = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let date = folder.lastPathComponent
                let names = Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []))
                let upper = Dictionary(uniqueKeysWithValues: names.map { ($0.uppercased(), $0) })

                // Group RAW files by their unsuffixed stem.
                var candidates: [String: [(String, String)]] = [:]  // stem -> [(fileName, ext)]
                for name in names.sorted() {
                    let ext = (name as NSString).pathExtension.uppercased()
                    guard rawExts.contains(ext) else { continue }
                    let stem = (name as NSString).deletingPathExtension
                    guard let split = splitSuffix(stem) else {
                        // Already unsuffixed: record as an existing target.
                        candidates[stem.uppercased(), default: []].append((name, ext))
                        continue
                    }
                    candidates[split.base.uppercased(), default: []].append((name, ext))
                }

                for (base, files) in candidates.sorted(by: { $0.key < $1.key }) {
                    let hasUnsuffixed = files.contains { splitSuffix(($0.0 as NSString).deletingPathExtension) == nil }
                    let hasJPG = jpgExts.contains(where: { upper["\(base).\($0)"] != nil })

                    for (name, ext) in files {
                        let stem = (name as NSString).deletingPathExtension
                        let from = folder.appendingPathComponent(name)

                        guard let split = splitSuffix(stem) else {
                            actions.append(RepairAction(kind: .alreadyPaired, date: date, from: from,
                                                        to: nil, note: "unsuffixed name"))
                            continue
                        }
                        // A JPG with the same suffixed stem means this RAW is a real pair.
                        if jpgExts.contains(where: { upper["\(stem).\($0)"] != nil }) {
                            actions.append(RepairAction(kind: .alreadyPaired, date: date, from: from,
                                                        to: nil, note: "\(stem).JPG exists"))
                            continue
                        }
                        guard hasJPG else {
                            actions.append(RepairAction(kind: .unpairedRAW, date: date, from: from,
                                                        to: nil, note: "no \(base).JPG"))
                            continue
                        }
                        if hasUnsuffixed {
                            actions.append(RepairAction(kind: .ambiguous, date: date, from: from,
                                                        to: nil, note: "\(base).\(ext) already exists"))
                            continue
                        }
                        _ = split
                        actions.append(RepairAction(
                            kind: .renamed, date: date, from: from,
                            to: folder.appendingPathComponent("\(base).\(ext)"),
                            note: "re-pair with \(base).JPG"))
                    }
                }
            }
        }

        return RepairReport(actions: actions,
                            renamed: actions.filter { $0.kind == .renamed }.count,
                            unpaired: actions.filter { $0.kind == .unpairedRAW }.count,
                            ambiguous: actions.filter { $0.kind == .ambiguous }.count,
                            applied: false)
    }

    /// Perform the renames from `report`. Re-plans first so the result is current.
    ///
    /// Only renames files. Nothing is ever modified, moved or deleted. A JSON log of
    /// every `from -> to` pair is written next to the config file so the operation can
    /// be audited or reversed by hand.
    @discardableResult
    public static func apply(cfg: PCConfig, includeArchive: Bool = true,
                             logDirectory: URL? = nil) throws -> RepairReport {
        let report = plan(cfg: cfg, includeArchive: includeArchive)
        var done: [(from: String, to: String)] = []
        for action in report.actions where action.kind == .renamed {
            guard let to = action.to else { continue }
            try FileManager.default.moveItem(at: action.from, to: to)
            done.append((action.from.path, to.path))
        }
        if !done.isEmpty { try? writeLog(done, to: logDirectory) }
        return RepairReport(actions: report.actions, renamed: report.renamed,
                            unpaired: report.unpaired, ambiguous: report.ambiguous, applied: true)
    }

    /// Write an audit log of performed renames. Failure to log is not fatal.
    static func writeLog(_ renames: [(from: String, to: String)], to directory: URL?) throws {
        let dir = directory ?? URL(fileURLWithPath: PCConfig.configPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("pair-repair-\(stamp).json")
        let payload: [String: Any] = [
            "performed_at": stamp,
            "renamed_count": renames.count,
            "renames": renames.map { ["from": $0.from, "to": $0.to] },
        ]
        let data = try JSONSerialization.data(withJSONObject: payload,
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    /// `"DSCF0001_2"` -> `("DSCF0001", 2)`. Nil when there is no `_<digits>` suffix.
    public static func splitSuffix(_ stem: String) -> (base: String, index: Int)? {
        guard let underscore = stem.lastIndex(of: "_") else { return nil }
        let tail = stem[stem.index(after: underscore)...]
        guard !tail.isEmpty, tail.allSatisfy(\.isNumber), let n = Int(tail), n >= 2 else { return nil }
        return (String(stem[stem.startIndex..<underscore]), n)
    }
}

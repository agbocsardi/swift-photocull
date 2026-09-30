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
    /// `DCIM` paths under `/Volumes/*`, sorted case-insensitively.
    public static func detectSDCards() -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: "/Volumes") else { return [] }
        var found: [URL] = []
        for name in entries {
            var isDir: ObjCBool = false
            let dcim = URL(fileURLWithPath: "/Volumes")
                .appendingPathComponent(name)
                .appendingPathComponent("DCIM")
            if fm.fileExists(atPath: dcim.path, isDirectory: &isDir), isDir.boolValue {
                found.append(dcim)
            }
        }
        return found.sorted {
            $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
        }
    }

    /// Scan `source` (or auto-detect) and copy matching files into `cfg.paths.inbox/{date}/`.
    /// `onProgress` is called synchronously as the run proceeds (call `run` from a
    /// background task/queue to keep it off the main thread).
    @discardableResult
    public static func run(cfg: PCConfig,
                           source: URL?,
                           onProgress: (@Sendable (IngestProgress) -> Void)?) throws -> IngestResult {
        var progress = IngestProgress()
        func report() { onProgress?(progress) }

        do {
            let src: URL
            if let source {
                src = source
            } else {
                guard let first = detectSDCards().first else {
                    throw IngestError.noSourceFound
                }
                src = first
            }

            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: src.path, isDirectory: &isDir),
                  isDir.boolValue else {
                throw IngestError.scanFailed("source does not exist or is not a directory: \(src.path)")
            }

            let allExts = cfg.jpgExtSet.union(cfg.rawExtSet)
            let files = scanSource(src, exts: allExts)

            progress.total = files.count
            progress.running = true
            report()  // total reported once up front

            let inboxRoot = URL(fileURLWithPath: PCConfig.expandHome(cfg.paths.inbox))
            let fm = FileManager.default
            var result = IngestResult(copied: 0, skipped: 0, folders: [])
            // Collision map per date folder: date → uppercased stem → count.
            var collisions: [String: [String: Int]] = [:]

            for file in files {
                progress.current = file.lastPathComponent
                let date = ExifReader.captureDate(url: file)
                let destFolder = inboxRoot.appendingPathComponent(date)
                try fm.createDirectory(at: destFolder, withIntermediateDirectories: true)

                var seen = collisions[date] ?? [:]
                let destName = safeDestName(file, seen: &seen)
                collisions[date] = seen
                let dest = destFolder.appendingPathComponent(destName)

                if sameFile(dest: dest, src: file) {
                    result.skipped += 1
                    progress.skipped = result.skipped
                } else {
                    try fm.copyItem(at: file, to: dest)  // copyItem preserves the mod date
                    result.copied += 1
                    progress.copied = result.copied
                }
                if !result.folders.contains(date) {
                    result.folders.append(date)
                }
                report()
            }

            result.folders.sort()
            progress.running = false
            progress.done = true
            report()
            return result
        } catch {
            progress.running = false
            progress.done = true
            progress.error = error.localizedDescription
            report()
            throw error
        }
    }

    /// All regular files under `source` whose uppercase extension is in `exts`, sorted by path.
    static func scanSource(_ source: URL, exts: Set<String>) -> [URL] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: source,
                                     includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [],
                                     errorHandler: { _, _ in true /* skip, keep walking */ }) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in en {
            guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  vals.isRegularFile == true else { continue }
            if exts.contains(url.pathExtension.uppercased()) {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    /// Collision-safe destination filename, mutating `seen`
    /// (uppercased FULL filename -> count).
    ///
    /// Deliberate divergence from the Go app, which keys the counter on the
    /// uppercased *stem* only. That renamed `DSCF0001.RAF` to `DSCF0001_2.RAF`
    /// whenever its `DSCF0001.JPG` was ingested in the same run, which silently
    /// destroyed the JPG+RAW pair the whole workflow depends on. Keying on the
    /// full filename still handles the case the Go tests describe (the same
    /// filename from two different camera folders) while keeping pairs intact.
    public static func safeDestName(_ src: URL, seen: inout [String: Int]) -> String {
        let base = src.lastPathComponent
        let ext = src.pathExtension
        let stem = ext.isEmpty ? base : String(base.dropLast(ext.count + 1))
        let key = base.uppercased()
        seen[key, default: 0] += 1
        let count = seen[key]!
        if count == 1 { return base }
        return ext.isEmpty ? "\(stem)_\(count)" : "\(stem)_\(count).\(ext)"
    }

    /// True when `dest` exists with the same byte size as `src`.
    static func sameFile(dest: URL, src: URL) -> Bool {
        let fm = FileManager.default
        guard let d = try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int64,
              let s = try? fm.attributesOfItem(atPath: src.path)[.size] as? Int64 else {
            return false
        }
        return d == s
    }
}

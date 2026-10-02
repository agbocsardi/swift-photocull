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
        // App Nap guard: mark CPU+IO as user-initiated so macOS does not
        // throttle the run, while still allowing idle *display* sleep
        // (not idleSystemSleepDisabled).
        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "PhotoCull ingest in progress")
        defer { ProcessInfo.processInfo.endActivity(activity) }

        let inboxRoot = URL(fileURLWithPath: PCConfig.expandHome(cfg.paths.inbox))
        let fm = FileManager.default
        // Lock-protected progress: the serial planner and the parallel copy
        // workers both mutate it (B2). All mutations funnel through `update`,
        // which returns the post-update snapshot so callers report a
        // consistent view.
        let progressBox = ProgressBox()
        func report() { onProgress?(progressBox.snapshot()) }

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
            guard fm.fileExists(atPath: src.path, isDirectory: &isDir),
                  isDir.boolValue else {
                throw IngestError.scanFailed("source does not exist or is not a directory: \(src.path)")
            }

            let allExts = cfg.jpgExtSet.union(cfg.rawExtSet)
            let files = scanSource(src, exts: allExts)

            _ = progressBox.update {
                $0.total = files.count
                $0.running = true
            }
            report()  // total reported once up front

            var result = IngestResult(copied: 0, skipped: 0, folders: [])

            // ── Phase 1 (serial, sorted file order — unchanged semantics):
            // EXIF captureDate, destination-folder creation, collision-safe
            // names and the sameFile skip decision all stay strictly ordered,
            // because the collision counter map and the createdFolder cache
            // are order-dependent state. Only the byte copies move to phase 2.
            var jobs: [CopyJob] = []
            // Collision map per date folder: date → uppercased stem → count.
            var collisions: [String: [String: Int]] = [:]
            // Files arrive sorted by path, so consecutive files usually share
            // one destination date folder — create it once per change.
            var createdFolder: URL?

            for (file, fileSize) in files {
                _ = progressBox.update { $0.current = file.lastPathComponent }
                let date = ExifReader.captureDate(url: file)
                let destFolder = inboxRoot.appendingPathComponent(date)
                if createdFolder != destFolder {
                    try fm.createDirectory(at: destFolder, withIntermediateDirectories: true)
                    createdFolder = destFolder
                }

                var seen = collisions[date] ?? [:]
                let destName = safeDestName(file, seen: &seen)
                collisions[date] = seen
                let dest = destFolder.appendingPathComponent(destName)

                if sameFile(dest: dest, srcSize: fileSize) {
                    result.skipped += 1
                    _ = progressBox.update { $0.skipped = result.skipped }
                } else {
                    jobs.append(CopyJob(src: file, dest: dest))
                }
                if !result.folders.contains(date) {
                    result.folders.append(date)
                }
                report()
            }

            // ── Phase 2 (parallel copies). Cross-volume copies cannot be
            // APFS-cloned (EXDEV — clonefile is same-volume only), so this is
            // a plain copyItem per file. Width is capped at 4: SSD fixtures
            // scale to ~5×, real UHS-I cards only to ~1.1–1.4×, and going
            // wider just contends on the card controller. Files are similar
            // sizes, so the width-bounded handout below behaves like a static
            // round-robin partition.
            //
            // Progress: counters live under the ProgressBox lock; report()
            // fires after each completed copy (AppState's 150ms
            // ProgressThrottle coalesces). `current` shifts from "file being
            // copied" to "most recently completed file" — with parallel
            // copies nothing is singularly "in flight" anymore.
            //
            // Errors: the first copy error stops new copies from starting;
            // already-started copies finish. Unstarted files stay on the
            // card, so a re-run picks up where this one stopped (sameFile
            // skips what landed completely) — the same user-visible outcome
            // as the old serial fail-fast.
            if !jobs.isEmpty {
                try copyAllParallel(jobs: jobs, progressBox: progressBox, onProgress: onProgress)
            }
            result.copied = progressBox.snapshot().copied

            result.folders.sort()
            _ = progressBox.update {
                $0.running = false
                $0.done = true
            }
            report()
            return result
        } catch {
            _ = progressBox.update {
                $0.running = false
                $0.done = true
                $0.error = error.localizedDescription
            }
            report()
            throw error
        }
    }

    /// All regular files under `source` whose uppercase extension is in `exts`,
    /// sorted by path, with each file's byte size. The size rides the same
    /// directory walk (B4) instead of costing a second stat per file later.
    static func scanSource(_ source: URL, exts: Set<String>) -> [(url: URL, size: Int64?)] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: source,
                                     includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                     options: [],
                                     errorHandler: { _, _ in true /* skip, keep walking */ }) else {
            return []
        }
        var files: [(url: URL, size: Int64?)] = []
        for case let url as URL in en {
            guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  vals.isRegularFile == true else { continue }
            if exts.contains(url.pathExtension.uppercased()) {
                files.append((url, vals.fileSize.map(Int64.init)))
            }
        }
        return files.sorted { $0.url.path < $1.url.path }
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

    /// True when `dest` exists with the same byte size as the source. The
    /// source size comes from the scan pass (B4), so only the destination is
    /// stat'ed here. A missing source size (stat failed during the scan)
    /// counts as "not the same", matching the old behavior of failing both
    /// stats → copy again.
    static func sameFile(dest: URL, srcSize: Int64?) -> Bool {
        guard let srcSize,
              let d = try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64 else {
            return false
        }
        return d == srcSize
    }
}

/// One planned byte copy (phase-2 work item).
private struct CopyJob: Sendable {
    let src: URL
    let dest: URL
}

/// Lock-protected IngestProgress shared between the serial planner and the
/// parallel copy workers (B2).
private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = IngestProgress()

    func update(_ f: (inout IngestProgress) -> Void) -> IngestProgress {
        lock.lock()
        defer { lock.unlock() }
        f(&value)
        return value
    }

    func snapshot() -> IngestProgress {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

extension Ingest {
    /// Copy `jobs` with at most `min(4, activeProcessorCount)` concurrent
    /// copyItem calls (B2). Throws the first copy error after already-started
    /// copies finish; items not yet started never run. The TaskGroup runs on
    /// a detached task and the synchronous caller waits on a semaphore —
    /// `run` stays a synchronous API (AppState and the CLI call it directly).
    fileprivate static func copyAllParallel(jobs: [CopyJob],
                                progressBox: ProgressBox,
                                onProgress: (@Sendable (IngestProgress) -> Void)?) throws {
        final class ErrorBox: @unchecked Sendable { var error: Error? }
        let errors = ErrorBox()
        let sem = DispatchSemaphore(value: 0)
        let width = min(4, max(1, ProcessInfo.processInfo.activeProcessorCount))
        Task.detached(priority: .userInitiated) {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    var next = 0
                    var inFlight = 0
                    var firstError: Error?

                    func add(_ i: Int) {
                        let job = jobs[i]
                        group.addTask {
                            // copyItem preserves the modification date.
                            try FileManager.default.copyItem(at: job.src, to: job.dest)
                            let snap = progressBox.update {
                                $0.copied += 1
                                $0.current = job.dest.lastPathComponent
                            }
                            onProgress?(snap)
                        }
                        inFlight += 1
                    }

                    // Keep exactly `width` children in flight; on the first
                    // error stop handing out new jobs and drain the rest.
                    while next < min(width, jobs.count) { add(next); next += 1 }
                    while inFlight > 0 {
                        do { _ = try await group.next() }
                        catch { if firstError == nil { firstError = error } }
                        inFlight -= 1
                        if firstError == nil && next < jobs.count { add(next); next += 1 }
                    }
                    if let firstError { throw firstError }
                }
            } catch {
                errors.error = error
            }
            sem.signal()
        }
        sem.wait()
        if let error = errors.error { throw error }
    }
}

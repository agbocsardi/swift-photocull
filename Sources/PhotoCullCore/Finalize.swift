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

/// What to do with edits when writing JPGs to the dump folder.
public enum CropExportMode: String, Sendable, CaseIterable {
    /// Copy the original JPG untouched.
    case original
    /// Write an edited copy (crop, tilt, rotation) when any is set, else copy
    /// the original.
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

        // ── Three phases (perf wave 3, B1) ─────────────────────────────────
        //
        // PHASE 1 (serial, exact scan order): decide reject/keep per pair and
        // allocate EVERY destination up front — dump dst, archive jpgDst and
        // rawDst via collisionFreeDestination. Destination allocation must
        // stay serial: collisionFreeDestination probes the filesystem with
        // fileExists(), and under concurrency two workers can probe the same
        // not-yet-written name, both see "free", and the second write clobbers
        // the first. Rejects are trashed immediately (a cheap move, and the
        // order stays deterministic). Unedited keepers dump via copyItem right
        // here — it is an APFS clone at ~0.1 ms, parallelizing buys nothing.
        // Only cropped keepers queue an export job.
        //
        // PHASE 2 (parallel, width = active core count): cropped exports via
        // ImagePipeline.export, each written to "<dst>.tmp" first and renamed
        // into place on success — a failed or cancelled encode then never
        // leaves a truncated dump file behind. All outcomes are collected;
        // nothing throws here.
        //
        // PHASE 3 (serial, original order): the archive moves, stopping at the
        // first pair whose export failed. This reproduces the old serial
        // fail-fast exactly: every pair before the failure is fully dumped and
        // archived, the failing pair and all later pairs keep their files in
        // the inbox, and the first error is thrown. Counters report what
        // actually happened. (Known trade-off of phase-1 immediacy: unedited
        // keepers after a failure already have their dump clone; a re-run
        // re-dumps what remains in the inbox under collision-free names.)

        var plans: [Plan] = []
        var jobs: [ExportJob] = []

        // PHASE 1
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
                var jobIndex: Int?
                if dump {
                    let dst = collisionFreeDestination(for: pair.jpg, in: dumpFolder)
                    let crop = cropMode == .applyCrop ? session.crop(for: pair.stem) : nil
                    let tilt = cropMode == .applyCrop ? session.tilt(for: pair.stem) : 0
                    let turns = cropMode == .applyCrop ? session.quarterTurns(for: pair.stem) : 0
                    let hasCrop = crop.map { !$0.isFullFrame } ?? false
                    if hasCrop || tilt != 0 || turns != 0 {
                        jobIndex = jobs.count
                        jobs.append(ExportJob(src: pair.jpg, dst: dst, crop: crop,
                                              tilt: tilt, turns: turns))
                    } else {
                        try fm.copyItem(at: pair.jpg, to: dst)  // APFS clone
                        dumped += 1
                    }
                }
                let jpgDst = collisionFreeDestination(for: pair.jpg, in: archiveFolder)
                var rawDst: URL?
                if let raw = pair.raw {
                    rawDst = collisionFreeDestination(for: raw, in: archiveFolder)
                }
                plans.append(Plan(jpg: pair.jpg, jpgDst: jpgDst,
                                  raw: pair.raw, rawDst: rawDst, jobIndex: jobIndex))
            }
        }

        // PHASE 2
        let outcomes = exportAllParallel(jobs: jobs)

        // PHASE 3
        var firstFailure: Error?
        for plan in plans {
            if let idx = plan.jobIndex {
                if let error = outcomes[idx].error {
                    firstFailure = error
                    break
                }
                dumped += 1
                cropped += 1
            }
            try fm.moveItem(at: plan.jpg, to: plan.jpgDst)
            archived += 1
            if let raw = plan.raw, let rawDst = plan.rawDst {
                try fm.moveItem(at: raw, to: rawDst)
                archived += 1
            }
        }
        if let firstFailure {
            throw firstFailure
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

    /// One cropped export queued by phase 1, executed in phase 2.
    private struct ExportJob: Sendable {
        let src: URL
        let dst: URL
        let crop: CropRect?
        let tilt: Double
        let turns: Int
    }

    /// Per-pair phase-3 plan: where the archive moves go, and which export
    /// job (if any) must have succeeded before they may run.
    private struct Plan {
        let jpg: URL
        let jpgDst: URL
        let raw: URL?
        let rawDst: URL?
        let jobIndex: Int?
    }

    /// Per-export outcome. Boxes the error in a class so results cross task
    /// boundaries without sending `any Error` values between tasks.
    private final class ExportOutcome: @unchecked Sendable {
        let error: Error?
        init(error: Error?) { self.error = error }
    }

    /// Unreachable placeholder: every child returns an outcome, even on error.
    private struct ExportOutcomeMissing: Error {}

    /// Run cropped exports `jobs` on a TaskGroup capped at the active core
    /// count (measured 3.1–3.7× over serial at width 8). Each export writes to
    /// "<dst>.tmp" and renames into place on success, so a failed encode never
    /// leaves a truncated dump file. Returns one outcome per job, aligned with
    /// the input; errors are reported, never thrown. The group runs on a
    /// detached task and the synchronous caller waits on a semaphore — `run`
    /// stays a synchronous API (AppState and the CLI call it directly).
    private static func exportAllParallel(jobs: [ExportJob]) -> [ExportOutcome] {
        final class ResultsBox: @unchecked Sendable { var values: [ExportOutcome] = [] }
        let box = ResultsBox()
        let sem = DispatchSemaphore(value: 0)
        let width = max(1, ProcessInfo.processInfo.activeProcessorCount)
        Task.detached(priority: .userInitiated) {
            let results = await withTaskGroup(of: (Int, ExportOutcome).self,
                                              returning: [ExportOutcome].self) { group in
                var next = 0
                func add(_ i: Int) {
                    let job = jobs[i]
                    group.addTask {
                        let tmp = job.dst.appendingPathExtension("tmp")
                        do {
                            try ImagePipeline.export(src: job.src, crop: job.crop, to: tmp,
                                                     quality: 0.9, tilt: job.tilt,
                                                     quarterTurns: job.turns)
                            try FileManager.default.moveItem(at: tmp, to: job.dst)
                            return (i, ExportOutcome(error: nil))
                        } catch {
                            try? FileManager.default.removeItem(at: tmp)
                            return (i, ExportOutcome(error: error))
                        }
                    }
                }
                // Keep exactly `width` children in flight; each completion
                // hands out the next job (files are one job, so ordering
                // within the group does not affect the phase-3 walk).
                while next < min(width, jobs.count) { add(next); next += 1 }
                var out = Array<ExportOutcome?>(repeating: nil, count: jobs.count)
                for await (i, outcome) in group {
                    out[i] = outcome
                    if next < jobs.count { add(next); next += 1 }
                }
                return out.map { $0 ?? ExportOutcome(error: ExportOutcomeMissing()) }
            }
            box.values = results
            sem.signal()
        }
        sem.wait()
        return box.values
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

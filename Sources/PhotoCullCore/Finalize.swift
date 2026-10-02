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
        // App Nap guard: mark CPU+IO as user-initiated so macOS does not
        // throttle the run, while still allowing idle *display* sleep
        // (not idleSystemSleepDisabled).
        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "PhotoCull finalize in progress")
        defer { ProcessInfo.processInfo.endActivity(activity) }

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
        // PHASE 1 (serial, exact scan order): PURE PLANNING — no filesystem
        // side effects beyond the dump/archive directory creations above,
        // which the old serial loop also did up-front. Classify each pair
        // and allocate EVERY destination — dump dst, archive jpgDst,
        // rawDst — via collisionFreeDestination. Allocation must stay
        // serial: it probes the filesystem with fileExists(), and under
        // concurrency two workers could probe the same not-yet-written
        // name, both see "free", and the second write clobbers the first.
        // Cropped keepers queue an export job.
        //
        // PHASE 2 (parallel, width = active core count): cropped exports
        // via ImagePipeline.export, each written to "<dst>.tmp" — the only
        // files this phase touches. A failed or cancelled encode then never
        // leaves a truncated file in the dump: failed encodes remove their
        // tmp, successes are left staged for phase 3 to promote. All
        // outcomes are collected; nothing throws here.
        //
        // PHASE 3 (serial, exact scan order, fail-fast): every ordered side
        // effect happens here — rejects trashed, unedited keepers
        // dump-cloned, staged exports renamed into place, archive moves —
        // in the original pair order, counters incrementing at the point
        // of effect. A failure at pair k therefore reproduces the old
        // serial end state exactly: pairs before k fully processed, k..N
        // untouched (still in the inbox, not dumped, later rejects not
        // trashed), and the first error thrown. On the break, staged tmp
        // exports of unprocessed pairs are removed — after any run (success
        // or failure) no *.tmp files remain; only a hard crash can leave
        // them, where the .tmp name marks them as incomplete anyway.

        // PHASE 1 — planning only.
        var plans: [Plan] = []
        var jobs: [ExportJob] = []
        for pair in pairs {
            var kind = Plan.Kind.dumpClone
            var dumpDst: URL?
            switch session.get(pair.stem) {
            case .reject:
                kind = .reject
            default:  // keep and undecided are treated the same
                if dump {
                    let dst = collisionFreeDestination(for: pair.jpg, in: dumpFolder)
                    let crop = cropMode == .applyCrop ? session.crop(for: pair.stem) : nil
                    let tilt = cropMode == .applyCrop ? session.tilt(for: pair.stem) : 0
                    let turns = cropMode == .applyCrop ? session.quarterTurns(for: pair.stem) : 0
                    let hasCrop = crop.map { !$0.isFullFrame } ?? false
                    if hasCrop || tilt != 0 || turns != 0 {
                        kind = .export(jobIndex: jobs.count)
                        jobs.append(ExportJob(src: pair.jpg, dst: dst, crop: crop,
                                              tilt: tilt, turns: turns))
                    } else {
                        dumpDst = dst
                    }
                }
            }
            let jpgDst = collisionFreeDestination(for: pair.jpg, in: archiveFolder)
            var rawDst: URL?
            if let raw = pair.raw {
                rawDst = collisionFreeDestination(for: raw, in: archiveFolder)
            }
            plans.append(Plan(kind: kind, jpg: pair.jpg, dumpDst: dumpDst,
                              jpgDst: jpgDst, raw: pair.raw, rawDst: rawDst))
        }

        // PHASE 2
        let outcomes = exportAllParallel(jobs: jobs)

        // PHASE 3 — all side effects, in exact scan order, fail-fast.
        var firstFailure: Error?
        loop: for (i, plan) in plans.enumerated() {
            switch plan.kind {
            case .reject:
                try trash(plan.jpg)
                trashed += 1
                if let raw = plan.raw {
                    try trash(raw)
                    trashed += 1
                }
                continue
            case .dumpClone:
                if let dumpDst = plan.dumpDst {
                    try fm.copyItem(at: plan.jpg, to: dumpDst)  // APFS clone
                    dumped += 1
                }
            case .export(let jobIndex):
                if let error = outcomes[jobIndex].error {
                    firstFailure = error
                    // The failing pair's tmp is already gone (removed by the
                    // worker's error path); remove the staged exports of
                    // every unprocessed pair so the dump stays clean.
                    for later in plans[(i + 1)...] {
                        if case .export(let j) = later.kind {
                            try? fm.removeItem(at: stagedPath(for: jobs[j].dst))
                        }
                    }
                    break loop
                }
                try fm.moveItem(at: stagedPath(for: jobs[jobIndex].dst),
                                to: jobs[jobIndex].dst)
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

    /// Per-pair phase-3 plan: what kind of pair this is (decided in phase 1),
    /// where the dump clone goes (unedited keepers, when dumping), which
    /// export job must have succeeded before the pair may proceed, and where
    /// the archive moves go.
    private struct Plan {
        enum Kind {
            /// Trash the jpg (+raw).
            case reject
            /// Unedited keeper: clone to the dump when dumping.
            case dumpClone
            /// Cropped keeper: promote staged export `jobIndex` first.
            case export(jobIndex: Int)
        }
        let kind: Kind
        let jpg: URL
        let dumpDst: URL?
        let jpgDst: URL
        let raw: URL?
        let rawDst: URL?
    }

    /// Where an export's staged ("<dst>.tmp") file lives until phase 3
    /// promotes it into place.
    private static func stagedPath(for dst: URL) -> URL {
        dst.appendingPathExtension("tmp")
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
    /// count (measured 3.1–3.7× over serial at width 8). Each export is
    /// written to "<dst>.tmp" and left staged — phase 3 does the ordered
    /// rename — so a failed encode never leaves a truncated dump file, and a
    /// failed RUN never leaves dumps for pairs the fail-fast contract keeps
    /// untouched. Returns one outcome per job, aligned with the input; errors
    /// are reported, never thrown. The group runs on a detached task and the
    /// synchronous caller waits on a semaphore — `run` stays a synchronous
    /// API (AppState and the CLI call it directly).
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
                        let tmp = stagedPath(for: job.dst)
                        do {
                            try ImagePipeline.export(src: job.src, crop: job.crop, to: tmp,
                                                     quality: 0.9, tilt: job.tilt,
                                                     quarterTurns: job.turns)
                            return (i, ExportOutcome(error: nil))  // stays staged for phase 3
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

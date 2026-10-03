import Foundation
import Darwin

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
        // PHASE 1 (serial): classify and reserve destinations in memory before
        // effects. Reservations prevent plans in this run from aliasing even
        // when the filesystem probes all report absent. They are not a lock:
        // an external writer can still race a later copy/move, which must fail
        // rather than overwrite its file.
        // PHASE 2 (parallel, current active-core width): edited JPGs encode to
        // files inside a newly-created private directory under dumpFolder.
        // PHASE 3 (serial, exact scan order, fail-fast): ordered effects occur
        // here. A failure preserves the completed prefix, but earlier dump or
        // archive effects within the failing pair may already have happened.
        // Deferred cleanup unlinks only this invocation's stage files and
        // removes its private directory only if empty; crashes may leave it.

        // PHASE 1 — planning only.
        var plans: [Plan] = []
        var jobs: [ExportJob] = []
        var reservations = Set<String>()
        var inventoriedFolders = Set<String>()
        for dir in dump ? [archiveFolder, dumpFolder] : [archiveFolder] {
            if inventoriedFolders.insert(dir.standardizedFileURL.path).inserted {
                reservations.formUnion(try destinationReservations(in: dir))
            }
        }
        for pair in pairs {
            var kind = Plan.Kind.dumpClone
            var dumpDst: URL?
            switch session.get(pair.stem) {
            case .reject:
                kind = .reject
            default:  // keep and undecided are treated the same
                if dump {
                    let dst = reserveDestination(for: pair.jpg, in: dumpFolder,
                                                 reservations: &reservations)
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
            var jpgDst: URL?
            var rawDst: URL?
            if case .reject = kind {
                // Rejects have no planned write destinations.
            } else {
                if let raw = pair.raw {
                    let destinations = reservePair(jpg: pair.jpg, raw: raw, in: archiveFolder,
                                                   reservations: &reservations)
                    jpgDst = destinations.jpg
                    rawDst = destinations.raw
                } else {
                    jpgDst = reserveDestination(for: pair.jpg, in: archiveFolder,
                                                reservations: &reservations)
                }
            }
            plans.append(Plan(kind: kind, jpg: pair.jpg, dumpDst: dumpDst,
                              jpgDst: jpgDst, raw: pair.raw, rawDst: rawDst))
        }
        var orphanDestinations: [(URL, URL)] = []
        for raw in orphanRAWs {
            orphanDestinations.append((raw, reserveDestination(for: raw, in: archiveFolder,
                                                               reservations: &reservations)))
        }

        // Create an invocation-owned staging area only when edits need it.
        var stageDirectory: URL?
        defer {
            for job in jobs { if let stage = job.stage { unlinkOwnedFile(stage) } }
            if let stageDirectory { _ = removeEmptyDirectory(stageDirectory) }
        }
        if !jobs.isEmpty {
            var candidate: URL
            while true {
                candidate = dumpFolder.appendingPathComponent(".photocull-stage-\(UUID().uuidString)",
                                                               isDirectory: true)
                if try createOwnedDirectory(candidate) {
                    stageDirectory = candidate
                    break
                }
            }
            for i in jobs.indices {
                jobs[i].stage = candidate.appendingPathComponent(String(i))
            }
        }
        // PHASE 2
        let outcomes = exportAllParallel(jobs: jobs)

        // PHASE 3 — all side effects, in exact scan order, fail-fast.
        var firstFailure: Error?
        loop: for plan in plans {
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
                    // Function-level defer unlinks all remaining owned stages.
                    break loop
                }
                guard let stage = jobs[jobIndex].stage else {
                    throw ExportOutcomeMissing()
                }
                try fm.moveItem(at: stage, to: jobs[jobIndex].dst)
                dumped += 1
                cropped += 1
            }
            guard let jpgDst = plan.jpgDst else {
                throw NSError(domain: "PhotoCullCore.Finalize", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "missing planned archive destination"])
            }
            try fm.moveItem(at: plan.jpg, to: jpgDst)
            archived += 1
            if let raw = plan.raw, let rawDst = plan.rawDst {
                try fm.moveItem(at: raw, to: rawDst)
                archived += 1
            }
        }
        if let firstFailure {
            throw firstFailure
        }

        for (raw, dst) in orphanDestinations {
            try fm.moveItem(at: raw, to: dst)
            archived += 1
        }

        cleanupSessionFolder(folder)

        return FinalizeResult(sessions: 1, archived: archived, trashed: trashed,
                              dumped: dumped, cropped: cropped, dumpFolder: dumpFolder.path)
    }

    /// Best-effort cleanup: preserve decisions whenever residual entries are
    /// visible (including hidden files, directories and alternate originals).
    /// A failed listing also retains the sidecar. This check is NOT an ownership
    /// lock: a concurrent writer arriving after it may lose the sidecar,
    /// but rmdir below can never recursively delete that writer's files.
    package static func cleanupSessionFolder(_ folder: URL) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path),
              names.allSatisfy({ $0 == Session.fileName }) else { return }

        // unlink only the known sidecar; unlike removeItem it cannot recurse
        // if that path is replaced by a directory during cleanup.
        folder.appendingPathComponent(Session.fileName).withUnsafeFileSystemRepresentation { path in
            if let path { _ = Darwin.unlink(path) }
        }
        _ = removeEmptyDirectory(folder)
    }

    /// Atomic, empty-only removal. Nonempty/inaccessible directories are
    /// retained; never substitute an enumerate-then-recursive removal.
    /// Package-scoped so regression tests need no public API or testable build.
    @discardableResult
    package static func removeEmptyDirectory(_ folder: URL) -> Bool {
        folder.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return Darwin.rmdir(path) == 0
        }
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
        var stage: URL?
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
        let jpgDst: URL?
        let raw: URL?
        let rawDst: URL?
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
    /// count. Each export is written to its private stage file; phase 3 does
    /// the ordered promotion. Returns one outcome per job, aligned with the input; errors
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
                        guard let stage = job.stage else {
                            return (i, ExportOutcome(error: ExportOutcomeMissing()))
                        }
                        do {
                            try ImagePipeline.export(src: job.src, crop: job.crop, to: stage,
                                                     quality: 0.9, tilt: job.tilt,
                                                     quarterTurns: job.turns)
                            return (i, ExportOutcome(error: nil))  // stays staged for phase 3
                        } catch {
                            unlinkOwnedFile(stage)
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

    /// A normalized reservation key; folding only the filename is a
    /// conservative case-insensitive policy regardless of volume settings.
    private static func reservationKey(for url: URL) -> String {
        url.deletingLastPathComponent().standardizedFileURL.path + "/" +
            url.lastPathComponent.uppercased()
    }

    /// Inventory each output directory once; directory listings include dangling links.
    private static func destinationReservations(in dir: URL) throws -> Set<String> {
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        return Set(names.map { reservationKey(for: dir.appendingPathComponent($0)) })
    }

    private static func destinationExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// mkdir is an exclusive ownership claim; only a UUID collision is retried.
    private static func createOwnedDirectory(_ url: URL) throws -> Bool {
        let (result, code) = url.withUnsafeFileSystemRepresentation { path -> (Int32, Int32) in
            guard let path else { return (-1, EINVAL) }
            let result = Darwin.mkdir(path, mode_t(0o700))
            return (result, result == 0 ? 0 : errno)
        }
        guard result == 0 else {
            if code == EEXIST { return false }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code),
                          userInfo: [NSFilePathErrorKey: url.path])
        }
        return true
    }

    private static func reserveDestination(for src: URL, in dir: URL,
                                           reservations: inout Set<String>) -> URL {
        let ext = src.pathExtension
        let base = src.lastPathComponent
        let stem = ext.isEmpty ? base : String(base.dropLast(ext.count + 1))
        var suffix = 1
        while true {
            let name: String
            if suffix == 1 { name = base }
            else { name = ext.isEmpty ? "\(stem)_\(suffix)" : "\(stem)_\(suffix).\(ext)" }
            let candidate = dir.appendingPathComponent(name)
            let key = reservationKey(for: candidate)
            if !destinationExists(candidate), !reservations.contains(key) {
                reservations.insert(key)
                return candidate
            }
            suffix += 1
        }
    }

    /// Reserve both members together, applying the same suffix to each stem.
    private static func reservePair(jpg: URL, raw: URL, in dir: URL,
                                    reservations: inout Set<String>) -> (jpg: URL, raw: URL) {
        func named(_ src: URL, suffix: Int) -> URL {
            let ext = src.pathExtension
            let base = src.lastPathComponent
            let stem = ext.isEmpty ? base : String(base.dropLast(ext.count + 1))
            let name = suffix == 1 ? base : (ext.isEmpty ? "\(stem)_\(suffix)" : "\(stem)_\(suffix).\(ext)")
            return dir.appendingPathComponent(name)
        }
        var suffix = 1
        while true {
            let jpgDst = named(jpg, suffix: suffix)
            let rawDst = named(raw, suffix: suffix)
            let jpgKey = reservationKey(for: jpgDst)
            let rawKey = reservationKey(for: rawDst)
            if !destinationExists(jpgDst), !destinationExists(rawDst),
               !reservations.contains(jpgKey), !reservations.contains(rawKey) {
                reservations.insert(jpgKey)
                reservations.insert(rawKey)
                return (jpgDst, rawDst)
            }
            suffix += 1
        }
    }

    private static func unlinkOwnedFile(_ url: URL) {
        url.withUnsafeFileSystemRepresentation { path in
            if let path { _ = Darwin.unlink(path) }
        }
    }

    /// Legacy non-reserving probe retained for package callers and focused checks.
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

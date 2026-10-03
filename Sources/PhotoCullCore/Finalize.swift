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
    public var retainedFolders: [String]
    public init(sessions: Int, archived: Int, trashed: Int, dumped: Int, cropped: Int, dumpFolder: String,
                retainedFolders: [String] = []) {
        self.sessions = sessions; self.archived = archived; self.trashed = trashed
        self.dumped = dumped; self.cropped = cropped; self.dumpFolder = dumpFolder
        self.retainedFolders = retainedFolders
    }
}

public enum Finalize {
    /// Counts for the confirmation sheet.
    public static func summary(cfg: PCConfig, date: String) throws -> FinalizeStats {
        try validateDate(date)
        let folder = try inboxFolder(cfg: cfg, date: date)
        try validateInputFolder(folder)
        let (pairs, _) = try FilePairs.scan(folder: folder,
                                            jpgExts: cfg.jpgExtSet, rawExts: cfg.rawExtSet)
        let session = try Session.load(folder: folder, strict: true)
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
        try run(cfg: cfg, date: date, dump: dump, cropMode: cropMode,
                dumpOverride: dumpOverride, syntheticTrash: nil)
    }

    package static func run(cfg: PCConfig, date: String, dump: Bool,
                            cropMode: CropExportMode, dumpOverride: URL?,
                            syntheticTrash: ((URL) throws -> Void)?) throws -> FinalizeResult {
        // App Nap guard: mark CPU+IO as user-initiated so macOS does not
        // throttle the run, while still allowing idle *display* sleep
        // (not idleSystemSleepDisabled).
        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "PhotoCull finalize in progress")
        defer { ProcessInfo.processInfo.endActivity(activity) }

        try validateDate(date)
        let fm = FileManager.default
        let folder = try inboxFolder(cfg: cfg, date: date)
        try validateInputFolder(folder)
        let directoryFD = folder.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW) } ?? -1
        }
        guard directoryFD >= 0 else { throw posixError("open session directory") }
        let lockURL = folder.appendingPathComponent(".photocull-operation.lock")
        let lockFD = lockURL.withUnsafeFileSystemRepresentation {
            $0.map { Darwin.open($0, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600) } ?? -1
        }
        guard lockFD >= 0 else { _ = Darwin.close(directoryFD); throw posixError("open operation lock") }
        var lock = flock()
        lock.l_type = Int16(F_WRLCK); lock.l_whence = Int16(SEEK_SET)
        defer {
            lock.l_type = Int16(F_UNLCK)
            _ = Darwin.fcntl(lockFD, F_SETLK, &lock)
            _ = Darwin.close(lockFD)
            _ = Darwin.close(directoryFD)
        }
        guard Darwin.fcntl(lockFD, F_SETLK, &lock) == 0 else {
            throw SafetyError("Another Finalize owns this session directory")
        }
        let recovery = folder.appendingPathComponent(".photocull-recovery.json")
        guard !pathExists(recovery) else {
            throw SafetyError("Manual recovery required; inspect \(recovery.path)")
        }
        let sidecar = folder.appendingPathComponent(Session.fileName)
        let sidecarBytes = try? Data(contentsOf: sidecar)
        let archiveFolder = URL(fileURLWithPath: PCConfig.expandHome(cfg.paths.archive))
            .appendingPathComponent(date)
        let dumpFolder = dumpOverride
            ?? URL(fileURLWithPath: PCConfig.expandHome(cfg.paths.dump)).appendingPathComponent(date)

        let (pairs, orphanRAWs) = try FilePairs.scan(folder: folder,
                                                     jpgExts: cfg.jpgExtSet,
                                                     rawExts: cfg.rawExtSet)
        let session = try Session.load(folder: folder, strict: true)
        try verifySidecar(sidecar, expected: sidecarBytes)
        try validateOutputs(input: folder, archive: archiveFolder, dump: dumpFolder, dumpEnabled: dump)
        let identities = try (pairs.flatMap { [$0.jpg] + ($0.raw.map { [$0] } ?? []) } + orphanRAWs)
            .reduce(into: [String: FileIdentity]()) { $0[$1.lastPathComponent] = try FileIdentity.read($1) }

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
        let recoveryJSON = try JSONSerialization.data(withJSONObject: [
            "invocation": UUID().uuidString, "date": date,
            "sources": identities.mapValues(\.description),
            "archive": archiveFolder.path, "dump": dumpFolder.path
        ], options: [.sortedKeys])
        guard recoveryJSON.withUnsafeBytes({ raw in
            recovery.withUnsafeFileSystemRepresentation { path in
                guard let path, let bytes = raw.baseAddress else { return false }
                let fd = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
                guard fd >= 0 else { return false }
                defer { _ = Darwin.close(fd) }
                return Darwin.write(fd, bytes, raw.count) == raw.count && Darwin.fsync(fd) == 0
            }
        }) else { throw SafetyError("Could not exclusively create recovery record at \(recovery.path)") }
        var firstFailure: Error?
        loop: for plan in plans {
            try verifySidecar(sidecar, expected: sidecarBytes)
            try verifyIdentity(plan.jpg, identities[plan.jpg.lastPathComponent])
            if let raw = plan.raw { try verifyIdentity(raw, identities[raw.lastPathComponent]) }
            switch plan.kind {
            case .reject:
                if let syntheticTrash { try syntheticTrash(plan.jpg) } else { try trash(plan.jpg) }
                trashed += 1
                if let raw = plan.raw {
                    if let syntheticTrash { try syntheticTrash(raw) } else { try trash(raw) }
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

        try verifySidecar(sidecar, expected: sidecarBytes)
        let removed = cleanupSessionFolder(folder)
        _ = unlinkPath(recovery)

        return FinalizeResult(sessions: 1, archived: archived, trashed: trashed,
                              dumped: dumped, cropped: cropped, dumpFolder: dumpFolder.path,
                              retainedFolders: removed ? [] : [folder.path])
    }

    /// Best-effort cleanup: preserve decisions whenever residual entries are
    /// visible (including hidden files, directories and alternate originals).
    /// A failed listing also retains the sidecar. This check is NOT an ownership
    /// lock: a concurrent writer arriving after it may lose the sidecar,
    /// but rmdir below can never recursively delete that writer's files.
    @discardableResult
    package static func cleanupSessionFolder(_ folder: URL) -> Bool {
        removeEmptyDirectory(folder)
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
            total.retainedFolders += r.retainedFolders
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

    /// Fail closed if native Trash rejects the operation; never fall back to ~/.Trash.
    static func trash(_ url: URL) throws {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
    }

    /// Absolute inbox folder URL for a validated single path component.
    static func inboxFolder(cfg: PCConfig, date: String) throws -> URL {
        try validateDate(date)
        return URL(fileURLWithPath: PCConfig.expandHome(cfg.paths.inbox)).appendingPathComponent(date)
    }

    private struct SafetyError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    private struct FileIdentity: CustomStringConvertible {
        let device: UInt64, inode: UInt64, size: Int64, modified: Int64
        var description: String { "dev=\(device),ino=\(inode),size=\(size),mtime=\(modified)" }
        static func read(_ url: URL) throws -> FileIdentity {
            var st = stat()
            let result = url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return -1 }
                return Int(Darwin.lstat(path, &st))
            }
            guard result == 0, (st.st_mode & S_IFMT) == S_IFREG else {
                throw SafetyError("Selected original is not a regular non-symlink file: \(url.path)")
            }
            return FileIdentity(device: UInt64(st.st_dev), inode: UInt64(st.st_ino),
                                size: Int64(st.st_size), modified: Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec))
        }
    }

    private static func validateDate(_ date: String) throws {
        guard !date.isEmpty, date != ".", date != "..", !date.contains("/"), !date.contains("\\"),
              URL(fileURLWithPath: date).lastPathComponent == date else {
            throw SafetyError("Date must be one nonempty path component")
        }
    }

    private static func validateInputFolder(_ folder: URL) throws {
        var st = stat()
        guard folder.withUnsafeFileSystemRepresentation({ $0.map { Darwin.lstat($0, &st) } ?? -1 }) == 0,
              (st.st_mode & S_IFMT) == S_IFDIR else {
            throw SafetyError("Inbox session must be a real, non-symlink directory: \(folder.path)")
        }
    }

    private static func canonical(_ url: URL) -> URL { url.resolvingSymlinksInPath().standardizedFileURL }
    private static func contains(_ parent: URL, _ child: URL) -> Bool {
        child.path == parent.path || child.path.hasPrefix(parent.path.hasSuffix("/") ? parent.path : parent.path + "/")
    }
    private static func validateOutputs(input: URL, archive: URL, dump: URL, dumpEnabled: Bool) throws {
        let src = canonical(input)
        for output in dumpEnabled ? [archive, dump] : [archive] {
            let dst = canonical(output)
            if contains(src, dst) || contains(dst, src) {
                throw SafetyError("Output folder overlaps the input session: \(output.path)")
            }
        }
    }

    private static func pathExists(_ url: URL) -> Bool {
        var st = stat()
        return url.withUnsafeFileSystemRepresentation { $0.map { Darwin.lstat($0, &st) == 0 } ?? false }
    }
    @discardableResult private static func unlinkPath(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { $0.map { Darwin.unlink($0) == 0 } ?? false }
    }
    private static func posixError(_ action: String) -> Error {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "\(action): \(String(cString: strerror(errno)))"])
    }
    private static func verifyIdentity(_ url: URL, _ planned: FileIdentity?) throws {
        guard let planned, try FileIdentity.read(url).description == planned.description else {
            throw SafetyError("Selected original changed after planning: \(url.path)")
        }
    }
    private static func verifySidecar(_ url: URL, expected: Data?) throws {
        let actual = try? Data(contentsOf: url)
        guard actual == expected else { throw SafetyError("Session sidecar changed during Finalize; preserved at \(url.path)") }
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

    /// Native exports run on a small GCD queue, never by blocking a Swift task
    /// waiting for cooperative executor work. Two jobs is conservative policy,
    /// not a measured throughput optimum.
    private static func exportAllParallel(jobs: [ExportJob]) -> [ExportOutcome] {
        guard !jobs.isEmpty else { return [] }
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = min(2, ProcessInfo.processInfo.activeProcessorCount)
        let lock = NSLock()
        var outcomes = Array<ExportOutcome?>(repeating: nil, count: jobs.count)
        var stopped = false
        for (index, job) in jobs.enumerated() {
            queue.addOperation {
                lock.lock(); let shouldStop = stopped; lock.unlock()
                guard !shouldStop, let stage = job.stage else {
                    lock.lock(); outcomes[index] = ExportOutcome(error: ExportOutcomeMissing()); lock.unlock()
                    return
                }
                do {
                    try autoreleasepool {
                        try ImagePipeline.export(src: job.src, crop: job.crop, to: stage,
                                                 quality: 0.9, tilt: job.tilt,
                                                 quarterTurns: job.turns)
                    }
                    lock.lock(); outcomes[index] = ExportOutcome(error: nil); lock.unlock()
                } catch {
                    unlinkOwnedFile(stage)
                    lock.lock(); stopped = true; outcomes[index] = ExportOutcome(error: error); lock.unlock()
                }
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        return outcomes.map { $0 ?? ExportOutcome(error: ExportOutcomeMissing()) }
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

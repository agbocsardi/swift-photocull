import Foundation
import Darwin

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

public enum CropExportMode: String, Sendable, CaseIterable {
    case original, applyCrop
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
    public static func summary(cfg: PCConfig, date: String) throws -> FinalizeStats {
        let input = try FinalizeDirectory(inboxFolder(cfg: cfg, date: date))
        let sidecar = try FinalizeSidecar.capture(input)
        let session = try sidecar.session()
        try input.verifyVisible()
        let (pairs, _) = try FilePairs.scan(folder: input.url, jpgExts: cfg.jpgExtSet, rawExts: cfg.rawExtSet)
        try sidecar.verify(input)
        var keep = 0, reject = 0, undecided = 0, keepRAW = 0, rejectRAW = 0
        for pair in pairs {
            switch session.get(pair.stem) {
            case .keep: keep += 1; if pair.hasRAW { keepRAW += 1 }
            case .reject: reject += 1; if pair.hasRAW { rejectRAW += 1 }
            case .undecided: undecided += 1
            }
        }
        return FinalizeStats(date: date, keep: keep, reject: reject, undecided: undecided,
                             keepRAW: keepRAW, rejectRAW: rejectRAW)
    }

    @discardableResult
    public static func run(cfg: PCConfig, date: String, dump: Bool,
                           cropMode: CropExportMode, dumpOverride: URL?) throws -> FinalizeResult {
        try run(cfg: cfg, date: date, dump: dump, cropMode: cropMode, dumpOverride: dumpOverride,
                hooks: FinalizeHooks())
    }

    package static func run(cfg: PCConfig, date: String, dump: Bool,
                            cropMode: CropExportMode, dumpOverride: URL?,
                            syntheticTrash: ((URL) throws -> Void)?) throws -> FinalizeResult {
        try run(cfg: cfg, date: date, dump: dump, cropMode: cropMode, dumpOverride: dumpOverride,
                hooks: FinalizeHooks(trash: syntheticTrash.map { handler in { url in try handler(url); return nil } }))
    }

    package static func run(cfg: PCConfig, date: String, dump: Bool,
                            cropMode: CropExportMode, dumpOverride: URL?,
                            hooks: FinalizeHooks) throws -> FinalizeResult {
        // Foreground work assertion; this option still allows idle system sleep.
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                             reason: "PhotoCull finalize in progress")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let input = try FinalizeDirectory(inboxFolder(cfg: cfg, date: date), lock: true)
        // Finished OperationQueue closures may retain descriptors past return; ownership ends here, after drain.
        defer { input.releaseLock() }
        // Only ENOENT means no record. Dangling links, unreadable records and directories block retries.
        var st = stat()
        if fstatat(input.fd, FinalizeRecovery.name, &st, AT_SYMLINK_NOFOLLOW) == 0 {
            throw FinalizeSafetyError("Manual recovery required; inspect \(input.currentPath)/\(FinalizeRecovery.name)")
        }
        guard errno == ENOENT else { throw finalizePOSIX("inspect recovery record") }
        try input.verifyVisible()
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: input.url.path)
            .filter { $0.hasPrefix(".photocull-claims-") }
        guard leftovers.isEmpty else {
            throw FinalizeSafetyError("Manual recovery required; retained claims in \(input.currentPath): \(leftovers.joined(separator: ", "))")
        }
        try input.verifyVisible()
        let sidecar = try FinalizeSidecar.capture(input)
        let session = try sidecar.session()
        try input.verifyVisible()
        let (pairs, orphans) = try FilePairs.scan(folder: input.url, jpgExts: cfg.jpgExtSet, rawExts: cfg.rawExtSet)
        let sources = pairs.flatMap { [$0.jpg] + ($0.raw.map { [$0] } ?? []) } + orphans
        let identities = try sources.reduce(into: [String: FinalizeIdentity]()) {
            $0[$1.lastPathComponent] = try input.readIdentity($1.lastPathComponent)
        }
        try sidecar.verify(input)
        let archiveURL = canonical(URL(fileURLWithPath: PCConfig.expandHome(cfg.paths.archive)).appendingPathComponent(date))
        let dumpURL = canonical(dumpOverride ?? URL(fileURLWithPath: PCConfig.expandHome(cfg.paths.dump)).appendingPathComponent(date))
        try validateOutputs(input: input.url, outputs: dump ? [archiveURL, dumpURL] : [archiveURL])
        let fm = FileManager.default
        try fm.createDirectory(at: archiveURL, withIntermediateDirectories: true)
        if dump { try fm.createDirectory(at: dumpURL, withIntermediateDirectories: true) }
        let archive = try FinalizeDirectory(archiveURL)
        let output = dump ? try FinalizeDirectory(dumpURL) : nil
        try validateOutputs(input: input.url, outputs: dump ? [archive.url, output!.url] : [archive.url])

        // Phase 1: one destination inventory and pair-consistent in-run reservations.
        var reservations = Set<String>(), inventoried = Set<String>()
        for dir in dump ? [archiveURL, dumpURL] : [archiveURL] {
            if inventoried.insert(dir.path).inserted { reservations.formUnion(try destinationReservations(in: dir)) }
        }
        var plans: [Plan] = [], jobs: [ExportJob] = []
        for pair in pairs {
            var kind = Plan.Kind.clone, dumpDst: URL?
            if session.get(pair.stem) == .reject { kind = .reject }
            else if dump {
                let dst = reserveDestination(for: pair.jpg, in: dumpURL, reservations: &reservations)
                let crop = cropMode == .applyCrop ? session.crop(for: pair.stem) : nil
                let tilt = cropMode == .applyCrop ? session.tilt(for: pair.stem) : 0
                let turns = cropMode == .applyCrop ? session.quarterTurns(for: pair.stem) : 0
                if !(crop?.isFullFrame ?? true) || tilt != 0 || turns != 0 {
                    kind = .export(jobs.count)
                    jobs.append(ExportJob(src: pair.jpg, dst: dst, crop: crop, tilt: tilt, turns: turns))
                } else { dumpDst = dst }
            }
            var jpgDst: URL?, rawDst: URL?
            if case .reject = kind {} else if let raw = pair.raw {
                let destinations = reservePair(jpg: pair.jpg, raw: raw, in: archiveURL, reservations: &reservations)
                jpgDst = destinations.jpg; rawDst = destinations.raw
            } else { jpgDst = reserveDestination(for: pair.jpg, in: archiveURL, reservations: &reservations) }
            plans.append(Plan(kind: kind, jpg: pair.jpg, raw: pair.raw, dumpDst: dumpDst, jpgDst: jpgDst, rawDst: rawDst))
        }
        let orphanPlans = orphans.map { ($0, reserveDestination(for: $0, in: archiveURL, reservations: &reservations)) }
        let invocation = UUID().uuidString
        let claims = try input.privateDirectory(".photocull-claims-\(invocation)-")
        var record: FinalizeRecovery?
        // Never recursively clean claims. An empty-only attempt before a record exists is harmless.
        defer { if record == nil { try? input.removeEmptyChild(claims) } }
        var exportDirectory: FinalizeDirectory?
        defer {
            if let stage = exportDirectory {
                // Only export outputs belong to this cleanup, never claimed originals.
                for index in jobs.indices { try? stage.unlink(String(index)) }
                try? output?.removeEmptyChild(stage)
            }
        }
        if !jobs.isEmpty {
            let stage = try output!.privateDirectory(".photocull-stage-")
            exportDirectory = stage
            for i in jobs.indices { jobs[i].stage = stage.url.appendingPathComponent(String(i)) }
        }
        try hooks.boundary?("planned", input.url)
        // Phase 2: fixed-width native workers; drain started jobs after failure.
        let outcomes = exportAllParallel(jobs: jobs, input: input, identities: identities, output: output,
                                         stage: exportDirectory, hooks: hooks)
        var recoveryPlans: [[String: Any]] = []
        for plan in plans {
            let dumpDestination: URL?
            if case .export(let i) = plan.kind { dumpDestination = jobs[i].dst } else { dumpDestination = plan.dumpDst }
            for (src, dst) in [(Optional(plan.jpg), plan.jpgDst), (plan.raw, plan.rawDst)] {
                guard let src else { continue }
                let action: String
                if case .reject = plan.kind { action = "native Trash" } else { action = "archive" }
                recoveryPlans.append(try recoveryPlan(src, claim: claims.url.appendingPathComponent(src.lastPathComponent),
                                                       destination: dst, dump: src == plan.jpg ? dumpDestination : nil,
                                                       action: action, identity: identities[src.lastPathComponent]!))
            }
        }
        for (raw, dst) in orphanPlans {
            recoveryPlans.append(try recoveryPlan(raw, claim: claims.url.appendingPathComponent(raw.lastPathComponent),
                                                   destination: dst, dump: nil, action: "archive orphan", identity: identities[raw.lastPathComponent]!))
        }
        try sidecar.verify(input); try archive.verifyVisible(); try output?.verifyVisible()
        do { record = try FinalizeRecovery(directory: input, claims: claims, invocation: invocation, plans: recoveryPlans) }
        catch { throw FinalizeSafetyError("Recovery preparation failed: \(error.localizedDescription); inspect \(input.currentPath)/\(FinalizeRecovery.name) and \(claims.currentPath). No source has been claimed.") }
        var archived = 0, trashed = 0, dumped = 0, cropped = 0
        do {
            // Phase 3 is serial. A failing pair can retain a completed dump/JPG prefix.
            for plan in plans {
                // An unstarted job receives the original observed encode error, not a placeholder.
                if case .export(let i) = plan.kind, let error = outcomes[i].error { throw error }
                try sidecar.verify(input)
                try claim([plan.jpg] + (plan.raw.map { [$0] } ?? []), input: input, claims: claims,
                          identities: identities, sidecar: sidecar, hooks: hooks)
                switch plan.kind {
                case .reject:
                    for src in [plan.jpg] + (plan.raw.map { [$0] } ?? []) {
                        try hooks.boundary?(src == plan.jpg ? "rejectJPG" : "rejectRAW", claims.url.appendingPathComponent(src.lastPathComponent))
                        try verifyOwned(src, claims: claims, input: input, expected: identities[src.lastPathComponent]!)
                        let owned = claims.url.appendingPathComponent(src.lastPathComponent)
                        let destination: URL?
                        if let handler = hooks.trash { destination = try handler(owned) }
                        else { destination = try trash(owned) }
                        trashed += 1
                        try record!.completed(src, at: destination, action: "Trash")
                    }
                    continue
                case .clone:
                    if let dst = plan.dumpDst {
                        try hooks.boundary?("dumpCopy", dst)
                        try copyClaimed(plan.jpg, to: output!, destination: dst, claims: claims,
                                        input: input, expected: identities[plan.jpg.lastPathComponent]!, hooks: hooks)
                        dumped += 1
                        try record!.completed(plan.jpg, at: dst, action: "dump copy")
                    }
                case .export(let i):
                    try hooks.boundary?("editedPromotion", jobs[i].dst)
                    try verifyOwned(plan.jpg, claims: claims, input: input, expected: identities[plan.jpg.lastPathComponent]!)
                    try output!.verifyVisible(); try exportDirectory!.verifyVisible()
                    try exportDirectory!.move(String(i), to: output!, name: jobs[i].dst.lastPathComponent)
                    dumped += 1; cropped += 1
                    try record!.completed(plan.jpg, at: jobs[i].dst, action: "edited dump")
                }
                for (src, dst, phase) in [(Optional(plan.jpg), plan.jpgDst, "archiveJPG"), (plan.raw, plan.rawDst, "archiveRAW")] {
                    guard let src, let dst else { continue }
                    try hooks.boundary?(phase, dst)
                    try archiveClaimed(src, to: archive, destination: dst, claims: claims, input: input,
                                       expected: identities[src.lastPathComponent]!, hooks: hooks)
                    archived += 1
                    try record!.completed(src, at: dst, action: "archive")
                }
            }
            for (raw, dst) in orphanPlans {
                try sidecar.verify(input)
                try claim([raw], input: input, claims: claims, identities: identities, sidecar: sidecar, hooks: hooks)
                try hooks.boundary?("orphan", dst)
                try archiveClaimed(raw, to: archive, destination: dst, claims: claims, input: input,
                                   expected: identities[raw.lastPathComponent]!, hooks: hooks)
                archived += 1
                try record!.completed(raw, at: dst, action: "archive orphan")
            }
            try sidecar.verify(input)
            try hooks.boundary?("recordRemoval", input.url.appendingPathComponent(FinalizeRecovery.name))
            try record!.removeOwned()
            try input.removeEmptyChild(claims)
            try input.verifyVisible()
            let removed = cleanupSessionFolder(input.url)
            return FinalizeResult(sessions: 1, archived: archived, trashed: trashed, dumped: dumped,
                                  cropped: cropped, dumpFolder: dumpURL.path,
                                  retainedFolders: removed ? [] : [input.currentPath])
        } catch {
            throw FinalizeSafetyError("Finalize stopped: \(error.localizedDescription). Completed prefix may remain. Manual inspect/repair: record \(input.currentPath)/\(FinalizeRecovery.name); claims \(claims.currentPath); archive \(archive.currentPath); dump \(output?.currentPath ?? "disabled"). Do not retry before inspecting these locations.")
        }
    }

    private static func recoveryPlan(_ src: URL, claim: URL, destination: URL?, dump: URL?, action: String,
                                     identity: FinalizeIdentity) throws -> [String: Any] {
        ["original": src.path, "claim": claim.path, "archive": destination?.path ?? "", "dump": dump?.path ?? "",
         "action": action, "identity": try JSONSerialization.jsonObject(with: JSONEncoder().encode(identity))]
    }

    private static func claim(_ sources: [URL], input: FinalizeDirectory, claims: FinalizeDirectory,
                              identities: [String: FinalizeIdentity], sidecar: FinalizeSidecar, hooks: FinalizeHooks) throws {
        var moved: [String] = []
        do {
            for src in sources {
                try hooks.boundary?("beforeClaim", src)
                try sidecar.verify(input); try claims.verifyVisible()
                try input.move(src.lastPathComponent, to: claims, name: src.lastPathComponent)
                moved.append(src.lastPathComponent)
            }
            // Both members must be claimed AND match the plan before either has effects.
            for src in sources { try claims.verify(src.lastPathComponent, identities[src.lastPathComponent]!) }
            try hooks.boundary?("claimed", claims.url)
            try sidecar.verify(input)
        } catch {
            // Restore every claimed object without overwriting an externally recreated source name.
            var retained: [String] = []
            for name in moved.reversed() {
                do { try claims.move(name, to: input, name: name) }
                catch { retained.append("\(claims.currentPath)/\(name)") }
            }
            throw FinalizeSafetyError("Claim failed: \(error.localizedDescription); retained claims: \(retained.joined(separator: ", "))")
        }
    }

    private static func verifyOwned(_ src: URL, claims: FinalizeDirectory, input: FinalizeDirectory,
                                    expected: FinalizeIdentity) throws {
        try input.verifyVisible(); try claims.verifyVisible()
        try claims.verify(src.lastPathComponent, expected)
    }
    private static func copyClaimed(_ src: URL, to output: FinalizeDirectory, destination: URL,
                                    claims: FinalizeDirectory, input: FinalizeDirectory,
                                    expected: FinalizeIdentity, hooks: FinalizeHooks) throws {
        try verifyOwned(src, claims: claims, input: input, expected: expected); try output.verifyVisible()
        let stage = try output.privateDirectory(".photocull-stage-")
        defer { try? stage.unlink("copy"); try? output.removeEmptyChild(stage) }
        try hooks.boundary?("copy", stage.url.appendingPathComponent("copy"))
        try verifyOwned(src, claims: claims, input: input, expected: expected)
        try output.verifyVisible(); try stage.verifyVisible()
        try FileManager.default.copyItem(at: claims.url.appendingPathComponent(src.lastPathComponent), to: stage.url.appendingPathComponent("copy"))
        try verifyOwned(src, claims: claims, input: input, expected: expected)
        let copied = try stage.readIdentity("copy")
        guard copied.size == expected.size else { throw FinalizeSafetyError("Incomplete claimed copy") }
        try hooks.boundary?("copyPromotion", destination)
        try verifyOwned(src, claims: claims, input: input, expected: expected)
        try stage.verifyVisible(); try output.verifyVisible()
        try stage.move("copy", to: output, name: destination.lastPathComponent)
    }
    private static func archiveClaimed(_ src: URL, to output: FinalizeDirectory, destination: URL,
                                       claims: FinalizeDirectory, input: FinalizeDirectory,
                                       expected: FinalizeIdentity, hooks: FinalizeHooks) throws {
        try verifyOwned(src, claims: claims, input: input, expected: expected); try output.verifyVisible()
        do { try claims.move(src.lastPathComponent, to: output, name: destination.lastPathComponent) }
        catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EXDEV) {
            // Cross-volume archive: promote a private destination-volume copy before unlinking ownership.
            try copyClaimed(src, to: output, destination: destination, claims: claims, input: input,
                            expected: expected, hooks: hooks)
            try verifyOwned(src, claims: claims, input: input, expected: expected)
            try claims.unlink(src.lastPathComponent)
        }
    }

    /// Keep every sidecar and residual entry. Only an actually empty directory may disappear.
    @discardableResult package static func cleanupSessionFolder(_ folder: URL) -> Bool { removeEmptyDirectory(folder) }
    @discardableResult package static func removeEmptyDirectory(_ folder: URL) -> Bool { Darwin.rmdir(folder.path) == 0 }

    @discardableResult
    public static func runMulti(cfg: PCConfig, dates: [String], dump: Bool, cropMode: CropExportMode) throws -> FinalizeResult {
        var total = FinalizeResult(sessions: 0, archived: 0, trashed: 0, dumped: 0, cropped: 0, dumpFolder: "")
        guard !dates.isEmpty else { return total }
        for date in dates { try FinalizeDirectory.basename(date) }
        let folder = URL(fileURLWithPath: PCConfig.expandHome(cfg.paths.dump)).appendingPathComponent(dumpFolderName(dates: dates))
        for date in dates {
            let result = try run(cfg: cfg, date: date, dump: dump, cropMode: cropMode, dumpOverride: dump ? folder : nil)
            total.sessions += result.sessions; total.archived += result.archived; total.trashed += result.trashed
            total.dumped += result.dumped; total.cropped += result.cropped; total.retainedFolders += result.retainedFolders
        }
        total.dumpFolder = folder.path
        return total
    }
    static func dumpFolderName(dates: [String]) -> String {
        let sorted = dates.sorted()
        guard let first = sorted.first else { return "" }
        return sorted.count > 1 ? first + " to " + sorted.last! : first
    }
    @discardableResult static func trash(_ url: URL) throws -> URL? {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }
    static func inboxFolder(cfg: PCConfig, date: String) throws -> URL {
        try FinalizeDirectory.basename(date)
        // Root aliases are permitted; the date component itself must never be a symlink.
        return canonical(URL(fileURLWithPath: PCConfig.expandHome(cfg.paths.inbox))).appendingPathComponent(date)
    }
    private static func canonical(_ url: URL) -> URL {
        // Preserve native canonical /private/tmp spelling; Foundation standardization aliases it to /tmp.
        var ancestor = url, suffix: [String] = []
        while ancestor.path != "/" {
            var st = stat()
            if lstat(ancestor.path, &st) == 0 { break }
            guard errno == ENOENT else { return url }
            suffix.insert(ancestor.lastPathComponent, at: 0)
            ancestor = ancestor.deletingLastPathComponent()
        }
        guard let resolved = realpath(ancestor.path, nil) else { return url }
        defer { free(resolved) }
        return suffix.reduce(URL(fileURLWithPath: String(cString: resolved))) { $0.appendingPathComponent($1) }
    }
    private static func validateOutputs(input: URL, outputs: [URL]) throws {
        let src = canonical(input).path
        for output in outputs {
            let dst = canonical(output).path
            if src == dst || dst.hasPrefix(src + "/") || src.hasPrefix(dst + "/") {
                throw FinalizeSafetyError("Output folder overlaps input: \(output.path)")
            }
        }
    }
    private struct Plan {
        enum Kind { case reject, clone, export(Int) }
        let kind: Kind
        let jpg: URL, raw: URL?, dumpDst: URL?, jpgDst: URL?, rawDst: URL?
    }
    private struct ExportJob: Sendable {
        let src: URL, dst: URL
        var stage: URL?
        let crop: CropRect?
        let tilt: Double
        let turns: Int
    }
    private struct ExportOutcome { let error: Error? }
    private final class ExportWork: @unchecked Sendable {
        private let lock = NSLock()
        private var next = 0
        private var errors: [Int: Error] = [:]
        private var completed = Set<Int>()
        func admit(count: Int) -> Int? {
            lock.lock(); defer { lock.unlock() }
            guard errors.isEmpty, next < count else { return nil }
            let index = next; next += 1; return index
        }
        func finish(_ index: Int, error: Error?) {
            lock.lock(); defer { lock.unlock() }
            completed.insert(index)
            if let error { errors[index] = error }
        }
        func outcomes(count: Int) -> [ExportOutcome] {
            lock.lock(); defer { lock.unlock() }
            let first = errors.keys.min().flatMap { errors[$0] }
            return (0..<count).map { ExportOutcome(error: errors[$0] ?? (completed.contains($0) ? nil : first)) }
        }
    }
    private static func exportAllParallel(jobs: [ExportJob], input: FinalizeDirectory,
                                          identities: [String: FinalizeIdentity], output: FinalizeDirectory?,
                                          stage: FinalizeDirectory?, hooks: FinalizeHooks) -> [ExportOutcome] {
        guard !jobs.isEmpty else { return [] }
        let work = ExportWork(), queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        let width = max(1, min(2, ProcessInfo.processInfo.activeProcessorCount))
        queue.maxConcurrentOperationCount = width
        // Only width worker operations exist; pending native jobs stop being admitted on observed failure.
        for _ in 0..<width {
            queue.addOperation {
                while let index = work.admit(count: jobs.count) {
                    let job = jobs[index]
                    do {
                        try autoreleasepool {
                            try hooks.boundary?("export", job.src)
                            try input.verifyVisible(); try output?.verifyVisible(); try stage?.verifyVisible()
                            try input.verify(job.src.lastPathComponent, identities[job.src.lastPathComponent]!)
                            try ImagePipeline.export(src: job.src, crop: job.crop, to: job.stage!, quality: 0.9,
                                                     tilt: job.tilt, quarterTurns: job.turns)
                            try input.verifyVisible(); try input.verify(job.src.lastPathComponent, identities[job.src.lastPathComponent]!)
                        }
                        work.finish(index, error: nil)
                    } catch {
                        work.finish(index, error: error)
                        try? hooks.boundary?("exportFailed", job.src)
                    }
                }
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        return work.outcomes(count: jobs.count)
    }

    private static func reservationKey(for url: URL) -> String {
        url.deletingLastPathComponent().standardizedFileURL.path + "/" + url.lastPathComponent.uppercased()
    }
    private static func destinationReservations(in dir: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: dir.path).map { reservationKey(for: dir.appendingPathComponent($0)) })
    }
    private static func reserveDestination(for src: URL, in dir: URL, reservations: inout Set<String>) -> URL {
        var suffix = 1
        while true {
            let candidate = named(src, in: dir, suffix: suffix)
            if reservations.insert(reservationKey(for: candidate)).inserted { return candidate }
            suffix += 1
        }
    }
    private static func named(_ src: URL, in dir: URL, suffix: Int) -> URL {
        let ext = src.pathExtension, base = src.lastPathComponent
        let stem = ext.isEmpty ? base : String(base.dropLast(ext.count + 1))
        return dir.appendingPathComponent(suffix == 1 ? base : (ext.isEmpty ? "\(stem)_\(suffix)" : "\(stem)_\(suffix).\(ext)"))
    }
    private static func reservePair(jpg: URL, raw: URL, in dir: URL, reservations: inout Set<String>) -> (jpg: URL, raw: URL) {
        var suffix = 1
        while true {
            let jpgDst = named(jpg, in: dir, suffix: suffix), rawDst = named(raw, in: dir, suffix: suffix)
            let jpgKey = reservationKey(for: jpgDst), rawKey = reservationKey(for: rawDst)
            if !reservations.contains(jpgKey), !reservations.contains(rawKey) {
                reservations.insert(jpgKey); reservations.insert(rawKey); return (jpgDst, rawDst)
            }
            suffix += 1
        }
    }
    static func collisionFreeDestination(for src: URL, in dir: URL) -> URL {
        var reservations = (try? destinationReservations(in: dir)) ?? []
        return reserveDestination(for: src, in: dir, reservations: &reservations)
    }
}

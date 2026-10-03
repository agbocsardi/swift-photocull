import Foundation
import Darwin
import CoreGraphics
import PhotoCullCore

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func with<R>(_ f: (inout T) -> R) -> R { lock.lock(); defer { lock.unlock() }; return f(&value) }
}
private final class Gate: @unchecked Sendable {
    private let state = Box((entered: false, released: false))
    private let semaphore = DispatchSemaphore(value: 0)
    func hold() {
        precondition(!Thread.isMainThread, "native work ran on MainActor/main thread")
        state.with { $0.entered = true }
        guard semaphore.wait(timeout: .now() + 20) == .success else { fatalError("native gate timeout") }
    }
    var entered: Bool { state.with { $0.entered } }
    func release() {
        let first = state.with { value -> Bool in
            if value.released { return false }; value.released = true; return true
        }
        if first { semaphore.signal() }
    }
}
@MainActor private var checks = 0
@MainActor private func expect(_ value: Bool, _ reason: String) {
    checks += 1
    if !value { fatalError("FinalizeOperation CHECK \(checks): \(reason)") }
}
@MainActor private func until(_ reason: String, _ predicate: () -> Bool) async {
    let deadline = Date().addingTimeInterval(20)
    while !predicate() {
        if Date() > deadline { fatalError("timeout: \(reason)") }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}

@MainActor private func operationChecks() async throws {
    guard let path = ProcessInfo.processInfo.environment["PC_FINALIZE_TEST_OUT"], path.hasPrefix("/") else {
        fatalError("Explicit PC_FINALIZE_TEST_OUT required")
    }
    let out = URL(fileURLWithPath: path), fm = FileManager.default
    let root = out.appendingPathComponent("synthetic/app-\(UUID().uuidString)")
    precondition(root.path.hasPrefix(out.path + "/"))
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    // Keep only generated artifacts for review. Every source/config/log/synthetic Trash is below root.
    var number = 0
    struct Fixture {
        let root: URL, input: URL, other: URL, archive: URL, dump: URL, trash: URL, source: URL, cfg: PCConfig
    }
    func jpeg(_ url: URL, _ r: CGFloat) throws {
        let ctx = CGContext(data: nil, width: 12, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: r, green: 0.2, blue: 0.3, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        try ImagePipeline.writeJPEG(ctx.makeImage()!, to: url, quality: 1)
    }
    func setup(count: Int = 3) throws -> Fixture {
        number += 1
        print("App fixture \(number)")
        let base = root.appendingPathComponent("case-\(number)")
        let input = base.appendingPathComponent("inbox/date"), other = base.appendingPathComponent("inbox/other")
        let archive = base.appendingPathComponent("archive/date"), dump = base.appendingPathComponent("dump/date")
        let trash = base.appendingPathComponent("trash"), source = base.appendingPathComponent("source")
        for dir in [input, other, archive, dump, trash, source] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        for (i, name) in ["A", "B", "C"].prefix(count).enumerated() {
            try jpeg(input.appendingPathComponent(name + ".JPG"), CGFloat(i + 1) / 4)
            try Data([UInt8(30 + i), UInt8(40 + i)]).write(to: input.appendingPathComponent(name + ".RAF"))
        }
        try jpeg(other.appendingPathComponent("Z.JPG"), 0.9)
        try Session.fresh().save(folder: input); try Session.fresh().save(folder: other)
        return Fixture(root: base, input: input, other: other, archive: archive, dump: dump, trash: trash, source: source,
                       cfg: PCConfig(paths: PathsConfig(inbox: base.appendingPathComponent("inbox").path,
                                                         archive: base.appendingPathComponent("archive").path,
                                                         dump: base.appendingPathComponent("dump").path),
                                     files: FilesConfig(rawExtensions: ["RAF"], jpgExtensions: ["JPG"])))
    }
    func data(_ dir: URL) throws -> Data { try Data(contentsOf: dir.appendingPathComponent(Session.fileName)) }
    func app(_ f: Fixture, hooks: AppState.OperationHooks? = nil) -> AppState {
        AppState(cfg: f.cfg, initializeAppearance: false, openInitialSession: false, operationHooks: hooks)
    }
    func syntheticTrash(_ f: Fixture, failRAW: Bool = false) -> (URL) throws -> URL? {
        { owned in
            precondition(owned.path.hasPrefix(f.input.path + "/.photocull-claims-"))
            let dst = f.trash.appendingPathComponent(owned.lastPathComponent)
            if failRAW && owned.pathExtension == "RAF" { try Data([250]).write(to: dst) }
            guard renameatx_np(AT_FDCWD, owned.path, AT_FDCWD, dst.path, UInt32(RENAME_EXCL)) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            return dst
        }
    }
    func ready(_ a: AppState) async {
        await until("summary ready") { !a.finalizeStats.isEmpty || a.errorMessage != nil }
        expect(a.errorMessage == nil && !a.finalizeStats.isEmpty, "strict preparation succeeds")
    }
    func blocked(_ a: AppState, _ f: Fixture) throws {
        let metadata = try data(f.input), otherBytes = try data(f.other)
        let active = a.activeDate, index = a.index, cursor = a.cursorDate, selected = a.selectedDates
        let crop = a.canvas.cropRect, tilt = a.canvas.cropTilt, cropMode = a.cropMode, aspect = a.cropAspect
        let decision = a.currentDecision, revision = a.revision, progress = a.ingestProgress, cards = a.detectedCards
        let owner = a.bulkOperation
        a.mark(.reject); a.clearDecision(); a.rotateQuarter(1); a.enterCropMode()
        a.commitCrop(); a.clearCrop(); a.cancelCrop(); a.resetCrop(); a.nudgeTilt(1); a.resetTilt(); a.cycleAspect(); a.applyAspect()
        a.undo(); a.redo(); a.setIndex(2); a.nav(.next); a.nav(.next, skipDecided: true)
        a.moveCursor(.next); a.cursorDate = "other"; a.openCursorSession(); a.open(date: "other"); a.loadCurrent(); a.reloadLibrary()
        a.toggleSelection("other"); a.clearSelection(); a.cycleFilter()
        a.beginIngest(); a.startIngest(); a.checkPairing(); a.repairPairingInteractive(); a.applyPairRepair()
        a.beginFinalize(date: "other"); a.beginGlobalFinalize()
        a.saveAndClose() // Must return BEFORE NSApp/window access.
        expect(!a.prepareForTermination() && !a.permitsTermination, "close/quit eligibility consults live owner")
        expect(a.bulkOperation == owner, "overlap calls cannot replace owner")
        expect(a.activeDate == active && a.index == index && a.cursorDate == cursor, "navigation frozen before mutation")
        expect(a.selectedDates == selected, "selection is unchanged")
        expect(a.canvas.cropRect == crop && a.canvas.cropTilt == tilt && a.cropMode == cropMode && a.cropAspect == aspect, "blocked crop functions keep drafts/UI intact")
        expect(a.currentDecision == decision && a.revision == revision, "blocked edit/undo/redo keep session state")
        expect(a.ingestProgress == progress && a.detectedCards == cards, "blocked ingest does not reset progress/detect cards")
        expect(try data(f.input) == metadata, "blocked operations preserve target sidecar bytes")
        expect(try data(f.other) == otherBytes, "non-active undo/overlap preserves other sidecar")
        expect(a.toast != "Crop saved" && a.toast != "Crop cleared", "blocked crop commit never falsely reports success")
    }

    // Real permissive AppState.open -> strict destructive entry: malformed/future bytes are never flushed away.
    for bad in ["{", "", "{\"version\":9,\"decisions\":{\"A\":\"reject\"}}"] {
        let f = try setup()
        let badBytes = Data(bad.utf8)
        try badBytes.write(to: f.input.appendingPathComponent(Session.fileName))
        let a = app(f); a.open(date: "date")
        expect(a.activeDate == "date" && a.pairs.count == 3, "permissive browsing still opens invalid sidecar")
        a.setIndex(1) // creates a pending persist timer; destructive preflight must cancel it before save.
        a.beginFinalizeCurrent()
        await until("strict app rejection") { a.bulkOperation == nil }
        expect(a.errorMessage != nil && a.modal == nil, "invalid preparation releases owner/sheet")
        try? await Task.sleep(nanoseconds: 650_000_000)
        expect(try data(f.input) == badBytes, "actual AppState entry preserves malformed/future bytes and cancels timer")
        expect(fm.fileExists(atPath: f.input.appendingPathComponent("A.JPG").path), "invalid app preparation has no effects")
    }
    // Crop drafts refuse destructive work, while ordinary browsing outside bulk retains its previous behavior.
    do {
        let f = try setup(), a = app(f)
        a.open(date: "date"); a.enterCropMode(); a.canvas.cropTilt = 3
        let crop = a.canvas.cropRect
        a.beginFinalizeCurrent(); a.beginGlobalFinalize(); a.startIngest(); a.applyPairRepair()
        expect(a.bulkOperation == nil && a.cropMode && a.canvas.cropTilt == 3 && a.canvas.cropRect == crop, "uncommitted draft blocks bulk without loss")
        expect(a.toast?.contains("crop draft") == true, "draft refusal gives feedback")
        a.setIndex(1)
        expect(a.index == 1 && !a.cropMode, "outside-bulk photo navigation remains compatible")
        a.enterCropMode(); a.open(date: "other")
        expect(a.activeDate == "other" && !a.cropMode, "outside-bulk session open remains compatible")
    }
    // Preparation owns confirmation; actual Core and post-native barriers exercise both live phases.
    do {
        let f = try setup(), core = Gate(), after = Gate()
        let hooks = AppState.OperationHooks(boundary: { event, _ in if event == "finalizeAfter" { after.hold() } },
            finalize: FinalizeHooks(boundary: { event, _ in if event == "planned" { core.hold() } }, trash: syntheticTrash(f)))
        let a = app(f, hooks: hooks)
        a.open(date: "other"); a.mark(.keep); a.open(date: "date") // undo target may be non-active.
        a.setIndex(1); a.selectedDates = ["date"]
        a.beginFinalizeCurrent(); await ready(a)
        expect(a.showingFinalizeSheet && a.bulkOperation != nil && !a.finalizeRunning, "confirmation retains preparation ownership")
        try blocked(a, f)
        a.confirmFinalize()
        await until("Core barrier entered") { core.entered }
        expect(a.finalizeRunning && a.modal == nil, "native execution owns files after sheet closes")
        try blocked(a, f)
        a.modal = .help; a.modal = nil
        expect(a.finalizeRunning, "modal replacement cannot cancel executing native run")
        a.confirmFinalize()
        let metadata = try data(f.input)
        try? await Task.sleep(nanoseconds: 650_000_000)
        expect(try data(f.input) == metadata, "persist timer cannot write during Core run")
        core.release()
        await until("native work returned, app completion held") { after.entered }
        expect(a.finalizeRunning && !a.permitsTermination, "owner lasts until native invocation actually returns")
        after.release()
        await until("Finalize success completion") { a.bulkOperation == nil }
        expect(a.errorMessage == nil && a.permitsTermination, "success releases common gate")
        expect(a.pairs.isEmpty && a.activeDate == "date", "success refresh reads actual retained metadata-only folder")
        expect(a.toast?.contains("retained:") == true, "completion surfaces retained session folder")
        expect((try fm.contentsOfDirectory(atPath: f.input.path)) == [Session.fileName], "success leaves no recovery/claim/lock files")
        expect((try fm.contentsOfDirectory(atPath: f.archive.path)).count == 6, "real native archive effects completed")
    }
    // Dismissal and late summary cannot overwrite a newer preparation, even with a different selected date set.
    do {
        let f = try setup(), old = Gate(), count = Box(0)
        let hooks = AppState.OperationHooks(boundary: { event, _ in
            if event == "summaryAfter", count.with({ $0 += 1; return $0 }) == 1 { old.hold() }
        })
        let a = app(f, hooks: hooks)
        a.open(date: "date"); a.beginFinalizeCurrent()
        await until("old summary held") { old.entered }
        a.modal = nil
        expect(a.bulkOperation == nil && a.finalizeStats.isEmpty, "dismissal invalidates pending preparation")
        a.selectedDates = ["other"]; a.beginGlobalFinalize(); await ready(a)
        let owner = a.bulkOperation
        expect(a.finalizeStats.map(\.date) == ["other"] && a.modal == .globalFinalize, "new preparation uses captured selected dates")
        old.release(); try? await Task.sleep(nanoseconds: 100_000_000)
        expect(a.bulkOperation == owner && a.finalizeStats.map(\.date) == ["other"] && a.modal == .globalFinalize, "late old summary cannot overwrite current confirmation")
        a.modal = .help
        expect(a.bulkOperation == nil && a.finalizeStats.isEmpty, "modal replacement invalidates only preparation")
        a.beginFinalize(date: "date")
        expect(a.modal == .help && a.bulkOperation == nil, "unrelated modal prevents preparation start")
        a.modal = nil
    }
    do {
        let f = try setup(count: 0), a = app(f)
        a.filter = .done
        a.beginGlobalFinalize()
        expect(a.bulkOperation == nil && a.modal == nil, "empty preparation releases cleanly")
    }
    // Confirmation uses captured dates/config/token, not later selection or mutable displayed stats.
    do {
        let f = try setup(count: 1), a = app(f, hooks: AppState.OperationHooks(finalize: FinalizeHooks(trash: syntheticTrash(f))))
        a.selectedDates = ["date", "other"]; a.beginGlobalFinalize(); await ready(a)
        expect(Set(a.finalizeStats.map(\.date)) == Set(["date", "other"]), "multi preparation captures selected dates")
        a.selectedDates = ["not-a-session"]
        a.finalizeStats = [FinalizeStats(date: "not-a-session", keep: 999, reject: 0, undecided: 0, keepRAW: 0, rejectRAW: 0)]
        a.confirmFinalize()
        await until("captured multi completion") { a.bulkOperation == nil }
        expect(a.errorMessage == nil, "confirmation cannot be redirected by changed selection/stats")
        expect(fm.fileExists(atPath: f.archive.appendingPathComponent("A.JPG").path), "captured first session archived")
        expect(fm.fileExists(atPath: f.root.appendingPathComponent("archive/other/Z.JPG").path), "captured second session archived")
        expect(a.toast?.contains("2 session(s)") == true && a.toast?.contains(f.input.path) == true && a.toast?.contains(f.other.path) == true, "multi completion aggregates retained folders")
    }
    // Both success and partial failure discard affected old Session/undo/redo references, not just active pointers.
    for failing in [false, true] {
        let f = try setup(), gate = Gate()
        let hooks = AppState.OperationHooks(finalize: FinalizeHooks(boundary: { event, _ in
            if event == "planned" { gate.hold() }
        }, trash: syntheticTrash(f, failRAW: failing)))
        let a = app(f, hooks: hooks)
        a.open(date: "date"); a.mark(.keep); a.rotateQuarter(1); a.undo() // affected undo AND redo entries.
        if failing {
            a.mark(.reject) // B; use the real app editor so outgoing flush cannot erase the fixture decision.
            a.rotateQuarter(1); a.undo() // also leave affected redo history for C.
        }
        let oldJPG = try Data(contentsOf: f.input.appendingPathComponent("B.JPG"))
        a.beginFinalizeCurrent(); await ready(a); a.confirmFinalize()
        await until("actual failing/success run held") { gate.entered }
        gate.release()
        await until("actual terminal completion") { a.bulkOperation == nil }
        if failing {
            expect(a.errorMessage?.contains("Manual inspect/repair") == true, "actual synthetic native reject error reported with recovery: \(a.errorMessage ?? "no error")")
            expect(a.pairs.map(\.stem) == ["C"], "failure refresh shows real partial filesystem, not stale pair list")
            expect(try Data(contentsOf: f.trash.appendingPathComponent("B.JPG")) == oldJPG, "failure prefix synthetic Trash marker exact")
            expect(fm.fileExists(atPath: f.input.appendingPathComponent(".photocull-recovery.json").path), "partial failure keeps retry blocker")
        } else { expect(a.errorMessage == nil, "success finishes without error") }
        let fresh = Session.fresh(); fresh.set("NEW", .keep); try fresh.save(folder: f.input)
        let replacement = try data(f.input)
        a.undo(); a.redo()
        try? await Task.sleep(nanoseconds: 650_000_000)
        expect(try data(f.input) == replacement, "terminal invalidation prevents stale undo/redo/timer writes into recreated session")
    }

    // Actual ingest native run; terminal callback cannot release ownership early or regress counts.
    do {
        let f = try setup(), after = Gate(), secondBefore = Gate()
        try jpeg(f.source.appendingPathComponent("X.JPG"), 0.7)
        try Data([201, 202, 203]).write(to: f.source.appendingPathComponent("X.RAF"))
        typealias Publisher = @Sendable (IngestProgress) -> Void
        let publishers = Box<[(UUID, Publisher)]>([]), starts = Box(0)
        let hooks = AppState.OperationHooks(boundary: { event, _ in
            if event == "ingestBefore" {
                let number = starts.with { $0 += 1; return $0 }
                if number == 2 { secondBefore.hold() }
            }
            if event == "ingestAfter", starts.with({ $0 }) == 1 { after.hold() }
        }, ingestPublisher: { token, publish in publishers.with { $0.append((token, publish)) } })
        let a = app(f, hooks: hooks); a.open(date: "date"); a.ingestSource = f.source.path
        a.startIngest()
        await until("actual ingest drained, return held") { after.entered }
        await until("queued ingest live progress") { a.ingestProgress.copied == 2 }
        expect(a.ingestProgress.running && !a.ingestProgress.done && a.bulkOperation != nil, "p.done callback is not authoritative gate release")
        try blocked(a, f)
        expect(starts.with { $0 } == 1, "startIngest reentry starts no second native invocation")
        let firstPublish = publishers.with { $0[0].1 }
        var regressing = a.ingestProgress; regressing.copied = 0; regressing.done = true
        firstPublish(regressing); try? await Task.sleep(nanoseconds: 50_000_000)
        expect(a.ingestProgress.copied == 2, "regressing actual-run callback rejected")
        after.release()
        await until("ingest authoritative completion") { a.bulkOperation == nil }
        let terminal = a.ingestProgress
        expect(terminal.done && !terminal.running && terminal.copied == 2 && terminal.total == 2 && terminal.error == nil, "authoritative success totals come from native result/callback collector")
        var late = terminal; late.copied = 999; late.total = 999; late.error = "stale"
        firstPublish(late); try? await Task.sleep(nanoseconds: 50_000_000)
        expect(a.ingestProgress == terminal, "post-terminal progress ignored")
        a.startIngest()
        await until("second ingest held before real work") { secondBefore.entered }
        firstPublish(late); try? await Task.sleep(nanoseconds: 50_000_000)
        expect(a.ingestProgress.copied == 0 && a.ingestProgress.error == nil, "old run UUID cannot publish into new ingest")
        secondBefore.release()
        await until("second ingest completion") { a.bulkOperation == nil }
        expect(a.ingestProgress.copied == 0 && a.ingestProgress.skipped == 2 && a.ingestProgress.total == 2, "new ingest authoritative skip totals correct")
        a.ingestSource = f.root.appendingPathComponent("missing-source").path
        a.startIngest()
        await until("actual ingest error completion") { a.bulkOperation == nil }
        expect(a.ingestProgress.done && !a.ingestProgress.running && a.ingestProgress.error != nil, "actual ingest error releases owner with terminal error")
        expect(a.permitsTermination, "ingest error restores termination eligibility")
    }

    // Repair runs off-main, flushes pending navigation before acquiring, and reloads after real rename.
    do {
        let f = try setup(), gate = Gate()
        try fm.removeItem(at: f.input.appendingPathComponent("A.RAF"))
        let raw = Data([211, 212]); try raw.write(to: f.input.appendingPathComponent("A_2.RAF"))
        let hooks = AppState.OperationHooks(boundary: { event, _ in if event == "repairBefore" { gate.hold() } },
                                            repairLogDirectory: f.root.appendingPathComponent("repair-logs"))
        let a = app(f, hooks: hooks); a.open(date: "date"); a.setIndex(2); a.applyPairRepair()
        await until("native repair held") { gate.entered }
        expect(try Session.load(folder: f.input).lastIndex == 2, "repair flushes pending index before native ownership")
        try blocked(a, f)
        gate.release()
        await until("repair completion") { a.bulkOperation == nil }
        expect(try Data(contentsOf: f.input.appendingPathComponent("A.RAF")) == raw, "real PairRepair moves exact generated RAW")
        expect(a.pairs.first?.hasRAW == true, "repair completion reloads actual pairs")
        expect((try fm.contentsOfDirectory(atPath: f.root.appendingPathComponent("repair-logs").path)).count == 1, "repair audit log confined to synthetic output")
    }
    // Native repair apply failure at a mutable destination retains every marker and releases ownership.
    do {
        let f = try setup(), gate = Gate()
        try fm.removeItem(at: f.input.appendingPathComponent("A.RAF"))
        let raw = Data([221, 222]); try raw.write(to: f.input.appendingPathComponent("A_2.RAF"))
        precondition(chmod(f.input.path, 0o500) == 0)
        defer { _ = chmod(f.input.path, 0o700) }
        // No active Session: avoid a pre-acquire flush masking the actual native apply failure.
        let hooks = AppState.OperationHooks(boundary: { event, _ in if event == "repairBefore" { gate.hold() } },
                                            repairLogDirectory: f.root.appendingPathComponent("repair-logs"))
        let a = app(f, hooks: hooks); a.applyPairRepair()
        await until("repair failure barrier") { gate.entered }; gate.release()
        await until("native repair failure completion") { a.bulkOperation == nil }
        expect(a.errorMessage?.contains("Repair failed") == true, "actual native repair failure is surfaced")
        precondition(chmod(f.input.path, 0o700) == 0)
        expect(try Data(contentsOf: f.input.appendingPathComponent("A_2.RAF")) == raw, "failed repair preserves original marker")
        expect(a.permitsTermination, "repair failure releases common gate")
    }
    print("FinalizeOperationChecks: \(checks) checks passed; artifacts: \(root.path)")
}

@main struct FinalizeOperationChecks {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        try await operationChecks()
    }
}

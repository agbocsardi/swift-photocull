import SwiftUI
import AppKit
import PhotoCullCore

enum Pane: Int, CaseIterable {
    case sessions = 1, image = 2, info = 3, filmstrip = 4
    var title: String {
        switch self {
        case .sessions: return "Sessions"
        case .image: return "Image"
        case .info: return "Info"
        case .filmstrip: return "Filmstrip"
        }
    }
}

enum SessionFilter: Int, CaseIterable {
    case all, active, done
    var label: String {
        switch self {
        case .all: return "All"
        case .active: return "Active"
        case .done: return "Done"
        }
    }
}

enum Modal: Identifiable, Equatable {
    case help
    case finalize(date: String)
    case globalFinalize
    case ingest
    case settings

    var id: String {
        switch self {
        case .help: return "help"
        case .finalize(let date): return "finalize-\(date)"
        case .globalFinalize: return "globalFinalize"
        case .ingest: return "ingest"
        case .settings: return "settings"
        }
    }
}

enum NavDir { case next, prev }

/// App-only preference. System inherits macOS appearance; the other choices
/// override PhotoCull without changing the computer's appearance.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Aspect presets available in crop mode.
enum CropAspect: String, CaseIterable {
    case free = "Free"
    case original = "Original"
    case square = "1:1"
    case fourThree = "4:3"
    case threeTwo = "3:2"
    case sixteenNine = "16:9"

    var ratio: Double? {
        switch self {
        case .free, .original: return nil
        case .square: return 1.0
        case .fourThree: return 4.0 / 3.0
        case .threeTwo: return 3.0 / 2.0
        case .sixteenNine: return 16.0 / 9.0
        }
    }
}

@MainActor
final class AppState: ObservableObject {

    // MARK: Config + library

    @Published var cfg: PCConfig = PCConfig.load()
    @Published var sessions: [SessionRow] = []

    // MARK: Active session

    @Published var activeDate: String?
    @Published var pairs: [FilePair] = []
    @Published var index: Int = 0
    /// Bumped whenever the (reference-typed) Session mutates, to force redraws.
    @Published var revision: Int = 0
    @Published var info = PhotoInfo()
    private var session: Session?

    // MARK: UI state

    @Published var cursorDate: String?
    @Published var focusedPane: Pane = .sessions
    @Published var filter: SessionFilter = .all
    @Published var selectedDates: Set<String> = []
    @Published var modal: Modal?
    @Published var showInspector = true
    @Published var appearance: AppAppearance = .system {
        didSet { applyAppearance() }
    }
    @Published var commandMode = false
    @Published var commandBuffer = ""
    @Published var toast: String?
    @Published var errorMessage: String?

    // MARK: Preview / crop

    @Published var cropMode = false
    @Published var cropAspect: CropAspect = .free
    /// True while the tilt slider has keyboard focus: arrows then nudge tilt
    /// instead of moving the crop region.
    @Published var tiltFocused = false
    /// When true the image pane shows the cropped result rather than the full frame.
    @Published var showCroppedPreview = true
    // Zoom/pan/cropRect/cropTilt live on `canvas` (CanvasState) above.

    // MARK: Ingest

    @Published var ingestProgress = IngestProgress()
    @Published var ingestSource: String = ""
    @Published var detectedCards: [URL] = []

    // MARK: Finalize

    @Published var finalizeStats: [FinalizeStats] = []
    @Published var cropExportMode: CropExportMode = .applyCrop
    /// True while a finalize runs on a background task. Finalize moves whole
    /// folders; a second concurrent run would race it.
    @Published private(set) var finalizeRunning = false

    // Views must observe the loader via environmentObject, not through app —
    // forwarding its changes here re-invalidated the whole window per decode.
    let imageLoader = ImageLoader()
    let thumbs = ThumbnailStore()
    /// Zoom/pan/crop geometry lives on its own observable (see CanvasState):
    /// it changes per drag tick / key repeat, far too often to republish the
    /// whole app object.
    let canvas = CanvasState()

    private var toastTask: Task<Void, Never>?
    /// Debounced sidecar write for navigation (trailing edge, ~500 ms).
    private var persistTask: Task<Void, Never>?
    private static let appearanceKey = "PhotoCull.appearance"

    private func applyAppearance() {
        if appearance == .system {
            UserDefaults.standard.removeObject(forKey: Self.appearanceKey)
        } else {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
        NSApplication.shared.appearance = appearance.nsAppearance
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.appearanceKey) ?? "system"
        appearance = AppAppearance(rawValue: saved) ?? .system
        applyAppearance()

        // No SD-card scan here: `detectSDCards` stats /Volumes/*/DCIM, and a
        // stale network mount can stall the first frame for seconds.
        // `beginIngest` detects (and defaults `ingestSource`) when needed.
        reloadLibrary()
        if let first = sessions.first { open(date: first.date) }
    }

    // MARK: - Derived

    var currentPair: FilePair? {
        guard index >= 0, index < pairs.count else { return nil }
        return pairs[index]
    }

    var currentStem: String? { currentPair?.stem }

    var currentDecision: Decision {
        guard let stem = currentStem, let session else { return .undecided }
        return session.get(stem)
    }

    var currentCrop: CropRect? {
        guard let stem = currentStem, let session else { return nil }
        return session.crop(for: stem)
    }

    var hasCrop: Bool { !(currentCrop?.isFullFrame ?? true) }

    var currentTilt: Double {
        guard let stem = currentStem else { return 0 }
        return session?.tilt(for: stem) ?? 0
    }

    var currentQuarterTurns: Int {
        guard let stem = currentStem else { return 0 }
        return session?.quarterTurns(for: stem) ?? 0
    }

    var hasTilt: Bool { abs(currentTilt) >= 0.05 }
    var isQuarterRotated: Bool { currentQuarterTurns != 0 }

    var showingFinalizeSheet: Bool {
        switch modal {
        case .finalize, .globalFinalize: return true
        default: return false
        }
    }

    var visibleSessions: [SessionRow] {
        switch filter {
        case .all: return sessions
        case .active: return sessions.filter { $0.status != .complete }
        case .done: return sessions.filter { $0.status == .complete }
        }
    }

    func decision(for stem: String) -> Decision {
        session?.get(stem) ?? .undecided
    }

    func crop(for stem: String) -> CropRect? { session?.crop(for: stem) }

    // MARK: - Library

    func reloadLibrary() {
        sessions = Library.loadSessions(cfg: cfg)
        if let active = activeDate, !sessions.contains(where: { $0.date == active }) {
            activeDate = nil
            pairs = []
            session = nil
        }
        if cursorDate == nil || !sessions.contains(where: { $0.date == cursorDate }) {
            cursorDate = activeDate ?? sessions.first?.date
        }
    }

    // MARK: - Session loading

    func open(date: String) {
        do {
            let folder = Library.inboxFolder(cfg: cfg, date: date)
            let loaded = try Session.load(folder: folder)
            let loadedPairs = try Library.pairs(cfg: cfg, date: date)
            session = loaded
            pairs = loadedPairs
            activeDate = date
            cursorDate = date
            index = min(max(0, loaded.lastIndex), max(0, loadedPairs.count - 1))
            revision += 1
            cropMode = false
            canvas.resetZoom()
            loadCurrent()
        } catch {
            fail("Could not open \(date): \(error.localizedDescription)")
        }
    }

    func loadCurrent() {
        guard let pair = currentPair else {
            info = PhotoInfo()
            imageLoader.load(url: nil, maxPixel: 0)
            return
        }
        let url = pair.jpg
        info = ExifReader.read(url: url)
        let target = currentMaxPixel
        imageLoader.load(url: url, maxPixel: target)
        // Prefetch neighbours so j/k feels instant.
        var neighbours: [URL] = []
        if index + 1 < pairs.count { neighbours.append(pairs[index + 1].jpg) }
        if index - 1 >= 0 { neighbours.append(pairs[index - 1].jpg) }
        imageLoader.prefetch(urls: neighbours, maxPixel: target)
        canvas.cropRect = session?.crop(for: pair.stem) ?? .full
    }

    /// Full-resolution target for decoding: big enough to crop from, bounded
    /// for memory. Capped at 3072 because ImageIO decode cost has a cliff
    /// above ~half native size (measured on a 26 MP file: 91 ms at 3072 vs
    /// 197 ms at 4096); 3072 also shrinks a cache slot 45→25 MB. Uses the
    /// EXIF block `loadCurrent` already read — no second disk read.
    var currentMaxPixel: Int {
        let longest = max(info.pixelWidth, info.pixelHeight)
        return longest > 0 ? min(longest, 3072) : 3072
    }

    /// Sidecar write for the open session. Rare/immediate path — navigation
    /// uses `schedulePersist` instead.
    private func persist() {
        guard let session, let date = activeDate else { return }
        do { try session.save(folder: Library.inboxFolder(cfg: cfg, date: date)) }
        catch { fail("Could not save session: \(error.localizedDescription)") }
    }

    /// Trailing-edge debounce for the per-keystroke navigation write: j/k no
    /// longer hits disk once per key, the sidecar lands ~500 ms after the
    /// last one (or immediately via `flushPersist`).
    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.persistTask = nil
            self.persist()
        }
    }

    /// Write a pending debounced persist now (close, finalize, ingest).
    private func flushPersist() {
        guard persistTask != nil else { return }
        persistTask?.cancel()
        persistTask = nil
        persist()
    }

    // MARK: - Undo / redo

    /// One reversible change. Unlimited depth. Edits capture their target
    /// session and its date, so undo works even after switching sessions.
    private struct Edit {
        let what: String
        let date: String
        let target: Session
        let change: (Session) -> Void
        let revert: (Session) -> Void
    }

    private var undoStack: [Edit] = []
    private var redoStack: [Edit] = []

    /// Apply a change, record it for undo, drop any redo history.
    private func run(_ what: String, change: @escaping (Session) -> Void,
                     revert: @escaping (Session) -> Void) {
        guard let target = session, let date = activeDate else { return }
        change(target)
        undoStack.append(Edit(what: what, date: date, target: target,
                              change: change, revert: revert))
        redoStack.removeAll()
        if target === session { revision += 1 }
        persist(target, date)
    }

    func undo() {
        guard let edit = undoStack.popLast() else { toastMessage("Nothing to undo"); return }
        edit.revert(edit.target)
        redoStack.append(edit)
        if edit.target === session { revision += 1 }
        persist(edit.target, edit.date)
        refreshRows()
        toastMessage("Undid \(edit.what)")
    }

    func redo() {
        guard let edit = redoStack.popLast() else { toastMessage("Nothing to redo"); return }
        edit.change(edit.target)
        undoStack.append(edit)
        if edit.target === session { revision += 1 }
        persist(edit.target, edit.date)
        refreshRows()
        toastMessage("Redid \(edit.what)")
    }

    private func persist(_ target: Session, _ date: String) {
        do { try target.save(folder: Library.inboxFolder(cfg: cfg, date: date)) }
        catch { fail("Could not save session: \(error.localizedDescription)") }
    }

    // MARK: - Navigation

    func setIndex(_ newIndex: Int) {
        guard !pairs.isEmpty else { return }
        index = min(max(0, newIndex), pairs.count - 1)
        session?.lastIndex = index
        schedulePersist()
        cropMode = false
        canvas.resetZoom()
        loadCurrent()
    }

    func nav(_ dir: NavDir, skipDecided: Bool = false) {
        guard !pairs.isEmpty else { return }
        if skipDecided {
            let step = dir == .next ? 1 : -1
            var i = index + step
            while i >= 0 && i < pairs.count {
                if decision(for: pairs[i].stem) == .undecided { setIndex(i); return }
                i += step
            }
            toastMessage(dir == .next ? "No later undecided photo" : "No earlier undecided photo")
            return
        }
        setIndex(index + (dir == .next ? 1 : -1))
    }

    /// Toggle-to-clear, otherwise set and auto-advance — matches the webapp.
    func mark(_ wanted: Decision) {
        guard let pair = currentPair else { return }
        let stem = pair.stem
        let current = decision(for: stem)
        if current == wanted {
            run("clearing \(stem)", change: { $0.set(stem, .undecided) },
                revert: { $0.set(stem, current) })
            refreshRows()
        } else {
            run("deciding \(stem)", change: { $0.set(stem, wanted) },
                revert: { $0.set(stem, current) })
            refreshRows()
            if index < pairs.count - 1 { setIndex(index + 1) }
        }
    }

    func clearDecision() {
        guard let pair = currentPair else { return }
        let stem = pair.stem
        let current = decision(for: stem)
        run("clearing \(stem)", change: { $0.set(stem, .undecided) },
            revert: { $0.set(stem, current) })
        refreshRows()
    }

    private func refreshRows() {
        // In-memory row update instead of a full inbox rescan: the open
        // session + pairs already hold everything `Library.loadSessions`
        // would re-derive from disk (and a rescan ran on every keystroke).
        // Full rescans stay in `reloadLibrary` (⌘R, post-ingest, post-finalize).
        guard let date = activeDate, let session,
              let i = sessions.firstIndex(where: { $0.date == date }) else { return }
        let stems = pairs.map(\.stem)
        let counts = session.statusCounts(stems: stems)
        sessions[i] = SessionRow(date: date,
                                 total: pairs.count,
                                 keep: counts.keep,
                                 reject: counts.reject,
                                 undecided: counts.undecided,
                                 status: session.folderStatus(stems: stems),
                                 cropped: session.crops.count)
    }

    // MARK: - Crop

    func enterCropMode() {
        guard currentPair != nil else { return }
        canvas.cropRect = currentCrop ?? .full
        canvas.cropTilt = currentTilt
        cropAspect = .free
        cropMode = true
        focusedPane = .image
    }

    func cancelCrop() {
        canvas.cropRect = currentCrop ?? .full
        canvas.cropTilt = currentTilt
        cropMode = false
    }

    func resetCrop() {
        canvas.cropRect = .full
        cropAspect = .free
    }

    func commitCrop() {
        guard let stem = currentStem else { return }
        let rect = canvas.cropRect.clamped(minSize: 0.02)
        let priorCrop = session?.crop(for: stem)
        let priorTilt = session?.tilt(for: stem)
        let newCrop: CropRect? = rect.isFullFrame ? nil : rect
        let newTilt: Double? = abs(canvas.cropTilt) < 0.05 ? nil : canvas.cropTilt
        run(newCrop == nil ? "clearing the crop" : "cropping \(stem)",
            change: { s in s.setCrop(stem, newCrop); s.setTilt(stem, newTilt) },
            revert: { s in s.setCrop(stem, priorCrop); s.setTilt(stem, priorTilt) })
        refreshRows()
        cropMode = false
        toastMessage(newCrop == nil ? (newTilt == nil ? "Crop cleared" : "Tilt saved")
                                     : "Crop saved")
    }

    func clearCrop() {
        guard let stem = currentStem else { return }
        let priorCrop = session?.crop(for: stem)
        let priorTilt = session?.tilt(for: stem)
        run("clearing the crop",
            change: { s in s.setCrop(stem, nil); s.setTilt(stem, nil) },
            revert: { s in s.setCrop(stem, priorCrop); s.setTilt(stem, priorTilt) })
        canvas.cropRect = .full
        canvas.cropTilt = 0
        refreshRows()
        toastMessage("Crop cleared")
    }

    /// Quarter-turn the current photo. Persisted immediately — rotation is an
    /// orientation fix, not something that needs an edit-mode commit.
    func rotateQuarter(_ dir: Int) {
        guard let stem = currentStem else { return }
        let prior = currentQuarterTurns
        run("rotating \(stem)",
            change: { $0.setQuarter(stem, prior + dir) },
            revert: { $0.setQuarter(stem, prior) })
    }

    /// Nudge the working tilt in crop mode. Values land on a 0.25° grid,
    /// clamped to ±45°.
    func nudgeTilt(_ delta: Double) {
        let v = ((canvas.cropTilt + delta) * 4).rounded() / 4
        canvas.cropTilt = min(45, max(-45, v))
    }

    func resetTilt() { canvas.cropTilt = 0 }

    /// Constrain `cropRect` to the selected aspect ratio, anchored at its centre.
    func applyAspect() {
        guard let ratio = cropAspect.ratio else {
            if cropAspect == .original, let pair = currentPair,
               let size = ImagePipeline.orientedPixelSize(url: pair.jpg), size.height > 0 {
                constrainTo(Double(size.width) / Double(size.height))
            }
            return
        }
        constrainTo(ratio)
    }

    private func constrainTo(_ ratio: Double) {
        // `ratio` is geometric (w/h on screen); normalized coords span the
        // image's own width/height, so scale by the inverse image aspect.
        guard let pair = currentPair,
              let size = ImagePipeline.orientedPixelSize(url: pair.jpg), size.height > 0 else { return }
        let r = ratio * Double(size.height) / Double(size.width)
        let cx = canvas.cropRect.x + canvas.cropRect.w / 2
        let cy = canvas.cropRect.y + canvas.cropRect.h / 2
        var w = canvas.cropRect.w
        var h = w / r
        if h > 1 { h = 1; w = h * r }
        if w > 1 { w = 1; h = w / r }
        let x = min(max(0, cx - w / 2), 1 - w)
        let y = min(max(0, cy - h / 2), 1 - h)
        canvas.cropRect = CropRect(x: x, y: y, w: w, h: h)
    }

    func cycleAspect() {
        let all = CropAspect.allCases
        let i = all.firstIndex(of: cropAspect) ?? 0
        cropAspect = all[(i + 1) % all.count]
        applyAspect()
    }

    // MARK: - Zoom / pan

    // resetZoom/zoomIn/zoomOut moved to CanvasState.

    // MARK: - Selection + filter

    func toggleSelection(_ date: String) {
        if selectedDates.contains(date) { selectedDates.remove(date) } else { selectedDates.insert(date) }
    }

    func toggleCursorSelection() {
        guard let date = cursorDate else { return }
        toggleSelection(date)
    }

    func clearSelection() { selectedDates.removeAll() }

    func toggleInspector() {
        withAnimation(Motion.normal) { showInspector.toggle() }
    }

    func cycleFilter() {
        filter = SessionFilter(rawValue: (filter.rawValue + 1) % SessionFilter.allCases.count) ?? .all
        if let cursor = cursorDate, !visibleSessions.contains(where: { $0.date == cursor }) {
            cursorDate = visibleSessions.first?.date
        }
    }

    /// WHY step-opens: moving the sidebar cursor also opens the session it
    /// lands on, so browsing sessions is one keypress per step instead of
    /// step-then-Enter. The `!= activeDate` guard keeps stepping a no-op when
    /// the target is already open (e.g. repeated steps at a clamped end);
    /// re-opening is cheap anyway (~5 ms + async decode that ImageLoader
    /// generation-cancels), so rapid stepping is safe. open() never moves
    /// focus, so pane 1 keeps the keys and you can keep stepping.
    func moveCursor(_ dir: NavDir) {
        let rows = visibleSessions
        guard !rows.isEmpty else { return }
        guard let cursor = cursorDate, let i = rows.firstIndex(where: { $0.date == cursor }) else {
            cursorDate = rows.first?.date
            if let target = cursorDate, target != activeDate { open(date: target) }
            return
        }
        let next = dir == .next ? min(i + 1, rows.count - 1) : max(i - 1, 0)
        let target = rows[next].date
        cursorDate = target
        if target != activeDate { open(date: target) }
    }

    func openCursorSession() {
        guard let date = cursorDate else { return }
        if date == activeDate { focusedPane = .image } else { open(date: date) }
    }

    // MARK: - External preview

    func openInPreview() {
        guard let url = currentPair?.jpg else { return }
        let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
        if FileManager.default.fileExists(atPath: preview.path) {
            NSWorkspace.shared.open([url], withApplicationAt: preview,
                                    configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func revealInFinder() {
        guard let url = currentPair?.jpg else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Finalize

    func beginFinalizeCurrent() {
        guard let date = activeDate else { return }
        beginFinalize(date: date)
    }

    /// Same detached-summary + publish pattern as `beginGlobalFinalize`, for a
    /// single arbitrary session (context menu). `Finalize.summary` walks the
    /// folder + parses the sidecar — keep it off the main thread so the sheet
    /// opens without a stall.
    func beginFinalize(date: String) {
        let cfg = self.cfg
        Task.detached(priority: .userInitiated) {
            do {
                let stats = try Finalize.summary(cfg: cfg, date: date)
                await MainActor.run {
                    self.finalizeStats = [stats]
                    if self.modal == nil { self.modal = .finalize(date: date) }
                }
            } catch {
                await MainActor.run {
                    self.fail("Could not read session: \(error.localizedDescription)")
                }
            }
        }
    }

    func beginGlobalFinalize() {
        let dates = selectedDates.isEmpty ? visibleSessions.map(\.date) : Array(selectedDates)
        guard !dates.isEmpty else { return }
        let cfg = self.cfg
        Task.detached(priority: .userInitiated) {
            do {
                let stats = try dates.sorted().map { try Finalize.summary(cfg: cfg, date: $0) }
                await MainActor.run {
                    self.finalizeStats = stats
                    if self.modal == nil { self.modal = .globalFinalize }
                }
            } catch {
                await MainActor.run {
                    self.fail("Could not read sessions: \(error.localizedDescription)")
                }
            }
        }
    }

    func confirmFinalize() {
        guard !finalizeRunning else { return }
        let dates: [String]
        switch modal {
        case .finalize(let date): dates = [date]
        case .globalFinalize:
            dates = finalizeStats.map(\.date)
        default: return
        }
        // Finalize reads the sidecar from disk — land any pending navigation
        // write first, then hand the whole run to a background task so the UI
        // stays responsive for the (long) move/trash/dump phase.
        flushPersist()
        modal = nil
        finalizeRunning = true
        toastMessage("Finalizing…")
        let cfg = self.cfg
        let cropMode = self.cropExportMode
        Task.detached(priority: .userInitiated) {
            do {
                let r: FinalizeResult
                if dates.count == 1 {
                    r = try Finalize.run(cfg: cfg, date: dates[0], dump: true,
                                         cropMode: cropMode, dumpOverride: nil)
                } else {
                    r = try Finalize.runMulti(cfg: cfg, dates: dates, dump: true, cropMode: cropMode)
                }
                await MainActor.run {
                    self.finalizeRunning = false
                    self.selectedDates.removeAll()
                    if let d = self.activeDate, dates.contains(d) {
                        self.activeDate = nil; self.pairs = []; self.session = nil
                    }
                    self.reloadLibrary()
                    if let first = self.sessions.first { self.open(date: first.date) }
                    if dates.count == 1 {
                        self.toastMessage("Finalized \(dates[0]) — \(r.archived) archived, \(r.trashed) trashed")
                    } else {
                        self.toastMessage("Finalized \(r.sessions) sessions — \(r.archived) archived, \(r.trashed) trashed")
                    }
                }
            } catch {
                await MainActor.run {
                    self.finalizeRunning = false
                    self.fail("Finalize failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Ingest

    func beginIngest() {
        detectedCards = Ingest.detectSDCards()
        if ingestSource.isEmpty, let first = detectedCards.first { ingestSource = first.path }
        ingestProgress = IngestProgress()
        modal = .ingest
    }

    func startIngest() {
        flushPersist()
        let source = ingestSource.trimmingCharacters(in: .whitespacesAndNewlines)
        var progress = IngestProgress()
        progress.running = true
        ingestProgress = progress
        let cfg = self.cfg
        // The copy loop reports once per file (~2k per card); republish at
        // most every ~150 ms, always letting the final result through.
        let throttle = ProgressThrottle()
        Task.detached(priority: .userInitiated) {
            do {
                let result = try Ingest.run(cfg: cfg, source: source.isEmpty ? nil : URL(fileURLWithPath: source)) { p in
                    guard throttle.shouldPublish(force: p.done) else { return }
                    Task { @MainActor in self.ingestProgress = p }
                }
                await MainActor.run {
                    var done = self.ingestProgress
                    done.running = false
                    done.done = true
                    done.copied = result.copied
                    done.skipped = result.skipped
                    self.ingestProgress = done
                    self.reloadLibrary()
                    self.toastMessage("Ingested \(result.copied) files into \(result.folders.count) session(s)")
                }
            } catch {
                await MainActor.run {
                    var p = self.ingestProgress
                    p.running = false
                    p.done = true
                    p.error = error.localizedDescription
                    self.ingestProgress = p
                }
            }
        }
    }

    // MARK: - RAW pair repair

    /// Dry-run report of misnamed RAW files. The inbox+archive walk runs on a
    /// background task; only the toast/report lands on the main thread.
    func checkPairing() {
        let cfg = self.cfg
        Task.detached(priority: .userInitiated) {
            let report = PairRepair.plan(cfg: cfg)
            await MainActor.run {
                if report.renamed == 0 {
                    self.toastMessage("RAW pairing OK — nothing to repair")
                } else {
                    self.toastMessage("\(report.renamed) RAW files can be re-paired (:R to repair)")
                }
            }
        }
    }

    /// Ask for confirmation, then rename misnamed RAWs back into their pairs.
    /// Plan off-thread, alert on the main thread once the count is known.
    func repairPairingInteractive() {
        let cfg = self.cfg
        Task.detached(priority: .userInitiated) {
            let report = PairRepair.plan(cfg: cfg)
            await MainActor.run {
                guard report.renamed > 0 else {
                    self.toastMessage("RAW pairing OK — nothing to repair")
                    return
                }
                self.confirmPairRepair(report)
            }
        }
    }

    private func confirmPairRepair(_ report: RepairReport) {
        let alert = NSAlert()
        alert.messageText = "Re-pair \(report.renamed) RAW files?"
        alert.informativeText = """
            Ingest used to rename a RAW to "<name>_2" whenever its JPG was copied in the \
            same run, which broke the JPG+RAW pair.

            This renames them back (e.g. DSCF0677_2.RAF -> DSCF0677.RAF) when the matching \
            JPG exists and the target name is free. Originals are not modified or deleted.
            """
        alert.addButton(withTitle: "Re-pair")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        applyPairRepair()
    }

    func applyPairRepair() {
        do {
            let report = try PairRepair.apply(cfg: cfg)
            toastMessage("Re-paired \(report.renamed) RAW files")
            reloadLibrary()
            if let date = activeDate { open(date: date) }
        } catch {
            fail("Repair failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Command mode

    func enterCommandMode() {
        commandMode = true
        commandBuffer = ""
    }

    func exitCommandMode() {
        commandMode = false
        commandBuffer = ""
    }

    func runCommand() {
        let cmd = commandBuffer
        exitCommandMode()
        switch cmd {
        case "f": beginFinalizeCurrent()
        case "F": beginGlobalFinalize()
        case "i": beginIngest()
        case "I": toggleInspector()
        case "c": enterCropMode()
        case "R": repairPairingInteractive()
        case "q": NSApp.terminate(nil)
        case "w": saveAndClose()
        default:
            if !cmd.isEmpty { toastMessage("Unknown command: :\(cmd)") }
        }
    }

    func saveAndClose() {
        flushPersist()
        NSApp.keyWindow?.performClose(nil)
    }

    // MARK: - Feedback

    func toastMessage(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.toast = nil }
        }
    }

    func fail(_ message: String) {
        errorMessage = message
        toastMessage(message)
    }

    // MARK: - Keyboard dispatch

    /// Returns true when the key was consumed.
    func handle(_ key: KeyEvent) -> Bool {
        if key.command {
            guard key.chars == "z" else { return false }
            if key.shift { redo() } else { undo() }
            return true
        }
        if commandMode { return handleCommandKey(key) }
        if let modal { return handleModalKey(key, modal: modal) }
        if cropMode { return handleCropKey(key) }
        return handleGlobalKey(key)
    }

    private func handleModalKey(_ key: KeyEvent, modal: Modal) -> Bool {
        switch modal {
        case .help:
            if key.isEscape || key.chars == "?" { self.modal = nil; return true }
            return false
        case .finalize, .globalFinalize:
            if key.chars == "y" || key.isReturn { confirmFinalize(); return true }
            if key.chars == "n" || key.isEscape { self.modal = nil; return true }
            return false
        case .ingest, .settings:
            if key.isEscape && !ingestProgress.running { self.modal = nil; return true }
            return false
        }
    }

    private func handleCommandKey(_ key: KeyEvent) -> Bool {
        if key.isEscape { exitCommandMode(); return true }
        if key.isReturn { runCommand(); return true }
        if key.isDelete {
            if !commandBuffer.isEmpty { commandBuffer.removeLast() }
            return true
        }
        if key.chars.count == 1 { commandBuffer += key.chars }
        return true
    }

    private func handleCropKey(_ key: KeyEvent) -> Bool {
        // While the tilt slider has focus, arrows adjust tilt, not the crop.
        if tiltFocused, let dir = key.arrow {
            let d: Double = dir == .left || dir == .up ? -1 : 1
            nudgeTilt(key.shift ? d : d / 4)
            return true
        }
        let step: Double = key.shift ? 0.02 : 0.005
        switch key.arrow {
        case .left:
            canvas.cropRect.x = max(0, canvas.cropRect.x - step)
            return true
        case .right:
            canvas.cropRect.x = min(1 - canvas.cropRect.w, canvas.cropRect.x + step)
            return true
        case .up:
            canvas.cropRect.y = max(0, canvas.cropRect.y - step)
            return true
        case .down:
            canvas.cropRect.y = min(1 - canvas.cropRect.h, canvas.cropRect.y + step)
            return true
        case nil: break
        }

        switch key.chars {
        case "h": canvas.cropRect.x = max(0, canvas.cropRect.x - step); return true
        case "l": canvas.cropRect.x = min(1 - canvas.cropRect.w, canvas.cropRect.x + step); return true
        case "k": canvas.cropRect.y = max(0, canvas.cropRect.y - step); return true
        case "j": canvas.cropRect.y = min(1 - canvas.cropRect.h, canvas.cropRect.y + step); return true
        case "a": cycleAspect(); return true
        case "r": resetCrop(); return true
        case "p": showCroppedPreview.toggle(); return true
        case ",": nudgeTilt(key.shift ? -1 : -0.25); return true
        case ".": nudgeTilt(key.shift ? 1 : 0.25); return true
        case "t": resetTilt(); return true
        default: break
        }

        if key.isReturn { commitCrop(); return true }
        if key.isEscape { cancelCrop(); return true }
        return false
    }

    private func handleGlobalKey(_ key: KeyEvent) -> Bool {
        // Command entry
        if key.chars == ":" { enterCommandMode(); return true }

        switch key.chars {
        case "z": mark(.keep); return true
        case "x": mark(.reject); return true
        case "o": openInPreview(); return true
        case "c": enterCropMode(); return true
        case "?": modal = .help; return true
        case "f": revealInFinder(); return true
        case "+", "=": canvas.zoomIn(); return true
        case "-": canvas.zoomOut(); return true
        case "0": canvas.resetZoom(); return true
        default: break
        }

        if key.isEscape {
            if !selectedDates.isEmpty { clearSelection() }
            else if let d = activeDate, d == cursorDate, focusedPane == .sessions { }
            else { modal = nil }
            commandMode = false
            return true
        }
        if key.isTab {
            if focusedPane == .sessions { cycleFilter() }
            else { focusedPane = Pane(rawValue: (focusedPane.rawValue % 4) + 1) ?? .sessions }
            return true
        }
        if let pane = Int(key.chars), let p = Pane(rawValue: pane) {
            focusedPane = p
            return true
        }
        if key.isSpace {
            if focusedPane == .sessions { toggleCursorSelection(); return true }
            return false
        }
        if key.isReturn {
            if focusedPane == .sessions { openCursorSession(); return true }
            return false
        }

        // Arrow keys supplement j/k. Horizontal arrows always move through
        // photos; vertical arrows move through sessions when the sidebar is
        // focused, otherwise through photos. Crop mode handles its own arrows
        // above, before reaching this global map.
        switch key.arrow {
        case .left: nav(.prev); return true
        case .right: nav(.next); return true
        case .up:
            focusedPane == .sessions ? moveCursor(.prev) : nav(.prev)
            return true
        case .down:
            focusedPane == .sessions ? moveCursor(.next) : nav(.next)
            return true
        case nil: break
        }

        switch key.chars {
        case "j":
            focusedPane == .sessions ? moveCursor(.next) : nav(.next)
            return true
        case "k":
            focusedPane == .sessions ? moveCursor(.prev) : nav(.prev)
            return true
        case "J":
            focusedPane == .sessions ? moveCursor(.next) : nav(.next, skipDecided: true)
            return true
        case "K":
            focusedPane == .sessions ? moveCursor(.prev) : nav(.prev, skipDecided: true)
            return true
        default: return false
        }
    }
}

/// Rate-limits main-thread progress publication from the ingest copy loop.
/// Called from one background thread, but declared `@unchecked Sendable` to
/// be honest about it; the lock costs nothing at this rate.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast

    /// True when ≥150 ms have passed since the last accepted publication.
    /// `force` lets a final result through unconditionally.
    func shouldPublish(force: Bool = false) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        guard force || now.timeIntervalSince(last) >= 0.15 else { return false }
        last = now
        return true
    }
}

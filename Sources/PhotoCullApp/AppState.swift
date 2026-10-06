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

    /// Fixture startup has already validated an explicit config and disposable bundle identity.
    let fixtureMode: Bool
    @Published private(set) var cfg: PCConfig
    @Published var sessions: [SessionRow] = []

    // MARK: Active session

    @Published var activeDate: String?
    @Published var pairs: [FilePair] = []
    @Published var index: Int = 0
    /// Bumped whenever the (reference-typed) Session mutates, to force redraws.
    @Published var revision: Int = 0
    @Published private(set) var sessionOpenEpoch = 0
    @Published var info = PhotoInfo()
    private var session: Session?

    // MARK: UI state

    @Published private var storedCursorDate: String?
    var cursorDate: String? {
        get { storedCursorDate }
        set { guard bulkOperation == nil else { return }; storedCursorDate = newValue }
    }
    @Published var focusedPane: Pane = .sessions
    @Published var filter: SessionFilter = .all
    @Published var selectedDates: Set<String> = []
    @Published var modal: Modal? {
        didSet {
            if case .preparing(let token) = bulkOperation,
               pendingFinalize?.token == token, modal != pendingFinalize?.modal {
                pendingFinalize = nil
                finalizeStats = []
                bulkOperation = nil
            }
        }
    }
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
    enum BulkOperation: Equatable { case preparing(UUID), finalize(UUID), ingest(UUID), repair(UUID) }
    @Published private(set) var bulkOperation: BulkOperation?
    private struct PreparedFinalize {
        let token: UUID, cfg: PCConfig, dates: [String], modal: Modal
        var ready = false
    }
    private var pendingFinalize: PreparedFinalize?
    /// Instance-local native barriers/callback capture. Never selected through config or environment.
    struct OperationHooks {
        var boundary: ((String, UUID) throws -> Void)?
        var finalize = FinalizeHooks()
        var repairLogDirectory: URL?
        var ingestPublisher: ((UUID, @escaping @Sendable (IngestProgress) -> Void) -> Void)?
    }
    private let operationHooks: OperationHooks?
    var permitsTermination: Bool { bulkOperation == nil }
    var finalizeRunning: Bool {
        if case .finalize = bulkOperation { return true }
        return false
    }

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
        // Fixture appearance is transient; SwiftUI/AppKit state uses its unique bundle domain.
        if !fixtureMode {
            if appearance == .system {
                UserDefaults.standard.removeObject(forKey: Self.appearanceKey)
            } else {
                UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
            }
        }
        NSApplication.shared.appearance = appearance.nsAppearance
    }

    init(cfg: PCConfig? = nil, initializeAppearance: Bool = true,
         openInitialSession: Bool = true, operationHooks: OperationHooks? = nil,
         fixtureMode: Bool = false) {
        precondition(!fixtureMode || cfg != nil, "Fixture AppState requires explicit validated config")
        self.fixtureMode = fixtureMode
        self.operationHooks = operationHooks
        self.cfg = cfg ?? PCConfig.load()
        if initializeAppearance && !fixtureMode {
            let saved = UserDefaults.standard.string(forKey: Self.appearanceKey) ?? "system"
            appearance = AppAppearance(rawValue: saved) ?? .system
            applyAppearance()
        }

        // No SD-card scan here: `detectSDCards` stats /Volumes/*/DCIM, and a
        // stale network mount can stall the first frame for seconds.
        // `beginIngest` detects (and defaults `ingestSource`) when needed.
        reloadLibrary()
        if openInitialSession, let first = sessions.first { open(date: first.date) }
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
        guard bulkOperation == nil else { return }
        sessions = Library.loadSessions(cfg: cfg)
        if let active = activeDate, !sessions.contains(where: { $0.date == active }) {
            clearActiveSession()
        }
        if cursorDate == nil || !sessions.contains(where: { $0.date == cursorDate }) {
            cursorDate = activeDate ?? sessions.first?.date
        }
    }

    private func clearActiveSession() {
        persistTask?.cancel()
        persistTask = nil
        activeDate = nil
        pairs = []
        session = nil
        info = PhotoInfo()
        imageLoader.load(url: nil, maxPixel: 0)
    }

    // MARK: - Session loading

    func open(date: String) {
        guard bulkOperation == nil, flushPersist() else { return }
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
            sessionOpenEpoch += 1
            cropMode = false
            canvas.resetZoom()
            loadCurrent()
        } catch {
            fail("Could not open \(date): \(error.localizedDescription)")
        }
    }

    func loadCurrent() {
        guard bulkOperation == nil else { return }
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

    /// Trailing-edge debounce for the per-keystroke navigation write: j/k no
    /// longer hits disk once per key, the sidecar lands ~500 ms after the
    /// last one (or immediately via `flushPersist`).
    private func schedulePersist() {
        guard bulkOperation == nil else { return }
        persistTask?.cancel()
        guard let target = session, let date = activeDate else { return }
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.persistTask = nil
            self.persist(target, date)
        }
    }

    /// Save the active session at every session/destructive-operation boundary.
    /// A failure leaves it active and prevents the caller from proceeding.
    @discardableResult
    private func flushPersist(ownedBy owner: BulkOperation? = nil) -> Bool {
        guard bulkOperation == owner else { return false }
        persistTask?.cancel()
        persistTask = nil
        guard let session, let date = activeDate else { return true }
        do {
            let folder = Library.inboxFolder(cfg: cfg, date: date)
            // Permissive browsing must not turn corrupt/future metadata into a fresh saved sidecar.
            _ = try Session.load(folder: folder, strict: true)
            try session.save(folder: folder)
            return true
        } catch {
            fail("Could not save session: \(error.localizedDescription)")
            return false
        }
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
        guard bulkOperation == nil, let target = session, let date = activeDate else { return }
        change(target)
        undoStack.append(Edit(what: what, date: date, target: target,
                              change: change, revert: revert))
        redoStack.removeAll()
        if target === session { revision += 1 }
        persist(target, date)
    }

    func undo() {
        guard bulkOperation == nil else { return }
        guard let edit = undoStack.popLast() else { toastMessage("Nothing to undo"); return }
        edit.revert(edit.target)
        redoStack.append(edit)
        if edit.target === session { revision += 1 }
        persist(edit.target, edit.date)
        refreshRows()
        toastMessage("Undid \(edit.what)")
    }

    func redo() {
        guard bulkOperation == nil else { return }
        guard let edit = redoStack.popLast() else { toastMessage("Nothing to redo"); return }
        edit.change(edit.target)
        undoStack.append(edit)
        if edit.target === session { revision += 1 }
        persist(edit.target, edit.date)
        refreshRows()
        toastMessage("Redid \(edit.what)")
    }

    private func persist(_ target: Session, _ date: String) {
        guard bulkOperation == nil else { return }
        do {
            let folder = Library.inboxFolder(cfg: cfg, date: date)
            _ = try Session.load(folder: folder, strict: true)
            try target.save(folder: folder)
        }
        catch { fail("Could not save session: \(error.localizedDescription)") }
    }

    // MARK: - Navigation

    func setIndex(_ newIndex: Int) {
        guard bulkOperation == nil, !pairs.isEmpty else { return }
        index = min(max(0, newIndex), pairs.count - 1)
        session?.lastIndex = index
        schedulePersist()
        cropMode = false
        canvas.resetZoom()
        loadCurrent()
    }

    func nav(_ dir: NavDir, skipDecided: Bool = false) {
        guard bulkOperation == nil, !pairs.isEmpty else { return }
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
        let target = min(max(index + (dir == .next ? 1 : -1), 0), pairs.count - 1)
        guard target != index else { return }
        setIndex(target)
    }

    /// Toggle-to-clear, otherwise set and auto-advance — matches the webapp.
    func mark(_ wanted: Decision) {
        guard bulkOperation == nil, let pair = currentPair else { return }
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
        guard bulkOperation == nil, let pair = currentPair else { return }
        let stem = pair.stem
        let current = decision(for: stem)
        run("clearing \(stem)", change: { $0.set(stem, .undecided) },
            revert: { $0.set(stem, current) })
        refreshRows()
    }

    private func refreshRows() {
        guard bulkOperation == nil else { return }
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
        guard bulkOperation == nil, currentPair != nil else { return }
        canvas.cropRect = currentCrop ?? .full
        canvas.cropTilt = currentTilt
        cropAspect = .free
        cropMode = true
        focusedPane = .image
    }

    func cancelCrop() {
        guard bulkOperation == nil else { return }
        canvas.cropRect = currentCrop ?? .full
        canvas.cropTilt = currentTilt
        cropMode = false
    }

    func resetCrop() {
        guard bulkOperation == nil else { return }
        canvas.cropRect = .full
        cropAspect = .free
    }

    func commitCrop() {
        guard bulkOperation == nil, let stem = currentStem else { return }
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
        guard bulkOperation == nil, let stem = currentStem else { return }
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
        guard bulkOperation == nil, let stem = currentStem else { return }
        let prior = currentQuarterTurns
        run("rotating \(stem)",
            change: { $0.setQuarter(stem, prior + dir) },
            revert: { $0.setQuarter(stem, prior) })
    }

    /// Nudge the working tilt in crop mode. Values land on a 0.25° grid,
    /// clamped to ±45°.
    func nudgeTilt(_ delta: Double) {
        guard bulkOperation == nil else { return }
        let v = ((canvas.cropTilt + delta) * 4).rounded() / 4
        canvas.cropTilt = min(45, max(-45, v))
    }

    func resetTilt() { guard bulkOperation == nil else { return }; canvas.cropTilt = 0 }

    /// Constrain `cropRect` to the selected aspect ratio, anchored at its centre.
    func applyAspect() {
        guard bulkOperation == nil else { return }
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
        guard bulkOperation == nil else { return }
        let all = CropAspect.allCases
        let i = all.firstIndex(of: cropAspect) ?? 0
        cropAspect = all[(i + 1) % all.count]
        applyAspect()
    }

    // MARK: - Zoom / pan

    // resetZoom/zoomIn/zoomOut moved to CanvasState.

    // MARK: - Selection + filter

    func toggleSelection(_ date: String) {
        guard bulkOperation == nil else { return }
        if selectedDates.contains(date) { selectedDates.remove(date) } else { selectedDates.insert(date) }
    }

    func toggleCursorSelection() {
        guard let date = cursorDate else { return }
        toggleSelection(date)
    }

    func clearSelection() { guard bulkOperation == nil else { return }; selectedDates.removeAll() }

    func toggleInspector() {
        withAnimation(Motion.normal) { showInspector.toggle() }
    }

    func cycleFilter() {
        guard bulkOperation == nil else { return }
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
        guard bulkOperation == nil else { return }
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
        guard bulkOperation == nil else { return }
        guard let date = cursorDate else { return }
        if date == activeDate { focusedPane = .image } else { open(date: date) }
    }

    // MARK: - External preview

    func openInPreview() {
        guard permitsOrdinaryIO(), bulkOperation == nil else { return }
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
        guard permitsOrdinaryIO(), bulkOperation == nil else { return }
        guard let url = currentPair?.jpg else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Finalize

    func beginFinalizeCurrent() {
        guard let date = activeDate else { return }
        beginFinalize(date: date)
    }

    /// Synchronous native bulk APIs run on GCD, never on a blocked cooperative task.
    private nonisolated static func onNativeQueue<T>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try body()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func canStartBulk() -> Bool {
        guard bulkOperation == nil else { toastMessage("Wait for the file operation to finish"); return false }
        guard !cropMode else { toastMessage("Commit or cancel the crop draft first"); return false }
        return true
    }

    func beginFinalize(date: String) {
        guard canStartBulk(), modal == nil else { return }
        prepareFinalize(dates: [date], modal: .finalize(date: date))
    }

    func beginGlobalFinalize() {
        guard canStartBulk(), modal == nil else { return }
        let dates = selectedDates.isEmpty ? visibleSessions.map(\.date) : Array(selectedDates)
        guard !dates.isEmpty else { return }
        prepareFinalize(dates: dates.sorted(), modal: .globalFinalize)
    }

    private func prepareFinalize(dates: [String], modal expectedModal: Modal) {
        // Cancel the timer BEFORE validation: permissive browsing may have opened corrupt metadata.
        // Validate all targets before any outgoing save; never "repair" corrupt JSON by flushing it.
        persistTask?.cancel(); persistTask = nil
        let token = UUID(), capturedConfig = cfg, outgoing = activeDate, hooks = operationHooks
        pendingFinalize = PreparedFinalize(token: token, cfg: capturedConfig, dates: dates, modal: expectedModal)
        bulkOperation = .preparing(token)
        finalizeStats = []
        modal = expectedModal
        Task {
            do {
                _ = try await Self.onNativeQueue {
                    try hooks?.boundary?("summaryBefore", token)
                    let validationDates = Set(dates + (outgoing.map { [$0] } ?? []))
                    for date in validationDates { _ = try Finalize.summary(cfg: capturedConfig, date: date) }
                }
                guard preparationMatches(token) else { return }
                guard flushPersist(ownedBy: .preparing(token)) else { cancelPreparation(token); return }
                let stats = try await Self.onNativeQueue {
                    let stats = try dates.map { try Finalize.summary(cfg: capturedConfig, date: $0) }
                    try hooks?.boundary?("summaryAfter", token)
                    return stats
                }
                guard preparationMatches(token) else { return }
                finalizeStats = stats
                pendingFinalize?.ready = true
                // Ownership remains held for the entire confirmation sheet lifetime.
            } catch {
                guard preparationMatches(token) else { return }
                cancelPreparation(token)
                fail("Could not read sessions: \(error.localizedDescription)")
            }
        }
    }

    private func preparationMatches(_ token: UUID) -> Bool {
        bulkOperation == .preparing(token) && pendingFinalize?.token == token &&
            pendingFinalize?.cfg == cfg && pendingFinalize?.modal == modal
    }
    private func cancelPreparation(_ token: UUID) {
        guard bulkOperation == .preparing(token) else { return }
        pendingFinalize = nil; finalizeStats = []; bulkOperation = nil; modal = nil
    }

    func confirmFinalize() {
        guard let prepared = pendingFinalize, prepared.ready, preparationMatches(prepared.token), !cropMode else { return }
        let token = prepared.token, dates = prepared.dates, cfg = prepared.cfg
        let exportMode = cropExportMode, hooks = operationHooks
        bulkOperation = .finalize(token) // Transition first: modal dismissal cannot cancel native work.
        pendingFinalize = nil; modal = nil
        toastMessage("Finalizing…")
        Task {
            do {
                let result = try await Self.onNativeQueue {
                    try hooks?.boundary?("finalizeBefore", token)
                    let result = try Finalize.runMulti(cfg: cfg, dates: dates, dump: true, cropMode: exportMode,
                                                        hooks: hooks?.finalize ?? FinalizeHooks())
                    try hooks?.boundary?("finalizeAfter", token)
                    return result
                }
                guard bulkOperation == .finalize(token) else { return }
                finishFileOperation(affected: Set(dates))
                finalizeStats = []
                let retained = result.retainedFolders.isEmpty ? "" : " — retained: \(result.retainedFolders.joined(separator: ", "))"
                toastMessage("Finalized \(result.sessions) session(s) — \(result.archived) archived, \(result.trashed) trashed\(retained)")
            } catch {
                guard bulkOperation == .finalize(token) else { return }
                finishFileOperation(affected: Set(dates))
                finalizeStats = []
                fail("Finalize failed: \(error.localizedDescription)")
            }
        }
    }

    private var knownSessionDates: Set<String> {
        Set(sessions.map(\.date) + undoStack.map(\.date) + redoStack.map(\.date) + (activeDate.map { [$0] } ?? []))
    }

    /// Dispose stale references/timers while still owned; only then release and reload actual partial state.
    private func finishFileOperation(affected: Set<String>) {
        let reopen = activeDate
        persistTask?.cancel(); persistTask = nil
        undoStack.removeAll { affected.contains($0.date) }
        redoStack.removeAll { affected.contains($0.date) }
        if let date = activeDate, affected.contains(date) { clearActiveSession() }
        selectedDates.subtract(affected)
        bulkOperation = nil
        reloadLibrary()
        if let reopen, sessions.contains(where: { $0.date == reopen }) { open(date: reopen) }
        else if activeDate == nil, let first = sessions.first { open(date: first.date) }
    }

    // MARK: - Ingest

    /// Shared entry guard, before even sidecar flush, card detection or external app access.
    private func permitsOrdinaryIO() -> Bool {
        guard !fixtureMode else { toastMessage("Unavailable in disposable fixture mode"); return false }
        return true
    }

    func beginIngest() {
        guard permitsOrdinaryIO(), canStartBulk(), modal == nil, flushPersist() else { return }
        detectedCards = Ingest.detectSDCards()
        if ingestSource.isEmpty, let first = detectedCards.first { ingestSource = first.path }
        ingestProgress = IngestProgress()
        modal = .ingest
    }

    func startIngest() {
        guard permitsOrdinaryIO(), canStartBulk(), modal == nil || modal == .ingest, flushPersist() else { return }
        let token = UUID(), cfg = cfg, hooks = operationHooks
        let source = ingestSource.trimmingCharacters(in: .whitespacesAndNewlines)
        bulkOperation = .ingest(token)
        var progress = IngestProgress(); progress.running = true; ingestProgress = progress
        let throttle = ProgressThrottle()
        let publish: @Sendable (IngestProgress) -> Void = { [weak self] p in
            guard throttle.observe(p) else { return }
            Task { @MainActor in self?.acceptIngestProgress(p, token: token) }
        }
        Task {
            // Capture authoritative callback totals even if MainActor publications are throttled/queued.
            let outcome: Result<IngestResult, Error>
            do {
                outcome = .success(try await Self.onNativeQueue {
                    hooks?.ingestPublisher?(token, publish)
                    try hooks?.boundary?("ingestBefore", token)
                    let result = try Ingest.run(cfg: cfg, source: source.isEmpty ? nil : URL(fileURLWithPath: source), onProgress: publish)
                    try hooks?.boundary?("ingestAfter", token)
                    return result
                })
            } catch { outcome = .failure(error) }
            guard bulkOperation == .ingest(token) else { return }
            var terminal = throttle.snapshot()
            terminal.running = false; terminal.done = true
            switch outcome {
            case .success(let result):
                terminal.copied = result.copied; terminal.skipped = result.skipped; terminal.error = nil
                terminal.total = max(terminal.total, result.copied + result.skipped)
                ingestProgress = terminal
                // Ingest can add to any date: old pair lists/undo references must be reloaded, not saved.
                finishFileOperation(affected: knownSessionDates)
                toastMessage("Ingested \(result.copied) files into \(result.folders.count) session(s)")
            case .failure(let error):
                terminal.error = error.localizedDescription; ingestProgress = terminal
                finishFileOperation(affected: knownSessionDates)
            }
        }
    }

    private func acceptIngestProgress(_ p: IngestProgress, token: UUID) {
        guard bulkOperation == .ingest(token), !ingestProgress.done,
              p.copied >= ingestProgress.copied, p.skipped >= ingestProgress.skipped,
              p.total >= ingestProgress.total else { return }
        var live = p
        // Callback completion is not authoritative native completion; retain ownership until return/drain.
        live.running = true; live.done = false
        ingestProgress = live
    }

    // MARK: - RAW pair repair

    func checkPairing() { planPairRepair(interactive: false) }
    func repairPairingInteractive() { planPairRepair(interactive: true) }

    private func planPairRepair(interactive: Bool) {
        guard permitsOrdinaryIO(), canStartBulk(), modal == nil, flushPersist() else { return }
        let token = UUID(), cfg = cfg, hooks = operationHooks
        bulkOperation = .repair(token)
        Task {
            do {
                let report = try await Self.onNativeQueue {
                    try hooks?.boundary?("repairPlan", token)
                    return PairRepair.plan(cfg: cfg)
                }
                guard bulkOperation == .repair(token) else { return }
                guard interactive, report.renamed > 0, modal == nil else {
                    bulkOperation = nil
                    toastMessage(report.renamed == 0 ? "RAW pairing OK — nothing to repair" : "\(report.renamed) RAW files can be re-paired (:R to repair)")
                    return
                }
                confirmPairRepair(report, token: token, cfg: cfg)
            } catch {
                guard bulkOperation == .repair(token) else { return }
                bulkOperation = nil; fail("Repair planning failed: \(error.localizedDescription)")
            }
        }
    }

    private func confirmPairRepair(_ report: RepairReport, token: UUID, cfg: PCConfig) {
        guard bulkOperation == .repair(token), modal == nil else { return }
        let alert = NSAlert()
        alert.messageText = "Re-pair \(report.renamed) RAW files?"
        alert.informativeText = "Renames misnamed RAW files when the matching JPG exists and the target is free. Originals are not modified or deleted."
        alert.addButton(withTitle: "Re-pair"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { bulkOperation = nil; return }
        guard bulkOperation == .repair(token) else { return }
        executePairRepair(token: token, cfg: cfg)
    }

    func applyPairRepair() {
        guard permitsOrdinaryIO(), canStartBulk(), modal == nil, flushPersist() else { return }
        let token = UUID()
        bulkOperation = .repair(token)
        executePairRepair(token: token, cfg: cfg)
    }

    private func executePairRepair(token: UUID, cfg: PCConfig) {
        let affected = knownSessionDates, hooks = operationHooks
        Task {
            do {
                let report = try await Self.onNativeQueue {
                    try hooks?.boundary?("repairBefore", token)
                    let report = try PairRepair.apply(cfg: cfg, logDirectory: hooks?.repairLogDirectory)
                    try hooks?.boundary?("repairAfter", token)
                    return report
                }
                guard bulkOperation == .repair(token) else { return }
                finishFileOperation(affected: affected)
                toastMessage("Re-paired \(report.renamed) RAW files")
            } catch {
                guard bulkOperation == .repair(token) else { return }
                finishFileOperation(affected: affected)
                fail("Repair failed: \(error.localizedDescription)")
            }
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
        case "q": if prepareForTermination() { NSApp.terminate(nil) }
        case "w": saveAndClose()
        default:
            if !cmd.isEmpty { toastMessage("Unknown command: :\(cmd)") }
        }
    }

    func prepareForTermination() -> Bool {
        guard permitsTermination else { toastMessage("Wait for the file operation to finish"); return false }
        return flushPersist()
    }

    func saveAndClose() {
        guard bulkOperation == nil, flushPersist() else { return }
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
        guard bulkOperation == nil else { return true }
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
/// Progress callbacks may arrive concurrently from ingest copy workers.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    private var latest = IngestProgress()

    /// Collect every callback under the same lock, even when its UI publication is throttled.
    func observe(_ p: IngestProgress) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard p.copied >= latest.copied, p.skipped >= latest.skipped, p.total >= latest.total else { return false }
        latest = p
        let now = Date()
        guard p.done || now.timeIntervalSince(last) >= 0.15 else { return false }
        last = now
        return true
    }
    func snapshot() -> IngestProgress { lock.lock(); defer { lock.unlock() }; return latest }
}

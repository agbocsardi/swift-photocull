import SwiftUI
import AppKit
import Combine
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
    @Published var commandMode = false
    @Published var commandBuffer = ""
    @Published var toast: String?
    @Published var errorMessage: String?

    // MARK: Preview / crop

    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero
    @Published var cropMode = false
    @Published var cropRect: CropRect = .full
    @Published var cropAspect: CropAspect = .free
    /// When true the image pane shows the cropped result rather than the full frame.
    @Published var showCroppedPreview = true

    // MARK: Ingest

    @Published var ingestProgress = IngestProgress()
    @Published var ingestSource: String = ""
    @Published var detectedCards: [URL] = []

    // MARK: Finalize

    @Published var finalizeStats: [FinalizeStats] = []
    @Published var cropExportMode: CropExportMode = .applyCrop

    let imageLoader = ImageLoader()
    let thumbs = ThumbnailStore()

    private var toastTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // ImageLoader owns its own @Published state, so views observing AppState
        // would never see a decoded photo arrive. Re-emit its changes.
        imageLoader.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        detectedCards = Ingest.detectSDCards()
        if let first = detectedCards.first { ingestSource = first.path }
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
            resetZoom()
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
        cropRect = session?.crop(for: pair.stem) ?? .full
    }

    /// Full-resolution target for decoding: big enough to crop from, bounded for memory.
    var currentMaxPixel: Int {
        let info = ExifReader.read(url: currentPair?.jpg ?? URL(fileURLWithPath: "/"))
        let longest = max(info.pixelWidth, info.pixelHeight)
        if longest > 0 { return min(longest, 4096) }
        return 4096
    }

    private func persist() {
        guard let session, let date = activeDate else { return }
        do { try session.save(folder: Library.inboxFolder(cfg: cfg, date: date)) }
        catch { fail("Could not save session: \(error.localizedDescription)") }
    }

    // MARK: - Navigation

    func setIndex(_ newIndex: Int) {
        guard !pairs.isEmpty else { return }
        index = min(max(0, newIndex), pairs.count - 1)
        session?.lastIndex = index
        persist()
        cropMode = false
        resetZoom()
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
        if self.decision(for: pair.stem) == wanted {
            session?.set(pair.stem, .undecided)
            revision += 1
            persist()
            refreshRows()
        } else {
            session?.set(pair.stem, wanted)
            revision += 1
            persist()
            refreshRows()
            if index < pairs.count - 1 { setIndex(index + 1) }
        }
    }

    func clearDecision() {
        guard let pair = currentPair else { return }
        session?.set(pair.stem, .undecided)
        revision += 1
        persist()
        refreshRows()
    }

    private func refreshRows() {
        let keep = sessions
        sessions = Library.loadSessions(cfg: cfg)
        // Preserve scroll/cursor identity across the reload.
        _ = keep
    }

    // MARK: - Crop

    func enterCropMode() {
        guard currentPair != nil else { return }
        cropRect = currentCrop ?? .full
        cropAspect = .free
        cropMode = true
        focusedPane = .image
    }

    func cancelCrop() {
        cropRect = currentCrop ?? .full
        cropMode = false
    }

    func resetCrop() {
        cropRect = .full
        cropAspect = .free
    }

    func commitCrop() {
        guard let stem = currentStem else { return }
        let rect = cropRect.clamped(minSize: 0.02)
        session?.setCrop(stem, rect.isFullFrame ? nil : rect)
        revision += 1
        persist()
        refreshRows()
        cropMode = false
        toastMessage(rect.isFullFrame ? "Crop cleared" : "Crop saved")
    }

    func clearCrop() {
        guard let stem = currentStem else { return }
        session?.setCrop(stem, nil)
        cropRect = .full
        revision += 1
        persist()
        refreshRows()
        toastMessage("Crop cleared")
    }

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
        let cx = cropRect.x + cropRect.w / 2
        let cy = cropRect.y + cropRect.h / 2
        var w = cropRect.w
        var h = w / ratio
        if h > 1 { h = 1; w = h * ratio }
        if w > 1 { w = 1; h = w / ratio }
        let x = min(max(0, cx - w / 2), 1 - w)
        let y = min(max(0, cy - h / 2), 1 - h)
        cropRect = CropRect(x: x, y: y, w: w, h: h)
    }

    func cycleAspect() {
        let all = CropAspect.allCases
        let i = all.firstIndex(of: cropAspect) ?? 0
        cropAspect = all[(i + 1) % all.count]
        applyAspect()
    }

    // MARK: - Zoom / pan

    func resetZoom() {
        zoom = 1
        pan = .zero
    }

    func zoomIn() { zoom = min(zoom * 1.25, 8) }
    func zoomOut() { zoom = max(zoom / 1.25, 0.1) }
    func zoomActual() { zoom = 1; pan = .zero }

    func panBy(dx: CGFloat, dy: CGFloat) {
        pan = CGSize(width: pan.width + dx, height: pan.height + dy)
    }

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

    func moveCursor(_ dir: NavDir) {
        let rows = visibleSessions
        guard !rows.isEmpty else { return }
        guard let cursor = cursorDate, let i = rows.firstIndex(where: { $0.date == cursor }) else {
            cursorDate = rows.first?.date
            return
        }
        let next = dir == .next ? min(i + 1, rows.count - 1) : max(i - 1, 0)
        cursorDate = rows[next].date
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
        do {
            finalizeStats = [try Finalize.summary(cfg: cfg, date: date)]
            modal = .finalize(date: date)
        } catch { fail("Could not read session: \(error.localizedDescription)") }
    }

    func beginGlobalFinalize() {
        let dates = selectedDates.isEmpty ? visibleSessions.map(\.date) : Array(selectedDates)
        guard !dates.isEmpty else { return }
        do {
            finalizeStats = try dates.sorted().map { try Finalize.summary(cfg: cfg, date: $0) }
            modal = .globalFinalize
        } catch { fail("Could not read sessions: \(error.localizedDescription)") }
    }

    func confirmFinalize() {
        let dates: [String]
        switch modal {
        case .finalize(let date): dates = [date]
        case .globalFinalize:
            dates = finalizeStats.map(\.date)
        default: return
        }
        modal = nil
        do {
            if dates.count == 1 {
                let r = try Finalize.run(cfg: cfg, date: dates[0], dump: true,
                                         cropMode: cropExportMode, dumpOverride: nil)
                toastMessage("Finalized \(dates[0]) — \(r.archived) archived, \(r.trashed) trashed")
            } else {
                let r = try Finalize.runMulti(cfg: cfg, dates: dates, dump: true, cropMode: cropExportMode)
                toastMessage("Finalized \(r.sessions) sessions — \(r.archived) archived, \(r.trashed) trashed")
            }
            selectedDates.removeAll()
            if let d = activeDate, dates.contains(d) { activeDate = nil; pairs = []; session = nil }
            reloadLibrary()
            if let first = sessions.first { open(date: first.date) }
        } catch { fail("Finalize failed: \(error.localizedDescription)") }
    }

    // MARK: - Ingest

    func beginIngest() {
        detectedCards = Ingest.detectSDCards()
        if ingestSource.isEmpty, let first = detectedCards.first { ingestSource = first.path }
        ingestProgress = IngestProgress()
        modal = .ingest
    }

    func startIngest() {
        let source = ingestSource.trimmingCharacters(in: .whitespacesAndNewlines)
        var progress = IngestProgress()
        progress.running = true
        ingestProgress = progress
        let cfg = self.cfg
        Task.detached(priority: .userInitiated) {
            do {
                let result = try Ingest.run(cfg: cfg, source: source.isEmpty ? nil : URL(fileURLWithPath: source)) { p in
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

    /// Report how many RAW files are misnamed (dry run).
    @discardableResult
    func checkPairing() -> RepairReport? {
        do {
            let report = PairRepair.plan(cfg: cfg)
            if report.renamed == 0 {
                toastMessage("RAW pairing OK — nothing to repair")
            } else {
                toastMessage("\(report.renamed) RAW files can be re-paired (:R to repair)")
            }
            return report
        } catch {
            fail("Pairing check failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Ask for confirmation, then rename misnamed RAWs back into their pairs.
    func repairPairingInteractive() {
        guard let report = checkPairing(), report.renamed > 0 else { return }
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
        persist()
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
        let step: Double = key.shift ? 0.02 : 0.005
        switch key.arrow {
        case .left:
            cropRect.x = max(0, cropRect.x - step)
            return true
        case .right:
            cropRect.x = min(1 - cropRect.w, cropRect.x + step)
            return true
        case .up:
            cropRect.y = max(0, cropRect.y - step)
            return true
        case .down:
            cropRect.y = min(1 - cropRect.h, cropRect.y + step)
            return true
        case nil: break
        }

        switch key.chars {
        case "h": cropRect.x = max(0, cropRect.x - step); return true
        case "l": cropRect.x = min(1 - cropRect.w, cropRect.x + step); return true
        case "k": cropRect.y = max(0, cropRect.y - step); return true
        case "j": cropRect.y = min(1 - cropRect.h, cropRect.y + step); return true
        case "a": cycleAspect(); return true
        case "r": resetCrop(); return true
        case "p": showCroppedPreview.toggle(); return true
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
        case "+", "=": zoomIn(); return true
        case "-": zoomOut(); return true
        case "0": resetZoom(); return true
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

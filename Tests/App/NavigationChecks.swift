import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import PhotoCullCore

@MainActor
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("CHECK FAILED: \(message)") }
}

@MainActor
private func runNavigationChecks() throws -> Int {
    guard let outputPath = ProcessInfo.processInfo.environment["PC_NAVIGATION_OUT"] else {
        throw NSError(domain: "NavigationChecks", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "PC_NAVIGATION_OUT is required"])
    }
    let outputRoot = URL(fileURLWithPath: outputPath).standardizedFileURL
    let root = outputRoot.appendingPathComponent("synthetic-\(UUID().uuidString)", isDirectory: true)
    guard root.path.hasPrefix(outputRoot.path + "/") else { throw CocoaError(.fileWriteInvalidFileName) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let inbox = root.appendingPathComponent("inbox", isDirectory: true)
    let archive = root.appendingPathComponent("archive", isDirectory: true)
    let dump = root.appendingPathComponent("dump", isDirectory: true)
    try [inbox, archive, dump].forEach {
        try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
    }
    let cfg = PCConfig(paths: PathsConfig(inbox: inbox.path, archive: archive.path, dump: dump.path),
                       files: FilesConfig(rawExtensions: ["RAF"], jpgExtensions: ["JPG", "JPEG"]))

    func addSession(_ date: String, count: Int, lastIndex: Int = 0,
                    complete: Bool = false) throws {
        let folder = inbox.appendingPathComponent(date, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for i in 0..<count {
            let url = folder.appendingPathComponent(String(format: "P%02d.JPG", i))
            let color = CGColor(red: CGFloat(i + 1) / CGFloat(count + 1), green: 0.2,
                                blue: date == "20250101" ? 0.8 : 0.1, alpha: 1)
            let context = CGContext(data: nil, width: 12, height: 8, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(color)
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
            precondition(CGImageDestinationFinalize(destination))
        }
        let session = Session.fresh()
        session.lastIndex = lastIndex
        if count > 0 {
            for i in 0..<count {
                let stem = String(format: "P%02d", i)
                session.setCrop(stem, CropRect(x: 0.1, y: 0.2, w: 0.5, h: 0.6))
                session.setTilt(stem, 2.5)
                session.setQuarter(stem, 1)
                if complete { session.set(stem, .keep) }
            }
        }
        try session.save(folder: folder)
    }

    try addSession("20240101", count: 3, lastIndex: 0)
    try addSession("20250101", count: 2, lastIndex: 1, complete: true)
    try addSession("20260101", count: 1)
    try addSession("20270101", count: 0)

    let app = AppState(cfg: cfg, initializeAppearance: false, openInitialSession: false)
    var checks = 0
    func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        check(value(), message); checks += 1
    }

    app.open(date: "20240101")
    app.setIndex(2)
    app.open(date: "20250101")
    let savedA = try Session.load(folder: inbox.appendingPathComponent("20240101"))
    expect(savedA.lastIndex == 2, "outgoing index is durable on immediate session switch")
    expect(app.activeDate == "20250101" && app.index == 1, "target session opens at saved index")
    expect(app.focusedPane == .sessions, "opening preserves sidebar focus")

    app.open(date: "20240101")
    expect(app.index == 2, "immediate A→B→A restores outgoing index without waiting for debounce")
    expect(app.currentCrop != nil, "saved crop survives session switching")
    expect(app.currentQuarterTurns == 1, "saved rotation survives session switching")
    expect(app.currentTilt == 2.5, "saved tilt survives session switching")
    app.setIndex(1)
    app.open(date: "20240101")
    expect(app.index == 1, "same-session reopen flushes then reloads latest position")

    app.filter = .active
    app.cursorDate = "20260101"
    app.moveCursor(.next)
    expect(app.cursorDate == "20240101" && app.activeDate == "20240101",
           "filtered stepping skips completed sessions")
    app.moveCursor(.next)
    expect(app.activeDate == "20240101", "navigation boundary is a no-op")
    app.open(date: "20270101")
    app.nav(.next)
    app.nav(.prev)
    expect(app.pairs.isEmpty && app.activeDate == "20270101", "empty session navigation remains safe")

    app.open(date: "20240101")
    app.setIndex(1)
    let aFolder = inbox.appendingPathComponent("20240101", isDirectory: true)
    let aSidecar = aFolder.appendingPathComponent(Session.fileName)
    let bFolder = inbox.appendingPathComponent("20250101", isDirectory: true)
    let bSidecar = bFolder.appendingPathComponent(Session.fileName)
    let bSession = try Session.load(folder: bFolder)
    let bPairs = try Library.pairs(cfg: cfg, date: "20250101")
    expect(bSession.lastIndex == 1 && bPairs.count == 2, "incoming B remains fully loadable")
    let bBytesBefore = try Data(contentsOf: bSidecar)
    try FileManager.default.removeItem(at: aSidecar)
    try FileManager.default.createDirectory(at: aSidecar, withIntermediateDirectories: false)
    app.open(date: "20250101")
    expect(app.activeDate == "20240101" && app.index == 1,
           "failed outgoing save aborts replacement and preserves active session")
    let bBytesAfter = try Data(contentsOf: bSidecar)
    expect(bBytesAfter == bBytesBefore, "failed A save never changes valid incoming B sidecar")
    expect(app.errorMessage != nil, "save error is surfaced")

    app.setIndex(2)
    try FileManager.default.removeItem(at: aFolder)
    app.reloadLibrary()
    expect(app.activeDate == nil && app.pairs.isEmpty, "reload removal clears active session state")
    expect(app.imageLoader.current == nil && !app.imageLoader.isLoading,
           "reload removal clears old image and pending load")

    let urlA = URL(fileURLWithPath: "/synthetic/A/P01.JPG")
    let urlB = URL(fileURLWithPath: "/synthetic/B/P01.JPG")
    let initial = FilmstripScrollTarget(date: "20240101", url: urlA, index: 1, openEpoch: 1)
    let sameIndexOtherSession = FilmstripScrollTarget(date: "20250101", url: urlB, index: 1, openEpoch: 2)
    let nextPhoto = FilmstripScrollTarget(date: "20240101", url: URL(fileURLWithPath: "/synthetic/A/P02.JPG"),
                                          index: 2, openEpoch: 1)
    let reopened = FilmstripScrollTarget(date: "20240101", url: urlA, index: 1, openEpoch: 2)
    expect(initial.behavior(from: nil) == .snap, "initial nonzero target snaps into position")
    expect(sameIndexOtherSession.behavior(from: initial) == .snap,
           "same-index cross-session target snaps")
    expect(initial != sameIndexOtherSession, "different session URLs are distinct scroll targets")
    expect(nextPhoto.behavior(from: initial) == .animate,
           "same-session photo navigation animates after edit revisions")
    expect(reopened.behavior(from: initial) == .snap, "same-session reopen recenters without traversal")
    return checks
}

@main
struct NavigationChecks {
    @MainActor static func main() throws {
        let count = try runNavigationChecks()
        print("Navigation checks: \(count) passed")
    }
}

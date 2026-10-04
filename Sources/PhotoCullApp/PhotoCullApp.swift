import SwiftUI
import AppKit

@main
enum PhotoCullMain {
    @MainActor static func main() {
        let args = CommandLine.arguments
        do {
            StartupConfiguration.current = try StartupConfiguration.resolve(
                arguments: Array(args.dropFirst()), bundleIdentifier: Bundle.main.bundleIdentifier)
        } catch {
            FileHandle.standardError.write(Data("PhotoCull: \(error.localizedDescription)\n".utf8))
            exit(2)
        }
        if args.contains("--repair-pairs") {
            exit(HeadlessCheck.repairPairs(apply: args.contains("--apply")))
        }
        if args.contains("--check") {
            exit(HeadlessCheck.run())
        }
        PhotoCullApp.main()
    }
}

struct PhotoCullApp: App {
    @StateObject private var app = StartupConfiguration.current.makeAppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(connectedApp)
                .environmentObject(app.imageLoader)
                .environmentObject(app.canvas)
                .frame(minWidth: 940, minHeight: 620)
        }
        .defaultSize(width: 1400, height: 880)
        // Unified toolbar: the app title and actions live in the real title bar,
        // so the traffic lights and the drag zone behave natively.
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .sidebar) {
                Button("Show Info Inspector") { app.toggleInspector() }
                    .keyboardShortcut("i", modifiers: .command)
            }
            CommandMenu("Cull") {
                Button("Ingest from SD Card…") { app.beginIngest() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Finalize Current Session…") { app.beginFinalizeCurrent() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(app.activeDate == nil)
                Button("Finalize Selected Sessions…") { app.beginGlobalFinalize() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(app.sessions.isEmpty)
                Divider()
                Button("Crop Current Photo") { app.enterCropMode() }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(app.currentPair == nil)
                Button("Open in Preview") { app.openInPreview() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(app.currentPair == nil)
                Button("Reveal in Finder") { app.revealInFinder() }
                    .disabled(app.currentPair == nil)
                Divider()
                Button("Reload Inbox") { app.reloadLibrary() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Check RAW Pairing") { app.checkPairing() }
                    .disabled(app.sessions.isEmpty)
                Button("Re-pair RAW Files…") { app.repairPairingInteractive() }
                    .disabled(app.sessions.isEmpty)
            }
        }

        // Its ordinary menu contains a direct Finder action; do not insert it in fixture mode.
        MenuBarExtra(isInserted: .constant(!app.fixtureMode)) {
            MenuBarView()
                .environmentObject(connectedApp)
        } label: {
            // A single image is reliable in MenuBarExtra's status-item renderer.
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    @MainActor private var connectedApp: AppState {
        delegate.operationState = app
        return app
    }

    private static let menuBarIcon: NSImage = {
        let bundled = Bundle.main.url(forResource: "PhotoCullMenuBar", withExtension: "png")
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("resources/PhotoCullMenuBar.png")
        if let icon = bundled.flatMap({ NSImage(contentsOf: $0) })
            ?? NSImage(contentsOf: development) {
            // A transparent, monochrome 36px image displayed at 18pt.
            // Template tint follows the system's light or dark menu bar.
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = true
            return icon
        }
        return NSImage(systemSymbolName: "camera.aperture", accessibilityDescription: "PhotoCull")!
    }()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var operationState: AppState?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        operationState?.prepareForTermination() == false ? .terminateCancel : .terminateNow
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        KeyMonitor.shared.start()
        if !StartupConfiguration.current.isFixture {
            Snapshot.applyRequestedAppearance()
            Snapshot.scheduleIfRequested()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

import SwiftUI
import AppKit

@main
enum PhotoCullMain {
    static func main() {
        let args = CommandLine.arguments
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
    @StateObject private var app = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(app)
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

        MenuBarExtra {
            MenuBarView()
                .environmentObject(app)
        } label: {
            Group {
                if let icon = Self.menuBarIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Image(systemName: "camera.aperture")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: 18, height: 18)
            .overlay(alignment: .topTrailing) {
                if app.ingestProgress.running {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(.background, lineWidth: 1))
                        .offset(x: 2, y: -2)
                }
            }
            .accessibilityLabel(app.ingestProgress.running ? "PhotoCull — ingesting" : "PhotoCull")
        }
        .menuBarExtraStyle(.window)
    }

    private static let menuBarIcon: NSImage? = {
        let fileManager = FileManager.default
        // The packaged app has the icon in its bundle. SwiftPM runs do not,
        // so also look beside the working directory and up from the executable.
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: "PhotoCull", withExtension: "icns") {
            candidates.append(bundled)
        }
        candidates.append(URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("resources/PhotoCull.icns"))
        if let executable = Bundle.main.executableURL {
            var directory = executable.deletingLastPathComponent()
            for _ in 0..<5 {
                candidates.append(directory.appendingPathComponent("resources/PhotoCull.icns"))
                directory.deleteLastPathComponent()
            }
        }
        for url in candidates {
            if let image = NSImage(contentsOf: url) {
                // Keep the real app icon's colors in both light and dark menu bars.
                image.isTemplate = false
                return image
            }
        }
        return nil
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        KeyMonitor.shared.start()
        Snapshot.applyRequestedAppearance()
        Snapshot.scheduleIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

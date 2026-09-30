import SwiftUI
import AppKit

@main
struct PhotoCullApp: App {
    @StateObject private var app = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: 1000, minHeight: 640)
                .background(EF.bg)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Cull") {
                Button("Ingest from SD card…") { app.beginIngest() }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Finalize current session…") { app.beginFinalizeCurrent() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(app.activeDate == nil)
                Button("Finalize selected sessions…") { app.beginGlobalFinalize() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(app.sessions.isEmpty)
                Divider()
                Button("Reload inbox") { app.reloadLibrary() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Crop current photo") { app.enterCropMode() }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(app.currentPair == nil)
                Button("Open in Preview") { app.openInPreview() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(app.currentPair == nil)
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(app)
        } label: {
            Image(systemName: app.ingestProgress.running
                  ? "arrow.down.circle"
                  : "camera.aperture")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        KeyMonitor.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

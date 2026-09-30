import SwiftUI
import PhotoCullCore

/// Contents of the menu bar extra.
struct MenuBarView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow

    private var undecidedTotal: Int {
        app.sessions.reduce(0) { $0 + ($1.total - $1.keep - $1.reject) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if app.ingestProgress.running {
                ingestStatus
                Divider()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Inbox")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(EF.aqua)
                Text("\(app.sessions.count) session\(app.sessions.count == 1 ? "" : "s") · \(undecidedTotal) undecided")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(EF.text)
                ForEach(app.sessions.prefix(6)) { row in
                    Button {
                        app.open(date: row.date)
                        activate()
                    } label: {
                        HStack(spacing: 6) {
                            Text(row.date)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(EF.subtle)
                            Badge(text: row.status.rawValue, color: row.status.color)
                            Spacer(minLength: 0)
                            Text("\(row.total - row.keep - row.reject)/\(row.total)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(EF.bg3)
                        }
                    }
                    .buttonStyle(.borderless)
                }
                if app.sessions.count > 6 {
                    Text("+ \(app.sessions.count - 6) more…")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(EF.bg3)
                }
            }
            .padding(10)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                menuButton("Ingest from SD card…", icon: "square.and.arrow.down") {
                    app.beginIngest()
                    activate()
                }
                .disabled(app.ingestProgress.running)

                menuButton("Open PhotoCull", icon: "macwindow") { activate() }

                menuButton("Finalize all sessions…", icon: "checkmark.circle") {
                    app.beginGlobalFinalize()
                    activate()
                }
                .disabled(app.sessions.isEmpty)

                menuButton("Reveal inbox in Finder", icon: "folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: app.cfg.paths.inbox))
                }
            }
            .padding(6)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                menuButton("Quit PhotoCull", icon: "power") { NSApp.terminate(nil) }
            }
            .padding(6)
        }
        .frame(width: 300)
        .background(EF.bg)
    }

    private var ingestStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ingesting…")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(EF.green)
            ProgressView(value: Double(app.ingestProgress.copied),
                         total: Double(max(1, app.ingestProgress.total)))
                .tint(EF.green)
            Text("\(app.ingestProgress.copied)/\(app.ingestProgress.total) · \(app.ingestProgress.current)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(EF.bg3)
                .lineLimit(1)
        }
        .padding(10)
    }

    private func menuButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 11)).frame(width: 14)
                Text(title).font(.system(size: 11))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
    }

    private func activate() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible == false }) {
            w.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
    }
}

struct MenuRowStyle: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(hovered ? EF.text : EF.subtle)
            .background(RoundedRectangle(cornerRadius: 4)
                .fill(hovered ? EF.bg1 : Color.clear))
            .onHover { hovered = $0 }
    }
}

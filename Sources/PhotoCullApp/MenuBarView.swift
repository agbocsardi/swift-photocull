import SwiftUI
import PhotoCullCore

/// Contents of the menu bar extra. Native menu-bar styling: quiet rows,
/// hover tint, compact counts.
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
                Divider().overlay(Palette.separator)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("INBOX")
                    .font(Typo.sectionHeader)
                    .tracking(0.4)
                    .foregroundStyle(Palette.tertiary)

                if app.sessions.isEmpty {
                    Text("No sessions")
                        .font(Typo.callout)
                        .foregroundStyle(Palette.tertiary)
                } else {
                    Text("\(app.sessions.count) session\(app.sessions.count == 1 ? "" : "s") · \(undecidedTotal) undecided")
                        .font(Typo.callout)
                        .foregroundStyle(Palette.secondary)

                    ForEach(app.sessions.prefix(6)) { row in
                        MenuBarRow(date: row.date,
                                   status: row.status,
                                   undecided: row.total - row.keep - row.reject,
                                   total: row.total) {
                            app.open(date: row.date)
                            activate()
                        }
                    }
                    if app.sessions.count > 6 {
                        Text("+ \(app.sessions.count - 6) more…")
                            .font(Typo.caption)
                            .foregroundStyle(Palette.quaternary)
                            .padding(.leading, 6)
                    }
                }
            }
            .padding(Metric.paneInset)

            Divider().overlay(Palette.separator)

            VStack(alignment: .leading, spacing: 1) {
                MenuBarButton("Ingest from SD Card…", icon: "square.and.arrow.down") {
                    app.beginIngest()
                    activate()
                }
                .disabled(app.ingestProgress.running)

                MenuBarButton("Open PhotoCull", icon: "macwindow") { activate() }

                MenuBarButton("Finalize All Sessions…", icon: "checkmark.circle") {
                    app.beginGlobalFinalize()
                    activate()
                }
                .disabled(app.sessions.isEmpty)

                MenuBarButton("Check RAW Pairing", icon: "link") {
                    app.checkPairing()
                    activate()
                }
                .disabled(app.sessions.isEmpty)

                MenuBarButton("Reveal Inbox in Finder", icon: "folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: app.cfg.paths.inbox))
                }
            }
            .padding(6)

            Divider().overlay(Palette.separator)

            MenuBarButton("Quit PhotoCull", icon: "power") { NSApp.terminate(nil) }
                .padding(6)
        }
        .frame(width: 296)
        .background(Palette.window)
    }

    private var ingestStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Ingesting…", systemImage: "arrow.down.circle")
                .font(Typo.caption.weight(.semibold))
                .foregroundStyle(Palette.keep)
            ProgressView(value: Double(app.ingestProgress.copied),
                         total: Double(max(1, app.ingestProgress.total)))
                .tint(Palette.keep)
            Text("\(app.ingestProgress.copied) of \(app.ingestProgress.total) · \(app.ingestProgress.current)")
                .font(Typo.mono)
                .foregroundStyle(Palette.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(Metric.paneInset)
    }

    private func activate() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.canBecomeMain }) {
            w.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
    }
}

private struct MenuBarRow: View {
    let date: String
    let status: FolderStatus
    let undecided: Int
    let total: Int
    let action: () -> Void

    @StateObject private var hover = ViewState(false)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(date)
                    .font(Typo.mono)
                    .foregroundStyle(Palette.secondary)
                DecisionBadge(text: status.rawValue, color: status.color, compact: true)
                Spacer(minLength: 0)
                Text("\(undecided)/\(total)")
                    .font(Typo.number)
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(hover.value ? Palette.hover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.value = $0 }
    }
}

private struct MenuBarButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @StateObject private var hover = ViewState(false)

    init(_ title: String, icon: String, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 15)
                Text(title).font(Typo.body)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .foregroundStyle(hover.value ? Palette.label : Palette.secondary)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(hover.value ? Palette.hover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.value = $0 }
    }
}

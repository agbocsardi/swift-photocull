import SwiftUI
import AppKit
import PhotoCullCore

/// Sidebar: the list of inbox sessions. Uses native sidebar row styling —
/// subtle hover, quiet selection, no heavy borders.
struct SessionsPane: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(text: "Sessions", number: 1,
                          focused: app.focusedPane == .sessions,
                          trailing: AnyView(trailing))

            if app.visibleSessions.isEmpty {
                EmptyState(icon: "photo.stack",
                           title: app.sessions.isEmpty ? "No sessions" : "Nothing matches",
                           message: app.sessions.isEmpty
                             ? "Ingest photos from an SD card to start culling."
                             : "No sessions match the “\(app.filter.label)” filter.",
                           actionTitle: app.sessions.isEmpty ? "Ingest Photos…" : nil,
                           action: app.sessions.isEmpty ? { app.beginIngest() } : nil)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(app.visibleSessions) { row in
                                SessionRowView(row: row)
                                    .id(row.date)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, Metric.elementGap)
                    }
                    .onChange(of: app.cursorDate) { _, new in
                        guard let new else { return }
                        withAnimation(Motion.fast) { proxy.scrollTo(new, anchor: .center) }
                    }
                }
            }
        }
        .background(Surface.chrome)
    }

    private var trailing: some View {
        HStack(spacing: 6) {
            if !app.selectedDates.isEmpty {
                Button {
                    withAnimation(Motion.fast) { app.clearSelection() }
                } label: {
                    Text("\(app.selectedDates.count) ✕")
                        .font(Typo.caption.weight(.semibold))
                        .foregroundStyle(Palette.warning)
                }
                .buttonStyle(.plain)
                .help("Clear selection (Esc)")
            }
            Button { app.cycleFilter() } label: {
                Text(app.filter.label)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiary)
            }
            .buttonStyle(.plain)
            .help("Show next session filter (Tab when Sessions is focused)")
        }
    }
}

/// One session row. Selection is quiet — a soft fill plus a bold date — as in
/// native sidebars, rather than a loud colour block.
private struct SessionRowView: View {
    @EnvironmentObject var app: AppState
    let row: SessionRow

    @StateObject private var hover = ViewState(false)

    private var isCursor: Bool { app.cursorDate == row.date }
    private var isActive: Bool { app.activeDate == row.date }
    private var isSelected: Bool { app.selectedDates.contains(row.date) }
    private var undecided: Int { row.total - row.keep - row.reject }

    var body: some View {
        HStack(spacing: 8) {
            // Progressive disclosure: the selection control only appears when the
            // row is hovered, selected, or the sidebar has keyboard focus.
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Palette.accent : Palette.secondary.opacity(0.6))
                .opacity(showsSelectionControl ? 1 : 0)
                .onTapGesture { withAnimation(Motion.fast) { app.toggleSelection(row.date) } }
                .help(isSelected ? "Remove from multi-session selection" : "Select for multi-session finalize")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.date)
                        .font(isActive ? Typo.headline : Typo.body)
                        .foregroundStyle(isActive ? Palette.label : Palette.secondary)
                    Spacer(minLength: 0)
                    DecisionBadge(text: row.status.rawValue, color: row.status.color, compact: true)
                }

                HStack(spacing: 8) {
                    Text("\(undecided)/\(row.total)")
                        .font(Typo.number)
                        .foregroundStyle(Palette.secondary)
                        .help("Undecided / total photos")
                    if row.keep > 0 {
                        Text("\(row.keep)")
                            .font(Typo.number).foregroundStyle(Palette.keep)
                            .help("Kept photos")
                    }
                    if row.reject > 0 {
                        Text("\(row.reject)")
                            .font(Typo.number).foregroundStyle(Palette.reject)
                            .help("Rejected photos")
                    }
                    if row.cropped > 0 {
                        Image(systemName: "crop")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.crop)
                            .help("\(row.cropped) cropped")
                    }
                    Spacer(minLength: 0)
                }

                ProgressLine(value: row.progress,
                             tint: row.status == .complete ? Palette.keep : Palette.accent)
                    .opacity(row.status == .unstarted ? 0.4 : 1)
            }
        }
        .padding(.horizontal, Metric.paneInset - 4)
        .padding(.vertical, 4)
        .frame(minHeight: Metric.sidebarRow)
        .background(
            RoundedRectangle(cornerRadius: Metric.radiusButton, style: .continuous)
                .fill(fill)
        )
        .contentShape(Rectangle())
        .onHover { hover.value = $0 }
        .onTapGesture { handleRowClick() }
        .help("\(row.date) — click to open, ⌘-click to select for multi-finalize")
        .contextMenu {
            Button("Open") { app.open(date: row.date) }
            Button("Finalize…") { app.finalizeStats = (try? [Finalize.summary(cfg: app.cfg, date: row.date)]) ?? []
                                    app.modal = .finalize(date: row.date) }
            Divider()
            Button(isSelected ? "Deselect" : "Select for Multi-Finalize") {
                app.toggleSelection(row.date)
            }
        }
    }

    /// Mouse parity with the keyboard: a plain click opens the session (Enter),
    /// ⌘-click toggles it in the multi-finalize selection (Space) — the native
    /// macOS multi-select idiom.
    private func handleRowClick() {
        let mods = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command) {
            withAnimation(Motion.fast) { app.toggleSelection(row.date) }
        } else if row.date == app.activeDate {
            app.cursorDate = row.date
        } else {
            app.open(date: row.date)
        }
    }

    private var showsSelectionControl: Bool {
        isSelected || hover.value || (isCursor && app.focusedPane == .sessions)
    }

    private var fill: Color {
        if isActive { return Palette.accent.opacity(0.16) }
        if isCursor { return Palette.quaternary.opacity(0.28) }
        if hover.value { return Palette.quaternary.opacity(0.16) }
        return .clear
    }
}

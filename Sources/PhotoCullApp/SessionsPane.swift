import SwiftUI
import PhotoCullCore

struct SessionsPane: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        PaneBox(number: 1, title: "Sessions",
                focused: app.focusedPane == .sessions,
                trailing: AnyView(trailing)) {
            if app.visibleSessions.isEmpty {
                EmptyHint(text: app.sessions.isEmpty
                          ? "No sessions in inbox.\nPress ⌘I to ingest photos."
                          : "No sessions match the “\(app.filter.label)” filter.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(app.visibleSessions) { row in
                                SessionRowView(row: row)
                                    .id(row.date)
                            }
                        }
                        .padding(4)
                    }
                    .onChange(of: app.cursorDate) { _, new in
                        guard let new else { return }
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(new, anchor: .center) }
                    }
                }
            }
        }
    }

    private var trailing: some View {
        HStack(spacing: 5) {
            if !app.selectedDates.isEmpty {
                Button {
                    app.clearSelection()
                } label: {
                    Text("\(app.selectedDates.count) selected ✕")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(EF.yellow)
                }
                .buttonStyle(.borderless)
                .help("Clear selection (Esc)")
            }
            Text(app.filter.label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(EF.subtle)
                .help("Cycle filter (Tab)")
        }
    }
}

private struct SessionRowView: View {
    @EnvironmentObject var app: AppState
    let row: SessionRow

    private var isCursor: Bool { app.cursorDate == row.date }
    private var isActive: Bool { app.activeDate == row.date }
    private var isSelected: Bool { app.selectedDates.contains(row.date) }

    var body: some View {
        HStack(spacing: 7) {
            Button {
                app.toggleSelection(row.date)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? EF.blue : EF.bg3)
            }
            .buttonStyle(.borderless)
            .help("Select for multi-session finalize (Space)")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.date)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isActive ? EF.text : EF.subtle)
                    Badge(text: row.status.rawValue, color: row.status.color)
                }
                HStack(spacing: 7) {
                    Text("\(row.total - row.keep - row.reject)/\(row.total)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(EF.bg3)
                        .help("undecided / total")
                    if row.keep > 0 {
                        Text("✓\(row.keep)").font(.system(size: 9, design: .monospaced)).foregroundStyle(EF.green)
                    }
                    if row.reject > 0 {
                        Text("✗\(row.reject)").font(.system(size: 9, design: .monospaced)).foregroundStyle(EF.red)
                    }
                    if row.cropped > 0 {
                        Text("▣\(row.cropped)").font(.system(size: 9, design: .monospaced)).foregroundStyle(EF.yellow)
                            .help("cropped photos")
                    }
                }
                ProgressBar(value: row.progress)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isCursor ? EF.bg1 : Color.clear)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isActive ? EF.blue : Color.clear)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { app.open(date: row.date) }
        .onTapGesture { app.cursorDate = row.date }
    }
}

struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(EF.bg3.opacity(0.45))
                Capsule().fill(EF.green.opacity(0.75))
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 3)
    }
}

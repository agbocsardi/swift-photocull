import SwiftUI
import PhotoCullCore

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var leftWidth = ViewState<CGFloat>(268)

    var body: some View {
        ZStack {
            EF.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderBar()
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        SessionsPane()
                            .frame(maxHeight: .infinity)
                        InfoPane()
                            .frame(height: 208)
                    }
                    .frame(width: leftWidth.value)

                    ResizeHandle(width: $leftWidth.value)

                    VStack(spacing: 0) {
                        ImagePane()
                            .frame(maxHeight: .infinity)
                        FilmstripPane()
                            .frame(height: 116)
                    }
                }
                .padding(6)

                FooterBar()
            }

            if app.commandMode { CommandBar() }

            if let toast = app.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(EF.bg)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(EF.aqua))
                        .padding(.bottom, 44)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            if app.modal == .help { HelpOverlay() }
            if app.modal == .ingest { IngestSheet() }
            if app.showingFinalizeSheet { FinalizeSheet() }
        }
        .background(EF.bg)
        .onAppear {
            KeyMonitor.shared.handler = { [weak app] key in
                guard let app else { return false }
                return app.handle(key)
            }
            KeyMonitor.shared.start()
        }
    }
}

// MARK: - Header

struct HeaderBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 8) {
            Text("photocull")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(EF.text)

            Text("·").foregroundStyle(EF.bg3)

            if let date = app.activeDate {
                Text(date)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(EF.blue)
                Text("·").foregroundStyle(EF.bg3)
                Text("[\(app.pairs.isEmpty ? 0 : app.index + 1)/\(app.pairs.count)]")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(EF.subtle)
                if let stem = app.currentStem {
                    Text("\(stem).JPG")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(EF.text)
                        .lineLimit(1)
                }
                Badge(text: app.currentDecision.label, color: app.currentDecision.color, filled: true)
                if app.hasCrop { Badge(text: "CROP", color: EF.yellow) }
                if app.currentPair?.hasRAW == true {
                    Badge(text: "+\(app.currentPair?.rawExt ?? "RAW")", color: EF.aqua)
                }
            } else {
                Text("no session").font(.system(size: 11, design: .monospaced)).foregroundStyle(EF.subtle)
            }

            Spacer(minLength: 12)

            Button {
                app.beginIngest()
            } label: {
                Label("Ingest", systemImage: "square.and.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(EF.aqua)
            .help("Ingest photos from an SD card (⌘I)")

            Button {
                app.beginGlobalFinalize()
            } label: {
                Label("Finalize", systemImage: "checkmark.circle")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(EF.green)
            .disabled(app.visibleSessions.isEmpty)
            .help("Finalize sessions (⌘F)")

            Button {
                app.modal = .help
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(EF.subtle)
            .help("Keyboard shortcuts (?)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(EF.bg1)
        .overlay(alignment: .bottom) { Divider().overlay(EF.bg3) }
    }
}

// MARK: - Footer

struct FooterBar: View {
    @EnvironmentObject var app: AppState

    private var hints: [(String, String)] {
        if app.cropMode {
            return [("←↑↓→", "move"), ("⇧←↑↓→", "resize"), ("a", "aspect"),
                    ("r", "reset"), ("p", "preview"), ("⏎", "apply"), ("Esc", "cancel")]
        }
        return [("z", "keep"), ("x", "reject"), ("c", "crop"), ("j/k", "next/prev"),
                ("J/K", "undecided"), ("o", "preview"), ("1-4", "pane"),
                ("Tab", "filter"), (":f", "finalize"), (":F", "finalize all"),
                (":i", "ingest"), ("?", "help")]
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(hints, id: \.0) { key, label in
                HStack(spacing: 3) {
                    Keycap(key: key)
                    Text(label)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(EF.bg3)
                }
            }
            Spacer(minLength: 0)
            if app.imageLoader.isLoading {
                ProgressView().controlSize(.mini).scaleEffect(0.6)
            }
            Text(app.cfg.paths.inbox.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(EF.bg3)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(EF.bg1)
        .overlay(alignment: .top) { Divider().overlay(EF.bg3) }
    }
}

// MARK: - Command bar

struct CommandBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                Text(":").foregroundStyle(EF.green)
                Text(app.commandBuffer)
                    .foregroundStyle(EF.text)
                Rectangle().fill(EF.aqua).frame(width: 7, height: 13)
                    .opacity(0.85)
                Spacer()
                Text("⏎ run · Esc cancel")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(EF.bg3)
            }
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 5).fill(EF.bg2))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(EF.green.opacity(0.5), lineWidth: 1))
            .padding(.horizontal, 60)
            .padding(.bottom, 48)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Resize handle

struct ResizeHandle: View {
    @Binding var width: CGFloat
    @StateObject private var drag = ViewState<CGFloat?>(nil)

    var body: some View {
        Rectangle()
            .fill(EF.bg3.opacity(0.5))
            .frame(width: 4)
            .contentShape(Rectangle().inset(by: -3))
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if drag.value == nil { drag.value = width }
                        width = min(max(180, (drag.value ?? width) + value.translation.width), 460)
                    }
                    .onEnded { _ in drag.value = nil }
            )
    }
}

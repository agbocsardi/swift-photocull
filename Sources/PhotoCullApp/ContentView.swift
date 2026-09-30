import SwiftUI
import AppKit
import PhotoCullCore

/// The app window: a native sidebar + content + inspector arrangement
/// (NavigationSplitView), a unified toolbar for global actions, and a status bar.
struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationSplitView {
            SessionsPane()
                .navigationSplitViewColumnWidth(min: Metric.sidebarMin,
                                                ideal: Metric.sidebarIdeal,
                                                max: 340)
        } detail: {
            VStack(spacing: 0) {
                ImagePane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider().overlay(Palette.separator)
                FilmstripPane()
                    .frame(height: Metric.filmstripHeight)
                Divider().overlay(Palette.separator)
                StatusBar()
            }
            .background(Palette.window)
            .inspector(isPresented: $app.showInspector) {
                InfoPane()
                    .inspectorColumnWidth(min: 220, ideal: Metric.inspectorWidth, max: 380)
            }
        }
        .navigationTitle(app.activeDate ?? "PhotoCull")
        .background(Palette.window)
        .toolbar { toolbarContent }
        .overlay(alignment: .bottom) { ToastView() }
        .sheet(item: $app.modal) { modal in
            switch modal {
            case .help:      HelpSheet()
            case .ingest:    IngestSheet()
            case .settings:  HelpSheet()
            case .finalize, .globalFinalize: FinalizeSheet()
            }
        }
        .onAppear {
            KeyMonitor.shared.handler = { [weak app] key in
                guard let app else { return false }
                return app.handle(key)
            }
            KeyMonitor.shared.start()
            // `--crop` opens crop mode so the overlay can be inspected in a snapshot.
            if CommandLine.arguments.contains("--crop") {
                app.enterCropMode()
                app.cropRect = CropRect(x: 0.14, y: 0.08, w: 0.62, h: 0.78)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Counter + current file + state, centred in the unified toolbar.
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                if app.activeDate != nil {
                    Text("[\(app.pairs.isEmpty ? 0 : app.index + 1)/\(app.pairs.count)]")
                        .font(Typo.number)
                        .foregroundStyle(Palette.secondary)
                    if let stem = app.currentStem {
                        Text("\(stem).JPG")
                            .font(Typo.mono)
                            .foregroundStyle(Palette.label)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 220)
                    }
                    DecisionBadge(text: app.currentDecision.label,
                                  color: app.currentDecision.color,
                                  filled: app.currentDecision != .undecided)
                    if app.hasCrop { DecisionBadge(text: "CROP", color: Palette.crop) }
                    if app.currentPair?.hasRAW == true {
                        DecisionBadge(text: "+\(app.currentPair?.rawExt ?? "RAW")", color: Palette.raw)
                    }
                } else {
                    Text("No session selected")
                        .font(Typo.body)
                        .foregroundStyle(Palette.tertiary)
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                app.beginIngest()
            } label: {
                Label("Ingest", systemImage: "square.and.arrow.down")
            }
            .help("Ingest photos from an SD card (⌘⇧I)")

            Button {
                app.beginGlobalFinalize()
            } label: {
                Label("Finalize", systemImage: "checkmark.circle")
            }
            .disabled(app.visibleSessions.isEmpty)
            .help("Finalize sessions (⌘⇧F)")

            Button {
                app.toggleInspector()
            } label: {
                Label("Info", systemImage: "sidebar.right")
            }
            .help("Show or hide the info inspector (⌘I)")

            Button {
                app.modal = .help
            } label: {
                Label("Help", systemImage: "questionmark.circle")
            }
            .help("Keyboard shortcuts (?)")
        }
    }
}

// MARK: - Status bar

/// Thin bottom bar: key hints on the left, inbox location on the right.
struct StatusBar: View {
    @EnvironmentObject var app: AppState

    private var hints: [(String, String)] {
        if app.cropMode {
            return [("←↑↓→", "move"), ("⇧←↑↓→", "resize"), ("a", "aspect"),
                    ("r", "reset"), ("⏎", "apply"), ("esc", "cancel")]
        }
        return [("z", "keep"), ("x", "reject"), ("c", "crop"), ("←/→", "prev/next"),
                ("J/K", "undecided"), ("o", "preview"), ("1-4", "pane"),
                ("tab", "filter"), (":f", "finalize"), ("?", "help")]
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(hints, id: \.0) { key, label in
                HStack(spacing: 3) {
                    Keycap(key: key)
                    Text(label)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 8)
            if app.imageLoader.isLoading {
                ProgressView().controlSize(.mini).scaleEffect(0.55)
            }
            Text(app.cfg.paths.inbox.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(Typo.mono)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, Metric.paneInset)
        .frame(height: Metric.statusHeight)
        .background(Surface.chrome)
    }
}

// MARK: - Toast

/// Lightweight confirmation that slides in and fades away.
struct ToastView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if let toast = app.toast {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.keep)
                Text(toast)
                    .font(Typo.callout)
                    .foregroundStyle(Palette.label)
            }
            .padding(.horizontal, Metric.paneInset)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous).fill(Surface.floating)
            )
            .overlay(Capsule(style: .continuous).strokeBorder(Palette.separator, lineWidth: 0.5))
            .shadowMedium()
            .padding(.bottom, Metric.floatingBottom)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(false)
            .animation(Motion.normal, value: toast)
        }
    }
}

// MARK: - Command bar

/// Vim-style `:` command entry. Floats over the content, dismissed with Esc.
struct CommandBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                Text(":").foregroundStyle(Palette.accent)
                Text(app.commandBuffer).foregroundStyle(Palette.label)
                Rectangle()
                    .fill(Palette.accent)
                    .frame(width: 1.5, height: 14)
                    .opacity(0.9)
                Spacer(minLength: 40)
                Text("⏎ run · esc cancel")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiary)
            }
            .font(Typo.body)
            .padding(.horizontal, Metric.paneInset)
            .frame(height: 32)
            .frame(maxWidth: 460)
            .background(RoundedRectangle(cornerRadius: Metric.radiusCard, style: .continuous)
                .fill(Surface.floating))
            .overlay(RoundedRectangle(cornerRadius: Metric.radiusCard, style: .continuous)
                .strokeBorder(Palette.separator, lineWidth: 0.5))
            .shadowMedium()
            .padding(.bottom, Metric.floatingBottom)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

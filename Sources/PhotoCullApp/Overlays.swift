import SwiftUI
import PhotoCullCore

// MARK: - Help

struct HelpOverlay: View {
    @EnvironmentObject var app: AppState

    private let actions: [(String, String)] = [
        ("z", "mark keep (toggle)"),
        ("x", "mark reject (toggle)"),
        ("c", "crop mode"),
        ("o", "open in Preview"),
        ("f", "reveal in Finder"),
        (":f", "finalize current session"),
        (":F", "finalize selected sessions"),
        (":i", "ingest photos (SD card)"),
        (":c", "crop current photo"),
        ("Space", "toggle session selection"),
    ]
    private let nav: [(String, String)] = [
        ("j / k", "next / previous photo"),
        ("J / K", "next / previous undecided"),
        ("h / l", "cycle session when pane 1 focused"),
        ("1–4", "focus pane"),
        ("Enter", "open session / apply crop"),
        ("Tab", "cycle session filter"),
        ("+ / -", "zoom in / out"),
        ("0", "fit to window"),
        ("Esc", "cancel crop / close overlay / clear selection"),
    ]
    private let crop: [(String, String)] = [
        ("← ↑ ↓ →", "move crop region"),
        ("⇧ + arrows", "resize crop region"),
        ("drag handles", "resize crop with the mouse"),
        ("drag inside", "move crop with the mouse"),
        ("a", "cycle aspect ratio"),
        ("r", "reset crop to full frame"),
        ("p", "toggle cropped preview"),
        ("Enter", "apply crop"),
        ("Esc", "cancel crop"),
    ]

    var body: some View {
        OverlayShell(title: "Keyboard shortcuts", onClose: { app.modal = nil }) {
            HStack(alignment: .top, spacing: 28) {
                column("Actions", actions)
                column("Navigation", nav)
                column("Crop mode", crop)
            }
        }
    }

    private func column(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(EF.aqua)
                .padding(.bottom, 2)
            ForEach(rows, id: \.0) { key, label in
                HStack(spacing: 7) {
                    Keycap(key: key)
                    Text(label)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(EF.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minWidth: 210, alignment: .leading)
    }
}

// MARK: - Overlay shell

struct OverlayShell<Content: View>: View {
    let title: String
    var width: CGFloat = 720
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(EF.text)
                    Spacer()
                    Button("Close") { onClose() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(EF.subtle)
                }
                content()
            }
            .padding(18)
            .frame(width: width, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(EF.bg2))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(EF.bg3, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        }
    }
}

// MARK: - Finalize

struct FinalizeSheet: View {
    @EnvironmentObject var app: AppState

    private var totals: (keep: Int, reject: Int, undecided: Int, photos: Int) {
        app.finalizeStats.reduce(into: (0, 0, 0, 0)) { acc, s in
            acc.0 += s.keep; acc.1 += s.reject; acc.2 += s.undecided; acc.3 += s.total
        }
    }

    var body: some View {
        OverlayShell(title: app.finalizeStats.count == 1
                     ? "Finalize \(app.finalizeStats.first?.date ?? "")"
                     : "Finalize \(app.finalizeStats.count) sessions",
                     width: 660,
                     onClose: { app.modal = nil }) {
            VStack(alignment: .leading, spacing: 12) {
                tableRow(header: true, cells: ["Session", "Keep", "Reject", "Undecided", "Total"])
                Divider().overlay(EF.bg3)
                ForEach(app.finalizeStats, id: \.date) { s in
                    tableRow(header: false, cells: ["\(s.date)", "\(s.keep)", "\(s.reject)",
                                                    "\(s.undecided)", "\(s.total)"])
                }
                Divider().overlay(EF.bg3)
                let t = totals
                tableRow(header: false, bold: true,
                         cells: ["Total", "\(t.keep)", "\(t.reject)", "\(t.undecided)", "\(t.photos)"])

                if totals.undecided > 0 {
                    Text("Undecided photos are treated as KEEP.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(EF.yellow)
                }

                Picker("Kept JPGs copied to \(app.cfg.paths.dump.replacingOccurrences(of: NSHomeDirectory(), with: "~"))", selection: $app.cropExportMode) {
                    Text("with crop applied").tag(CropExportMode.applyCrop)
                    Text("originals").tag(CropExportMode.original)
                }
                .pickerStyle(.radioGroup)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(EF.text)

                Text("Rejects (JPG + paired RAW) move to the Trash.\nKeepers move to archive/<date>/. Originals are never modified.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(EF.bg3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("Cancel (n)") { app.modal = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Confirm (y)") { app.confirmFinalize() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func tableRow(header: Bool, bold: Bool = false, cells: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, cell in
                Text(cell)
                    .font(.system(size: 11, weight: header || bold ? .bold : .regular, design: .monospaced))
                    .foregroundStyle(color(for: i, header: header))
                    .frame(width: i == 0 ? 170 : 88, alignment: i == 0 ? .leading : .trailing)
            }
            Spacer(minLength: 0)
        }
    }

    private func color(for column: Int, header: Bool) -> Color {
        if header { return EF.bg3 }
        switch column {
        case 1: return EF.green
        case 2: return EF.red
        case 3: return EF.subtle
        default: return EF.text
        }
    }
}

// MARK: - Ingest

struct IngestSheet: View {
    @EnvironmentObject var app: AppState
    @FocusState private var pathFocused: Bool

    var body: some View {
        OverlayShell(title: "Ingest photos", width: 640, onClose: {
            if !app.ingestProgress.running { app.modal = nil }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                if app.detectedCards.isEmpty {
                    Text("No SD card detected under /Volumes/ with a DCIM folder.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(EF.yellow)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Detected card\(app.detectedCards.count > 1 ? "s" : "")")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(EF.aqua)
                        ForEach(app.detectedCards, id: \.path) { url in
                            Button {
                                app.ingestSource = url.path
                            } label: {
                                Text(url.path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(app.ingestSource == url.path ? EF.blue : EF.text)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text("Source")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(EF.bg3)
                    TextField("/Volumes/SDCARD/DCIM", text: $app.ingestSource)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .focused($pathFocused)
                        .disabled(app.ingestProgress.running)
                    Button("Choose…") { chooseFolder() }
                        .disabled(app.ingestProgress.running)
                }

                if app.ingestProgress.running || app.ingestProgress.done {
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: Double(app.ingestProgress.copied),
                                     total: Double(max(1, app.ingestProgress.total)))
                            .tint(EF.green)
                        HStack {
                            Text("\(app.ingestProgress.copied)/\(app.ingestProgress.total) copied")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(EF.subtle)
                            Spacer()
                            Text(app.ingestProgress.current)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(EF.bg3)
                                .lineLimit(1)
                        }
                        if let err = app.ingestProgress.error {
                            Text(err)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(EF.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Text("Photos are copied (never moved) into \(app.cfg.paths.inbox.replacingOccurrences(of: NSHomeDirectory(), with: "~"))/<capture-date>/ . The card stays untouched until you erase it.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(EF.bg3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("Close") { app.modal = nil }
                        .disabled(app.ingestProgress.running)
                    Button("Start Ingest") { app.startIngest() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(app.ingestProgress.running || app.ingestSource.isEmpty)
                }
            }
        }
        .onAppear { pathFocused = false }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose source"
        if panel.runModal() == .OK, let url = panel.url { app.ingestSource = url.path }
    }
}

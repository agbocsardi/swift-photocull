import SwiftUI
import PhotoCullCore

struct InfoPane: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        PaneBox(number: 3, title: "Info", focused: app.focusedPane == .info) {
            if app.currentPair == nil {
                EmptyHint(text: "No photo selected")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        row("Camera", app.info.camera)
                        row("Lens", app.info.lens)
                        row("ISO", app.info.iso)
                        row("Shutter", app.info.shutter)
                        row("Aperture", app.info.aperture)
                        row("Size", app.info.size)
                        row("Captured", app.info.dateTimeOriginal)
                        rawRow
                        cropRow
                        fileRow
                    }
                    .padding(8)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        Group {
            if let value, !value.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text(label)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(EF.bg3)
                        .frame(width: 62, alignment: .leading)
                    Text(value)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(EF.text)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var rawRow: some View {
        HStack(spacing: 8) {
            Text("RAW")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(EF.bg3)
                .frame(width: 62, alignment: .leading)
            if let ext = app.currentPair?.rawExt {
                Text("+\(ext)").font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(EF.aqua)
            } else {
                Text("—").font(.system(size: 10, design: .monospaced)).foregroundStyle(EF.bg3)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }

    private var cropRow: some View {
        HStack(spacing: 8) {
            Text("Crop")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(EF.bg3)
                .frame(width: 62, alignment: .leading)
            if let crop = app.currentCrop, !crop.isFullFrame {
                Text(String(format: "%.0f%% × %.0f%%",
                            crop.w * 100, crop.h * 100))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(EF.yellow)
                Button("clear") { app.clearCrop() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(EF.red)
            } else {
                Text("full frame").font(.system(size: 10, design: .monospaced)).foregroundStyle(EF.bg3)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }

    private var fileRow: some View {
        Group {
            if let url = app.currentPair?.jpg {
                HStack(alignment: .top, spacing: 8) {
                    Text("File")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(EF.bg3)
                        .frame(width: 62, alignment: .leading)
                    Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(EF.bg3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
        }
    }
}

struct EmptyHint: View {
    let text: String
    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(EF.bg3)
                .multilineTextAlignment(.center)
                .padding(16)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

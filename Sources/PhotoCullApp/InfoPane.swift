import SwiftUI
import PhotoCullCore

/// Right-hand inspector: everything known about the current photo.
/// Grouped in labelled sections, in the macOS inspector idiom.
struct InfoPane: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(text: "Info", number: 3,
                          focused: app.focusedPane == .info,
                          trailing: AnyView(
                Button {
                    app.toggleInspector()
                } label: {
                    Image(systemName: "sidebar.right").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.tertiary)
                .help("Hide the inspector (⌘I)")
            ))

            if app.currentPair == nil {
                EmptyState(icon: "info.circle",
                           title: "No photo",
                           message: "Select a session, then a photo, to see its details.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        group("Photo") {
                            InspectorRow(label: "File", value: app.currentStem.map { "\($0).JPG" }, mono: true)
                            InspectorRow(label: "Size", value: app.info.size)
                            InspectorRow(label: "Captured", value: app.info.dateTimeOriginal)
                            InspectorRow(label: "RAW",
                                         value: app.currentPair?.rawExt.map { "+\($0)" } ?? "—",
                                         tint: app.currentPair?.hasRAW == true ? Palette.raw : Palette.quaternary)
                        }

                        group("Camera") {
                            InspectorRow(label: "Model", value: app.info.camera)
                            InspectorRow(label: "Lens", value: app.info.lens)
                            InspectorRow(label: "ISO", value: app.info.iso)
                            InspectorRow(label: "Shutter", value: app.info.shutter)
                            InspectorRow(label: "Aperture", value: app.info.aperture)
                        }

                        group("Cull") {
                            InspectorRow(label: "Decision", value: nil) {
                                DecisionBadge(text: app.currentDecision.label,
                                              color: app.currentDecision.color,
                                              filled: app.currentDecision != .undecided)
                            }

                            InspectorRow(label: "Crop", value: nil) {
                                if let crop = app.currentCrop, !crop.isFullFrame {
                                    Text(String(format: "%.0f%% × %.0f%%", crop.w * 100, crop.h * 100))
                                        .font(Typo.callout)
                                        .foregroundStyle(Palette.crop)
                                    Button("Clear") { app.clearCrop() }
                                        .buttonStyle(.plain)
                                        .font(Typo.caption)
                                        .foregroundStyle(Palette.reject)
                                        .help("Remove the saved crop; the original photo stays unchanged")
                                } else {
                                    Text("Full frame")
                                        .font(Typo.callout)
                                        .foregroundStyle(Palette.quaternary)
                                }
                            }

                            InspectorRow(label: "Position",
                                         value: app.pairs.isEmpty ? nil : "\(app.index + 1) of \(app.pairs.count)",
                                         tint: nil)
                        }

                        group("Location") {
                            Text(app.currentPair?.jpg.path
                                    .replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "")
                                .font(Typo.mono)
                                .foregroundStyle(Palette.tertiary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 10)
                        }
                    }
                }
            }
        }
        .background(Surface.chrome)
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        SectionHeader(text: title)
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, Metric.paneInset)
        .padding(.bottom, Metric.elementGap)
    }
}

import SwiftUI
import PhotoCullCore

/// The content area: the photo itself, on an opaque neutral canvas, with a
/// floating action bar for the actions that apply to the current photo.
struct ImagePane: View {
    @EnvironmentObject var app: AppState

    /// What the pane actually draws (cropped preview, or the full frame in crop mode).
    private var displayImage: CGImage? {
        guard let img = app.imageLoader.current else { return nil }
        if app.cropMode { return img }
        if app.showCroppedPreview, let crop = app.currentCrop, !crop.isFullFrame {
            return ImagePipeline.crop(img, to: crop) ?? img
        }
        return img
    }

    var body: some View {
        ZStack {
            // Opaque canvas: content areas should not be translucent.
            Color(nsColor: .underPageBackgroundColor)

            if let cg = displayImage {
                GeometryReader { geo in
                    let container = geo.size
                    let base = fitSize(CGSize(width: cg.width, height: cg.height), into: container)
                    let shown = CGSize(width: base.width * app.zoom, height: base.height * app.zoom)
                    let origin = CGPoint(
                        x: (container.width - shown.width) / 2 + app.pan.width,
                        y: (container.height - shown.height) / 2 + app.pan.height)

                    ZStack(alignment: .topLeading) {
                        Image(decorative: cg, scale: 1)
                            .resizable()
                            .interpolation(app.zoom > 1.5 ? .none : .high)
                            .frame(width: shown.width, height: shown.height)
                            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                            .offset(x: origin.x, y: origin.y)

                        if app.cropMode {
                            CropOverlay(
                                rect: $app.cropRect,
                                imageRect: CGRect(origin: origin, size: shown),
                                aspect: app.cropAspect.ratio,
                                onAspectRequest: { app.applyAspect() }
                            )
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                guard !app.cropMode else { return }
                                app.pan = CGSize(width: value.translation.width,
                                                 height: value.translation.height)
                            }
                    )
                }
            } else if app.imageLoader.isLoading {
                ProgressView().controlSize(.small)
            } else if app.activeDate == nil {
                EmptyState(icon: "photo.on.rectangle.angled",
                           title: "No session selected",
                           message: "Pick a session in the sidebar to start culling.",
                           actionTitle: app.sessions.isEmpty ? "Ingest Photos…" : nil,
                           action: app.sessions.isEmpty ? { app.beginIngest() } : nil)
            } else {
                EmptyState(icon: "photo",
                           title: "No photos",
                           message: "This session has no JPG files.")
            }

            // Floating action bar, previews only.
            if displayImage != nil, !app.cropMode {
                VStack {
                    Spacer()
                    FloatingActionBar()
                        .padding(.bottom, Metric.elementGap * 2)
                }
            }

            if app.commandMode {
                CommandBar()
            }
        }
        // Pane 2 marker, so the numbered keyboard map stays discoverable.
        .overlay(alignment: .topLeading) {
            HStack(spacing: Metric.elementGap - 2) {
                PaneBadge(number: 2, focused: app.focusedPane == .image)
                if app.cropMode {
                    Text("CROP MODE")
                        .font(Typo.sectionHeader)
                        .tracking(0.4)
                        .foregroundStyle(Palette.crop)
                }
            }
            .padding(.horizontal, app.cropMode ? Metric.elementGap : 0)
            .padding(.vertical, app.cropMode ? 5 : 0)
            .background(
                Capsule(style: .continuous)
                    .fill(app.cropMode ? AnyShapeStyle(Surface.floating) : AnyShapeStyle(Color.clear))
            )
            .padding(Metric.paneInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.normal, value: app.cropMode)
    }

    private func fitSize(_ size: CGSize, into container: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, container.width > 0, container.height > 0 else {
            return CGSize(width: 1, height: 1)
        }
        let pad: CGFloat = Metric.canvasPad
        let avail = CGSize(width: max(1, container.width - pad), height: max(1, container.height - pad))
        let scale = min(avail.width / size.width, avail.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

/// Pill-shaped action bar over the photo: icons with tooltips, vibrancy + shadow.
struct FloatingActionBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 2) {
            action(app.currentDecision == .keep ? "checkmark.circle.fill" : "checkmark.circle",
                   tint: Palette.keep, tip: "Keep (z)", filled: app.currentDecision == .keep) {
                app.mark(.keep)
            }
            action(app.currentDecision == .reject ? "xmark.circle.fill" : "xmark.circle",
                   tint: Palette.reject, tip: "Reject (x)", filled: app.currentDecision == .reject) {
                app.mark(.reject)
            }

            Divider().frame(height: 16).overlay(Palette.separator)

            action("crop", tint: app.hasCrop ? Palette.crop : Palette.secondary,
                   tip: app.hasCrop ? "Adjust crop (c)" : "Crop (c)", filled: false) {
                app.enterCropMode()
            }
            action(app.showCroppedPreview ? "rectangle.inset.filled" : "rectangle",
                   tint: Palette.secondary,
                   tip: app.showCroppedPreview ? "Show full frame (p)" : "Show cropped (p)",
                   filled: false) {
                app.showCroppedPreview.toggle()
            }

            Divider().frame(height: 16).overlay(Palette.separator)

            action("minus.magnifyingglass", tint: Palette.secondary, tip: "Zoom out (−)", filled: false) {
                app.zoomOut()
            }
            Text(String(format: "%.0f%%", app.zoom * 100))
                .font(Typo.number)
                .foregroundStyle(Palette.secondary)
                .frame(width: 40)
            action("plus.magnifyingglass", tint: Palette.secondary, tip: "Zoom in (+)", filled: false) {
                app.zoomIn()
            }
            action("arrow.up.left.and.arrow.down.right", tint: Palette.secondary,
                   tip: "Fit to window (0)", filled: false) { app.resetZoom() }

            Divider().frame(height: 16).overlay(Palette.separator)

            action("arrow.up.forward.app", tint: Palette.secondary,
                   tip: "Open in Preview (o)", filled: false) { app.openInPreview() }
            action("folder", tint: Palette.secondary,
                   tip: "Reveal in Finder (f)", filled: false) { app.revealInFinder() }
        }
        .padding(.horizontal, Metric.elementGap)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(Surface.floating))
        .overlay(Capsule(style: .continuous).strokeBorder(Palette.separator, lineWidth: 0.5))
        .shadowMedium()
    }

    private func action(_ symbol: String, tint: Color, tip: String, filled: Bool,
                        _ run: @escaping () -> Void) -> some View {
        FloatingButton(symbol: symbol, tint: tint, tip: tip, filled: filled, run: run)
    }
}

/// Icon-only control for the floating bar: hover tint, tooltip, press feedback.
private struct FloatingButton: View {
    let symbol: String
    let tint: Color
    let tip: String
    let filled: Bool
    let run: () -> Void

    @StateObject private var hover = ViewState(false)

    var body: some View {
        Button(action: run) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(filled ? Color.white : tint)
                .frame(width: Metric.controlHeight, height: Metric.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: Metric.radiusButton, style: .continuous)
                        .fill(filled ? tint : (hover.value ? Palette.hover : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { hover.value = $0 }
        .help(tip)
    }
}

import SwiftUI
import PhotoCullCore

/// Pane 2 — the photo itself, on an opaque neutral canvas, with a floating
/// action bar. It carries the same header treatment as the other three panes so
/// the numbered keyboard map stays coherent.
struct ImagePane: View {
    @EnvironmentObject var app: AppState
    /// Keyboard focus on the tilt slider: arrows then nudge tilt.
    @FocusState private var tiltFocused: Bool
    /// 1-slot memo for the CPU edit pipeline (see `memoizedDisplayImage`).
    @StateObject private var memo = EditMemo()

    /// Everything the CPU-rendered bitmap depends on. In crop mode the CPU
    /// path stops after the quarter turn — live tilt is a GPU transform —
    /// so the key deliberately reads the CPU tilt/crop as unused there and
    /// slider ticks leave the memo valid.
    private struct EditKey: Equatable {
        var image: ObjectIdentifier?
        var quarterTurns: Int
        var cpuTilt: Double
        var crop: CropRect?
        var cropMode: Bool
        var showCroppedPreview: Bool
    }

    private final class EditMemo: ObservableObject {
        var key: EditKey?
        var image: CGImage?
    }

    /// What the pane draws: the exact edit pipeline the export runs
    /// (quarter turn → tilt → crop), so preview == output. Memoized to a
    /// single slot keyed on the pipeline inputs, so body evaluations that
    /// change nothing the bitmap depends on (pan/zoom drags, hover, toasts)
    /// reuse the previous CGImage instead of resampling ~45 MB per frame.
    /// In crop mode the CPU work stops after the quarter turn; the live tilt
    /// renders on the GPU (see body). Committing leaves crop mode, which
    /// changes the key and runs the real CPU pipeline once for the settled
    /// state — keeping at-rest pixels identical to the export.
    private func memoizedDisplayImage() -> CGImage? {
        guard let current = app.imageLoader.current else {
            if memo.key != nil { memo.key = nil; memo.image = nil }
            return nil
        }
        let cropMode = app.cropMode
        let cpuTilt = cropMode ? 0 : app.currentTilt
        var crop: CropRect?
        if !cropMode, app.showCroppedPreview, let c = app.currentCrop, !c.isFullFrame {
            crop = c
        }
        let key = EditKey(image: ObjectIdentifier(current),
                          quarterTurns: app.currentQuarterTurns,
                          cpuTilt: cpuTilt,
                          crop: crop,
                          cropMode: cropMode,
                          showCroppedPreview: app.showCroppedPreview)
        if memo.key == key, let cached = memo.image { return cached }

        var img = current
        if app.currentQuarterTurns != 0 {
            img = ImagePipeline.rotateQuarter(img, turns: app.currentQuarterTurns)
        }
        if cpuTilt != 0 {
            img = ImagePipeline.rotateToFill(img, degrees: cpuTilt)
        }
        if let crop {
            img = ImagePipeline.crop(img, to: crop) ?? img
        }
        memo.key = key
        memo.image = img
        return img
    }

    var body: some View {
        VStack(spacing: 0) {
            // Evaluate the pipeline exactly once per body; both the canvas
            // and the action-bar visibility below reuse this.
            let cg = memoizedDisplayImage()

            SectionHeader(text: "Canvas", number: 2,
                          focused: app.focusedPane == .image,
                          trailing: { trailing })

            ZStack {
                // Opaque canvas: content areas should not be translucent.
                Color(nsColor: .underPageBackgroundColor)

                if let cg {
                    GeometryReader { geo in
                        let container = geo.size
                        let base = fitSize(CGSize(width: cg.width, height: cg.height), into: container)
                        let shown = CGSize(width: base.width * app.zoom, height: base.height * app.zoom)
                        let origin = CGPoint(
                            x: (container.width - shown.width) / 2 + app.pan.width,
                            y: (container.height - shown.height) / 2 + app.pan.height)

                        ZStack(alignment: .topLeading) {
                            if app.cropMode {
                                liveTiltImage(cg: cg, shown: shown, origin: origin)
                            } else {
                                Image(decorative: cg, scale: 1)
                                    .resizable()
                                    .interpolation(app.zoom > 1.5 ? .none : .high)
                                    .frame(width: shown.width, height: shown.height)
                                    // Peak interaction cost: skip the
                                    // full-canvas Gaussian while cropping.
                                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                                    .offset(x: origin.x, y: origin.y)
                            }

                            if app.cropMode {
                                CropOverlay(
                                    rect: $app.cropRect,
                                    imageRect: CGRect(origin: origin, size: shown),
                                    aspect: app.cropAspect.ratio,
                                    onAspectRequest: { app.applyAspect() },
                                    onInteract: {
                                        if app.tiltFocused {
                                            tiltFocused = false
                                            app.tiltFocused = false
                                        }
                                    }
                                )
                            }
                            if app.cropMode {
                                VStack {
                                    Spacer()
                                    tiltBar
                                }
                                .frame(width: container.width, height: container.height)
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
                if cg != nil, !app.cropMode {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Surface.chrome)
        .animation(Motion.normal, value: app.cropMode)
        .onChange(of: tiltFocused) { _, focused in app.tiltFocused = focused }
        .onChange(of: app.cropMode) { _, on in
            if !on {
                tiltFocused = false
                app.tiltFocused = false
            }
        }
    }

    /// GPU live tilt for crop mode: draws the memoized (quarter-turned)
    /// base image, then scales by the shared cover factor and rotates —
    /// Core Animation work, no CPU resample per 0.25° tick. The uniform
    /// fit-scale into `shown` commutes with the rotate+cover transform, so
    /// this fills the same `shown` rect the CPU `rotateToFill` output
    /// would, and `CropOverlay`'s `imageRect` mapping stays correct.
    private func liveTiltImage(cg: CGImage, shown: CGSize, origin: CGPoint) -> some View {
        Image(decorative: cg, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: shown.width, height: shown.height)
            .scaleEffect(CGFloat(ImagePipeline.coverScale(
                width: Double(shown.width), height: Double(shown.height),
                degrees: app.cropTilt)))
            .rotationEffect(.degrees(app.cropTilt))
            .clipped()
            .offset(x: origin.x, y: origin.y)
    }

    /// Floating tilt control under the canvas while crop mode is open.
    /// Drag it, or click it to focus and use ← → (⇧ for 1°) / ↑ ↓.
    private var tiltBar: some View {
        HStack(spacing: Metric.elementGap) {
            Text("TILT")
                .font(Typo.sectionHeader)
                .tracking(0.4)
                .foregroundStyle(Palette.crop)
                .onTapGesture { tiltFocused = true }
            Slider(value: Binding(
                get: { app.cropTilt },
                set: { app.cropTilt = ($0 * 4).rounded() / 4 }),
                in: -45...45, step: 0.25)
                .frame(width: 320)
                .focused($tiltFocused)
            Text(String(format: "%+.2f°", app.cropTilt))
                .font(Typo.number)
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
            FloatingButton(symbol: "arrow.counterclockwise", tint: Palette.secondary,
                           tip: "Reset tilt (t)", filled: false) { app.resetTilt() }
        }
        .padding(.horizontal, Metric.elementGap + 4)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(Surface.floating))
        .overlay(Capsule(style: .continuous).strokeBorder(Palette.separator, lineWidth: 0.5))
        .shadowMedium()
        .padding(.bottom, Metric.elementGap * 2)
    }

    /// Right-hand header content: crop and zoom state, mirroring the other panes.
    private var trailing: some View {
        HStack(spacing: Metric.elementGap) {
            if app.cropMode {
                Text("CROP")
                    .font(Typo.sectionHeader)
                    .tracking(0.4)
                    .foregroundStyle(Palette.crop)
                Text(app.cropAspect.rawValue)
                    .font(Typo.number)
                    .foregroundStyle(Palette.secondary)
                Text(String(format: "%.0f%% × %.0f%%", app.cropRect.w * 100, app.cropRect.h * 100))
                    .font(Typo.number)
                    .foregroundStyle(Palette.secondary)
                Text(String(format: "%+.1f°", app.cropTilt))
                    .font(Typo.number)
                    .foregroundStyle(app.cropTilt != 0 ? Palette.crop : Palette.secondary)
            } else if app.currentPair != nil {
                if app.hasCrop { DecisionBadge(text: "CROPPED", color: Palette.crop) }
                if app.hasTilt { DecisionBadge(text: "TILTED", color: Palette.crop) }
                if app.isQuarterRotated { DecisionBadge(text: "ROTATED", color: Palette.crop) }
                Text(String(format: "%.0f%%", app.zoom * 100))
                    .font(Typo.number)
                    .foregroundStyle(Palette.secondary)
            }
        }
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
                   tint: Palette.keep,
                   tip: app.currentDecision == .keep
                     ? "Undo keep for this photo (z)"
                     : "Keep this photo and go to the next (z)",
                   filled: app.currentDecision == .keep) {
                app.mark(.keep)
            }
            action(app.currentDecision == .reject ? "xmark.circle.fill" : "xmark.circle",
                   tint: Palette.reject,
                   tip: app.currentDecision == .reject
                     ? "Undo reject for this photo (x)"
                     : "Reject this photo and go to the next (x)",
                   filled: app.currentDecision == .reject) {
                app.mark(.reject)
            }

            Divider().frame(height: 16).overlay(Palette.separator)

            action("crop", tint: app.hasCrop ? Palette.crop : Palette.secondary,
                   tip: app.hasCrop ? "Adjust the saved crop (c)" : "Crop without changing the original (c)",
                   filled: false) {
                app.enterCropMode()
            }
            action(app.showCroppedPreview ? "rectangle.inset.filled" : "rectangle",
                   tint: Palette.secondary,
                   tip: app.hasCrop
                     ? (app.showCroppedPreview ? "Show the full frame" : "Show the saved crop")
                     : "Save a crop first to compare it with the full frame",
                   filled: false) {
                app.showCroppedPreview.toggle()
            }
            .disabled(!app.hasCrop)

            action("rotate.left", tint: Palette.secondary,
                   tip: "Rotate a quarter turn left", filled: false) {
                app.rotateQuarter(-1)
            }
            action("rotate.right", tint: Palette.secondary,
                   tip: "Rotate a quarter turn right", filled: false) {
                app.rotateQuarter(1)
            }

            Divider().frame(height: 16).overlay(Palette.separator)

            action("minus.magnifyingglass", tint: Palette.secondary, tip: "Zoom out (-)", filled: false) {
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
                .font(Typo.iconMedium)
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
        .accessibilityLabel(Text(tip))
    }
}

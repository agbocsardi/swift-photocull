import SwiftUI
import PhotoCullCore

/// Pane 2 — the photo itself, on an opaque neutral canvas, with a floating
/// action bar. It carries the same header treatment as the other three panes so
/// the numbered keyboard map stays coherent.
struct ImagePane: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loader: ImageLoader
    @EnvironmentObject var canvas: CanvasState
    /// Keyboard focus on the tilt slider: arrows then nudge tilt.
    @FocusState private var tiltFocused: Bool
    @StateObject private var renderer = EditRenderer()

    private var renderRequest: EditRenderRequest? {
        guard let source = loader.current else { return nil }
        let cpuTilt = app.cropMode ? 0 : app.currentTilt
        let crop = !app.cropMode && app.showCroppedPreview ? app.currentCrop : nil
        let key = EditRenderKey(source: source, url: app.currentPair?.jpg,
                                quarterTurns: app.currentQuarterTurns, cpuTilt: cpuTilt, crop: crop)
        return EditRenderRequest(key: key, source: source)
    }

    private func displayImage(for request: EditRenderRequest?) -> CGImage? {
        guard let request else { return nil }
        if request.key.quarterTurns == 0, request.key.cpuTilt == 0, request.key.crop == nil {
            return request.source
        }
        guard renderer.ready?.key == request.key else { return nil }
        return renderer.ready?.image
    }

    var body: some View {
        VStack(spacing: 0) {
            // A mismatched old result is hidden synchronously, before the
            // keyed task submits the latest request.
            let request = renderRequest
            let cg = displayImage(for: request)

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
                        let shown = CGSize(width: base.width * canvas.zoom, height: base.height * canvas.zoom)
                        let origin = CGPoint(
                            x: (container.width - shown.width) / 2 + canvas.pan.width,
                            y: (container.height - shown.height) / 2 + canvas.pan.height)

                        ZStack(alignment: .topLeading) {
                            if app.cropMode {
                                liveTiltImage(cg: cg, shown: shown, origin: origin)
                            } else {
                                Image(decorative: cg, scale: 1)
                                    .resizable()
                                    .interpolation(canvas.zoom > 1.5 ? .none : .high)
                                    .frame(width: shown.width, height: shown.height)
                                    // Peak interaction cost: skip the
                                    // full-canvas Gaussian while cropping.
                                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                                    .offset(x: origin.x, y: origin.y)
                            }

                            if app.cropMode {
                                CropOverlay(
                                    rect: $canvas.cropRect,
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
                                    canvas.pan = CGSize(width: value.translation.width,
                                                        height: value.translation.height)
                                }
                        )
                    }
                } else if request != nil {
                    ProgressView("Rendering edits…").controlSize(.small)
                } else if loader.isLoading {
                    // Instant placeholder: the filmstrip's 256 px thumb while
                    // the full decode runs — perceived miss latency ≈ 0.
                    // Falls back to the spinner when the LRU evicted it or
                    // the session's thumbs haven't decoded yet. Read the
                    // thumb ONLY here, never in the `cg != nil` path above:
                    // `cached(for:)` locks the 512-slot LRU on every body.
                    if let pair = app.currentPair, let ph = app.thumbs.cached(for: pair.jpg) {
                        Image(decorative: ph, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .rotationEffect(.degrees(Double(app.currentQuarterTurns) * 90))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(Metric.canvasPad)
                            .opacity(0.9)
                            .transition(.opacity)
                    } else {
                        ProgressView().controlSize(.small)
                    }
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
            // Crossfade the real decode in over the thumb placeholder.
            .animation(Motion.fast, value: loader.isLoading)
        }
        .background(Surface.chrome)
        .task(id: renderRequest?.key) {
            guard let request = renderRequest else {
                renderer.reset()
                return
            }
            guard request.key.quarterTurns != 0 || request.key.cpuTilt != 0 || request.key.crop != nil else {
                renderer.reset()
                return
            }
            renderer.submit(request)
        }
        .animation(Motion.normal, value: app.cropMode)
        .onDisappear { renderer.reset() }
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
                degrees: canvas.cropTilt)))
            .rotationEffect(.degrees(canvas.cropTilt))
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
                get: { canvas.cropTilt },
                set: { canvas.cropTilt = ($0 * 4).rounded() / 4 }),
                in: -45...45, step: 0.25)
                .frame(width: 320)
                .focused($tiltFocused)
            Text(String(format: "%+.2f°", canvas.cropTilt))
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
                Text(String(format: "%.0f%% × %.0f%%", canvas.cropRect.w * 100, canvas.cropRect.h * 100))
                    .font(Typo.number)
                    .foregroundStyle(Palette.secondary)
                Text(String(format: "%+.1f°", canvas.cropTilt))
                    .font(Typo.number)
                    .foregroundStyle(canvas.cropTilt != 0 ? Palette.crop : Palette.secondary)
            } else if app.currentPair != nil {
                if app.hasCrop { DecisionBadge(text: "CROPPED", color: Palette.crop) }
                if app.hasTilt { DecisionBadge(text: "TILTED", color: Palette.crop) }
                if app.isQuarterRotated { DecisionBadge(text: "ROTATED", color: Palette.crop) }
                Text(String(format: "%.0f%%", canvas.zoom * 100))
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
    @EnvironmentObject var canvas: CanvasState

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
                canvas.zoomOut()
            }
            Text(String(format: "%.0f%%", canvas.zoom * 100))
                .font(Typo.number)
                .foregroundStyle(Palette.secondary)
                .frame(width: 40)
            action("plus.magnifyingglass", tint: Palette.secondary, tip: "Zoom in (+)", filled: false) {
                canvas.zoomIn()
            }
            action("arrow.up.left.and.arrow.down.right", tint: Palette.secondary,
                   tip: "Fit to window (0)", filled: false) { canvas.resetZoom() }

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

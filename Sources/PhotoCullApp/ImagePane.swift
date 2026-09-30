import SwiftUI
import PhotoCullCore

struct ImagePane: View {
    @EnvironmentObject var app: AppState

    /// What the pane actually draws.
    private var displayImage: CGImage? {
        guard let img = app.imageLoader.current else { return nil }
        if app.cropMode { return img }
        if app.showCroppedPreview, let crop = app.currentCrop, !crop.isFullFrame {
            return ImagePipeline.crop(img, to: crop) ?? img
        }
        return img
    }

    var body: some View {
        PaneBox(number: 2, title: app.cropMode ? "Image — CROP MODE" : "Image",
                focused: app.focusedPane == .image,
                trailing: AnyView(trailing)) {
            ZStack {
                Color.black.opacity(0.35)

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
                } else {
                    EmptyHint(text: app.activeDate == nil
                              ? "Select a session to start culling"
                              : "No images in this session")
                }
            }
        }
    }

    private var trailing: some View {
        HStack(spacing: 5) {
            if app.cropMode {
                Badge(text: app.cropAspect.rawValue, color: EF.yellow)
                Text(String(format: "%.0f×%.0f%%", app.cropRect.w * 100, app.cropRect.h * 100))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(EF.subtle)
            } else {
                if app.hasCrop { Badge(text: "CROPPED", color: EF.yellow) }
                Text(String(format: "%.0f%%", app.zoom * 100))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(EF.bg3)
            }
        }
    }

    private func fitSize(_ size: CGSize, into container: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, container.width > 0, container.height > 0 else {
            return CGSize(width: 1, height: 1)
        }
        let pad: CGFloat = 10
        let avail = CGSize(width: max(1, container.width - pad), height: max(1, container.height - pad))
        let scale = min(avail.width / size.width, avail.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

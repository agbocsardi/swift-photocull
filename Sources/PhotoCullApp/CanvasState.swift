import SwiftUI
import PhotoCullCore

/// Canvas transform state, split out of AppState. These four fields change at
/// event frequency — every drag tick, crop-arrow key repeat, slider tick —
/// while AppState is observed by ~160 view bodies. Keeping them here means a
/// drag tick re-evaluates only the views that observe CanvasState (the image
/// pane and the action bar) instead of the whole window. Plain `let` on
/// AppState (nested objects do not propagate); views get it injected as
/// environmentObject.
@MainActor
final class CanvasState: ObservableObject {
    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero
    @Published var cropRect: CropRect = .full
    /// Working tilt angle while crop mode is open (degrees, clockwise on screen).
    @Published var cropTilt: Double = 0

    func resetZoom() {
        zoom = 1
        pan = .zero
    }

    func zoomIn() { zoom = min(zoom * 1.25, 8) }
    func zoomOut() { zoom = max(zoom / 1.25, 0.1) }
}

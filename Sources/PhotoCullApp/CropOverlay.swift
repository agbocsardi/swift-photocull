import SwiftUI
import PhotoCullCore

/// Draggable, resizable crop rectangle drawn over the full image.
struct CropOverlay: View {
    @Binding var rect: CropRect
    /// Where the full image is drawn on screen, in the pane's coordinate space.
    let imageRect: CGRect
    /// Locked aspect ratio (w/h), or nil for free.
    let aspect: Double?
    var onAspectRequest: () -> Void = {}

    private enum Handle {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight, move, none
    }

    @State private var startRect: CropRect?
    @State private var handle: Handle = .none

    private let handleHit: CGFloat = 18
    private let minSize: Double = 0.02

    var body: some View {
        let r = screenRect
        ZStack(alignment: .topLeading) {
            // Dim everything outside the crop.
            Path { p in
                p.addRect(imageRect)
                p.addRect(r)
            }
            .fill(EF.bg.opacity(0.62), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle()
                .stroke(EF.yellow, lineWidth: 1.5)
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
                .allowsHitTesting(false)

            ruleOfThirds(r)

            ForEach(handlePoints(r), id: \.0) { _, point in
                Rectangle()
                    .fill(EF.yellow)
                    .frame(width: 9, height: 9)
                    .overlay(Rectangle().stroke(EF.bg, lineWidth: 1))
                    .offset(x: point.x - 4.5, y: point.y - 4.5)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .gesture(drag)
        .onTapGesture(count: 2) { onAspectRequest() }
    }

    private var screenRect: CGRect {
        CGRect(x: imageRect.minX + rect.x * imageRect.width,
               y: imageRect.minY + rect.y * imageRect.height,
               width: rect.w * imageRect.width,
               height: rect.h * imageRect.height)
    }

    @ViewBuilder
    private func ruleOfThirds(_ r: CGRect) -> some View {
        Path { p in
            for f in [1.0 / 3.0, 2.0 / 3.0] {
                p.move(to: CGPoint(x: r.minX + r.width * f, y: r.minY))
                p.addLine(to: CGPoint(x: r.minX + r.width * f, y: r.maxY))
                p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * f))
                p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * f))
            }
        }
        .stroke(EF.yellow.opacity(0.35), lineWidth: 0.5)
        .allowsHitTesting(false)
    }

    private func handlePoints(_ r: CGRect) -> [(String, CGPoint)] {
        [("tl", CGPoint(x: r.minX, y: r.minY)), ("t", CGPoint(x: r.midX, y: r.minY)),
         ("tr", CGPoint(x: r.maxX, y: r.minY)), ("l", CGPoint(x: r.minX, y: r.midY)),
         ("r", CGPoint(x: r.maxX, y: r.midY)), ("bl", CGPoint(x: r.minX, y: r.maxY)),
         ("b", CGPoint(x: r.midX, y: r.maxY)), ("br", CGPoint(x: r.maxX, y: r.maxY))]
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if startRect == nil {
                    startRect = rect
                    handle = hitHandle(value.startLocation)
                }
                guard let start = startRect, imageRect.width > 0, imageRect.height > 0 else { return }
                let dx = Double(value.translation.width / imageRect.width)
                let dy = Double(value.translation.height / imageRect.height)
                rect = resized(start: start, dx: dx, dy: dy)
            }
            .onEnded { _ in
                startRect = nil
                handle = .none
            }
    }

    private func hitHandle(_ p: CGPoint) -> Handle {
        let r = screenRect
        let nearL = abs(p.x - r.minX) < handleHit
        let nearR = abs(p.x - r.maxX) < handleHit
        let nearT = abs(p.y - r.minY) < handleHit
        let nearB = abs(p.y - r.maxY) < handleHit
        let insideX = p.x > r.minX - handleHit && p.x < r.maxX + handleHit
        let insideY = p.y > r.minY - handleHit && p.y < r.maxY + handleHit
        guard insideX, insideY else { return .none }

        switch (nearL, nearR, nearT, nearB) {
        case (true, _, true, _): return .topLeft
        case (true, _, _, true): return .bottomLeft
        case (_, true, true, _): return .topRight
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return .move
        }
    }

    private func resized(start: CropRect, dx: Double, dy: Double) -> CropRect {
        var x = start.x, y = start.y, w = start.w, h = start.h

        switch handle {
        case .move:
            x = start.x + dx
            y = start.y + dy
        case .topLeft:
            x = start.x + dx; y = start.y + dy
            w = start.w - dx; h = start.h - dy
        case .top:
            y = start.y + dy; h = start.h - dy
        case .topRight:
            y = start.y + dy; w = start.w + dx; h = start.h - dy
        case .left:
            x = start.x + dx; w = start.w - dx
        case .right:
            w = start.w + dx
        case .bottomLeft:
            x = start.x + dx; w = start.w - dx; h = start.h + dy
        case .bottom:
            h = start.h + dy
        case .bottomRight:
            w = start.w + dx; h = start.h + dy
        case .none:
            return rect
        }

        // Enforce a locked aspect ratio.
        if let aspect, aspect > 0, handle != .move {
            switch handle {
            case .top, .bottom:
                w = h * aspect
            default:
                h = w / aspect
            }
        }

        w = max(minSize, w)
        h = max(minSize, h)
        if w > 1 { w = 1 }
        if h > 1 { h = 1 }
        x = min(max(0, x), 1 - w)
        y = min(max(0, y), 1 - h)

        return CropRect(x: x, y: y, w: w, h: h)
    }
}

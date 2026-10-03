import SwiftUI
import PhotoCullCore

struct EditRenderKey: Equatable {
    let source: ObjectIdentifier
    let url: URL?
    let quarterTurns: Int
    let cpuTilt: Double
    let crop: CropRect?

    init(source: CGImage, url: URL?, quarterTurns: Int, cpuTilt: Double, crop: CropRect?) {
        self.source = ObjectIdentifier(source)
        self.url = url
        self.quarterTurns = ((quarterTurns % 4) + 4) % 4
        self.cpuTilt = cpuTilt == 0 ? 0 : cpuTilt
        self.crop = crop.flatMap { $0.isFullFrame ? nil : $0 }
    }
}

struct EditRenderRequest {
    let key: EditRenderKey
    let source: CGImage
}

/// One running exact-pipeline render and one replaceable latest request.
@MainActor
final class EditRenderer: ObservableObject {
    @Published private(set) var ready: (key: EditRenderKey, image: CGImage, source: CGImage)?

    private let transform: (EditRenderRequest, @escaping () async -> Bool,
                            (@Sendable (String) -> Void)?) async -> CGImage?
    private let stageObserver: (@Sendable (String) -> Void)?
    private var desiredKey: EditRenderKey?
    private var running = false
    private var pending: EditRenderRequest?
    var isRendering: Bool { running }
    private var serial = 0

    init(transform: @escaping (EditRenderRequest, @escaping () async -> Bool,
                               (@Sendable (String) -> Void)?) async -> CGImage? = EditRenderer.render,
         stageObserver: (@Sendable (String) -> Void)? = nil) {
        self.transform = transform
        self.stageObserver = stageObserver
    }

    func submit(_ request: EditRenderRequest) {
        if ready?.key == request.key {
            if desiredKey != request.key {
                serial += 1
                desiredKey = request.key
                pending = nil
            }
            return
        }
        if desiredKey == request.key {
            if running && pending?.key != request.key { return }
            if pending?.key == request.key { return }
        }
        serial += 1
        desiredKey = request.key
        if running {
            pending = request
        } else {
            start(request, serial: serial)
        }
    }

    func reset() {
        serial += 1
        desiredKey = nil
        pending = nil
        ready = nil
    }

    private func isCurrent(_ key: EditRenderKey, serial requestSerial: Int) -> Bool {
        desiredKey == key && serial == requestSerial
    }

    private func start(_ request: EditRenderRequest, serial requestSerial: Int) {
        running = true
        let transform = self.transform
        let stageObserver = self.stageObserver
        let renderer = self
        Task.detached(priority: .userInitiated) {
            let output = await transform(request, {
                await MainActor.run { renderer.isCurrent(request.key, serial: requestSerial) }
            }, stageObserver)
            await MainActor.run { renderer.finish(output, for: request, serial: requestSerial) }
        }
    }

    private func finish(_ output: CGImage?, for request: EditRenderRequest, serial requestSerial: Int) {
        if isCurrent(request.key, serial: requestSerial), let output {
            ready = (request.key, output, request.source)
        }
        running = false
        if let next = pending {
            pending = nil
            let nextSerial = serial
            start(next, serial: nextSerial)
        }
    }

    nonisolated private static func render(_ request: EditRenderRequest,
                                           isCurrent: @escaping () async -> Bool,
                                           stageObserver: (@Sendable (String) -> Void)?) async -> CGImage? {
        guard await isCurrent() else { return nil }
        var image = request.source
        if request.key.quarterTurns != 0 {
            stageObserver?("quarter")
            image = ImagePipeline.rotateQuarter(image, turns: request.key.quarterTurns)
        }
        guard await isCurrent() else { return nil }
        if request.key.cpuTilt != 0 {
            stageObserver?("tilt")
            image = ImagePipeline.rotateToFill(image, degrees: request.key.cpuTilt)
        }
        guard await isCurrent() else { return nil }
        if let crop = request.key.crop {
            stageObserver?("crop")
            image = ImagePipeline.crop(image, to: crop) ?? image
        }
        return image
    }
}

import Foundation
import CoreGraphics
import CoreFoundation
import PhotoCullCore

private var checks = 0
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError("CHECK \(checks) failed: \(message)") }
}

private func image(width: Int, height: Int, colorSpace: CGColorSpace) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                       space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for y in 0..<height {
        for x in 0..<width {
            ctx.setFillColor(red: CGFloat(x % 251) / 250, green: CGFloat(y % 241) / 240,
                             blue: CGFloat((x + y) % 239) / 238, alpha: 1)
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    return ctx.makeImage()!
}

private func bytes(_ image: CGImage) -> [UInt8] {
    guard let data = image.dataProvider?.data else { fatalError("missing pixel data") }
    let ptr = CFDataGetBytePtr(data)!
    return Array(UnsafeBufferPointer(start: ptr, count: CFDataGetLength(data)))
}

private func expected(_ source: CGImage, turns: Int, tilt: Double, crop: CropRect?) -> CGImage {
    var result = ImagePipeline.rotateQuarter(source, turns: turns)
    if tilt != 0 { result = ImagePipeline.rotateToFill(result, degrees: tilt) }
    if let crop { result = ImagePipeline.crop(result, to: crop) ?? result }
    return result
}

private final class StageAffinity: @unchecked Sendable {
    private let lock = NSLock()
    private var observations: [(String, Bool)] = []
    func record(_ stage: String, isMainThread: Bool) {
        lock.withLock { observations.append((stage, isMainThread)) }
    }
    var snapshot: [(String, Bool)] { lock.withLock { observations } }
}

private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var _starts = 0
    private var _active = 0
    private var _maximumActive = 0
    var starts: Int { lock.withLock { _starts } }
    var active: Int { lock.withLock { _active } }
    var maximumActive: Int { lock.withLock { _maximumActive } }

    func pause() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            _starts += 1
            _active += 1
            _maximumActive = max(_maximumActive, _active)
            self.continuation = continuation
            lock.unlock()
        }
        finishActive()
    }

    private func finishActive() { lock.withLock { _active -= 1 } }

    func release() {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }
}

@main
struct EditRenderingChecks {
    @MainActor static func main() async {
        for (spaceName, sizes) in [("sRGB", [(31, 20), (20, 31)]), ("Display P3", [(33, 22), (22, 33)])] {
            let space = CGColorSpace(name: spaceName == "sRGB" ? CGColorSpace.sRGB : CGColorSpace.displayP3)!
            for (width, height) in sizes {
                let source = image(width: width, height: height, colorSpace: space)
                for turns in 0...3 {
                    for tilt in [-4.25, 0, 3.5] {
                        let crop = CropRect(x: 0.13, y: 0.17, w: 0.71, h: 0.67)
                        let key = EditRenderKey(source: source, url: nil, quarterTurns: turns,
                                                cpuTilt: tilt, crop: crop)
                        let renderer = EditRenderer()
                        renderer.submit(EditRenderRequest(key: key, source: source))
                        let deadline = ContinuousClock.now + .seconds(5)
                        while renderer.ready?.key != key && ContinuousClock.now < deadline {
                            try? await Task.sleep(for: .milliseconds(5))
                        }
                        guard let actual = renderer.ready?.image else { fatalError("render timed out") }
                        let reference = expected(source, turns: turns, tilt: tilt, crop: crop)
                        check(actual.width == reference.width && actual.height == reference.height,
                              "dimensions \(spaceName) \(width)x\(height), turns=\(turns), tilt=\(tilt)")
                        check(actual.colorSpace?.name == reference.colorSpace?.name, "color profile retained")
                        check(bytes(actual) == bytes(reference), "pixels match existing pipeline")
                    }
                }
            }
        }

        let src = image(width: 8, height: 5, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let idle = EditRenderKey(source: src, url: URL(fileURLWithPath: "/a"), quarterTurns: 0,
                                 cpuTilt: 0, crop: .full)
        let equivalent = EditRenderKey(source: src, url: URL(fileURLWithPath: "/a"), quarterTurns: 4,
                                      cpuTilt: -0.0, crop: nil)
        check(idle == equivalent, "key uses effective inputs and normalized turns")
        check(ObjectIdentifier(src) == idle.source, "unedited display preserves source identity")

        let affinity = StageAffinity()
        let actualKey = EditRenderKey(source: src, url: nil, quarterTurns: 1, cpuTilt: 2,
                                      crop: CropRect(x: 0.1, y: 0.1, w: 0.8, h: 0.8))
        let actualRenderer = EditRenderer(stageObserver: {
            affinity.record($0, isMainThread: Thread.isMainThread)
        })
        actualRenderer.submit(EditRenderRequest(key: actualKey, source: src))
        let actualDeadline = ContinuousClock.now + .seconds(5)
        while actualRenderer.ready?.key != actualKey && ContinuousClock.now < actualDeadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        check(actualRenderer.ready?.key == actualKey, "default renderer completed")
        check(actualRenderer.ready?.source === src, "ready result retains its identified source")
        check(affinity.snapshot.map(\.0) == ["quarter", "tilt", "crop"],
              "affinity observed in each actual default transform stage")
        check(affinity.snapshot.allSatisfy { !$0.1 }, "all actual transform stages run off main thread")

        let gate = Gate()
        let controlled = EditRenderer { request, isCurrent, _ in
            await gate.pause()
            guard await isCurrent() else { return nil }
            return request.source
        }
        func req(_ turns: Int) -> EditRenderRequest {
            let key = EditRenderKey(source: src, url: nil, quarterTurns: turns, cpuTilt: 1, crop: nil)
            return EditRenderRequest(key: key, source: src)
        }
        let first = req(1), middle = req(2), latest = req(3)
        controlled.submit(first)
        let firstStarted = ContinuousClock.now + .seconds(3)
        while gate.starts == 0 && ContinuousClock.now < firstStarted { try? await Task.sleep(for: .milliseconds(5)) }
        check(gate.starts == 1, "first request started")
        controlled.submit(first)
        controlled.submit(middle)
        controlled.submit(latest)
        check(gate.starts == 1, "only one job runs while pending request is replaced")
        gate.release()
        let secondStarted = ContinuousClock.now + .seconds(3)
        while gate.starts < 2 && ContinuousClock.now < secondStarted { try? await Task.sleep(for: .milliseconds(5)) }
        check(gate.starts == 2, "latest pending request started after current job")
        gate.release()
        let published = ContinuousClock.now + .seconds(3)
        while controlled.ready?.key != latest.key && ContinuousClock.now < published {
            try? await Task.sleep(for: .milliseconds(5))
        }
        check(controlled.ready?.key == latest.key, "obsolete requests never replace latest result")
        check(gate.maximumActive == 1, "at most one transform active")
        controlled.reset()
        check(controlled.ready == nil, "reset clears published result")

        let resetGate = Gate()
        let resetRenderer = EditRenderer { request, _, _ in
            await resetGate.pause()
            return request.source
        }
        resetRenderer.submit(first)
        let resetStarted = ContinuousClock.now + .seconds(3)
        while resetGate.starts == 0 && ContinuousClock.now < resetStarted {
            try? await Task.sleep(for: .milliseconds(5))
        }
        check(resetGate.starts == 1, "reset test render started")
        resetRenderer.reset()
        resetGate.release()
        let resetFinished = ContinuousClock.now + .seconds(3)
        while resetRenderer.isRendering && ContinuousClock.now < resetFinished {
            try? await Task.sleep(for: .milliseconds(5))
        }
        try? await Task.sleep(for: .milliseconds(10))
        check(resetRenderer.ready == nil, "reset during render suppresses publication")
        print("PASS: \(checks) edit-render checks")
    }
}

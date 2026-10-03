import Foundation
import CoreGraphics
import PhotoCullCore

@MainActor
private final class Checks {
    private(set) var count = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard condition() else { fatalError("CHECK \(count) failed: \(message)") }
    }
}

private final class Probe: @unchecked Sendable {
    private let lock = NSLock()
    private var starts: [String: Int] = [:]
    private var active = 0
    private var peak = 0
    func start(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        starts[key, default: 0] += 1; active += 1; peak = max(peak, active)
    }
    func end() { lock.lock(); active -= 1; lock.unlock() }
    func count(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return starts[key, default: 0] }
    var maxActive: Int { lock.lock(); defer { lock.unlock() }; return peak }
}

private final class Gate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    func wait() -> Bool { entered.signal(); return release.wait(timeout: .now() + 3) == .success }
}

@MainActor
@main
private struct ImageLoadingChecks {
    static func main() async throws {
        let checks = Checks()
        func url(_ name: String) -> URL { URL(fileURLWithPath: "/synthetic/\(name).jpg") }
        func image(_ red: CGFloat) -> CGImage {
            let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(red: red, green: 0, blue: 1 - red, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            return ctx.makeImage()!
        }
        func eventually(_ condition: @escaping @MainActor () -> Bool, _ label: String) async {
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                if condition() { return }
                try? await Task.sleep(for: .milliseconds(10))
            }
            fatalError("Timed out: \(label)")
        }
        func waitForEntry(_ gate: Gate, _ label: String) async {
            await eventually({ gate.entered.wait(timeout: .now()) == .success }, label)
        }

        // Cold demand clears prior pixels before native work can finish.
        do {
            let a = image(1), b = image(0)
            let loader = ImageLoader(decode: { name, _ in name.lastPathComponent.hasPrefix("A") ? a : b }, embedded: { _, _ in nil })
            loader.load(url: url("A"), maxPixel: 100)
            await eventually({ loader.publishedStage == .sharp }, "A sharp result")
            loader.load(url: url("B"), maxPixel: 100)
            checks.expect(loader.current == nil && loader.isLoading, "cold B must clear A immediately")
            await eventually({ loader.publishedStage == .sharp }, "B sharp result")
            checks.expect(loader.current === b && loader.publishedKey == ImageCache.key(url: url("B"), maxPixel: 100), "B identity published")
        }

        // Reversed completion order cannot publish A over B.
        do {
            let ga = Gate(), gb = Gate(), a = image(1), b = image(0)
            let loader = ImageLoader(decode: { u, _ in
                let gate = u.lastPathComponent.hasPrefix("A") ? ga : gb
                _ = gate.wait()
                return u.lastPathComponent.hasPrefix("A") ? a : b
            }, embedded: { _, _ in nil })
            loader.load(url: url("A-reverse"), maxPixel: 200)
            await waitForEntry(ga, "A decode entered")
            loader.load(url: url("B-reverse"), maxPixel: 200)
            await waitForEntry(gb, "B decode entered")
            gb.release.signal(); await eventually({ loader.current === b }, "B first")
            ga.release.signal(); try? await Task.sleep(for: .milliseconds(80))
            checks.expect(loader.current === b, "late A cannot replace B")
        }

        // A→B→A rejoins the original active A job rather than launching another decode.
        do {
            let gate = Gate(), probe = Probe(), a = image(1), b = image(0)
            let loader = ImageLoader(decode: { u, _ in
                probe.start(u.lastPathComponent); _ = gate.wait(); probe.end()
                return u.lastPathComponent.hasPrefix("A") ? a : b
            }, embedded: { _, _ in nil })
            loader.load(url: url("A-back"), maxPixel: 250)
            await waitForEntry(gate, "backtrack A entered")
            loader.load(url: url("B-back"), maxPixel: 250)
            loader.load(url: url("A-back"), maxPixel: 250)
            gate.release.signal(); gate.release.signal()
            await eventually({ loader.current === a }, "A backtrack completion")
            checks.expect(probe.count("A-back.jpg") == 1, "A→B→A reuses active A")
        }

        // Foreground joins a running full-key prefetch, while size remains part of identity.
        do {
            let gate = Gate(), probe = Probe(), marker = image(0.5)
            let loader = ImageLoader(decode: { u, _ in
                probe.start(u.lastPathComponent); _ = gate.wait(); probe.end(); return marker
            }, embedded: { _, _ in nil })
            loader.prefetch(urls: [url("joined")], maxPixel: 300)
            await waitForEntry(gate, "prefetch entered")
            loader.load(url: url("joined"), maxPixel: 300)
            gate.release.signal(); await eventually({ loader.current === marker }, "joined demand")
            checks.expect(probe.count("joined.jpg") == 1, "prefetch and demand decode once")
            loader.load(url: url("joined"), maxPixel: 301)
            gate.release.signal()
            await eventually({ probe.count("joined.jpg") == 2 && !loader.isLoading }, "distinct size decode")
            checks.expect(probe.count("joined.jpg") == 2, "maxPixel creates distinct job")
        }

        // A stale embedded stage must not start sharp decoding after navigation.
        do {
            let previewGate = Gate(), probe = Probe(), sharp = image(0.25)
            let loader = ImageLoader(decode: { u, _ in probe.start(u.lastPathComponent); probe.end(); return sharp },
                                     embedded: { u, _ in
                                         if u.lastPathComponent.hasPrefix("stale") {
                                             _ = previewGate.wait(); return image(0.75)
                                         }
                                         return nil
                                     })
            loader.load(url: url("stale-preview"), maxPixel: 400)
            await waitForEntry(previewGate, "embedded attempt entered")
            loader.load(url: url("fresh"), maxPixel: 400)
            previewGate.release.signal()
            await eventually({ loader.publishedKey == ImageCache.key(url: url("fresh"), maxPixel: 400) }, "fresh demand")
            checks.expect(probe.count("stale-preview.jpg") == 0, "stale preview skips sharp decode")
        }

        // Nil, failure, and invalidation all retire loading; stale work cannot warm cache.
        do {
            let gate = Gate(), probe = Probe(), marker = image(0.4)
            let loader = ImageLoader(decode: { u, _ in
                probe.start(u.lastPathComponent); _ = gate.wait(); probe.end(); return marker
            }, embedded: { _, _ in nil })
            loader.load(url: url("invalidated"), maxPixel: 500)
            await waitForEntry(gate, "decode before invalidate")
            loader.invalidate(); gate.release.signal()
            try? await Task.sleep(for: .milliseconds(80))
            checks.expect(loader.current == nil && !loader.isLoading, "invalidate remains empty")
            loader.load(url: url("invalidated"), maxPixel: 500)
            await waitForEntry(gate, "replacement decode entered")
            checks.expect(probe.count("invalidated.jpg") == 2, "invalidated result not cached")
            gate.release.signal(); await eventually({ !loader.isLoading }, "post-invalidate decode")
            loader.load(url: nil, maxPixel: 0)
            checks.expect(loader.current == nil && !loader.isLoading, "nil clears demand")
        }
        do {
            let preview = image(0.8)
            let loader = ImageLoader(decode: { _, _ in nil }, embedded: { _, _ in preview })
            loader.load(url: url("failure"), maxPixel: 600)
            await eventually({ !loader.isLoading }, "failed decode retires")
            checks.expect(loader.current === preview && loader.publishedStage == .embeddedPreview && loader.sharpFailed,
                          "sharp failure remains an explicitly low-quality preview")
        }

        // Shared loader admits at most two native jobs and lets the latest demand jump queued warmups.
        do {
            let gate = Gate(), probe = Probe(), marker = image(0.5)
            let names = (0..<6).map { "queued-\($0)" }
            let loader = ImageLoader(decode: { u, _ in
                probe.start(u.lastPathComponent); _ = gate.wait(); probe.end(); return marker
            }, embedded: { _, _ in nil })
            loader.prefetch(urls: names.map(url), maxPixel: 700)
            await waitForEntry(gate, "two loader slots filled")
            await waitForEntry(gate, "second loader slot filled")
            checks.expect(probe.maxActive <= 2, "native loader concurrency is capped at two")
            let target = url(names.last!)
            loader.load(url: target, maxPixel: 700)
            gate.release.signal(); gate.release.signal()
            await waitForEntry(gate, "latest demand admitted")
            gate.release.signal()
            await eventually({ loader.publishedKey == ImageCache.key(url: target, maxPixel: 700) }, "latest queued demand succeeds")
            checks.expect(probe.count("queued-5.jpg") == 1, "latest target was not dropped")
        }

        // Thumbnail work has a separate four-job cap and clear rejects old fills.
        do {
            let gate = Gate(), probe = Probe(), marker = image(0.6)
            let store = ThumbnailStore(decode: { u, _ in
                probe.start(u.lastPathComponent); _ = gate.wait(); probe.end(); return marker
            })
            for i in 0..<8 { _ = store.thumbnail(for: url("thumb-\(i)")) }
            for _ in 0..<4 { await waitForEntry(gate, "thumbnail slot filled") }
            checks.expect(probe.maxActive <= 4, "thumbnail native concurrency is capped at four")
            for _ in 0..<4 { gate.release.signal() }
            for _ in 0..<4 { await waitForEntry(gate, "queued thumbnail admitted") }
            for _ in 0..<4 { gate.release.signal() }
            await eventually({ store.cached(for: url("thumb-7")) != nil }, "last thumbnail completes")
        }
        do {
            let gate = Gate(), store = ThumbnailStore(decode: { _, _ in _ = gate.wait(); return image(0.3) })
            _ = store.thumbnail(for: url("thumb-clear"))
            await waitForEntry(gate, "thumbnail before clear")
            store.clear(); gate.release.signal()
            try? await Task.sleep(for: .milliseconds(60))
            checks.expect(store.cached(for: url("thumb-clear")) == nil, "clear blocks old thumbnail cache fill")
        }

        // Embedded-only helper must reject a generated JPEG without a thumbnail; sharp still works.
        do {
            let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OUT"]!, isDirectory: true)
            let root = output.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let jpg = root.appendingPathComponent("plain.jpg")
            try ImagePipeline.writeJPEG(image(0.2), to: jpg, quality: 0.9)
            checks.expect(ImagePipeline.embeddedThumbnail(url: jpg, maxPixel: 256) == nil, "no-embedded JPEG yields nil preview")
            checks.expect(ImagePipeline.load(url: jpg, maxPixel: 256) != nil, "no-embedded JPEG decodes sharp")
        }

        print("ImageLoadingChecks: \(checks.count) checks passed")
    }
}

import SwiftUI
import PhotoCullCore

/// Async full-size image loading with an LRU cache and neighbour prefetch.
@MainActor
final class ImageLoader: ObservableObject {
    @Published private(set) var current: CGImage?
    @Published private(set) var isLoading = false

    private let cache = ImageCache(capacity: 16)
    private var generation = 0

    /// Load `url` at `maxPixel`, discarding any older in-flight request.
    func load(url: URL?, maxPixel: Int) {
        generation += 1
        let gen = generation
        guard let url else { current = nil; isLoading = false; return }

        let key = ImageCache.key(url: url, maxPixel: maxPixel)
        if let hit = cache.image(for: key) {
            current = hit
            isLoading = false
            return
        }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let img = ImagePipeline.load(url: url, maxPixel: maxPixel)
            await MainActor.run {
                guard gen == self.generation else { return }
                if let img { self.cache.store(img, for: key) }
                self.current = img
                self.isLoading = false
            }
        }
    }

    /// Warm the cache for the given URLs without touching `current`.
    func prefetch(urls: [URL], maxPixel: Int) {
        let missing = urls.filter { cache.image(for: ImageCache.key(url: $0, maxPixel: maxPixel)) == nil }
        guard !missing.isEmpty else { return }
        Task.detached(priority: .utility) {
            for url in missing {
                let key = ImageCache.key(url: url, maxPixel: maxPixel)
                if let img = ImagePipeline.load(url: url, maxPixel: maxPixel) {
                    await MainActor.run { self.cache.store(img, for: key) }
                }
            }
        }
    }

    func invalidate() {
        cache.clear()
        current = nil
    }
}

/// Shared thumbnail cache backing the filmstrip and session rows.
@MainActor
final class ThumbnailStore: ObservableObject {
    /// Bumped whenever a thumbnail arrives or the cache clears, so observed
    /// cells re-read `cached(for:)`. The LRU below is the ONLY storage:
    /// a parallel published dictionary would pin every thumbnail in memory
    /// forever (defeating the capacity limit) and disagree with the cache
    /// once entries get evicted.
    @Published private(set) var generation = 0

    private let cache = ImageCache(capacity: 512)
    private var inFlight: Set<String> = []
    /// Keys whose decode returned nil, so cells show a failure mark instead
    /// of spinning forever. Not retried within this run; a repaired file is
    /// picked up after an app relaunch (or a future `clear()` call site).
    private var failed: Set<String> = []
    private let maxPixel = 256

    func thumbnail(for url: URL) -> CGImage? {
        let key = ImageCache.key(url: url, maxPixel: maxPixel)
        if let hit = cache.image(for: key) { return hit }
        guard !failed.contains(key), !inFlight.contains(key) else { return nil }
        inFlight.insert(key)
        Task.detached(priority: .utility) {
            let img = ImagePipeline.thumbnail(url: url, maxPixel: self.maxPixel)
            await MainActor.run {
                self.inFlight.remove(key)
                if let img {
                    self.failed.remove(key)
                    self.cache.store(img, for: key)
                } else {
                    self.failed.insert(key)
                }
                self.generation += 1
            }
        }
        return nil
    }

    func cached(for url: URL) -> CGImage? {
        cache.image(for: ImageCache.key(url: url, maxPixel: maxPixel))
    }

    func isFailed(_ url: URL) -> Bool {
        failed.contains(ImageCache.key(url: url, maxPixel: maxPixel))
    }

    func clear() {
        cache.clear()
        generation += 1
    }
}

extension CGImage {
    var nsImage: NSImage { NSImage(cgImage: self, size: NSSize(width: width, height: height)) }
}

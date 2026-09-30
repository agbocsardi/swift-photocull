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
    @Published private(set) var images: [String: CGImage] = [:]

    private let cache = ImageCache(capacity: 512)
    private var inFlight: Set<String> = []
    private let maxPixel = 256

    func thumbnail(for url: URL) -> CGImage? {
        let key = ImageCache.key(url: url, maxPixel: maxPixel)
        if let hit = cache.image(for: key) { return hit }
        guard !inFlight.contains(key) else { return nil }
        inFlight.insert(key)
        Task.detached(priority: .utility) {
            let img = ImagePipeline.thumbnail(url: url, maxPixel: self.maxPixel)
            await MainActor.run {
                self.inFlight.remove(key)
                if let img {
                    self.cache.store(img, for: key)
                    self.images[key] = img
                }
            }
        }
        return nil
    }

    func cached(for url: URL) -> CGImage? {
        cache.image(for: ImageCache.key(url: url, maxPixel: maxPixel))
    }

    func clear() {
        cache.clear()
        images = [:]
    }
}

extension CGImage {
    var nsImage: NSImage { NSImage(cgImage: self, size: NSSize(width: width, height: height)) }
}

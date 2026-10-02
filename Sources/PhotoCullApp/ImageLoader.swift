import SwiftUI
import PhotoCullCore

/// Async full-size image loading with an LRU cache and neighbour prefetch.
@MainActor
final class ImageLoader: ObservableObject {
    @Published private(set) var current: CGImage?
    @Published private(set) var isLoading = false

    private let cache = ImageCache(capacity: 16, byteBudget: 512 * 1024 * 1024)
    private var generation = 0
    /// Neighbour URLs with a prefetch decode already running, so back-to-back
    /// j/k doesn't start duplicate decodes of the same file (a hit is stored
    /// only when the child finishes, so the cache check alone misses in-flight
    /// work).
    private var inFlight: Set<URL> = []

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
            // Early-out before the heavy decode when a newer navigation has
            // already superseded this one, so rapid j/k doesn't pile up
            // stale 24–48 MP decodes that each run to completion.
            let stale = await MainActor.run { gen != self.generation }
            guard !stale else { return }
            let img = ImagePipeline.load(url: url, maxPixel: maxPixel)
            await MainActor.run {
                guard gen == self.generation else { return }
                if let img { self.cache.store(img, for: key) }
                self.current = img
                self.isLoading = false
            }
        }
    }

    /// Warm the cache for the given URLs without touching `current`. All
    /// missing URLs decode concurrently in one utility task group — two
    /// neighbours arrive in ~½ the serial time on a cold cache (measured
    /// 1.73×) and storage stays serialized on the MainActor.
    func prefetch(urls: [URL], maxPixel: Int) {
        let missing = urls.filter {
            cache.image(for: ImageCache.key(url: $0, maxPixel: maxPixel)) == nil
                && !inFlight.contains($0)
        }
        guard !missing.isEmpty else { return }
        let gen = generation
        for url in missing { inFlight.insert(url) }
        Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for url in missing {
                    group.addTask {
                        // Same staleness check per URL: once a navigation
                        // bumps the generation, this old neighbour is not
                        // worth decoding. Either way the child retires its
                        // in-flight mark when it finishes.
                        let stale = await MainActor.run { gen != self.generation }
                        if !stale {
                            let key = ImageCache.key(url: url, maxPixel: maxPixel)
                            if let img = ImagePipeline.load(url: url, maxPixel: maxPixel) {
                                await MainActor.run { self.cache.store(img, for: key) }
                            }
                        }
                        await MainActor.run { _ = self.inFlight.remove(url) }
                    }
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

    private let cache = ImageCache(capacity: 512, byteBudget: 128 * 1024 * 1024)
    private var inFlight: Set<String> = []
    /// True while a `generation` bump is queued for this runloop tick, so a
    /// burst of thumbnail arrivals (a ~150-photo session mount) coalesces to
    /// at most one announcement per tick instead of one per arrival.
    private var announceScheduled = false
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
                self.scheduleAnnounce()
            }
        }
        return nil
    }

    /// Queue one `generation` bump for this runloop tick, collapsing any
    /// further arrivals before it fires. `clear()` still announces directly.
    private func scheduleAnnounce() {
        guard !announceScheduled else { return }
        announceScheduled = true
        Task { @MainActor in
            self.announceScheduled = false
            self.generation += 1
        }
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

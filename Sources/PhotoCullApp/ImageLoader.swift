import SwiftUI
import PhotoCullCore

/// Two native full-image operations may run at once; queued work is MainActor-owned.
@MainActor
final class ImageLoader: ObservableObject {
    @Published private(set) var current: CGImage?
    @Published private(set) var isLoading = false
    private(set) var publishedKey: String?
    private(set) var publishedStage: Stage?
    @Published private(set) var sharpFailed = false

    enum Stage: Equatable { case embeddedPreview, sharp }

    private let cache = ImageCache(capacity: 16, byteBudget: 512 * 1024 * 1024)
    private let decode: (URL, Int) -> CGImage?
    private let embedded: (URL, Int) -> CGImage?
    private var generation = 0
    private var epoch = 0
    private var requestedKey: String?
    private var jobs: [String: Job] = [:]
    private var queue: [String] = []
    private var active = 0

    private final class Job {
        let id = UUID()
        let key: String
        let url: URL
        let maxPixel: Int
        let epoch: Int
        var demandGeneration: Int?
        var prefetchGeneration: Int?
        var started = false

        init(key: String, url: URL, maxPixel: Int, epoch: Int,
             demandGeneration: Int? = nil, prefetchGeneration: Int? = nil) {
            self.key = key; self.url = url; self.maxPixel = maxPixel; self.epoch = epoch
            self.demandGeneration = demandGeneration; self.prefetchGeneration = prefetchGeneration
        }
    }

    init(decode: @escaping (URL, Int) -> CGImage? = ImagePipeline.load,
         embedded: @escaping (URL, Int) -> CGImage? = ImagePipeline.embeddedThumbnail) {
        self.decode = decode
        self.embedded = embedded
    }

    /// Load `url` at `maxPixel`, discarding obsolete queued navigation work.
    func load(url: URL?, maxPixel: Int) {
        generation += 1
        let gen = generation
        guard let url else {
            requestedKey = nil
            current = nil; publishedKey = nil; publishedStage = nil
            sharpFailed = false; isLoading = false
            pruneQueue()
            return
        }

        let key = ImageCache.key(url: url, maxPixel: maxPixel)
        requestedKey = key
        current = nil; publishedKey = nil; publishedStage = nil
        sharpFailed = false
        if let hit = cache.image(for: key) {
            current = hit; publishedKey = key; publishedStage = .sharp; isLoading = false
            pruneQueue()
            return
        }
        isLoading = true
        if let job = jobs[key], job.epoch == epoch {
            job.demandGeneration = gen
        } else {
            let job = Job(key: key, url: url, maxPixel: maxPixel, epoch: epoch, demandGeneration: gen)
            jobs[key] = job; queue.append(key)
        }
        pruneQueue()
        schedule()
    }

    /// Add ±1 callers' warmups to the same full-key request queue as demand.
    func prefetch(urls: [URL], maxPixel: Int) {
        let gen = generation
        for url in urls {
            let key = ImageCache.key(url: url, maxPixel: maxPixel)
            guard cache.image(for: key) == nil else { continue }
            if let job = jobs[key], job.epoch == epoch {
                job.prefetchGeneration = gen
            } else {
                let job = Job(key: key, url: url, maxPixel: maxPixel, epoch: epoch,
                              prefetchGeneration: gen)
                jobs[key] = job; queue.append(key)
            }
        }
        schedule()
    }

    func invalidate() {
        epoch += 1; generation += 1
        cache.clear(); jobs.removeAll(); queue.removeAll()
        requestedKey = nil; current = nil; publishedKey = nil; publishedStage = nil
        sharpFailed = false; isLoading = false
    }

    private func pruneQueue() {
        queue.removeAll { key in
            guard let job = jobs[key], !job.started else { return true }
            let usefulDemand = job.key == requestedKey && job.demandGeneration == generation
            let usefulPrefetch = job.prefetchGeneration == generation
            guard usefulDemand || usefulPrefetch else {
                jobs.removeValue(forKey: key)
                return true
            }
            return false
        }
    }

    private func schedule() {
        while active < 2, !queue.isEmpty {
            // Latest demand first; otherwise retain FIFO order.
            if let i = queue.firstIndex(where: { jobs[$0]?.demandGeneration == generation }) {
                queue.insert(queue.remove(at: i), at: 0)
            }
            let key = queue.removeFirst()
            guard let job = jobs[key], job.epoch == epoch, !job.started else { continue }
            let useful = job.key == requestedKey && job.demandGeneration == generation
                || job.prefetchGeneration == generation
            guard useful else { jobs.removeValue(forKey: key); continue }
            job.started = true; active += 1
            let previewAtStart = job.key == requestedKey && job.demandGeneration == generation
            run(job, previewAtStart: previewAtStart)
        }
    }

    private func run(_ job: Job, previewAtStart: Bool) {
        let decode = self.decode
        let embedded = self.embedded
        let priority: TaskPriority = previewAtStart ? .userInitiated : .utility
        Task.detached(priority: priority) {
            if previewAtStart {
                let mayTryPreview = await MainActor.run { self.isCurrent(job) }
                if mayTryPreview {
                    let preview = embedded(job.url, min(job.maxPixel, 256))
                    let mayContinue = await MainActor.run { self.publishPreview(preview, for: job) }
                    guard mayContinue else {
                        await MainActor.run { self.finishSkipped(job) }
                        return
                    }
                } else {
                    let stillUseful = await MainActor.run { self.isUseful(job) }
                    guard stillUseful else {
                        await MainActor.run { self.finishSkipped(job) }
                        return
                    }
                }
            } else {
                let stillUseful = await MainActor.run { self.isUseful(job) }
                guard stillUseful else {
                    await MainActor.run { self.finishSkipped(job) }
                    return
                }
            }
            // Re-check after embedded decoding; stale previews never trigger sharp work.
            let mayDecode = await MainActor.run { self.isUseful(job) }
            guard mayDecode else {
                await MainActor.run { self.finishSkipped(job) }
                return
            }
            let image = decode(job.url, job.maxPixel)
            await MainActor.run { self.finish(job, image: image) }
        }
    }

    private func isCurrent(_ job: Job) -> Bool {
        job.epoch == epoch && jobs[job.key]?.id == job.id
            && requestedKey == job.key && job.demandGeneration == generation
    }

    private func isUseful(_ job: Job) -> Bool {
        job.epoch == epoch && jobs[job.key]?.id == job.id
            && ((requestedKey == job.key && job.demandGeneration == generation)
                || job.prefetchGeneration == generation)
    }

    private func publishPreview(_ image: CGImage?, for job: Job) -> Bool {
        guard isCurrent(job) else { return isUseful(job) }
        if let image {
            current = image; publishedKey = job.key; publishedStage = .embeddedPreview
        }
        return isUseful(job)
    }

    private func finishSkipped(_ job: Job) {
        retire(job)
        // If demand joined during stale-job retirement, admit its exact key now.
        if requestedKey == job.key, isLoading, cache.image(for: job.key) == nil,
           jobs[job.key] == nil {
            let retry = Job(key: job.key, url: job.url, maxPixel: job.maxPixel, epoch: epoch,
                            demandGeneration: generation)
            jobs[job.key] = retry; queue.append(job.key)
        }
        schedule()
    }

    private func finish(_ job: Job, image: CGImage?) {
        if job.epoch == epoch, jobs[job.key]?.id == job.id, let image {
            cache.store(image, for: job.key)
            if requestedKey == job.key, job.demandGeneration == generation {
                current = image; publishedKey = job.key; publishedStage = .sharp
                isLoading = false; sharpFailed = false
            }
        } else if job.epoch == epoch, jobs[job.key]?.id == job.id,
                  requestedKey == job.key, job.demandGeneration == generation {
            current = nil; publishedKey = nil; publishedStage = nil
            isLoading = false; sharpFailed = true
        }
        retire(job)
        if requestedKey == job.key, isLoading, cache.image(for: job.key) == nil,
           jobs[job.key] == nil {
            // A same-key demand may have arrived at the completion boundary.
            let retry = Job(key: job.key, url: job.url, maxPixel: job.maxPixel,
                            epoch: epoch, demandGeneration: generation)
            jobs[job.key] = retry; queue.append(job.key)
        }
        schedule()
    }

    private func retire(_ job: Job) {
        active = max(0, active - 1)
        if jobs[job.key]?.id == job.id { jobs.removeValue(forKey: job.key) }
    }
}

/// Shared thumbnail cache backing the filmstrip and session rows.
@MainActor
final class ThumbnailStore: ObservableObject {
    @Published private(set) var generation = 0
    private let cache = ImageCache(capacity: 512, byteBudget: 128 * 1024 * 1024)
    private let decode: (URL, Int) -> CGImage?
    private var epoch = 0
    private var active = 0
    private var queue: [(key: String, url: URL, epoch: Int)] = []
    private var queued: Set<String> = []
    private var inFlight: [String: UUID] = [:]
    private var announceScheduled = false
    private var failed: Set<String> = []
    private let maxPixel = 256

    init(decode: @escaping (URL, Int) -> CGImage? = ImagePipeline.thumbnail) { self.decode = decode }

    func thumbnail(for url: URL) -> CGImage? {
        let key = ImageCache.key(url: url, maxPixel: maxPixel)
        if let hit = cache.image(for: key) { return hit }
        guard !failed.contains(key), !queued.contains(key), inFlight[key] == nil else { return nil }
        // ponytail: pending URLs are O(requested session cells); bound only after tested visible-window admission.
        queued.insert(key); queue.append((key, url, epoch)); schedule()
        return nil
    }

    private func schedule() {
        while active < 4, !queue.isEmpty {
            let request = queue.removeFirst()
            queued.remove(request.key)
            guard request.epoch == epoch else { continue }
            active += 1
            let jobID = UUID()
            inFlight[request.key] = jobID
            let decode = self.decode
            let maxPixel = self.maxPixel
            Task.detached(priority: .utility) {
                let image = decode(request.url, maxPixel)
                await MainActor.run {
                    self.active -= 1
                    if self.inFlight[request.key] == jobID { self.inFlight.removeValue(forKey: request.key) }
                    if request.epoch == self.epoch && self.inFlight[request.key] == nil {
                        if let image { self.cache.store(image, for: request.key); self.failed.remove(request.key) }
                        else { self.failed.insert(request.key) }
                        self.scheduleAnnounce()
                    }
                    self.schedule()
                }
            }
        }
    }

    private func scheduleAnnounce() {
        guard !announceScheduled else { return }
        announceScheduled = true
        Task { @MainActor in self.announceScheduled = false; self.generation += 1 }
    }

    func cached(for url: URL) -> CGImage? {
        cache.image(for: ImageCache.key(url: url, maxPixel: maxPixel))
    }

    func isFailed(_ url: URL) -> Bool { failed.contains(ImageCache.key(url: url, maxPixel: maxPixel)) }

    func clear() {
        epoch += 1; cache.clear(); failed.removeAll(); queue.removeAll(); queued.removeAll(); inFlight.removeAll()
        generation += 1
    }
}

extension CGImage {
    var nsImage: NSImage { NSImage(cgImage: self, size: NSSize(width: width, height: height)) }
}

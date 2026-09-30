import Foundation
import PhotoCullCore

/// `PhotoCull --check` — exercises the real stack (config, library, EXIF, image
/// decode) against the user's actual inbox without opening a window.
enum HeadlessCheck {
    /// `PhotoCull --repair-pairs [--apply]` — fix RAW files renamed to `_2` by the
    /// Go app's stem-keyed collision rule, so JPG+RAW pairs work again.
    static func repairPairs(apply: Bool) -> Int32 {
        let cfg = PCConfig.load()
        do {
            let report = apply
                ? try PairRepair.apply(cfg: cfg)
                : PairRepair.plan(cfg: cfg)
            print("scanned inbox:   \(cfg.paths.inbox)")
            print("scanned archive: \(cfg.paths.archive)")
            print("")
            print("would re-pair:   \(report.renamed) RAW files")
            print("already paired:  \(report.actions.filter { $0.kind == .alreadyPaired }.count)")
            print("unpaired RAWs:   \(report.unpaired)  (no matching JPG — left alone)")
            print("ambiguous:       \(report.ambiguous)  (target name taken — left alone)")
            print("")
            let renamed = report.actions.filter { $0.kind == .renamed }
            for a in renamed.prefix(12) {
                print("  \(a.date)  \(a.from.lastPathComponent)  ->  \(a.to?.lastPathComponent ?? "?")")
            }
            if renamed.count > 12 { print("  … and \(renamed.count - 12) more") }
            if apply {
                print("\nAPPLIED \(report.renamed) renames.")
                print("An audit log was written to \(URL(fileURLWithPath: PCConfig.configPath).deletingLastPathComponent().path)/")
                print("Only file names changed — no photo content was read, written or deleted.")
            } else {
                print("\nDry run. Re-run with --apply to perform the renames.")
            }
            return 0
        } catch {
            print("repair failed: \(error)")
            return 1
        }
    }

    static func run() -> Int32 {
        let cfg = PCConfig.load()
        print("config:  \(PCConfig.configPath)")
        print("inbox:   \(cfg.paths.inbox)")
        print("archive: \(cfg.paths.archive)")
        print("dump:    \(cfg.paths.dump)")
        print("jpg ext: \(cfg.files.jpgExtensions.joined(separator: ", "))")
        print("raw ext: \(cfg.files.rawExtensions.joined(separator: ", "))")

        let cards = Ingest.detectSDCards()
        print("cards:   \(cards.isEmpty ? "(none mounted)" : cards.map(\.path).joined(separator: ", "))")

        let rows = Library.loadSessions(cfg: cfg)
        print("\nsessions: \(rows.count)")
        for r in rows {
            print(String(format: "  %@  %-12@ %3d/%-3d  keep %-3d reject %-3d crop %d",
                         r.date, r.status.rawValue, r.total - r.keep - r.reject,
                         r.total, r.keep, r.reject, r.cropped))
        }

        guard let newest = rows.first else {
            print("\nno sessions to inspect")
            return 0
        }

        do {
            let folder = Library.inboxFolder(cfg: cfg, date: newest.date)
            let pairs = try Library.pairs(cfg: cfg, date: newest.date)
            let session = try Session.load(folder: folder)
            print("\ninspecting \(newest.date): \(pairs.count) pairs, last_index \(session.lastIndex)")
            guard let first = pairs.first else { return 0 }

            print("  first: \(first.jpg.lastPathComponent) raw=\(first.rawExt ?? "—") decision=\(session.get(first.stem).rawValue)")
            let info = ExifReader.read(url: first.jpg)
            print("  exif:  camera=\(info.camera ?? "—") lens=\(info.lens ?? "—") iso=\(info.iso ?? "—") " +
                  "shutter=\(info.shutter ?? "—") aperture=\(info.aperture ?? "—") " +
                  "size=\(info.size ?? "—") orientation=\(info.orientation)")
            print("  captured: \(info.dateTimeOriginal ?? "—")")

            if let size = ImagePipeline.orientedPixelSize(url: first.jpg) {
                print("  oriented size: \(size.width)×\(size.height)")
            } else {
                print("  oriented size: FAILED")
            }

            let started = Date()
            if let img = ImagePipeline.load(url: first.jpg, maxPixel: 2048) {
                let ms = Date().timeIntervalSince(started) * 1000
                print(String(format: "  decode 2048px: %d×%d in %.0f ms", img.width, img.height, ms))
                let crop = CropRect(x: 0.25, y: 0.25, w: 0.5, h: 0.5)
                if let c = ImagePipeline.crop(img, to: crop) {
                    print("  50% crop:      \(c.width)×\(c.height)")
                } else {
                    print("  50% crop:      FAILED")
                }
            } else {
                print("  decode 2048px: FAILED")
            }

            if let thumb = ImagePipeline.thumbnail(url: first.jpg, maxPixel: 256) {
                print("  thumbnail:     \(thumb.width)×\(thumb.height)")
            } else {
                print("  thumbnail:     FAILED")
            }

            let cache = ImageCache(capacity: 2)
            for i in 0..<4 {
                if let img = ImagePipeline.thumbnail(url: first.jpg, maxPixel: 64 + i) {
                    cache.store(img, for: "k\(i)")
                }
            }
            print("  cache kept:    \(cache.image(for: "k3") != nil ? "newest" : "MISSING") / oldest evicted: \(cache.image(for: "k0") == nil)")

            let stats = try Finalize.summary(cfg: cfg, date: newest.date)
            print("  finalize would: archive \(stats.keep + stats.undecided) pairs, trash \(stats.reject)")
        } catch {
            print("\nERROR: \(error)")
            return 1
        }
        return 0
    }
}

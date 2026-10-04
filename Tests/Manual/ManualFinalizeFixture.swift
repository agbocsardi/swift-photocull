import Foundation
import CoreGraphics
import CoreText
import ImageIO
import CryptoKit
import Darwin

// No app startup, standard config load, card detection, Finalize.run or Trash.
private let date = "2024-05-03"
private let names = ["01_RED_KEEP.JPG", "02_GREEN_KEEP.JPG", "03_BLUE_EDIT_KEEP.JPG",
                     "04_ORANGE_REJECT.JPG", "05_PURPLE_REJECT.JPG", "06_CYAN_UNDECIDED.JPG"]
private let decisions = ["keep", "keep", "keep", "reject", "reject", "undecided"]
private let markers = ["notes.txt": "Unrelated fixture notes: preserve me.\n",
                       "unrelated-subfolder/marker.txt": "Unrelated nested marker: preserve me.\n"]
private let fm = FileManager.default
private func require(_ ok: Bool, _ message: String) throws {
    if !ok { throw NSError(domain: "ManualFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
private func hash(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
}
private func text(_ value: String, at url: URL) throws {
    try Data(value.utf8).write(to: url, options: .withoutOverwriting)
}
private func inventory(_ root: URL) throws -> Set<String> {
    var result = Set<String>()
    var enumerationError: Error?
    guard let en = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                errorHandler: { _, error in enumerationError = error; return false }) else {
        throw NSError(domain: "ManualFixture", code: 2)
    }
    for case let url as URL in en {
        var st = stat()
        try require(lstat(url.path, &st) == 0, "Cannot stat \(url.path)")
        try require(st.st_mode & S_IFMT == S_IFREG || st.st_mode & S_IFMT == S_IFDIR,
                    "Symlink/special file prohibited: \(url.path)")
        let path = url.path
        try require(path.hasPrefix(root.path + "/"), "Path escape: \(path)")
        result.insert(String(path.dropFirst(root.path.count + 1)))
    }
    if let error = enumerationError { throw error }
    return result
}
private func checkImage(_ url: URL, width: Int = 960, height: Int = 640, captureDate: Bool = true) throws {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetType(src) as String? == "public.jpeg",
          CGImageSourceGetCount(src) == 1,
          let decoded = CGImageSourceCreateImageAtIndex(src, 0,
              [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
          let loaded = ImagePipeline.load(url: url, maxPixel: max(width, height)),
          let thumb = ImagePipeline.thumbnail(url: url, maxPixel: 128) else {
        throw NSError(domain: "ManualFixture", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "JPEG decode failed: \(url.path)"])
    }
    try require(decoded.width == width && decoded.height == height &&
                loaded.width == width && loaded.height == height &&
                max(thumb.width, thumb.height) <= 128, "Wrong dimensions: \(url.path)")
    if captureDate { try require(ExifReader.captureDate(url: url) == date, "Wrong EXIF date") }
}
private func configText(_ root: URL) -> String {
    PCConfig(paths: PathsConfig(inbox: root.appendingPathComponent("inbox").path,
                               archive: root.appendingPathComponent("archive").path,
                               dump: root.appendingPathComponent("export").path),
             files: FilesConfig(rawExtensions: ["RAF", "RW2"], jpgExtensions: ["JPG", "JPEG"])).toTOML()
}
private func drawJPEG(_ number: Int, to url: URL) throws {
    let colors: [[CGFloat]] = [[0.80, 0.12, 0.12], [0.10, 0.55, 0.22], [0.10, 0.30, 0.80],
                              [0.95, 0.43, 0.05], [0.55, 0.18, 0.72], [0.05, 0.60, 0.68]]
    let c = colors[number - 1]
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: 960, height: 640, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "ManualFixture", code: 4)
    }
    ctx.setFillColor(red: c[0], green: c[1], blue: c[2], alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: 960, height: 640))
    ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 0.6); ctx.setLineWidth(2)
    for x in stride(from: 0, through: 960, by: 80) {
        ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: 640))
    }
    for y in stride(from: 0, through: 640, by: 80) {
        ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: 960, y: y))
    }
    ctx.strokePath()
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1)); ctx.setLineWidth(12)
    ctx.stroke(CGRect(x: 12, y: 12, width: 936, height: 616))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(5)
    ctx.move(to: CGPoint(x: 0, y: 320)); ctx.addLine(to: CGPoint(x: 960, y: 320)); ctx.strokePath()
    // Asymmetric white top-left square and black bottom-right circle track tilt/orientation.
    ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 32, y: 520, width: 80, height: 80))
    ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillEllipse(in: CGRect(x: 840, y: 32, width: 80, height: 80))
    func label(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)]
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attrs)), ctx)
    }
    label(String(format: "%02d", number), x: 360, y: 365, size: 180)
    label(names[number - 1], x: 145, y: 160, size: 27)
    label("TOP / 80px GRID / GENERATED ONLY", x: 195, y: 570, size: 25)
    guard let image = ctx.makeImage(),
          let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
        throw NSError(domain: "ManualFixture", code: 5)
    }
    let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92,
        kCGImagePropertyOrientation: 1,
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:05:03 12:00:0\(number)"]]
    CGImageDestinationAddImage(dst, image, props as CFDictionary)
    try require(CGImageDestinationFinalize(dst), "JPEG encoding failed")
}
private func generate(_ root: URL) throws {
    // New data directories only; repeat generation must fail, never overwrite.
    for path in ["inbox", "archive", "export", "config", "checks"] {
        try fm.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: false)
    }
    let folder = root.appendingPathComponent("inbox/\(date)")
    try fm.createDirectory(at: folder, withIntermediateDirectories: false)
    try fm.createDirectory(at: folder.appendingPathComponent("unrelated-subfolder"), withIntermediateDirectories: false)
    for (path, value) in markers { try text(value, at: folder.appendingPathComponent(path)) }
    try text(configText(root), at: root.appendingPathComponent("config/config.toml"))
    var files: [[String: Any]] = []
    for (i, name) in names.enumerated() {
        let url = folder.appendingPathComponent(name)
        try drawJPEG(i + 1, to: url)
        files.append(["path": "inbox/\(date)/\(name)", "sha256": try hash(url),
                      "bytes": try Data(contentsOf: url).count, "width": 960, "height": 640,
                      "initial_decision": "undecided", "manual_decision": decisions[i],
                      "archive": decisions[i] == "reject" ? "none" : "archive/\(date)/\(name)",
                      "export": decisions[i] == "reject" ? "none" : "export/\(date)/\(name)",
                      "expected_export_dimensions": decisions[i] == "reject" ? "none" :
                        (i == 2 ? "640x640 (1:1 preset, +2 degree tilt)" : "960x640"),
                      "trash": decisions[i] == "reject" ? "native macOS Trash; location not controlled by config" : "none"])
    }
    // Exercise only pure image export on generated bytes, not Finalize/Trash.
    let probe = root.appendingPathComponent("checks/crop-probe.JPG")
    try ImagePipeline.export(src: folder.appendingPathComponent(names[2]),
        crop: CropRect(x: 1.0 / 6, y: 0, w: 2.0 / 3, h: 1), to: probe, quality: 0.9, tilt: 2)
    let markerManifest = try markers.keys.sorted().map { path in
        ["path": "inbox/\(date)/\(path)", "sha256": try hash(folder.appendingPathComponent(path))]
    }
    let manifest: [String: Any] = ["version": 1, "root": root.path, "session_date": date,
        "launch_cleared": false, "config": root.appendingPathComponent("config/config.toml").path,
        "files": files, "markers": markerManifest, "crop_probe_sha256": try hash(probe),
        "expected_summary": ["keep": 3, "reject": 2, "undecided": 1, "total": 6, "raw": 0],
        "expected_finalize": ["archived": 4, "trashed": 2, "dumped": 4, "cropped": 1]]
    try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        .write(to: root.appendingPathComponent("manifest.json"), options: .withoutOverwriting)
    print("Generated six genuine JPEG inputs, no sidecar/RAW/card, isolated proposed TOML and pure crop probe.")
}
private func validate(_ root: URL, finalized: Bool) throws {
    _ = try inventory(root) // Reject every descendant symlink/special file, including compiler outputs.
    guard let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("manifest.json"))) as? [String: Any],
          let files = manifest["files"] as? [[String: Any]] else {
        throw NSError(domain: "ManualFixture", code: 7, userInfo: [NSLocalizedDescriptionKey: "Malformed manifest"])
    }
    try require(manifest["root"] as? String == root.path && manifest["session_date"] as? String == date &&
                manifest["config"] as? String == root.appendingPathComponent("config/config.toml").path &&
                manifest["launch_cleared"] as? Bool == false, "Wrong manifest root/isolation")
    let configURL = root.appendingPathComponent("config/config.toml")
    try require(try String(contentsOf: configURL, encoding: .utf8) == configText(root), "Wrong/incomplete TOML; not loading")
    // The actual explicit-path production API; never PCConfig.load() or configPath.
    let cfg = PCConfig.load(from: configURL)
    try require(cfg.toTOML() == configText(root), "Production config parser mismatch")
    let folder = Library.inboxFolder(cfg: cfg, date: date)
    let markerPaths = Set(markers.keys).union(["unrelated-subfolder"])
    let expectedInbox = markerPaths.union(finalized ? [Session.fileName] : Set(names))
    try require(try inventory(root.appendingPathComponent("inbox")) == Set([date] + expectedInbox.map { "\(date)/\($0)" }),
                "Unexpected inbox entries")
    try require(files.count == 6 && Set(files.compactMap { $0["path"] as? String }) ==
                Set(names.map { "inbox/\(date)/\($0)" }), "Unexpected manifest files")
    try require(try inventory(root.appendingPathComponent("config")) == ["config.toml"], "Extra config entries")
    let expectedMarkers = try markers.keys.sorted().map { path in
        ["path": "inbox/\(date)/\(path)", "sha256": try hash(folder.appendingPathComponent(path))]
    }
    try require(manifest["markers"] as? [[String: String]] == expectedMarkers, "Marker manifest mismatch")
    for (path, value) in markers {
        try require(try String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8) == value,
                    "Marker changed: \(path)")
    }
    let selected = names.enumerated().filter { decisions[$0.offset] != "reject" }.map(\.element)
    if finalized {
        try require(try inventory(folder) == markerPaths.union([Session.fileName]), "Unexpected residual inputs/recovery claims")
        try require(try inventory(root.appendingPathComponent("archive")) == Set([date] + selected.map { "\(date)/\($0)" }), "Archive file set mismatch")
        try require(try inventory(root.appendingPathComponent("export")) == Set([date] + selected.map { "\(date)/\($0)" }), "Export file set mismatch")
        let session = try Session.load(folder: folder, strict: true)
        for (i, name) in names.enumerated() {
            try require(session.get(URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent).rawValue == decisions[i], "Manual decision mismatch: \(name)")
        }
        let editedStem = String(names[2].dropLast(4))
        try require(Set(session.crops.keys) == [editedStem] && session.crop(for: editedStem)?.isFullFrame == false &&
                    Set(session.tilts.keys) == [editedStem] && session.tilt(for: editedStem) == 2 && session.rotations.isEmpty,
                    "Expected only #03 square crop and +2 degree tilt, no rotations")
    } else {
        try require(try inventory(folder) == markerPaths.union(names), "Initial inputs mismatch (sidecar must be absent)")
        try require(try inventory(root.appendingPathComponent("archive")).isEmpty && inventory(root.appendingPathComponent("export")).isEmpty, "Outputs must be empty")
        let rows = Library.loadSessions(cfg: cfg)
        try require(rows.count == 1 && rows[0].date == date && rows[0].total == 6 && rows[0].status == .unstarted,
                    "Actual Library did not discover fresh six-photo session")
        let (pairs, orphans) = try FilePairs.scan(folder: folder, jpgExts: cfg.jpgExtSet, rawExts: cfg.rawExtSet)
        try require(pairs.map { $0.jpg.lastPathComponent } == names && pairs.allSatisfy { !$0.hasRAW } && orphans.isEmpty,
                    "Actual pairing mismatch")
        let summary = try Finalize.summary(cfg: cfg, date: date) // Read-only actual production summary.
        try require(summary.keep == 0 && summary.reject == 0 && summary.undecided == 6 && summary.keepRAW == 0 && summary.rejectRAW == 0,
                    "Actual initial Finalize summary mismatch")
    }
    for (i, name) in names.enumerated() {
        let row = files.first { $0["path"] as? String == "inbox/\(date)/\(name)" }!
        try require(row["initial_decision"] as? String == "undecided" && row["manual_decision"] as? String == decisions[i] &&
                    row["width"] as? Int == 960 && row["height"] as? Int == 640 &&
                    row["archive"] as? String == (decisions[i] == "reject" ? "none" : "archive/\(date)/\(name)") &&
                    row["export"] as? String == (decisions[i] == "reject" ? "none" : "export/\(date)/\(name)"),
                    "Manifest intention/dimensions/output paths mismatch")
        if finalized && decisions[i] == "reject" { continue } // Do not inspect system Trash.
        let original = finalized ? root.appendingPathComponent("archive/\(date)/\(name)") : folder.appendingPathComponent(name)
        try require(try hash(original) == row["sha256"] as? String && Data(contentsOf: original).count == row["bytes"] as? Int,
                    "Original bytes changed: \(name)")
        try checkImage(original)
        if finalized {
            let output = root.appendingPathComponent("export/\(date)/\(name)")
            if i == 2 {
                try checkImage(output, width: 640, height: 640, captureDate: false)
                try require(try hash(output) != hash(original), "Edited export was not edited")
            } else {
                try require(try hash(output) == hash(original), "Unedited export bytes changed: \(name)")
                try checkImage(output)
            }
        }
    }
    let probe = root.appendingPathComponent("checks/crop-probe.JPG")
    try require(try inventory(root.appendingPathComponent("checks")) == ["crop-probe.JPG"], "Extra check outputs")
    try require(try hash(probe) == manifest["crop_probe_sha256"] as? String, "Probe changed")
    try checkImage(probe, width: 640, height: 640, captureDate: false)
    print("PASS: canonical root, no symlinks/escape; exact config/data file sets; hashes, native JPEG decode, actual Config/Library/Pairing/Summary, pure crop export.")
    print(finalized ? "Finalized fixture files verified; native Trash presence/restorability NOT checked." : "Initial 0 keep / 0 reject / 6 undecided; archive/export empty; no saved decisions.")
    print("GUI launch BLOCKED: no supported independent startup config; standard preferences and Ingest volume detection are not isolated.")
}
@main private enum Main {
    static func main() {
        do {
            let args = CommandLine.arguments
            try require(args.count == 3 && ["generate", "validate", "validate-finalized"].contains(args[1]),
                        "Usage: fixture generate|validate|validate-finalized /private/tmp/photocull-manual-fixture-...")
            let path = args[2]
            guard let resolved = realpath(path, nil) else { throw NSError(domain: "ManualFixture", code: 6) }
            defer { free(resolved) }
            try require(path == String(cString: resolved) && path.hasPrefix("/private/tmp/photocull-manual-fixture-") &&
                        !String(path.dropFirst("/private/tmp/".count)).contains("/"), "Noncanonical/unsafe fixture root")
            let root = URL(fileURLWithPath: path, isDirectory: true)
            var st = stat()
            try require(lstat(path, &st) == 0 && st.st_mode & S_IFMT == S_IFDIR && st.st_uid == getuid(), "Wrong root type/owner")
            if args[1] == "generate" { _ = try inventory(root); try generate(root) }
            else { try validate(root, finalized: args[1] == "validate-finalized") }
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8)); exit(1)
        }
    }
}

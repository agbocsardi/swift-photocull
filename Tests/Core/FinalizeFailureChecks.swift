import Foundation
import Darwin

#if FINALIZE_DESCRIPTOR_CHECKS
// Compile this branch WITH the actual Session.swift/FinalizeSafety.swift, not the library.
// Forward native syscalls; reuse each closed FD immediately so a second close is observable.
private var observingCloses = false
private var closeCounts: [Int32: Int] = [:]
private var markerPath = ""
private var failCall = ""
private var statCountdown = 0
private var injected = false
private var descriptorChecks = 0

@discardableResult
func close(_ fd: Int32) -> Int32 {
    let result = Darwin.close(fd)
    if observingCloses {
        closeCounts[fd, default: 0] += 1
        if closeCounts[fd] == 1 {
            precondition(Darwin.open(markerPath, O_RDONLY | O_CLOEXEC) == fd,
                         "must immediately reuse the closed descriptor")
        }
    }
    return result
}
func fsync(_ fd: Int32) -> Int32 {
    if failCall == "fsync" {
        failCall = ""; injected = true; errno = EIO; return -1
    }
    return Darwin.fsync(fd)
}
func pwrite(_ fd: Int32, _ bytes: UnsafeRawPointer?, _ count: Int, _ offset: off_t) -> Int {
    if failCall == "pwrite" {
        failCall = ""; injected = true; errno = ENOSPC; return -1
    }
    return Darwin.pwrite(fd, bytes, count, offset)
}
func fstat(_ fd: Int32, _ value: UnsafeMutablePointer<stat>!) -> Int32 {
    if statCountdown > 0 {
        statCountdown -= 1
        if statCountdown == 0 { injected = true; errno = EIO; return -1 }
    }
    return Darwin.fstat(fd, value)
}
private func fdExpect(_ value: Bool, _ message: String) {
    descriptorChecks += 1
    precondition(value, message)
}
private func checkFailedInit(_ label: String, count: Int, injection: Bool = false,
                             _ body: () throws -> Void) {
    closeCounts = [:]; injected = false; observingCloses = true
    do { try body(); fatalError("\(label) must fail") }
    catch { print("Expected \(label): \(error.localizedDescription)") }
    observingCloses = false
    fdExpect(closeCounts.count == count, "\(label): every acquired FD closed")
    if injection { fdExpect(injected, "\(label): syscall injection fired") }
    for (fd, closes) in closeCounts {
        fdExpect(closes == 1, "\(label): exactly one close per acquired FD")
        var bytes = [UInt8](repeating: 0, count: 3)
        fdExpect(Darwin.read(fd, &bytes, bytes.count) == 3 && bytes == [4, 5, 6],
                 "\(label): unrelated reused descriptor remains readable")
        precondition(Darwin.close(fd) == 0)
    }
}
@main struct FinalizeDescriptorChecks {
    static func main() throws {
        guard let path = ProcessInfo.processInfo.environment["PC_FINALIZE_TEST_OUT"], path.hasPrefix("/") else {
            fatalError("Explicit absolute PC_FINALIZE_TEST_OUT required")
        }
        let root = URL(fileURLWithPath: path).appendingPathComponent("synthetic/descriptors-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        markerPath = root.appendingPathComponent("marker").path
        try Data([4, 5, 6]).write(to: URL(fileURLWithPath: markerPath))
        let owner = try FinalizeDirectory(root, lock: true)
        withExtendedLifetime(owner) {
            checkFailedInit("flock contention", count: 1) { _ = try FinalizeDirectory(root, lock: true) }
            statCountdown = 1
            checkFailedInit("directory pre-initialization fstat", count: 1, injection: true) {
                _ = try FinalizeDirectory(root)
            }
        }
        owner.releaseLock()
        for scenario in ["journal-open", "journal-stat", "record-open", "record-stat", "pwrite", "fsync", "durable-stat"] {
            let url = root.appendingPathComponent(scenario)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            let input = try FinalizeDirectory(url), claims = try input.privateDirectory("claims-")
            if scenario == "journal-open" { try Data([7]).write(to: claims.url.appendingPathComponent(".progress.jsonl")) }
            if scenario == "record-open" { try Data([8]).write(to: url.appendingPathComponent(FinalizeRecovery.name)) }
            failCall = scenario
            statCountdown = ["journal-stat": 1, "record-stat": 2, "durable-stat": 3][scenario] ?? 0
            let count = scenario == "journal-open" ? 0 : (["journal-stat", "record-open"].contains(scenario) ? 1 : 2)
            withExtendedLifetime((input, claims)) {
                checkFailedInit(scenario, count: count, injection: !scenario.hasSuffix("-open")) {
                    _ = try FinalizeRecovery(directory: input, claims: claims, invocation: scenario, plans: [])
                }
            }
            failCall = ""; statCountdown = 0
        }
        print("FinalizeDescriptorChecks: \(descriptorChecks) checks passed; artifacts: \(root.path)")
    }
}
#else
import CoreGraphics
import PhotoCullCore

@_silgen_name("flock") private func probeFlock(_ fd: Int32, _ operation: Int32) -> Int32

func finalizeLockProbe(_ path: String) {
    let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    precondition(fd >= 0)
    defer { close(fd) }
    precondition(probeFlock(fd, LOCK_EX | LOCK_NB) == -1 && errno == EWOULDBLOCK,
                 "independent-process nonblocking flock must refuse contention")
}

private struct FileToken: Equatable {
    let device: Int32, inode: UInt64
    static func read(_ url: URL) -> Self {
        var st = stat()
        precondition(lstat(url.path, &st) == 0)
        return Self(device: st.st_dev, inode: st.st_ino)
    }
}
private var checks = 0
private func expect(_ value: Bool, _ message: String) {
    checks += 1
    if !value { fatalError("FinalizeFailure CHECK \(checks): \(message)") }
}
private func failure(_ body: () throws -> Void) -> Error {
    do { try body() } catch { return error }
    fatalError("Expected failure, but operation succeeded")
}
private final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func change<R>(_ f: (inout T) -> R) -> R { lock.lock(); defer { lock.unlock() }; return f(&value) }
}
private func jpeg(_ url: URL, red: CGFloat) throws {
    let context = CGContext(data: nil, width: 12, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: red, green: 0.2, blue: 0.1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
    try ImagePipeline.writeJPEG(context.makeImage()!, to: url, quality: 1)
}

func suiteFinalizeFailureChecks() throws {
    let fm = FileManager.default
    guard let path = ProcessInfo.processInfo.environment["PC_FINALIZE_TEST_OUT"], path.hasPrefix("/") else {
        fatalError("Explicit absolute PC_FINALIZE_TEST_OUT required")
    }
    let out = URL(fileURLWithPath: path)
    let root = out.appendingPathComponent("synthetic/failures-\(UUID().uuidString)")
    precondition(root.path.hasPrefix(out.path + "/"))
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    // Keep generated artifacts for review. No personal inputs; every config path is beneath root.
    var n = 0
    struct Fixture {
        let root: URL, input: URL, archive: URL, dump: URL, trash: URL, cfg: PCConfig
    }
    func setup() throws -> Fixture {
        n += 1
        let base = root.appendingPathComponent("case-\(n)")
        let input = base.appendingPathComponent("inbox/date")
        let archive = base.appendingPathComponent("archive/date"), dump = base.appendingPathComponent("dump/date")
        let trash = base.appendingPathComponent("synthetic-trash")
        for dir in [input, archive, dump, trash] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        return Fixture(root: base, input: input, archive: archive, dump: dump, trash: trash,
                       cfg: PCConfig(paths: PathsConfig(inbox: base.appendingPathComponent("inbox").path,
                                                         archive: base.appendingPathComponent("archive").path,
                                                         dump: base.appendingPathComponent("dump").path),
                                     files: FilesConfig(rawExtensions: ["RAF"], jpgExtensions: ["JPG"])))
    }
    func write(_ dir: URL, _ name: String, _ bytes: Data) throws { try bytes.write(to: dir.appendingPathComponent(name)) }
    func bytes(_ url: URL, _ wanted: Data, _ why: String) { expect((try? Data(contentsOf: url)) == wanted, why) }
    func sidecar(_ f: Fixture, reject: Bool = false, edited: Bool = false) throws -> Data {
        let s = Session.fresh()
        if reject { s.set("B", .reject) }
        if edited { for stem in ["A", "B", "C"] { s.setCrop(stem, CropRect(x: 0.1, y: 0.1, w: 0.8, h: 0.8)) } }
        try s.save(folder: f.input)
        return try Data(contentsOf: f.input.appendingPathComponent(Session.fileName))
    }
    func run(_ f: Fixture, dump: Bool = true, edited: Bool = false, hooks: FinalizeHooks = FinalizeHooks()) throws -> FinalizeResult {
        try Finalize.run(cfg: f.cfg, date: "date", dump: dump, cropMode: edited ? .applyCrop : .original,
                         dumpOverride: nil, hooks: hooks)
    }
    func claims(_ f: Fixture) throws -> URL {
        let names = try fm.contentsOfDirectory(atPath: f.input.path).filter { $0.hasPrefix(".photocull-claims-") }
        expect(names.count == 1, "exactly one retained claim directory")
        return f.input.appendingPathComponent(names[0])
    }
    func noStages(_ f: Fixture) throws {
        for dir in [f.dump, f.archive] {
            expect(!(try fm.contentsOfDirectory(atPath: dir.path)).contains { $0.hasPrefix(".photocull-stage-") }, "no owned export/copy stages")
        }
    }
    func retryBlocked(_ f: Fixture) throws {
        let effects = Locked(0)
        let err = failure { _ = try run(f, hooks: FinalizeHooks(boundary: { _, _ in effects.change { $0 += 1 } },
                                                                trash: { _ in fatalError("retry reached Trash") })) }
        expect(err.localizedDescription.contains("Manual recovery"), "retry explains manual recovery: \(err.localizedDescription); fixture \(f.root.path)")
        expect(effects.change { $0 } == 0, "retry has zero effects/admissions")
    }

    // Strict bytes/type/version/key validation preserves every source and metadata byte.
    for bad in ["{", "", "{\"version\":2}", "{\"version\":1,\"decisions\":{\"a\":\"keep\",\"A\":\"reject\"}}"] {
        let f = try setup(), original = Data([1, 2, 3])
        try write(f.input, "A.JPG", original); try write(f.input, Session.fileName, Data(bad.utf8))
        _ = failure { _ = try run(f) }
        bytes(f.input.appendingPathComponent("A.JPG"), original, "invalid sidecar original unchanged")
        bytes(f.input.appendingPathComponent(Session.fileName), Data(bad.utf8), "invalid sidecar bytes unchanged")
        expect((try fm.contentsOfDirectory(atPath: f.archive.path)).isEmpty, "invalid sidecar no archive effects")
    }
    do {
        let f = try setup(), original = Data([4, 5])
        try write(f.input, "A.JPG", original)
        let result = try run(f)
        bytes(f.archive.appendingPathComponent("A.JPG"), original, "missing sidecar archives undecided")
        bytes(f.dump.appendingPathComponent("A.JPG"), original, "missing sidecar dumps undecided")
        expect(result.retainedFolders.isEmpty && !fm.fileExists(atPath: f.input.path), "empty session cleanup removes owned record first")
    }
    for date in ["", ".", "..", "../escape", "a/b", "bad\0name"] {
        let f = try setup()
        _ = failure { _ = try Finalize.summary(cfg: f.cfg, date: date) }
        expect((try fm.contentsOfDirectory(atPath: f.archive.path)).isEmpty, "invalid component fails before effects")
    }
    do {
        let f = try setup(), original = Data([6])
        try write(f.input, "A.JPG", original)
        let alias = f.root.appendingPathComponent("alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: f.input)
        _ = failure { _ = try Finalize.run(cfg: f.cfg, date: "date", dump: true, cropMode: .original, dumpOverride: alias) }
        bytes(f.input.appendingPathComponent("A.JPG"), original, "aliased input/output refused")
        let real = f.root.appendingPathComponent("real-date")
        try fm.moveItem(at: f.input, to: real)
        try fm.createSymbolicLink(at: f.input, withDestinationURL: real)
        _ = failure { _ = try run(f) }
        bytes(real.appendingPathComponent("A.JPG"), original, "session symlink refused")
    }
    do {
        let f = try setup(), original = Data([7])
        let target = f.root.appendingPathComponent("target")
        try original.write(to: target)
        try fm.createSymbolicLink(at: f.input.appendingPathComponent("A.JPG"), withDestinationURL: target)
        _ = failure { _ = try run(f) }
        bytes(target, original, "selected symlink target untouched")
    }

    // Every named phase injection must actually fire; prefix, partial pair, later sources and retry checked.
    for phase in ["rejectJPG", "rejectRAW", "copy", "editedPromotion", "archiveJPG", "archiveRAW", "orphan"] {
        let f = try setup(), edited = phase == "editedPromotion", rejecting = phase.hasPrefix("reject")
        var markers: [String: Data] = [:]
        for (i, name) in ["A.JPG", "A.RAF", "B.JPG", "B.RAF", "C.JPG", "C.RAF", "D.RAF"].enumerated() {
            if edited && name.hasSuffix("JPG") { try jpeg(f.input.appendingPathComponent(name), red: CGFloat(i + 1) / 8) }
            else { try write(f.input, name, Data([UInt8(20 + i), UInt8(80 + i)])) }
            markers[name] = try Data(contentsOf: f.input.appendingPathComponent(name))
        }
        let metadata = try sidecar(f, reject: rejecting, edited: edited)
        let sentinel = Data([201, 202]); try write(f.dump, "unrelated.tmp", sentinel)
        let fired = Locked(false)
        let hooks = FinalizeHooks(boundary: { event, url in
            let target: Bool
            if phase == "copy" {
                // Actual Foundation copy failure in an exclusively owned stage, for B only.
                target = event == "copy" && fm.fileExists(atPath: f.archive.appendingPathComponent("A.JPG").path)
            } else { target = event == phase && (phase == "orphan" || url.lastPathComponent.hasPrefix("B")) }
            if target && !fired.change({ let old = $0; $0 = true; return old }) {
                if phase.hasPrefix("reject") { return } // Native synthetic Trash handler injects below.
                try fm.createSymbolicLink(atPath: url.path, withDestinationPath: f.root.appendingPathComponent("absent").path)
            }
        }, trash: { owned in
            precondition(owned.path.hasPrefix(f.input.path + "/.photocull-claims-"))
            let name = owned.lastPathComponent
            expect((try? Data(contentsOf: owned)) == markers[name], "Trash sees owned planned marker")
            let dst = f.trash.appendingPathComponent(name)
            if (phase == "rejectJPG" && name == "B.JPG") || (phase == "rejectRAW" && name == "B.RAF") {
                try Data([222]).write(to: dst)
            }
            guard renameatx_np(AT_FDCWD, owned.path, AT_FDCWD, dst.path, UInt32(RENAME_EXCL)) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            return dst
        })
        let error = failure { _ = try run(f, edited: edited, hooks: hooks) }
        expect(fired.change { $0 }, "\(phase) injection actually fired")
        let claim = try claims(f)
        expect(error.localizedDescription.contains(claim.path), "error includes exact owned claims")
        bytes(f.input.appendingPathComponent(Session.fileName), metadata, "\(phase) retains sidecar")
        bytes(f.archive.appendingPathComponent("A.JPG"), markers["A.JPG"]!, "\(phase) completed prefix JPG")
        bytes(f.archive.appendingPathComponent("A.RAF"), markers["A.RAF"]!, "\(phase) completed prefix RAW")
        if phase == "orphan" {
            bytes(claim.appendingPathComponent("D.RAF"), markers["D.RAF"]!, "orphan retained owned")
            bytes(f.archive.appendingPathComponent("C.JPG"), markers["C.JPG"]!, "pair prefix before orphan complete")
        } else {
            bytes(f.input.appendingPathComponent("C.JPG"), markers["C.JPG"]!, "later JPG untouched")
            bytes(f.input.appendingPathComponent("C.RAF"), markers["C.RAF"]!, "later RAW untouched")
            bytes(f.input.appendingPathComponent("D.RAF"), markers["D.RAF"]!, "later orphan untouched")
            if phase == "archiveRAW" {
                bytes(f.archive.appendingPathComponent("B.JPG"), markers["B.JPG"]!, "failing pair JPG prefix completed")
            } else if phase == "rejectRAW" {
                bytes(f.trash.appendingPathComponent("B.JPG"), markers["B.JPG"]!, "reject JPG prefix completed")
            } else { bytes(claim.appendingPathComponent("B.JPG"), markers["B.JPG"]!, "failing JPG retained claimed") }
            bytes(claim.appendingPathComponent("B.RAF"), markers["B.RAF"]!, "failing RAW retained claimed")
        }
        bytes(f.dump.appendingPathComponent("unrelated.tmp"), sentinel, "unrelated tmp untouched")
        let record = try Data(contentsOf: f.input.appendingPathComponent(".photocull-recovery.json"))
        let document = try JSONSerialization.jsonObject(with: record) as! [String: Any]
        let plans = document["sources"] as! [[String: Any]]
        expect(plans.allSatisfy { ($0["claim"] as? String)?.hasPrefix(claim.path + "/") == true && $0["identity"] is [String: Any] }, "record has precise structured per-source plans")
        let journal = URL(fileURLWithPath: document["progress"] as! String)
        let events = try Data(contentsOf: journal).split(separator: 10).map {
            try JSONSerialization.jsonObject(with: Data($0)) as! [String: String]
        }
        expect(events.contains { $0["location"] == f.archive.appendingPathComponent("A.JPG").path && $0["action"] == "archive" }, "durable progress records precise completed archive path")
        if phase == "rejectRAW" {
            expect(events.contains { $0["location"] == f.trash.appendingPathComponent("B.JPG").path && $0["action"] == "Trash" }, "native returned Trash path recorded")
        }
        if phase.hasPrefix("reject") {
            bytes(f.trash.appendingPathComponent(phase == "rejectJPG" ? "B.JPG" : "B.RAF"), Data([222]), "synthetic native Trash collision never overwrites foreign marker")
        }
        try noStages(f); try retryBlocked(f)
    }

    // Race at copy promotion, including dangling-link destination, never overwrites.
    for dangling in [false, true] {
        let f = try setup(), original = Data([61, 62]), outsider = Data([91, 92])
        try write(f.input, "A.JPG", original); _ = try sidecar(f)
        var fired = false
        _ = failure { _ = try run(f, hooks: FinalizeHooks(boundary: { event, dst in
            if event == "copyPromotion" {
                fired = true
                if dangling { try fm.createSymbolicLink(atPath: dst.path, withDestinationPath: "missing") }
                else { try outsider.write(to: dst) }
            }
        })) }
        expect(fired, "copy promotion race fired")
        if dangling { expect((try? fm.destinationOfSymbolicLink(atPath: f.dump.appendingPathComponent("A.JPG").path)) == "missing", "dangling destination preserved") }
        else { bytes(f.dump.appendingPathComponent("A.JPG"), outsider, "external destination marker preserved") }
        bytes(try claims(f).appendingPathComponent("A.JPG"), original, "copy race original remains owned")
        try noStages(f); try retryBlocked(f)
    }

    // Inject EXDEV inside the native move's catchable block; execute the REAL archive fallback.
    // No mounts: this proves error-path sequencing, not physical cross-volume behavior.
    for scenario in ["success", "copy", "promotion-file", "promotion-link", "unlink"] {
        let f = try setup(), original = Data([181, 182, 183]), stranger = Data([191, 192])
        let src = f.input.appendingPathComponent("A.JPG"), dst = f.archive.appendingPathComponent("A.JPG")
        try original.write(to: src)
        let identity = FileToken.read(src), metadata = try sidecar(f)
        var forced = 0, copies = 0, promotions = 0, unlinks = 0
        var stageCopy: URL?, owned: URL?
        let hooks = FinalizeHooks(boundary: { event, url in
            if event == "claimed" { owned = url.appendingPathComponent("A.JPG") }
            if event == "archiveMove" {
                forced += 1
                expect(forced == 1 && url == dst, "EXDEV injected once at actual archive move")
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(EXDEV))
            }
            if event == "copy" {
                copies += 1; stageCopy = url
                expect(url.path.hasPrefix(f.archive.path + "/.photocull-stage-"), "fallback copy stage on archive destination")
                if scenario == "copy" { try stranger.write(to: url) } // Real Foundation copy collision.
            }
            if event == "copyPromotion" {
                promotions += 1
                bytes(stageCopy!, original, "fallback actually copied original before promotion")
                expect(FileToken.read(stageCopy!) != identity, "fallback copy has distinct inode")
                bytes(owned!, original, "source still owned before promotion")
                if scenario == "promotion-file" { try stranger.write(to: url) }
                if scenario == "promotion-link" { try fm.createSymbolicLink(atPath: url.path, withDestinationPath: "missing") }
            }
            if event == "archiveUnlink" {
                unlinks += 1
                bytes(dst, original, "archive promoted before owned source unlink")
                bytes(url, original, "owned source still intact at unlink boundary")
                if scenario == "unlink" { precondition(chmod(url.deletingLastPathComponent().path, 0o500) == 0) }
            }
        }, trash: { _ in fatalError("EXDEV archive must not reach Trash") })
        defer { if let owned { _ = chmod(owned.deletingLastPathComponent().path, 0o700) } }
        if scenario == "success" {
            let result = try run(f, dump: false, hooks: hooks)
            expect(result.archived == 1, "EXDEV success counted")
            bytes(dst, original, "EXDEV archive bytes exact")
            expect(FileToken.read(dst) != identity, "EXDEV final output distinct inode")
            expect(!fm.fileExists(atPath: owned!.path) && !fm.fileExists(atPath: src.path), "EXDEV success removes owned source")
            expect((try fm.contentsOfDirectory(atPath: f.input.path)) == [Session.fileName], "EXDEV success removes claims and record only")
        } else {
            let error = failure { _ = try run(f, dump: false, hooks: hooks) }
            if scenario == "unlink" { precondition(chmod(owned!.deletingLastPathComponent().path, 0o700) == 0) }
            bytes(try claims(f).appendingPathComponent("A.JPG"), original, "EXDEV failure retains claimed source")
            expect(FileToken.read(owned!) == identity, "EXDEV failure retains original inode")
            expect(error.localizedDescription.contains(owned!.deletingLastPathComponent().path), "EXDEV error identifies manual recovery claims")
            expect(fm.fileExists(atPath: f.input.appendingPathComponent(".photocull-recovery.json").path), "EXDEV failure retains recovery record")
            if scenario == "promotion-file" { bytes(dst, stranger, "EXDEV promotion never overwrites outsider") }
            else if scenario == "promotion-link" {
                expect((try? fm.destinationOfSymbolicLink(atPath: dst.path)) == "missing", "EXDEV promotion preserves dangling link")
            } else if scenario == "unlink" {
                bytes(dst, original, "EXDEV unlink failure preserves promoted prefix")
                expect(FileToken.read(dst) != identity, "EXDEV unlink failure prefix is copied inode")
            } else { expect(!fm.fileExists(atPath: dst.path), "EXDEV failed copy never promoted") }
            try retryBlocked(f)
        }
        expect(forced == 1 && copies == 1, "EXDEV catch entered actual fallback once")
        expect(promotions == (scenario == "copy" ? 0 : 1), "EXDEV actual Foundation copy success/failure observed")
        expect(unlinks == (["success", "unlink"].contains(scenario) ? 1 : 0), "EXDEV unlink only after successful exclusive promotion")
        bytes(f.input.appendingPathComponent(Session.fileName), metadata, "EXDEV preserves sidecar")
        try noStages(f)
    }

    // JPG and orphan replacement after planning is claimed, rejected, restored, never acted on under old decisions.
    for name in ["A.JPG", "O.RAF"] {
        let f = try setup(), original = Data([70, 71]), replacement = Data([80, 81])
        try write(f.input, name, original); _ = try sidecar(f)
        let old = f.root.appendingPathComponent("old-\(name)"), originalIdentity = FileToken.read(f.input.appendingPathComponent(name))
        var fired = false, replacementIdentity: FileToken?
        _ = failure { _ = try run(f, hooks: FinalizeHooks(boundary: { event, src in
            if event == "beforeClaim", src.lastPathComponent == name {
                fired = true; try fm.moveItem(at: src, to: old); try replacement.write(to: src)
                // Equalize size/type/mtime exactly: refusing this replacement requires inode identity, not just metadata.
                var st = stat(); precondition(lstat(old.path, &st) == 0)
                var times = [st.st_atimespec, st.st_mtimespec]
                precondition(utimensat(AT_FDCWD, src.path, &times, AT_SYMLINK_NOFOLLOW) == 0)
                replacementIdentity = FileToken.read(src)
            }
        }, trash: { _ in fatalError("replacement reached Trash") })) }
        expect(fired, "replacement boundary fired")
        bytes(old, original, "original displaced by external writer retained")
        bytes(f.input.appendingPathComponent(name), replacement, "replacement restored unchanged")
        expect(FileToken.read(old) == originalIdentity, "displaced original inode remains intact")
        expect(FileToken.read(f.input.appendingPathComponent(name)) == replacementIdentity && replacementIdentity != originalIdentity, "replacement retains its distinct inode through claim/restore")
        expect((try fm.contentsOfDirectory(atPath: f.archive.path)).isEmpty, "replacement not archived")
        try retryBlocked(f)
    }
    // Failure on the pair's second claim restores the first; occupied restoration retains it.
    for occupied in [false, true] {
        let f = try setup(), jpg = Data([101]), raw = Data([102]), outsider = Data([103])
        try write(f.input, "A.JPG", jpg); try write(f.input, "A.RAF", raw); _ = try sidecar(f)
        let displaced = f.root.appendingPathComponent("displaced-RAW")
        var fired = false
        _ = failure { _ = try run(f, hooks: FinalizeHooks(boundary: { event, src in
            if event == "beforeClaim", src.lastPathComponent == "A.RAF" {
                fired = true; try fm.moveItem(at: src, to: displaced)
                if occupied { try write(f.input, "A.JPG", outsider) }
            }
        })) }
        expect(fired, "second claim failure fires")
        bytes(displaced, raw, "second member preserved")
        if occupied {
            bytes(f.input.appendingPathComponent("A.JPG"), outsider, "occupied restore never overwritten")
            bytes(try claims(f).appendingPathComponent("A.JPG"), jpg, "first claim retained with exact marker")
        } else { bytes(f.input.appendingPathComponent("A.JPG"), jpg, "first member restored no-overwrite") }
        expect((try fm.contentsOfDirectory(atPath: f.dump.path)).isEmpty, "no effects before both claimed")
        try retryBlocked(f)
    }
    do {
        let f = try setup(), original = Data([111]), replacement = Data([112])
        try write(f.input, "A.JPG", original); _ = try sidecar(f)
        let old = f.root.appendingPathComponent("old-date")
        var fired = false
        _ = failure { _ = try run(f, hooks: FinalizeHooks(boundary: { event, _ in
            if event == "planned" {
                fired = true; try fm.moveItem(at: f.input, to: old)
                try fm.createDirectory(at: f.input, withIntermediateDirectories: false)
                try write(f.input, "A.JPG", replacement)
            }
        })) }
        expect(fired, "directory replacement barrier fired")
        bytes(old.appendingPathComponent("A.JPG"), original, "pinned old directory original retained")
        bytes(f.input.appendingPathComponent("A.JPG"), replacement, "replacement directory untouched")
        expect((try fm.contentsOfDirectory(atPath: f.archive.path)).isEmpty, "directory swap no archive effects")
    }
    // Absence is not equivalent to a newly unreadable/type-invalid sidecar.
    do {
        let f = try setup(), original = Data([121])
        try write(f.input, "O.RAF", original)
        var fired = false
        _ = failure { _ = try run(f, hooks: FinalizeHooks(boundary: { event, _ in
            if event == "beforeClaim" {
                fired = true; try fm.createSymbolicLink(atPath: f.input.appendingPathComponent(Session.fileName).path,
                                                       withDestinationPath: "missing-sidecar")
            }
        })) }
        expect(fired, "absent sidecar replacement fired")
        bytes(f.input.appendingPathComponent("O.RAF"), original, "orphan unchanged by absent-to-invalid sidecar")
        expect((try? fm.destinationOfSymbolicLink(atPath: f.input.appendingPathComponent(Session.fileName).path)) == "missing-sidecar", "new unreadable sidecar preserved")
        try retryBlocked(f)
    }
    // Recovery-name substitution must not be blindly unlinked or allow another run.
    do {
        let f = try setup(), original = Data([131]), stranger = Data([132, 133])
        try write(f.input, "A.JPG", original); _ = try sidecar(f)
        let oldRecord = f.root.appendingPathComponent("original-record.json")
        var fired = false
        let error = failure { _ = try run(f, hooks: FinalizeHooks(boundary: { event, record in
            if event == "recordRemoval" {
                fired = true; try fm.moveItem(at: record, to: oldRecord); try stranger.write(to: record)
            }
        })) }
        expect(fired, "record replacement injection fires")
        bytes(try claims(f).appendingPathComponent("recovery-metadata"), stranger, "substituted record retained not deleted")
        expect(fm.fileExists(atPath: oldRecord.path), "original recovery record retained")
        expect(error.localizedDescription.contains(oldRecord.path), "record substitution reports actual owned plan location")
        expect(fm.fileExists(atPath: try claims(f).appendingPathComponent(".progress.jsonl").path), "record substitution preserves progress journal")
        bytes(f.archive.appendingPathComponent("A.JPG"), original, "record failure preserves completed prefix")
        try retryBlocked(f)
    }
    // A source replaced immediately after native encoding must invalidate the export BEFORE any source claim.
    do {
        let f = try setup(), replacement = Data([140, 141, 142])
        let src = f.input.appendingPathComponent("A.JPG"), old = f.root.appendingPathComponent("encoded-original.JPG")
        try jpeg(src, red: 0.8)
        let original = try Data(contentsOf: src), originalIdentity = FileToken.read(src)
        let s = Session.fresh(); s.setCrop("A", CropRect(x: 0.1, y: 0.1, w: 0.8, h: 0.8)); try s.save(folder: f.input)
        let fired = Locked(false), attemptedClaims = Locked(0)
        _ = failure { _ = try run(f, edited: true, hooks: FinalizeHooks(boundary: { event, url in
            if event == "exported" {
                fired.change { $0 = true }; try fm.moveItem(at: url, to: old); try replacement.write(to: url)
            }
            if event == "beforeClaim" { attemptedClaims.change { $0 += 1 } }
        })) }
        expect(fired.change { $0 }, "post-encoding stability boundary fires")
        expect(attemptedClaims.change { $0 } == 0, "unstable encoded source causes no claim admission")
        bytes(old, original, "post-encoding displaced source bytes intact")
        expect(FileToken.read(old) == originalIdentity, "encoded original inode intact")
        bytes(src, replacement, "post-encoding replacement bytes intact")
        expect((try fm.contentsOfDirectory(atPath: f.dump.path)).isEmpty, "stale encoded output never promoted")
        try noStages(f); try retryBlocked(f)
    }
    // A directory swap after the originals are claimed must restore into the pinned OLD namespace only.
    do {
        let f = try setup(), jpg = Data([143]), raw = Data([144]), stranger = Data([145])
        try write(f.input, "A.JPG", jpg); try write(f.input, "A.RAF", raw); _ = try sidecar(f)
        let old = f.root.appendingPathComponent("old-claimed-date")
        var fired = false
        let error = failure { _ = try run(f, hooks: FinalizeHooks(boundary: { event, _ in
            if event == "claimed" {
                fired = true; try fm.moveItem(at: f.input, to: old)
                try fm.createDirectory(at: f.input, withIntermediateDirectories: false)
                try write(f.input, "A.JPG", stranger)
            }
        })) }
        expect(fired, "post-claim directory swap fires")
        bytes(old.appendingPathComponent("A.JPG"), jpg, "first original restored to pinned old date")
        bytes(old.appendingPathComponent("A.RAF"), raw, "second original restored to pinned old date")
        bytes(f.input.appendingPathComponent("A.JPG"), stranger, "new visible date never touched")
        expect(error.localizedDescription.contains(old.path), "recovery diagnostics resolve old pinned directory path")
        expect((try fm.contentsOfDirectory(atPath: f.archive.path)).isEmpty, "post-claim swap no archive effects")
    }
    // Output namespace substitution is refused after dump prefix, without acting on the replacement directory.
    do {
        let f = try setup(), jpg = Data([146]), stranger = Data([147])
        try write(f.input, "A.JPG", jpg); _ = try sidecar(f)
        let old = f.root.appendingPathComponent("old-archive")
        var fired = false
        _ = failure { _ = try run(f, hooks: FinalizeHooks(boundary: { event, _ in
            if event == "archiveJPG" {
                fired = true; try fm.moveItem(at: f.archive, to: old)
                try fm.createDirectory(at: f.archive, withIntermediateDirectories: false)
                try write(f.archive, "A.JPG", stranger)
            }
        })) }
        expect(fired, "archive substitution fires")
        bytes(f.archive.appendingPathComponent("A.JPG"), stranger, "replacement output marker untouched")
        bytes(try claims(f).appendingPathComponent("A.JPG"), jpg, "output swap retains claimed original")
        bytes(f.dump.appendingPathComponent("A.JPG"), jpg, "output swap preserves dump prefix")
        try retryBlocked(f)
    }
    // Edited output-directory replacement must fail while cleaning stages through the pinned OLD output FD.
    do {
        let f = try setup(), stranger = Data([146, 147, 148])
        let src = f.input.appendingPathComponent("A.JPG"), old = f.root.appendingPathComponent("old-dump")
        try jpeg(src, red: 0.5)
        let original = try Data(contentsOf: src)
        let s = Session.fresh(); s.setCrop("A", CropRect(x: 0.1, y: 0.1, w: 0.8, h: 0.8)); try s.save(folder: f.input)
        var fired = false
        let error = failure { _ = try run(f, edited: true, hooks: FinalizeHooks(boundary: { event, _ in
            if event == "editedPromotion" {
                fired = true; try fm.moveItem(at: f.dump, to: old)
                try fm.createDirectory(at: f.dump, withIntermediateDirectories: false)
                try write(f.dump, "A.JPG", stranger)
            }
        })) }
        expect(fired, "edited output substitution fires")
        bytes(f.dump.appendingPathComponent("A.JPG"), stranger, "replacement dump marker untouched")
        bytes(try claims(f).appendingPathComponent("A.JPG"), original, "edited output replacement retains claimed original")
        expect((try fm.contentsOfDirectory(atPath: old.path)).isEmpty, "old pinned output has no owned export stages after substitution")
        expect(error.localizedDescription.contains(old.path), "output substitution diagnostics give retained old directory")
        try noStages(f); try retryBlocked(f)
    }
    // Successful rejects use only the invocation's synthetic native handler, even when it returns no path.
    do {
        let f = try setup(), jpg = Data([148]), raw = Data([149])
        try write(f.input, "B.JPG", jpg); try write(f.input, "B.RAF", raw)
        let metadata = try sidecar(f, reject: true)
        let result = try run(f, hooks: FinalizeHooks(trash: { owned in
            let dst = f.trash.appendingPathComponent(owned.lastPathComponent)
            guard renameatx_np(AT_FDCWD, owned.path, AT_FDCWD, dst.path, UInt32(RENAME_EXCL)) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            return nil
        }))
        expect(result.trashed == 2 && result.archived == 0, "successful synthetic reject counts pair")
        bytes(f.trash.appendingPathComponent("B.JPG"), jpg, "successful synthetic JPG marker exact")
        bytes(f.trash.appendingPathComponent("B.RAF"), raw, "successful synthetic RAW marker exact")
        bytes(f.input.appendingPathComponent(Session.fileName), metadata, "successful rejection retains decisions")
        expect((try fm.contentsOfDirectory(atPath: f.input.path)) == [Session.fileName], "successful rejection removes only own metadata/empty claims")
    }
    // Changed bytes before a later pair/orphan preserve the changed decisions and already-completed prefix.
    for target in ["B.JPG", "O.RAF"] {
        let f = try setup(), a = Data([151]), b = Data([152]), changed = Data(#"{"version":1,"decisions":{"B":"reject"}}"#.utf8)
        try write(f.input, "A.JPG", a); try write(f.input, target, b); _ = try sidecar(f)
        var fired = false
        _ = failure { _ = try run(f, hooks: FinalizeHooks(boundary: { event, src in
            if event == "beforeClaim", src.lastPathComponent == target {
                fired = true; try write(f.input, Session.fileName, changed)
            }
        }, trash: { _ in fatalError("changed sidecar reached Trash") })) }
        expect(fired, "later sidecar change boundary fires")
        bytes(f.archive.appendingPathComponent("A.JPG"), a, "sidecar change preserves completed prefix")
        bytes(f.input.appendingPathComponent(target), b, "sidecar change keeps later source")
        bytes(f.input.appendingPathComponent(Session.fileName), changed, "changed sidecar never overwritten")
        try retryBlocked(f)
    }
    do {
        let f = try setup(), original = Data([161])
        try write(f.input, "A.JPG", original)
        var fired = false
        _ = failure { _ = try run(f, hooks: FinalizeHooks(boundary: { event, _ in
            if event == "beforeClaim" {
                fired = true
                try write(f.input, Session.fileName, Data("{\"version\":1}".utf8))
                precondition(chmod(f.input.appendingPathComponent(Session.fileName).path, 0) == 0)
            }
        })) }
        expect(fired, "absent to permission-unreadable sidecar fires")
        precondition(chmod(f.input.appendingPathComponent(Session.fileName).path, 0o600) == 0)
        bytes(f.input.appendingPathComponent("A.JPG"), original, "unreadable new sidecar keeps original")
        try retryBlocked(f)
    }
    do {
        let f = try setup(), original = Data([171])
        try write(f.input, "A.JPG", original); _ = try sidecar(f)
        var fired = false, claimPath: URL?
        _ = failure { _ = try run(f, hooks: FinalizeHooks(boundary: { event, _ in
            if event == "recordRemoval" {
                fired = true; claimPath = try claims(f)
                precondition(chmod(claimPath!.path, 0o500) == 0)
            }
        })) }
        expect(fired, "record removal native permission failure fires")
        precondition(chmod(claimPath!.path, 0o700) == 0)
        expect(fm.fileExists(atPath: f.input.appendingPathComponent(".photocull-recovery.json").path), "record-removal error retains blocker")
        bytes(f.archive.appendingPathComponent("A.JPG"), original, "cleanup error preserves completed original")
        try retryBlocked(f)
    }
    // Admission stops on observed native encode failure; a held first worker proves no queued C/D work starts.
    do {
        let f = try setup()
        try jpeg(f.input.appendingPathComponent("A.JPG"), red: 0.8)
        for name in ["B.JPG", "C.JPG", "D.JPG"] { try write(f.input, name, Data("invalid jpeg \(name)".utf8)) }
        let s = Session.fresh()
        for stem in ["A", "B", "C", "D"] { s.setCrop(stem, CropRect(x: 0.1, y: 0.1, w: 0.8, h: 0.8)) }
        try s.save(folder: f.input)
        let failed = DispatchSemaphore(value: 0), aStarted = DispatchSemaphore(value: 0)
        let admitted = Locked<[String]>([])
        let err = failure { _ = try run(f, edited: true, hooks: FinalizeHooks(boundary: { event, src in
            if event == "export" {
                admitted.change { $0.append(src.lastPathComponent) }
                if src.lastPathComponent == "A.JPG" {
                    aStarted.signal()
                    guard failed.wait(timeout: .now() + 15) == .success else { fatalError("encode-failure observation timeout") }
                } else if src.lastPathComponent == "B.JPG" {
                    guard aStarted.wait(timeout: .now() + 15) == .success else { fatalError("first export start timeout") }
                }
            }
            if event == "exportFailed" { failed.signal() }
        })) }
        expect(Set(admitted.change { $0 }) == Set(["A.JPG", "B.JPG"]), "stop native admission after observed failure")
        expect(!err.localizedDescription.contains("ExportOutcomeMissing"), "preserve original encode error")
        expect(fm.fileExists(atPath: f.archive.appendingPathComponent("A.JPG").path), "started successful native worker drained")
        expect(fm.fileExists(atPath: f.input.appendingPathComponent("C.JPG").path), "unadmitted later original untouched")
        try noStages(f); try retryBlocked(f)
    }
    // True same-process flock contention: independent runs/descriptors, not fcntl process locks.
    do {
        let f = try setup(), original = Data([141])
        try write(f.input, "A.JPG", original); _ = try sidecar(f)
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
        let outcome = Locked<Error?>(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            do { _ = try run(f, hooks: FinalizeHooks(boundary: { event, _ in
                if event == "planned" {
                    entered.signal()
                    guard release.wait(timeout: .now() + 15) == .success else { fatalError("contention release timeout") }
                }
            })) } catch { outcome.change { $0 = error } }
            finished.signal()
        }
        guard entered.wait(timeout: .now() + 15) == .success else { fatalError("contention entry timeout") }
        let err = failure { _ = try run(f) }
        expect(err.localizedDescription.contains("Another Finalize"), "same-process independent run refused")
        bytes(f.input.appendingPathComponent("A.JPG"), original, "contender has zero original effects")
        let child = Process(), childFinished = DispatchSemaphore(value: 0)
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--flock-probe", f.input.path]
        child.terminationHandler = { _ in childFinished.signal() }
        try child.run()
        guard childFinished.wait(timeout: .now() + 15) == .success else { fatalError("independent process flock timeout") }
        expect(child.terminationStatus == 0, "independent-process descriptor also refuses lock contention")
        release.signal()
        guard finished.wait(timeout: .now() + 15) == .success else { fatalError("contention finish timeout") }
        expect(outcome.change { $0 } == nil, "first run drains successfully")
        expect(!(try fm.contentsOfDirectory(atPath: f.input.path)).contains { $0.hasPrefix(".photocull-") && $0 != Session.fileName }, "success leaves no claims/lock/recovery record")
    }
    print("FinalizeFailureChecks: \(checks) checks passed; artifacts: \(root.path)")
}
#endif

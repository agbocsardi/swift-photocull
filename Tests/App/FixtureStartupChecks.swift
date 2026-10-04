#if FIXTURE_CORE_CHECKS
import Foundation
import Darwin

// Actual Config/native lstat, with only the selected OWNED test path's UID changed.
// This permits owner-refusal checks without chown privileges or foreign files.
@_silgen_name("lstat") private func nativeLstat(_ path: UnsafePointer<CChar>, _ st: UnsafeMutablePointer<stat>) -> Int32
func lstat(_ path: String, _ st: UnsafeMutablePointer<stat>) -> Int32 {
    let result = path.withCString { nativeLstat($0, st) }
    if result == 0, let selected = getenv("PC_FIXTURE_OWNER_SPOOF"), path == String(cString: selected) {
        st.pointee.st_uid = getuid() &+ 1
    }
    return result
}
#else
import Foundation
import AppKit
import Darwin
import PhotoCullCore

// Test-local names shadow ONLY the App module's unsafe APIs. No actual ordinary
// preferences/cards/repair/external-app API is reached, even by negative controls.
private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1)
}
private final class Calls: @unchecked Sendable {
    static let shared = Calls()
    private let lock = NSLock()
    private var values: [String: Int] = [:]
    func add(_ key: String) { lock.lock(); defer { lock.unlock() }; values[key, default: 0] += 1 }
    func count(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return values[key, default: 0] }
    func reset() { lock.lock(); defer { lock.unlock() }; values = [:] }
}
final class UserDefaults {
    static let standard = UserDefaults()
    func string(forKey: String) -> String? { Calls.shared.add("preferences"); return nil }
    func set(_ value: Any?, forKey: String) { Calls.shared.add("preferences") }
    func removeObject(forKey: String) { Calls.shared.add("preferences") }
}
final class NSApplication {
    static let shared = NSApplication()
    var appearance: NSAppearance?
}
final class NSWorkspace {
    static let shared = NSWorkspace()
    final class OpenConfiguration {}
    func open(_ url: URL) { Calls.shared.add("external") }
    func open(_ urls: [URL], withApplicationAt: URL, configuration: OpenConfiguration) { Calls.shared.add("external") }
    func activateFileViewerSelecting(_ urls: [URL]) { Calls.shared.add("external") }
}
enum Ingest {
    static func detectSDCards() -> [URL] { Calls.shared.add("cards"); return [] }
    static func run(cfg: PCConfig, source: URL?, onProgress: (@Sendable (IngestProgress) -> Void)?) throws -> IngestResult {
        Calls.shared.add("ingest"); return IngestResult(copied: 0, skipped: 0, folders: [])
    }
}
enum PairRepair {
    static func plan(cfg: PCConfig) -> RepairReport {
        Calls.shared.add("repair"); return RepairReport(actions: [], renamed: 0, unpaired: 0, ambiguous: 0, applied: false)
    }
    static func apply(cfg: PCConfig, logDirectory: URL? = nil) throws -> RepairReport { plan(cfg: cfg) }
}

@main struct FixtureStartupChecks {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let fm = FileManager.default
        guard let out = ProcessInfo.processInfo.environment["PC_FIXTURE_STARTUP_OUT"],
              out.hasPrefix("/private/tmp/photocull-manual-launch-") else { fail("Explicit owned launch output root required") }
        let root = URL(fileURLWithPath: out), config = root.appendingPathComponent("config/config.toml")
        let original = try Data(contentsOf: config)
        let id = StartupConfiguration.fixtureIdentifierPrefix + UUID().uuidString.lowercased()
        let args = ["--fixture-config", config.path]
        var checks = 0
        func expect(_ condition: Bool, _ label: String) {
            checks += 1; if !condition { fail("FixtureStartup CHECK \(checks): \(label)") }
        }
        func reject(_ label: String, _ body: () throws -> Void) {
            do { try body(); fail("FixtureStartup accepted \(label)") }
            catch { expect(true, "reject \(label)"); print("Rejected: \(label)") }
        }
        func resolve(_ arguments: [String] = [], _ bundle: String? = nil) throws -> StartupConfiguration {
            try StartupConfiguration.resolve(arguments: arguments, bundleIdentifier: bundle)
        }
        func rejectText(_ label: String, _ text: Data) throws {
            try text.write(to: config)
            reject(label) { _ = try resolve(args, id) }
            expect(try Data(contentsOf: config) == text, "rejection never rewrites \(label)")
            try original.write(to: config)
        }
        let startup = try resolve(args, id)
        expect(startup.isFixture && startup.fixtureConfig?.paths.inbox == root.appendingPathComponent("inbox").path, "valid strict fixture config")
        expect(try PCConfig.loadFixture(from: config.path) == startup.fixtureConfig, "real read-only native loader matches resolver")
        expect(try Data(contentsOf: config) == original, "successful loader is read-only")
        for flags in [[], ["--check"], ["--repair-pairs"], ["--repair-pairs", "--apply"],
                      ["--snapshot", out + "/never.png", "--appearance", "dark"], ["--crop"], ["--unknown"]] {
            expect(try !resolve(flags, "local.photocull.swift").isFixture, "ordinary flag routing preserved: \(flags)")
            expect(try !resolve(flags, nil).isFixture, "ordinary unbundled routing preserved: \(flags)")
        }
        expect(Calls.shared.count("preferences") == 0 && Calls.shared.count("cards") == 0, "routing itself has no preference/card side effects")
        for bundle in [nil, "local.photocull.swift", "local.photocull.fixture", "local.photocull.fixture.bad", StartupConfiguration.fixtureIdentifierPrefix] as [String?] {
            reject("wrong/missing bundle identity \(bundle ?? "nil")") { _ = try resolve(args, bundle) }
        }
        reject("fixture identity without flag") { _ = try resolve([], id) }
        for flag in ["--check", "--repair-pairs", "--apply", "--snapshot", "--crop", "--appearance", "-psn_0_1", "--unknown"] {
            reject("mixed trailing \(flag)") { _ = try resolve(args + [flag], id) }
            reject("mixed leading \(flag)") { _ = try resolve([flag] + args, id) }
            reject("fixture identity with ordinary flag \(flag)") { _ = try resolve([flag], id) }
        }
        for malformed in [["--fixture-config"], args + args, ["--fixture-config=" + config.path],
                          ["--fixture-config-other", config.path], [config.path, "--fixture-config"]] {
            reject("malformed/duplicate flag \(malformed)") { _ = try resolve(malformed, id) }
        }
        for path in ["config/config.toml", "~/config.toml", "", out + "/config/missing.toml",
                     out.replacingOccurrences(of: "/private/tmp/", with: "/tmp/") + "/config/config.toml",
                     out + "/config/../config/config.toml"] {
            reject("missing/relative/noncanonical path \(path)") { _ = try resolve(["--fixture-config", path], id) }
        }
        let saved = root.appendingPathComponent("checks/config-saved.toml")
        try fm.moveItem(at: config, to: saved)
        reject("missing canonical config") { _ = try resolve(args, id) }
        expect(!fm.fileExists(atPath: config.path), "missing config never created")
        try fm.moveItem(at: saved, to: config)
        let text = String(data: original, encoding: .utf8)!
        for (label, invalid) in [
            ("empty", ""), ("malformed", "{"), ("comment/unknown format", text + "# comment\n"),
            ("missing inbox", text.replacingOccurrences(of: "  inbox = \"\(out)/inbox\"\n", with: "")),
            ("missing archive", text.replacingOccurrences(of: "  archive = \"\(out)/archive\"\n", with: "")),
            ("missing export", text.replacingOccurrences(of: "  dump = \"\(out)/export\"\n", with: "")),
            ("missing files", String(text.split(separator: "[", omittingEmptySubsequences: false).dropLast().joined(separator: "["))),
            ("missing raw", text.replacingOccurrences(of: "  raw_extensions = [\"RAF\", \"RW2\"]\n", with: "")),
            ("missing jpg", text.replacingOccurrences(of: "  jpg_extensions = [\"JPG\", \"JPEG\"]\n", with: "")),
            ("empty extensions", text.replacingOccurrences(of: "[\"RAF\", \"RW2\"]", with: "[]")),
            ("unsupported extensions", text.replacingOccurrences(of: "RW2", with: "TXT")),
            ("relative inbox", text.replacingOccurrences(of: out + "/inbox", with: "inbox")),
            ("wrong archive root", text.replacingOccurrences(of: out + "/archive", with: out + "/checks")),
            ("wrong export root", text.replacingOccurrences(of: out + "/export", with: out + "/archive")),
            ("outside inbox", text.replacingOccurrences(of: out + "/inbox", with: "/private/tmp")),
            ("traversal inbox", text.replacingOccurrences(of: out + "/inbox", with: out + "/checks/../inbox")),
            ("duplicate key", text.replacingOccurrences(of: "[paths]\n", with: "[paths]\n  inbox = \"wrong\"\n")),
            ("unknown key", text + "  unsafe = \"yes\"\n"),
            ("unterminated quote", text.replacingOccurrences(of: "/inbox\"", with: "/inbox")),
            ("oversized", String(repeating: "#", count: 16_385))] {
            try rejectText(label, Data(invalid.utf8))
        }
        try rejectText("invalid UTF-8", Data([0xff, 0xfe]))
        let other = root.appendingPathComponent("config/other.toml")
        try original.write(to: other)
        reject("wrong config basename") { _ = try resolve(["--fixture-config", other.path], id) }
        try fm.removeItem(at: other)
        let wrongDirectory = root.appendingPathComponent("checks/config.toml")
        try original.write(to: wrongDirectory)
        reject("wrong config directory") { _ = try resolve(["--fixture-config", wrongDirectory.path], id) }
        try fm.removeItem(at: wrongDirectory)
        for name in ["inbox", "archive", "export"] {
            let directory = root.appendingPathComponent(name), savedDir = root.appendingPathComponent("checks/\(name)-missing")
            try fm.moveItem(at: directory, to: savedDir)
            reject("missing data directory \(name)") { _ = try resolve(args, id) }
            try Data("owned wrong node type".utf8).write(to: directory)
            reject("regular file instead of data directory \(name)") { _ = try resolve(args, id) }
            try fm.removeItem(at: directory); try fm.moveItem(at: savedDir, to: directory)
        }
        // Permissions and node types are all changed only on OWNED generated objects.
        for path in [out, config.path, out + "/config", out + "/inbox", out + "/archive", out + "/export"] {
            let mode: mode_t = path == config.path ? 0o600 : 0o700
            precondition(chmod(path, 0) == 0)
            reject("unreadable item \(path)") { _ = try resolve(args, id) }
            precondition(chmod(path, mode) == 0)
        }
        precondition(chmod(out, 0o755) == 0)
        reject("non-private fixture root") { _ = try resolve(args, id) }
        precondition(chmod(out, 0o700) == 0)
        for path in [out, out + "/config", config.path, out + "/inbox", out + "/archive", out + "/export",
                     out + "/inbox/2024-05-03/notes.txt"] {
            setenv("PC_FIXTURE_OWNER_SPOOF", path, 1)
            reject("wrong owner (native forward + UID injection) \(path)") { _ = try resolve(args, id) }
            unsetenv("PC_FIXTURE_OWNER_SPOOF")
        }
        let link = root.appendingPathComponent("inbox/2024-05-03/owned-link.JPG")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "notes.txt")
        reject("symlink in input subtree") { _ = try resolve(args, id) }
        try fm.removeItem(at: link)
        for name in ["inbox", "archive", "export"] {
            let directory = root.appendingPathComponent(name), originalDir = root.appendingPathComponent("checks/\(name)-saved")
            try fm.moveItem(at: directory, to: originalDir)
            try fm.createSymbolicLink(atPath: directory.path, withDestinationPath: "checks/\(name)-saved")
            reject("symlink data root \(name)") { _ = try resolve(args, id) }
            try fm.removeItem(at: directory); try fm.moveItem(at: originalDir, to: directory)
        }
        try fm.moveItem(at: config, to: saved)
        try fm.createSymbolicLink(atPath: config.path, withDestinationPath: "../checks/config-saved.toml")
        reject("symlink config") { _ = try resolve(args, id) }
        try fm.removeItem(at: config); try fm.moveItem(at: saved, to: config)
        let configDir = config.deletingLastPathComponent(), savedConfigDir = root.appendingPathComponent("checks/config-dir-saved")
        try fm.moveItem(at: configDir, to: savedConfigDir)
        try fm.createSymbolicLink(atPath: configDir.path, withDestinationPath: "checks/config-dir-saved")
        reject("symlink config ancestor") { _ = try resolve(args, id) }
        try fm.removeItem(at: configDir); try fm.moveItem(at: savedConfigDir, to: configDir)
        try fm.linkItem(at: config, to: saved)
        reject("hardlinked config") { _ = try resolve(args, id) }
        try fm.removeItem(at: saved)
        let special = root.appendingPathComponent("inbox/owned-pipe")
        precondition(mkfifo(special.path, 0o600) == 0)
        reject("special input node") { _ = try resolve(args, id) }
        try fm.removeItem(at: special)
        try fm.moveItem(at: config, to: saved)
        try fm.createDirectory(at: config, withIntermediateDirectories: false)
        reject("directory config") { _ = try resolve(args, id) }
        try fm.removeItem(at: config); try fm.moveItem(at: saved, to: config)
        expect(try resolve(args, id).fixtureConfig == startup.fixtureConfig, "valid fixture after all mutations restored")
        expect(try Data(contentsOf: config) == original, "all config controls restored exactly")

        Calls.shared.reset()
        let app = startup.makeAppState() // Real initializer, default initializeAppearance:true, no NSApp/default prefs.
        expect(app.fixtureMode && app.pairs.count == 6 && app.appearance == .system, "fixture startup opens only generated session")
        expect(Calls.shared.count("preferences") == 0, "fixture initializer skips appearance preference reads/writes")
        app.appearance = .system
        expect(Calls.shared.count("preferences") == 0, "fixture appearance changes never persist standard preferences")
        let sidecar = root.appendingPathComponent("inbox/2024-05-03/.photocull.json")
        expect(!fm.fileExists(atPath: sidecar.path), "startup did not create decisions")
        app.ingestSource = out + "/inbox"
        app.beginIngest(); app.startIngest(); app.checkPairing(); app.repairPairingInteractive(); app.applyPairRepair()
        app.openInPreview(); app.revealInFinder()
        app.commandBuffer = "i"; app.runCommand(); app.commandBuffer = "R"; app.runCommand()
        try await Task.sleep(nanoseconds: 100_000_000)
        expect(app.bulkOperation == nil && app.modal == nil && app.detectedCards.isEmpty, "shared methods block forbidden fixture work")
        expect(!fm.fileExists(atPath: sidecar.path), "blocked entries return before any outgoing sidecar flush")
        for kind in ["preferences", "cards", "ingest", "repair", "external"] {
            expect(Calls.shared.count(kind) == 0, "fixture guard prevents actual \(kind) API reach")
        }
        app.setIndex(2); app.enterCropMode(); app.applyAspect(); app.cropAspect = .square; app.applyAspect()
        app.nudgeTilt(2); app.commitCrop(); app.mark(.keep)
        expect(app.index == 3 && app.decision(for: "03_BLUE_EDIT_KEEP") == .keep, "fixture decision auto-advance remains supported")
        let session = try Session.load(folder: sidecar.deletingLastPathComponent(), strict: true)
        expect(session.crop(for: "03_BLUE_EDIT_KEEP")?.isFullFrame == false && session.tilt(for: "03_BLUE_EDIT_KEEP") == 2,
               "fixture crop/tilt persist only under explicit inbox")
        app.beginFinalizeCurrent()
        for _ in 0..<1000 {
            if !app.finalizeStats.isEmpty || app.errorMessage != nil { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        expect(app.finalizeStats.first?.keep == 1 && app.finalizeStats.first?.undecided == 5, "fixture read-only confirmation summary")
        app.modal = nil
        expect(app.bulkOperation == nil && app.prepareForTermination(), "fixture cancel/termination flush supported; no Finalize confirmation")
        // Keep fixture generation virgin after test-side decisions, preserving every JPEG/marker.
        try fm.removeItem(at: sidecar)
        Calls.shared.reset()
        let ordinary = AppState(cfg: startup.fixtureConfig!, initializeAppearance: true)
        expect(!ordinary.fixtureMode && Calls.shared.count("preferences") >= 2, "ordinary preference behavior preserved via harmless test shadow")
        Calls.shared.reset()
        ordinary.beginIngest()
        expect(Calls.shared.count("cards") == 1 && ordinary.modal == .ingest, "ordinary ingest entry remains enabled; test shadow never scans /Volumes")
        ordinary.modal = nil; ordinary.checkPairing()
        for _ in 0..<1000 {
            if ordinary.bulkOperation == nil { break }; try await Task.sleep(nanoseconds: 5_000_000)
        }
        ordinary.openInPreview(); ordinary.revealInFinder()
        expect(Calls.shared.count("repair") == 1 && Calls.shared.count("external") == 2, "ordinary repair/external routes preserved with safe shadows")
        if fm.fileExists(atPath: sidecar.path) { try fm.removeItem(at: sidecar) }
        print("FixtureStartupChecks: \(checks) checks passed; no GUI, ordinary config/preferences, card scans or Trash APIs executed")
    }
}
#endif

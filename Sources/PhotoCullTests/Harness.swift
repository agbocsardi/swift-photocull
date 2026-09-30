import Foundation

/// Tiny test harness (XCTest is unavailable in a CommandLineTools-only toolchain).

nonisolated(unsafe) var pcFailures: [String] = []
nonisolated(unsafe) var pcChecks = 0

public func check(_ cond: Bool, _ msg: String, file: String = #fileID, line: Int = #line) {
    pcChecks += 1
    if cond {
        print("  ok   \(msg)")
    } else {
        let where_ = "\(file):\(line)"
        pcFailures.append("\(msg)  [\(where_)]")
        print("  FAIL \(msg)  [\(where_)]")
    }
}

public func checkEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String,
                                     file: String = #fileID, line: Int = #line) {
    check(a == b, "\(msg) (got \(a), want \(b))", file: file, line: line)
}

public func checkClose(_ a: Double, _ b: Double, _ tol: Double = 0.001, _ msg: String,
                       file: String = #fileID, line: Int = #line) {
    check(abs(a - b) <= tol, "\(msg) (got \(a), want \(b)±\(tol))", file: file, line: line)
}

public func suite(_ name: String, _ body: () throws -> Void) {
    print("\n== \(name) ==")
    do { try body() } catch { pcFailures.append("\(name) threw: \(error)"); print("  THREW \(error)") }
}

/// Temp directory that is removed when the process exits.
public func makeTempDir(_ tag: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("pc-\(tag)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

public func touch(_ url: URL, bytes: Int = 8) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try Data(repeating: 0x41, count: bytes).write(to: url)
}

/// URL of the bundled fixture images (the photocull repo's test JPEGs).
public func fixtureURL(_ name: String) -> URL? {
    let bases = [
        ProcessInfo.processInfo.environment["PC_FIXTURES"],
        FileManager.default.currentDirectoryPath + "/testdata",
        NSHomeDirectory() + "/Documents/1-projects/photocull/tests/fixtures",
    ].compactMap { $0 }
    for b in bases {
        let u = URL(fileURLWithPath: b).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: u.path) { return u }
    }
    return nil
}

import Foundation
import PhotoCullCore

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { print("  ok   \(message)") }
    else { fputs("  FAIL \(message)\n", stderr); failures += 1 }
    checks += 1
}

struct CallbackState {
    var events: [IngestProgress] = []
    var activeCopies = 0
    var maxConcurrentCopies = 0
}

var checks = 0
var failures = 0
guard CommandLine.arguments.count == 2 else {
    fputs("usage: IngestCollectorChecks OUT\n", stderr)
    exit(2)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
let root = out.appendingPathComponent("ingest-collector-\(UUID().uuidString)", isDirectory: true)
guard root.path.hasPrefix(out.path + "/") else { fatalError("synthetic root escaped OUT") }
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

let card = root.appendingPathComponent("card/DCIM/100FUJI", isDirectory: true)
try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
let day = Calendar.current.date(from: DateComponents(year: 2024, month: 9, day: 12, hour: 12))!
var originals: [String: Data] = [:]
for index in 0..<12 {
    let name = String(format: "SYN%04d.JPG", index)
    let marker = UInt8(index + 1)
    let bytes = Data(repeating: marker, count: 256 * 1024)
    originals[name] = bytes
    let file = card.appendingPathComponent(name)
    try bytes.write(to: file)
    try FileManager.default.setAttributes([.modificationDate: day], ofItemAtPath: file.path)
}
let cfg = PCConfig(
    paths: PathsConfig(inbox: root.appendingPathComponent("inbox").path,
                       archive: root.appendingPathComponent("archive").path,
                       dump: root.appendingPathComponent("dump").path),
    files: FilesConfig(rawExtensions: [], jpgExtensions: ["JPG"]))
let box = LockedBox(CallbackState())
let runError = LockedBox<String?>(nil)
let finished = DispatchSemaphore(value: 0)
DispatchQueue.global().async {
    do {
        _ = try Ingest.run(cfg: cfg, source: card.deletingLastPathComponent()) { event in
            if event.copied > 0 {
                box.update { $0.activeCopies += 1; $0.maxConcurrentCopies = max($0.maxConcurrentCopies, $0.activeCopies) }
                Thread.sleep(forTimeInterval: 0.025)
                box.update { $0.events.append(event); $0.activeCopies -= 1 }
            } else {
                box.update { $0.events.append(event) }
            }
        }
    } catch {
        runError.update { $0 = String(describing: error) }
    }
    finished.signal()
}
guard finished.wait(timeout: .now() + 20) == .success else {
    fputs("Timed out waiting for Ingest callbacks\n", stderr)
    exit(1)
}
let state = box.snapshot()
check(runError.snapshot() == nil, "Ingest completes without error (\(runError.snapshot() ?? "none"))")
check(state.maxConcurrentCopies > 1, "copy callbacks overlapped")
check(state.events.count == 26, "received all 26 expected progress events (\(state.events.count))")
check(state.events.first?.total == 12 && state.events.first?.running == true && state.events.first?.copied == 0,
      "first event reports the total before planning")
check(state.events.filter { $0.done && !$0.running && $0.error == nil }.count == 1,
      "one terminal success event")
check(state.events.last?.done == true && state.events.last?.copied == 12,
      "terminal event arrives after callbacks drain")
check(state.events.filter { $0.copied > 0 && !$0.done }.map(\.copied).sorted() == Array(1...12),
      "copy progress snapshots form the exact 1...12 multiset")
let inbox = root.appendingPathComponent("inbox/2024-09-12")
for (name, expected) in originals {
    check((try? Data(contentsOf: inbox.appendingPathComponent(name))) == expected,
          "copied marker bytes preserved for \(name)")
}
let sum = LockedBox(0)
DispatchQueue.concurrentPerform(iterations: 2_000) { _ in sum.update { $0 += 1 } }
check(sum.snapshot() == 2_000, "LockedBox concurrent update/snapshot is race-safe")
print("CHECKS \(checks), FAILURES \(failures)")
exit(failures == 0 ? 0 : 1)

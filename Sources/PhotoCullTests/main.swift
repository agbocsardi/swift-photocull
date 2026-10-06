import Foundation

// PhotoCull test runner. Run: swift run PhotoCullTests
// Exit code 0 = all checks passed.
// Synthetic, no-Trash regression only: PhotoCullTests --finalize-safety-only

let allRunners: [(String, () throws -> Void)] = [
    ("Config", suiteConfig),
    ("FilePairs", suiteFilePairs),
    ("Session", suiteSession),
    ("Exif", suiteExif),
    ("Ingest", suiteIngest),
    ("Finalize", suiteFinalize),
    ("FinalizeSafety", suiteFinalizeSafety),
    ("FinalizeParallel", suiteFinalizeParallel),
    ("IngestConcurrent", suiteIngestConcurrent),
    ("ImagePipeline", suiteImagePipeline),
    ("Rotation", suiteRotation),
    ("Library", suiteLibrary),
    ("EndToEnd", suiteEndToEnd),
    ("PairRepair", suitePairRepair),
]

let args = Array(CommandLine.arguments.dropFirst())
let runners: [(String, () throws -> Void)]
if args.isEmpty {
    runners = allRunners
} else if args == ["--finalize-safety-only"] {
    runners = [("FinalizeSafety", suiteFinalizeSafety)]
} else if args.count == 2 && args[0] == "--suite" {
    guard let selected = allRunners.first(where: { $0.0 == args[1] }) else {
        fputs("Unknown suite: \(args[1])\n", stderr)
        exit(2)
    }
    runners = [selected]
} else {
    fputs("Usage: PhotoCullTests [--suite NAME | --finalize-safety-only]\n", stderr)
    exit(2)
}

print("Selected \(runners.count) suite(s): \(runners.map(\.0).joined(separator: ", "))")
for (name, fn) in runners {
    let before = pcChecks
    suite(name, fn)
    print("  suite checks: \(pcChecks - before)")
}

print("\n" + String(repeating: "─", count: 48))
if pcFailures.isEmpty {
    print("PASS — \(pcChecks) checks")
    exit(0)
} else {
    print("FAIL — \(pcFailures.count) of \(pcChecks) checks failed:")
    for f in pcFailures { print("  • \(f)") }
    exit(1)
}

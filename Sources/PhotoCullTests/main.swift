import Foundation

// PhotoCull test runner. Run: swift run PhotoCullTests
// Exit code 0 = all checks passed.
// Synthetic, no-Trash regression only: PhotoCullTests --finalize-safety-only

let runners: [(String, () throws -> Void)] = CommandLine.arguments.contains("--finalize-safety-only")
    ? [("FinalizeSafety", suiteFinalizeSafety)] : [
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

for (name, fn) in runners { suite(name, fn) }

print("\n" + String(repeating: "─", count: 48))
if pcFailures.isEmpty {
    print("PASS — \(pcChecks) checks")
    exit(0)
} else {
    print("FAIL — \(pcFailures.count) of \(pcChecks) checks failed:")
    for f in pcFailures { print("  • \(f)") }
    exit(1)
}

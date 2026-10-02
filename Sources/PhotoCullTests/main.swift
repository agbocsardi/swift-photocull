import Foundation

// PhotoCull test runner. Run: swift run PhotoCullTests
// Exit code 0 = all checks passed.

let runners: [(String, () throws -> Void)] = [
    ("Config", suiteConfig),
    ("FilePairs", suiteFilePairs),
    ("Session", suiteSession),
    ("Exif", suiteExif),
    ("Ingest", suiteIngest),
    ("Finalize", suiteFinalize),
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

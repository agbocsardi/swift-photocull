import Foundation
import PhotoCullCore

func suiteSession() throws {
    let dir = try makeTempDir("session")

    // ── decode the exact Go sample string ──
    let goSample = #"{"version":1,"decisions":{"DSCF1234":"keep","P1000567":"reject"},"last_index":12}"#
    let sampleURL = dir.appendingPathComponent("sample")
    try FileManager.default.createDirectory(at: sampleURL, withIntermediateDirectories: true)
    try Data(goSample.utf8).write(to: sampleURL.appendingPathComponent(Session.fileName))
    let decoded = try Session.load(folder: sampleURL)
    checkEqual(decoded.version, 1, "sample version")
    checkEqual(decoded.get("DSCF1234"), Decision.keep, "sample keep decision")
    checkEqual(decoded.get("P1000567"), Decision.reject, "sample reject decision")
    checkEqual(decoded.get("OTHER"), Decision.undecided, "absent stem → undecided")
    checkEqual(decoded.lastIndex, 12, "sample last_index")

    // ── re-encode byte-compat with Go's MarshalIndent ──
    let expected = """
    {
      "version": 1,
      "decisions": {
        "DSCF1234": "keep",
        "P1000567": "reject"
      },
      "last_index": 12
    }
    """
    let roundtripURL = try makeTempDir("session-save")
    try decoded.save(folder: roundtripURL)
    let savedText = try String(contentsOf: roundtripURL.appendingPathComponent(Session.fileName), encoding: .utf8)
    checkEqual(savedText, expected, "save byte-matches Go MarshalIndent output")

    let reloaded = try Session.load(folder: roundtripURL)
    checkEqual(reloaded.version, decoded.version, "round-trip version")
    checkEqual(reloaded.get("DSCF1234"), Decision.keep, "round-trip decision")
    checkEqual(reloaded.lastIndex, decoded.lastIndex, "round-trip last index")

    // ── decisions keys sorted in output ──
    let sortedSession = Session(version: 1, decisions: ["Z": .keep, "A": .reject, "M": .undecided],
                                lastIndex: 0, crops: [:])
    try sortedSession.save(folder: roundtripURL)
    let sortedText = try String(contentsOf: roundtripURL.appendingPathComponent(Session.fileName), encoding: .utf8)
    check(sortedText.contains("\"A\": \"reject\",\n    \"M\": \"undecided\",\n    \"Z\": \"keep\""),
          "decision keys sorted")
    checkEqual(sortedSession.get("m"), Decision.undecided, "get uppercases lookup")
    checkEqual(sortedSession.get("M"), Decision.undecided, "explicit undecided round-trips")
    check(sortedSession.decisions.keys.allSatisfy { $0 == $0.uppercased() }, "stored keys uppercased")

    // ── crops omitted when empty, included when set ──
    check(!savedText.contains("crops"), "crops omitted when empty")
    let cropSession = Session(version: 1, decisions: ["DSCF1234": .keep], lastIndex: 3, crops: [:])
    cropSession.setCrop("dscf1234", CropRect(x: 0.1, y: 0, w: 0.9, h: 1))
    try cropSession.save(folder: roundtripURL)
    let cropText = try String(contentsOf: roundtripURL.appendingPathComponent(Session.fileName), encoding: .utf8)
    check(cropText.contains("\"crops\""), "crops included when non-empty")
    check(cropText.contains("\"x\": 0.1"), "crop x serialized as number")
    let cropReloaded = try Session.load(folder: roundtripURL)
    checkEqual(cropReloaded.crop(for: "DSCF1234"), CropRect(x: 0.1, y: 0, w: 0.9, h: 1), "crop round-trips")
    cropReloaded.setCrop("DSCF1234", nil)
    check(cropReloaded.crop(for: "DSCF1234") == nil, "setCrop nil removes")
    try cropReloaded.save(folder: roundtripURL)
    let noCropText = try String(contentsOf: roundtripURL.appendingPathComponent(Session.fileName), encoding: .utf8)
    check(!noCropText.contains("crops"), "crops omitted again after removal")

    // ── missing file → fresh ──
    let emptyURL = try makeTempDir("session-missing")
    let fresh = try Session.load(folder: emptyURL)
    checkEqual(fresh.version, 1, "missing file → version 1")
    checkEqual(fresh.lastIndex, 0, "missing file → lastIndex 0")
    check(fresh.decisions.isEmpty, "missing file → no decisions")

    // ── corrupt JSON → fresh, no crash, no throw ──
    let corruptURL = try makeTempDir("session-corrupt")
    try Data("{not json".utf8).write(to: corruptURL.appendingPathComponent(Session.fileName))
    let fromCorrupt = try Session.load(folder: corruptURL)
    checkEqual(fromCorrupt.version, 1, "corrupt JSON → fresh session")

    // ── statusCounts ──
    let sc = Session.fresh()
    sc.set("A", .keep)
    sc.set("B", .reject)
    let counts = sc.statusCounts(stems: ["A", "B", "C"])
    checkEqual(counts.keep, 1, "statusCounts keep")
    checkEqual(counts.reject, 1, "statusCounts reject")
    checkEqual(counts.undecided, 1, "statusCounts undecided")

    // ── folderStatus: all four states ──
    let st = Session.fresh()
    let stems = ["A", "B", "C"]
    checkEqual(st.folderStatus(stems: []), FolderStatus.empty, "no stems → empty")
    checkEqual(st.folderStatus(stems: stems), FolderStatus.unstarted, "no decisions → unstarted")
    checkEqual(st.folderStatus(stems: stems).rawValue, "unstarted", "unstarted rawValue")
    st.set("A", .keep)
    checkEqual(st.folderStatus(stems: stems), FolderStatus.inProgress, "some decisions → in progress")
    checkEqual(st.folderStatus(stems: stems).rawValue, "in progress", "in-progress rawValue")
    st.set("B", .reject)
    st.set("C", .undecided)
    checkEqual(st.folderStatus(stems: stems), FolderStatus.complete, "all present → complete")
    checkEqual(st.folderStatus(stems: ["X"]), FolderStatus.unstarted, "single unseen stem → unstarted")

    // ── CropRect ──
    check(CropRect.full.isFullFrame, "full rect is full frame")
    check(CropRect(x: 0.004, y: 0, w: 0.996, h: 1).isFullFrame, "within tolerance → full frame")
    check(!CropRect(x: 0.01, y: 0, w: 1, h: 1).isFullFrame, "x beyond tolerance → not full")
    check(!CropRect(x: 0, y: 0, w: 1, h: 0.9).isFullFrame, "short height → not full")
    let clamped = CropRect(x: 1.2, y: -0.5, w: 2, h: 0.01).clamped(minSize: 0.1)
    check(clamped.x >= 0 && clamped.y >= 0 && clamped.x + clamped.w <= 1 && clamped.y + clamped.h <= 1,
          "clamped rect stays in frame")
    check(clamped.w >= 0.1 && clamped.h >= 0.1, "clamped rect respects minSize")
    let inside = CropRect(x: 0.2, y: 0.3, w: 0.4, h: 0.2).clamped(minSize: 0.05)
    checkEqual(inside, CropRect(x: 0.2, y: 0.3, w: 0.4, h: 0.2), "valid rect unchanged by clamp")
    checkClose(CropRect(x: 0, y: 0, w: 2, h: 0.5).aspect, 4.0, 0.001, "aspect = w/h")
}

import Foundation
import PhotoCullCore

func suiteLibrary() throws {
    let home = NSHomeDirectory()
    let root = try makeTempDir("library")
    let inbox = root.appendingPathComponent("inbox")
    let cfg = PCConfig(paths: PathsConfig(inbox: inbox.path,
                                          archive: root.appendingPathComponent("archive").path,
                                          dump: root.appendingPathComponent("dump").path),
                       files: FilesConfig(rawExtensions: ["RAF"], jpgExtensions: ["JPG"]))
    checkEqual(Library.inboxFolder(cfg: cfg, date: "2025-01-01").path,
               inbox.appendingPathComponent("2025-01-01").path, "inboxFolder joins date")
    checkEqual(Library.inboxFolder(cfg: cfg, date: "").path, inbox.path, "inboxFolder empty date → inbox")

    // ── missing inbox → [] ──
    checkEqual(Library.loadSessions(cfg: cfg), [], "missing inbox → empty list")

    // ── three folders + a stray file ──
    for date in ["2025-01-01", "2025-03-10", "2024-12-31"] {
        try FileManager.default.createDirectory(at: inbox.appendingPathComponent(date),
                                                withIntermediateDirectories: true)
    }
    try touch(inbox.appendingPathComponent("notafolder.txt"))

    let f1 = inbox.appendingPathComponent("2025-01-01")
    try touch(f1.appendingPathComponent("A.JPG"))
    try touch(f1.appendingPathComponent("B.JPG"))
    try touch(f1.appendingPathComponent("B.RAF"))
    try touch(f1.appendingPathComponent("C.JPG"))
    let s1 = Session.fresh()
    s1.set("A", .keep)
    s1.set("B", .reject)
    s1.setCrop("B", CropRect(x: 0.1, y: 0.1, w: 0.5, h: 0.5))
    s1.setCrop("C", CropRect(x: 0, y: 0, w: 0.8, h: 0.8))
    try s1.save(folder: f1)

    // 2025-03-10: untouched folder with one file → unstarted
    try touch(inbox.appendingPathComponent("2025-03-10").appendingPathComponent("X.JPG"))

    // 2024-12-31: no files at all → empty
    let rows = Library.loadSessions(cfg: cfg)

    // Newest first (descending string compare)
    checkEqual(rows.map { $0.date }, ["2025-03-10", "2025-01-01", "2024-12-31"], "sessions newest first")

    // Rollups for the decided folder
    let decided = rows.first { $0.date == "2025-01-01" }!
    checkEqual(decided.total, 3, "row total counts pairs")
    checkEqual(decided.keep, 1, "row keep count")
    checkEqual(decided.reject, 1, "row reject count")
    checkEqual(decided.undecided, 1, "row undecided count")
    checkEqual(decided.status, FolderStatus.inProgress, "row status in progress")
    checkEqual(decided.cropped, 2, "cropped counts stems with crop")
    checkClose(decided.progress, 2.0 / 3.0, 0.001, "progress = (keep+reject)/total")

    let unstarted = rows.first { $0.date == "2025-03-10" }!
    checkEqual(unstarted.status, FolderStatus.unstarted, "no decisions → unstarted row")
    checkEqual(unstarted.total, 1, "unstarted total")
    checkEqual(unstarted.cropped, 0, "no crops → cropped 0")
    checkClose(unstarted.progress, 0.0, 0.001, "unstarted progress 0")

    let empty = rows.first { $0.date == "2024-12-31" }!
    checkEqual(empty.status, FolderStatus.empty, "no files → empty row")
    checkClose(empty.progress, 0.0, 0.001, "empty progress 0")

    // ── Library.pairs mirrors FilePairs.pairs ──
    let pairs = try Library.pairs(cfg: cfg, date: "2025-01-01")
    checkEqual(FilePairs.stems(pairs), ["A", "B", "C"], "Library.pairs sorted stems")
    checkEqual(pairs[1].raw?.lastPathComponent, "B.RAF", "Library.pairs keeps RAW")
    check(pairs[0].raw == nil, "Library.pairs jpg-only")

    // ── corrupt session file behaves like fresh ──
    let corruptFolder = inbox.appendingPathComponent("2025-03-10")
    try Data("garbage{".utf8).write(to: corruptFolder.appendingPathComponent(Session.fileName))
    let rowsAfterCorrupt = Library.loadSessions(cfg: cfg)
    let corruptRow = rowsAfterCorrupt.first { $0.date == "2025-03-10" }!
    checkEqual(corruptRow.status, FolderStatus.unstarted, "corrupt session → treated as unstarted")

    _ = home // keep home referenced for ~ checks in config suite only
}

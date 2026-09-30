import Foundation
import PhotoCullCore

func suiteConfig() throws {
    let home = NSHomeDirectory()

    // ── TOML parse of the real default file shape ──
    let defaultTOML = """
    [paths]
      inbox = "~/Pictures/PhotoCull/inbox"
      archive = "~/Pictures/PhotoCull/archive"
      dump = "~/Downloads"

    [files]
      raw_extensions = ["RAF", "RW2"]
      jpg_extensions = ["JPG", "JPEG"]
    """
    let parsed = TOMLParser.parse(defaultTOML)
    checkEqual(parsed["paths"]?["inbox"], TOMLValue.string("~/Pictures/PhotoCull/inbox"), "parse default inbox")
    checkEqual(parsed["paths"]?["dump"], TOMLValue.string("~/Downloads"), "parse default dump")
    checkEqual(parsed["files"]?["raw_extensions"], TOMLValue.array(["RAF", "RW2"]), "parse default raw exts")
    checkEqual(parsed["files"]?["jpg_extensions"], TOMLValue.array(["JPG", "JPEG"]), "parse default jpg exts")

    // ── parser features: comments, blank lines, trailing comments, top-level keys ──
    let messy = """
    # leading comment

    top = "yes"   # trailing comment
    [paths]
    inbox = "/tmp/in" # note
    archive="/tmp/arch"
    empty_val = ""
    arr = [ "A" , "B" ,]  # spaced array
    """
    let messyParsed = TOMLParser.parse(messy)
    checkEqual(messyParsed[""]?["top"], TOMLValue.string("yes"), "top-level key under \"\" section")
    checkEqual(messyParsed["paths"]?["inbox"], TOMLValue.string("/tmp/in"), "trailing comment stripped")
    checkEqual(messyParsed["paths"]?["archive"], TOMLValue.string("/tmp/arch"), "no-space `=` handled")
    checkEqual(messyParsed["paths"]?["empty_val"], TOMLValue.string(""), "empty string value")
    checkEqual(messyParsed["paths"]?["arr"], TOMLValue.array(["A", "B"]), "spaced array parsed")

    // ── round-trip toTOML → parse ──
    let cfg = PCConfig.defaultConfig()
    let roundTrip = TOMLParser.parse(cfg.toTOML())
    checkEqual(roundTrip["paths"]?["inbox"], TOMLValue.string("~/Pictures/PhotoCull/inbox"), "round-trip inbox")
    checkEqual(roundTrip["paths"]?["archive"], TOMLValue.string("~/Pictures/PhotoCull/archive"), "round-trip archive")
    checkEqual(roundTrip["paths"]?["dump"], TOMLValue.string("~/Downloads"), "round-trip dump")
    checkEqual(roundTrip["files"]?["raw_extensions"], TOMLValue.array(["RAF", "RW2"]), "round-trip raw exts")
    checkEqual(roundTrip["files"]?["jpg_extensions"], TOMLValue.array(["JPG", "JPEG"]), "round-trip jpg exts")

    // ── toTOML matches Go's BurntSushi marshal byte-for-byte ──
    let goOutput = """
    [paths]
      inbox = "~/Pictures/PhotoCull/inbox"
      archive = "~/Pictures/PhotoCull/archive"
      dump = "~/Downloads"

    [files]
      raw_extensions = ["RAF", "RW2"]
      jpg_extensions = ["JPG", "JPEG"]
    """
    checkEqual(cfg.toTOML(), goOutput + "\n", "toTOML matches Go marshal exactly")

    // ── ~ expansion ──
    checkEqual(PCConfig.expandHome("~/Pictures/x"), home + "/Pictures/x", "expandHome expands ~/")
    checkEqual(PCConfig.expandHome("/absolute/path"), "/absolute/path", "expandHome leaves absolute paths")
    checkEqual(PCConfig.expandHome("relative"), "relative", "expandHome leaves relative paths")
    checkEqual(PCConfig.expandHome("~notilda"), "~notilda", "expandHome ignores bare ~")

    // ── ext sets are uppercased ──
    let setCfg = PCConfig(paths: PathsConfig(inbox: "/i", archive: "/a", dump: "/d"),
                          files: FilesConfig(rawExtensions: ["raf", "Rw2"], jpgExtensions: ["jpg"]))
    checkEqual(setCfg.rawExtSet, Set(["RAF", "RW2"]), "rawExtSet uppercased")
    checkEqual(setCfg.jpgExtSet, Set(["JPG"]), "jpgExtSet uppercased")

    // ── load(from:): custom file, values picked up and ~ expanded ──
    let dir = try makeTempDir("config")
    let cfgURL = dir.appendingPathComponent("config.toml")
    try """
    [paths]
      inbox = "~/myinbox"
      archive = "~/myarchive"
      dump = "~/mydump"

    [files]
      raw_extensions = ["ORF"]
      jpg_extensions = ["JPG"]
    """.write(to: cfgURL, atomically: true, encoding: .utf8)
    let loaded = PCConfig.load(from: cfgURL)
    checkEqual(loaded.paths.inbox, home + "/myinbox", "load expands ~ inbox")
    checkEqual(loaded.paths.archive, home + "/myarchive", "load expands ~ archive")
    checkEqual(loaded.paths.dump, home + "/mydump", "load expands ~ dump")
    checkEqual(loaded.files.rawExtensions, ["ORF"], "load picks up raw extensions")
    checkEqual(loaded.files.jpgExtensions, ["JPG"], "load picks up jpg extensions")

    // ── load(from:): missing file → defaults written to disk ──
    let missingURL = dir.appendingPathComponent("sub").appendingPathComponent("config.toml")
    let loadedMissing = PCConfig.load(from: missingURL)
    checkEqual(loadedMissing, PCConfig.defaultConfig().expandedForTest, "missing file → expanded defaults")
    check(FileManager.default.fileExists(atPath: missingURL.path), "default file created on first load")
    let reread = TOMLParser.parse(try String(contentsOf: missingURL, encoding: .utf8))
    checkEqual(reread["paths"]?["inbox"], TOMLValue.string("~/Pictures/PhotoCull/inbox"),
               "written default file parses back to default inbox")

    // ── load(from:): corrupt file → defaults, no crash ──
    let corruptURL = dir.appendingPathComponent("corrupt.toml")
    try "this is [not toml at all ===".write(to: corruptURL, atomically: true, encoding: .utf8)
    checkEqual(PCConfig.load(from: corruptURL), PCConfig.defaultConfig().expandedForTest,
               "corrupt file → defaults")

    // ── configPath points at ~/.config/photocull/config.toml ──
    checkEqual(PCConfig.configPath, home + "/.config/photocull/config.toml", "configPath shape")
}

extension PCConfig {
    /// Default config with `~/` expanded — handy for comparisons in tests.
    var expandedForTest: PCConfig {
        var c = self
        c.paths.inbox = PCConfig.expandHome(c.paths.inbox)
        c.paths.archive = PCConfig.expandHome(c.paths.archive)
        c.paths.dump = PCConfig.expandHome(c.paths.dump)
        return c
    }
}

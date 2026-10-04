import Foundation
import Darwin

// Config.swift — reads/writes ~/.config/photocull/config.toml
// Byte-compatible with the Go implementation's config format.

public struct PathsConfig: Codable, Sendable, Equatable {
    public var inbox: String
    public var archive: String
    public var dump: String
    public init(inbox: String, archive: String, dump: String) {
        self.inbox = inbox; self.archive = archive; self.dump = dump
    }
}

public struct FilesConfig: Codable, Sendable, Equatable {
    public var rawExtensions: [String]
    public var jpgExtensions: [String]
    public init(rawExtensions: [String], jpgExtensions: [String]) {
        self.rawExtensions = rawExtensions; self.jpgExtensions = jpgExtensions
    }
}

public struct PCConfig: Codable, Sendable, Equatable {
    public var paths: PathsConfig
    public var files: FilesConfig
    public init(paths: PathsConfig, files: FilesConfig) { self.paths = paths; self.files = files }

    /// Defaults identical to Go `DefaultConfig()`.
    public static func defaultConfig() -> PCConfig {
        PCConfig(
            paths: PathsConfig(inbox: "~/Pictures/PhotoCull/inbox",
                               archive: "~/Pictures/PhotoCull/archive",
                               dump: "~/Downloads"),
            files: FilesConfig(rawExtensions: ["RAF", "RW2"], jpgExtensions: ["JPG", "JPEG"]))
    }

    /// Absolute path of the config file: `~/.config/photocull/config.toml`.
    public static var configPath: String {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config")
            .appendingPathComponent("photocull")
            .appendingPathComponent("config.toml").path
    }

    /// Load config, creating the default file when missing. `~/` is expanded.
    public static func load() -> PCConfig {
        load(from: URL(fileURLWithPath: configPath))
    }

    /// Load config from an explicit file path (testable variant of `load()`).
    /// Missing file → write defaults there, then use defaults.
    /// Unreadable file or parse failure → fall back to defaults. Never fatal.
    public static func load(from url: URL) -> PCConfig {
        var cfg = PCConfig.defaultConfig()

        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            applyTOML(TOMLParser.parse(text), into: &cfg)
        } else {
            // Missing or unreadable: best-effort write of the default file.
            try? writeDefaultConfig(cfg, to: url)
        }

        cfg.paths.inbox = expandHome(cfg.paths.inbox)
        cfg.paths.archive = expandHome(cfg.paths.archive)
        cfg.paths.dump = expandHome(cfg.paths.dump)
        return cfg
    }

    /// Strict, read-only loader for generated disposable fixtures, never normal config/defaults.
    public static func loadFixture(from path: String) throws -> PCConfig {
        func reject(_ message: String) -> Error {
            NSError(domain: "PhotoCull.Fixture", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message])
        }
        func inspect(_ path: String, directory: Bool) throws -> stat {
            var st = stat()
            guard lstat(path, &st) == 0, st.st_uid == getuid(),
                  st.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
                  st.st_mode & 0o444 != 0,
                  directory || st.st_nlink == 1 else { throw reject("Not a readable owned non-symlink fixture item: \(path)") }
            return st
        }
        let components = path.split(separator: "/").map(String.init)
        guard path.hasPrefix("/private/tmp/"), !path.utf8.contains(0), components.count == 5,
              path == "/" + components.joined(separator: "/"), !components.contains("."), !components.contains("..") else {
            throw reject("Fixture config must have an absolute canonical generated-root/config/config.toml spelling")
        }
        let url = URL(fileURLWithPath: path), root = url.deletingLastPathComponent().deletingLastPathComponent()
        guard url.lastPathComponent == "config.toml", url.deletingLastPathComponent().lastPathComponent == "config",
              root.lastPathComponent.hasPrefix("photocull-manual-fixture-") || root.lastPathComponent.hasPrefix("photocull-manual-launch-") else {
            throw reject("Expected generated fixture root/config/config.toml")
        }
        // Inspect each ancestor BEFORE realpath/open so a bad link cannot lead into user data.
        for ancestor in ["/private", "/private/tmp"] {
            var st = stat()
            guard lstat(ancestor, &st) == 0, st.st_mode & S_IFMT == S_IFDIR else { throw reject("Fixture ancestor is not a real directory") }
        }
        let rootInfo = try inspect(root.path, directory: true)
        guard rootInfo.st_mode & 0o077 == 0 else { throw reject("Fixture root must be private to its owner") }
        _ = try inspect(url.deletingLastPathComponent().path, directory: true)
        let before = try inspect(path, directory: false)
        guard let resolved = realpath(path, nil) else { throw reject("Cannot resolve fixture config") }
        defer { free(resolved) }
        guard path == String(cString: resolved) else { throw reject("Fixture config path is not canonical") }
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw reject("Cannot read fixture config") }
        defer { close(fd) }
        var pinned = stat()
        guard fstat(fd, &pinned) == 0, pinned.st_dev == before.st_dev, pinned.st_ino == before.st_ino else {
            throw reject("Fixture config replaced while opening")
        }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 { if errno == EINTR { continue }; throw reject("Cannot read fixture config") }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= 16_384 else { throw reject("Fixture config is too large") }
        }
        guard let text = String(data: data, encoding: .utf8) else { throw reject("Fixture config is not UTF-8") }
        let parsed = TOMLParser.parse(text)
        guard case .string(let inbox)? = parsed["paths"]?["inbox"],
              case .string(let archive)? = parsed["paths"]?["archive"],
              case .string(let dump)? = parsed["paths"]?["dump"],
              case .array(let raw)? = parsed["files"]?["raw_extensions"],
              case .array(let jpg)? = parsed["files"]?["jpg_extensions"] else {
            throw reject("Incomplete fixture config")
        }
        let cfg = PCConfig(paths: PathsConfig(inbox: inbox, archive: archive, dump: dump),
                           files: FilesConfig(rawExtensions: raw, jpgExtensions: jpg))
        // ponytail: generated-only TOML ceiling; ordinary config parsing remains permissive/unchanged.
        guard text == cfg.toTOML(), raw == ["RAF", "RW2"], jpg == ["JPG", "JPEG"],
              inbox == root.appendingPathComponent("inbox").path,
              archive == root.appendingPathComponent("archive").path,
              dump == root.appendingPathComponent("export").path else {
            throw reject("Fixture config must exactly match the generated TOML and contained inbox/archive/export paths")
        }
        for path in [inbox, archive, dump] {
            _ = try inspect(path, directory: true)
            var enumerationError: Error?
            guard let entries = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil,
                errorHandler: { _, error in enumerationError = error; return false }) else { throw reject("Cannot enumerate fixture data") }
            for case let item as URL in entries {
                var st = stat()
                guard lstat(item.path, &st) == 0, item.path.hasPrefix(path + "/"),
                      st.st_mode & S_IFMT == S_IFDIR || st.st_mode & S_IFMT == S_IFREG else {
                    throw reject("Symlink/special item in fixture: \(item.path)")
                }
                _ = try inspect(item.path, directory: st.st_mode & S_IFMT == S_IFDIR)
            }
            if let error = enumerationError { throw error }
        }
        var after = stat()
        let visible = try inspect(path, directory: false)
        guard fstat(fd, &after) == 0, after.st_dev == before.st_dev, after.st_ino == before.st_ino,
              after.st_size == before.st_size, after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
              after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec,
              visible.st_dev == before.st_dev, visible.st_ino == before.st_ino else { throw reject("Fixture config changed during validation") }
        return cfg
    }

    /// Overlay parsed TOML values onto `cfg` (only known keys, only matching shapes).
    static func applyTOML(_ parsed: [String: [String: TOMLValue]], into cfg: inout PCConfig) {
        if let section = parsed["paths"] {
            if case .string(let v)? = section["inbox"] { cfg.paths.inbox = v }
            if case .string(let v)? = section["archive"] { cfg.paths.archive = v }
            if case .string(let v)? = section["dump"] { cfg.paths.dump = v }
        }
        if let section = parsed["files"] {
            if case .array(let v)? = section["raw_extensions"], !v.isEmpty { cfg.files.rawExtensions = v }
            if case .array(let v)? = section["jpg_extensions"], !v.isEmpty { cfg.files.jpgExtensions = v }
        }
    }

    /// Write the default config file, creating parent directories as needed.
    static func writeDefaultConfig(_ cfg: PCConfig, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try cfg.toTOML().data(using: .utf8)?.write(to: url)
    }

    /// Uppercased JPG extension set.
    public var jpgExtSet: Set<String> { Set(files.jpgExtensions.map { $0.uppercased() }) }
    /// Uppercased RAW extension set.
    public var rawExtSet: Set<String> { Set(files.rawExtensions.map { $0.uppercased() }) }

    /// Expand a leading `~/` to the user's home directory.
    public static func expandHome(_ path: String) -> String {
        guard path.hasPrefix("~/") else { return path }
        return NSHomeDirectory() + "/" + path.dropFirst(2)
    }

    /// Serialize back to TOML in the same shape Go's toml.Marshal produces:
    /// `[section]` header, 2-space indented `key = value` lines, blank line
    /// between sections, trailing newline.
    public func toTOML() -> String {
        func quoted(_ s: String) -> String { "\"\(s)\"" }
        func array(_ a: [String]) -> String { "[" + a.map(quoted).joined(separator: ", ") + "]" }
        var out = ""
        out += "[paths]\n"
        out += "  inbox = \(quoted(paths.inbox))\n"
        out += "  archive = \(quoted(paths.archive))\n"
        out += "  dump = \(quoted(paths.dump))\n"
        out += "\n[files]\n"
        out += "  raw_extensions = \(array(files.rawExtensions))\n"
        out += "  jpg_extensions = \(array(files.jpgExtensions))\n"
        return out
    }
}

public enum TOMLValue: Sendable, Equatable {
    case string(String)
    case array([String])
}

/// Minimal TOML reader for the shapes used by photocull configs:
/// `[section]` headers, `key = "string"`, `key = ["a", "b"]`, `#` comments.
public enum TOMLParser {
    /// Parse `text` into `[section: [key: value]]`. Keys outside any section
    /// are stored under the `""` section.
    public static func parse(_ text: String) -> [String: [String: TOMLValue]] {
        var result: [String: [String: TOMLValue]] = ["": [:]]
        var section = ""

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("[") {
                guard let end = line.firstIndex(of: "]") else { continue }
                let name = String(line[line.index(after: line.startIndex)..<end])
                    .trimmingCharacters(in: .whitespaces)
                section = name
                if result[section] == nil { result[section] = [:] }
                continue
            }

            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            value = stripTrailingComment(value)

            if value.hasPrefix("\"") {
                if let str = parseQuoted(value) {
                    result[section]?[key] = .string(str)
                }
            } else if value.hasPrefix("[") {
                let items = splitArrayItems(value).compactMap { parseQuoted($0) }
                result[section]?[key] = .array(items)
            }
        }
        return result
    }

    /// Cut a trailing `# comment` that sits outside of any quoted string.
    static func stripTrailingComment(_ value: String) -> String {
        var inQuote = false
        var escaped = false
        for (i, ch) in value.enumerated() {
            if escaped { escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == "\"" { inQuote.toggle(); continue }
            if ch == "#" && !inQuote {
                return String(value.prefix(i)).trimmingCharacters(in: .whitespaces)
            }
        }
        return value
    }

    /// Given a value starting with `"`, return the unescaped string content.
    static func parseQuoted(_ value: String) -> String? {
        guard let first = value.first, first == "\"" else { return nil }
        var out = ""
        var escaped = false
        var idx = value.index(after: value.startIndex)
        while idx < value.endIndex {
            let ch = value[idx]
            if escaped {
                switch ch {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                default: out.append(ch)
                }
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "\"" {
                return out
            } else {
                out.append(ch)
            }
            idx = value.index(after: idx)
        }
        return nil // unterminated string
    }

    /// Split `[ "a", "b" ]` contents into raw item strings.
    static func splitArrayItems(_ value: String) -> [String] {
        var inner = value
        if inner.hasPrefix("[") { inner.removeFirst() }
        if inner.hasSuffix("]") { inner.removeLast() }
        return inner.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }
}

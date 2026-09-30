import Foundation

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
        fatalError("TODO: Config.configPath")
    }

    /// Load config, creating the default file when missing. `~/` is expanded.
    public static func load() -> PCConfig {
        fatalError("TODO: Config.load")
    }

    /// Uppercased JPG extension set.
    public var jpgExtSet: Set<String> { fatalError("TODO: Config.jpgExtSet") }
    /// Uppercased RAW extension set.
    public var rawExtSet: Set<String> { fatalError("TODO: Config.rawExtSet") }

    /// Expand a leading `~/` to the user's home directory.
    public static func expandHome(_ path: String) -> String {
        fatalError("TODO: Config.expandHome")
    }

    /// Serialize back to TOML in the same shape Go's toml.Marshal produces.
    public func toTOML() -> String { fatalError("TODO: Config.toTOML") }
}

public enum TOMLValue: Sendable, Equatable {
    case string(String)
    case array([String])
}

/// Minimal TOML reader for the shapes used by photocull configs:
/// `[section]` headers, `key = "string"`, `key = ["a", "b"]`, `#` comments.
public enum TOMLParser {
    /// Parse `text` into `[section: [key: value]]`.
    public static func parse(_ text: String) -> [String: [String: TOMLValue]] {
        fatalError("TODO: TOMLParser.parse")
    }
}

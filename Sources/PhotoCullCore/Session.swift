import Foundation

// Session.swift — read/write `.photocull.json` sidecar.
// JSON round-trips with the Go implementation:
//   {"version":1,"decisions":{"DSCF1234":"keep"},"last_index":12}
// `crops` is an additive key the Go app ignores.

public enum Decision: String, Codable, Sendable, CaseIterable {
    case keep, reject, undecided
}

/// Normalized crop rectangle in *oriented display space*, origin top-left.
/// Values are 0...1 fractions of the oriented image's width/height.
public struct CropRect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    /// Full-frame crop (0, 0, 1, 1).
    public static let full = CropRect(x: 0, y: 0, w: 1, h: 1)

    /// True when this rect covers the whole frame (within 0.5% tolerance).
    public var isFullFrame: Bool { fatalError("TODO: CropRect.isFullFrame") }

    /// Clamp into 0...1 and enforce a minimum size on each axis.
    public func clamped(minSize: Double) -> CropRect { fatalError("TODO: CropRect.clamped") }

    /// Aspect ratio w/h in oriented space.
    public var aspect: Double { fatalError("TODO: CropRect.aspect") }
}

public enum FolderStatus: String, Sendable {
    case empty
    case unstarted
    case inProgress = "in progress"
    case complete
}

public final class Session {
    public static let fileName = ".photocull.json"

    public var version: Int
    /// Keys are UPPERCASED stems.
    public var decisions: [String: Decision]
    public var lastIndex: Int
    /// Keys are UPPERCASED stems. Empty when nothing is cropped.
    public var crops: [String: CropRect]

    public init(version: Int, decisions: [String: Decision], lastIndex: Int, crops: [String: CropRect]) {
        self.version = version; self.decisions = decisions
        self.lastIndex = lastIndex; self.crops = crops
    }

    /// Fresh empty session (version 1, no decisions, lastIndex 0).
    public static func fresh() -> Session { fatalError("TODO: Session.fresh") }

    /// Load from `folder/.photocull.json`; returns a fresh session when absent.
    public static func load(folder: URL) throws -> Session { fatalError("TODO: Session.load") }

    /// Write to `folder/.photocull.json` with sorted keys and 2-space indent.
    public func save(folder: URL) throws { fatalError("TODO: Session.save") }

    public func get(_ stem: String) -> Decision { fatalError("TODO: Session.get") }
    public func set(_ stem: String, _ decision: Decision) { fatalError("TODO: Session.set") }
    public func crop(for stem: String) -> CropRect? { fatalError("TODO: Session.crop") }
    public func setCrop(_ stem: String, _ rect: CropRect?) { fatalError("TODO: Session.setCrop") }

    /// (keep, reject, undecided) counts over the given stems.
    public func statusCounts(stems: [String]) -> (keep: Int, reject: Int, undecided: Int) {
        fatalError("TODO: Session.statusCounts")
    }

    /// Folder-level rollup used by the sessions list.
    public func folderStatus(stems: [String]) -> FolderStatus { fatalError("TODO: Session.folderStatus") }
}

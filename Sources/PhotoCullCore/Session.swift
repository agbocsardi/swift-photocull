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
    public var isFullFrame: Bool {
        let tol = 0.005
        return abs(x) <= tol && abs(y) <= tol && abs(w - 1) <= tol && abs(h - 1) <= tol
    }

    /// Clamp into 0...1 and enforce a minimum size on each axis, keeping the
    /// rect inside the frame.
    public func clamped(minSize: Double) -> CropRect {
        var w = min(max(self.w, minSize), 1)
        var h = min(max(self.h, minSize), 1)
        var x = min(max(self.x, 0), 1 - w)
        var y = min(max(self.y, 0), 1 - h)
        x = max(x, 0); y = max(y, 0)
        if w.isNaN { w = minSize }; if h.isNaN { h = minSize }
        return CropRect(x: x, y: y, w: w, h: h)
    }

    /// Aspect ratio w/h in oriented space.
    public var aspect: Double { h == 0 ? 0 : w / h }
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
    /// Fine straightening angle per stem, in degrees. Positive tilts the photo
    /// clockwise on screen. Empty when nothing is tilted.
    public var tilts: [String: Double]
    /// Quarter turns per stem (1 = 90° clockwise on screen). Empty when none.
    public var rotations: [String: Int]

    public init(version: Int, decisions: [String: Decision], lastIndex: Int, crops: [String: CropRect],
                tilts: [String: Double] = [:], rotations: [String: Int] = [:]) {
        self.version = version; self.decisions = decisions
        self.lastIndex = lastIndex; self.crops = crops
        self.tilts = tilts; self.rotations = rotations
    }

    /// Fresh empty session (version 1, no decisions, lastIndex 0).
    public static func fresh() -> Session {
        Session(version: 1, decisions: [:], lastIndex: 0, crops: [:])
    }

    /// Load from `folder/.photocull.json`; returns a fresh session when absent.
    /// A corrupt file also yields a fresh session; only I/O errors throw.
    public static func load(folder: URL, strict: Bool = false) throws -> Session {
        let url = folder.appendingPathComponent(Session.fileName)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // Missing file → fresh (Go: os.IsNotExist → newSession()).
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError {
                return Session.fresh()
            }
            if ns.domain == NSPOSIXErrorDomain && ns.code == ENOENT {
                return Session.fresh()
            }
            throw error
        }

        return try decode(data: data, strict: strict)
    }

    /// Destructive callers decode the exact bytes captured from their pinned input.
    package static func decode(data: Data, strict: Bool) throws -> Session {
        guard !data.isEmpty else {
            if strict { throw SidecarError.invalid("empty sidecar") }
            return Session.fresh()
        }

        struct RawShape: Decodable {
            var version: Int?
            var decisions: [String: Decision]?
            var last_index: Int?
            var crops: [String: CropRect]?
            var tilts: [String: Double]?
            var rotations: [String: Int]?
        }
        guard let raw = try? JSONDecoder().decode(RawShape.self, from: data) else {
            if strict { throw SidecarError.invalid("malformed sidecar") }
            return Session.fresh() // corrupt JSON must not crash
        }
        if strict, raw.version != 1 {
            throw SidecarError.invalid("unsupported sidecar version \(raw.version.map(String.init) ?? "missing")")
        }
        if strict {
            for keys in [Array((raw.decisions ?? [:]).keys), Array((raw.crops ?? [:]).keys),
                         Array((raw.tilts ?? [:]).keys), Array((raw.rotations ?? [:]).keys)] {
                guard Set(keys.map { $0.uppercased() }).count == keys.count else {
                    throw SidecarError.invalid("ambiguous case-folded stem keys")
                }
            }
        }
        var decisions: [String: Decision] = [:]
        for (k, v) in raw.decisions ?? [:] { decisions[k.uppercased()] = v }
        var crops: [String: CropRect] = [:]
        for (k, v) in raw.crops ?? [:] { crops[k.uppercased()] = v }
        var tilts: [String: Double] = [:]
        for (k, v) in raw.tilts ?? [:] { tilts[k.uppercased()] = v }
        var rotations: [String: Int] = [:]
        for (k, v) in raw.rotations ?? [:] { rotations[k.uppercased()] = v }
        return Session(version: raw.version ?? 0,
                       decisions: decisions,
                       lastIndex: raw.last_index ?? 0,
                       crops: crops,
                       tilts: tilts,
                       rotations: rotations)
    }

    /// Write to `folder/.photocull.json` with sorted keys and 2-space indent,
    /// byte-compatible with Go's `json.MarshalIndent`. `crops`, `tilts` and
    /// `rotations` are additive keys the Go app ignores; each is included
    /// only when non-empty.
    public func save(folder: URL) throws {
        var parts: [String] = []
        parts.append("  \"version\": \(version)")
        parts.append("  \"decisions\": \(Self.decisionsJSON(decisions))")
        parts.append("  \"last_index\": \(lastIndex)")
        if !crops.isEmpty { parts.append("  \"crops\": \(Self.cropsJSON(crops))") }
        if !tilts.isEmpty { parts.append("  \"tilts\": \(Self.tiltsJSON(tilts))") }
        if !rotations.isEmpty { parts.append("  \"rotations\": \(Self.rotationsJSON(rotations))") }
        let out = "{\n" + parts.joined(separator: ",\n") + "\n}"
        let url = folder.appendingPathComponent(Session.fileName)
        try out.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    public enum SidecarError: Error, LocalizedError {
        case invalid(String)
        public var errorDescription: String? {
            if case .invalid(let reason) = self { return "Unsafe Finalize sidecar: \(reason)" }
            return nil
        }
    }

    public func get(_ stem: String) -> Decision {
        decisions[stem.uppercased()] ?? .undecided
    }

    public func set(_ stem: String, _ decision: Decision) {
        decisions[stem.uppercased()] = decision
    }

    public func crop(for stem: String) -> CropRect? {
        crops[stem.uppercased()]
    }

    public func setCrop(_ stem: String, _ rect: CropRect?) {
        let key = stem.uppercased()
        if let rect { crops[key] = rect } else { crops.removeValue(forKey: key) }
    }

    public func tilt(for stem: String) -> Double {
        tilts[stem.uppercased()] ?? 0
    }

    /// `nil` (or a near-zero angle) removes the entry.
    public func setTilt(_ stem: String, _ degrees: Double?) {
        let key = stem.uppercased()
        guard let degrees, abs(degrees) >= 0.05 else { tilts.removeValue(forKey: key); return }
        tilts[key] = degrees
    }

    public func quarterTurns(for stem: String) -> Int {
        rotations[stem.uppercased()] ?? 0
    }

    /// `nil` (or a multiple of 4) removes the entry.
    public func setQuarter(_ stem: String, _ turns: Int?) {
        let key = stem.uppercased()
        let normalized = ((turns ?? 0) % 4 + 4) % 4
        guard normalized != 0 else { rotations.removeValue(forKey: key); return }
        rotations[key] = normalized
    }

    /// (keep, reject, undecided) counts over the given stems.
    public func statusCounts(stems: [String]) -> (keep: Int, reject: Int, undecided: Int) {
        var keep = 0, reject = 0, undecided = 0
        for stem in stems {
            switch get(stem) {
            case .keep: keep += 1
            case .reject: reject += 1
            case .undecided: undecided += 1
            }
        }
        return (keep, reject, undecided)
    }

    /// Folder-level rollup used by the sessions list. Only real decisions
    /// (keep/reject) count as decided — toggle-to-clear writes an `.undecided`
    /// value back into `decisions`, and a session where that happened must drop
    /// out of `complete`. (Deliberate divergence from Go, which counted mere
    /// presence as seen.)
    public func folderStatus(stems: [String]) -> FolderStatus {
        if stems.isEmpty { return .empty }
        let decided = stems.filter { get($0) != .undecided }.count
        if decided == 0 { return .unstarted }
        if decided == stems.count { return .complete }
        return .inProgress
    }

    // ── JSON serialization (hand-rolled for Go byte-compatibility) ──────────

    static func jsonEscape(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else {
                    out.unicodeScalars.append(ch)
                }
            }
        }
        return out
    }

    /// Shortest numeric form, like Go's JSON encoder for float64.
    static func jsonNumber(_ v: Double) -> String {
        if v.isNaN || v.isInfinite { return "0" }
        if v == v.rounded() && abs(v) < 1e15 {
            return String(Int64(v))
        }
        return "\(v)"
    }

    static func decisionsJSON(_ decisions: [String: Decision]) -> String {
        if decisions.isEmpty { return "{}" }
        var lines: [String] = []
        for key in decisions.keys.sorted() {
            lines.append("    \"\(jsonEscape(key))\": \"\(decisions[key]!.rawValue)\"")
        }
        return "{\n" + lines.joined(separator: ",\n") + "\n  }"
    }

    static func cropJSON(_ rect: CropRect) -> String {
        "{\n" +
        "      \"x\": \(jsonNumber(rect.x)),\n" +
        "      \"y\": \(jsonNumber(rect.y)),\n" +
        "      \"w\": \(jsonNumber(rect.w)),\n" +
        "      \"h\": \(jsonNumber(rect.h))\n" +
        "    }"
    }

    static func cropsJSON(_ crops: [String: CropRect]) -> String {
        if crops.isEmpty { return "{}" }
        var lines: [String] = []
        for key in crops.keys.sorted() {
            lines.append("    \"\(jsonEscape(key))\": \(cropJSON(crops[key]!))")
        }
        return "{\n" + lines.joined(separator: ",\n") + "\n  }"
    }

    static func tiltsJSON(_ tilts: [String: Double]) -> String {
        if tilts.isEmpty { return "{}" }
        var lines: [String] = []
        for key in tilts.keys.sorted() {
            lines.append("    \"\(jsonEscape(key))\": \(jsonNumber(tilts[key]!))")
        }
        return "{\n" + lines.joined(separator: ",\n") + "\n  }"
    }

    static func rotationsJSON(_ rotations: [String: Int]) -> String {
        if rotations.isEmpty { return "{}" }
        var lines: [String] = []
        for key in rotations.keys.sorted() {
            lines.append("    \"\(jsonEscape(key))\": \(rotations[key]!)")
        }
        return "{\n" + lines.joined(separator: ",\n") + "\n  }"
    }
}

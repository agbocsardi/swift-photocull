import Foundation
import Darwin

// Darwin imports both struct flock and flock(2). Bind the existing BSD symbol explicitly.
@_silgen_name("flock") private func directoryFlock(_ fd: Int32, _ operation: Int32) -> Int32

struct FinalizeSafetyError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func finalizePOSIX(_ action: String, code: Int32 = errno) -> Error {
    NSError(domain: NSPOSIXErrorDomain, code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "\(action): \(String(cString: strerror(code)))"])
}

struct FinalizeIdentity: Codable, Equatable {
    let device: Int32, inode: UInt64, type: UInt16, size: Int64, seconds: Int64, nanos: Int64
    init(_ st: stat) {
        device = st.st_dev; inode = st.st_ino; type = st.st_mode & UInt16(S_IFMT)
        size = st.st_size; seconds = Int64(st.st_mtimespec.tv_sec); nanos = Int64(st.st_mtimespec.tv_nsec)
    }
    func sameObject(_ other: Self) -> Bool { device == other.device && inode == other.inode && type == other.type }
}

/// A pinned, non-symlink directory. Namespace mutations below are relative to its descriptor.
final class FinalizeDirectory {
    let url: URL
    let fd: Int32
    let identity: FinalizeIdentity
    private var locked = false

    init(_ url: URL, lock: Bool = false) throws {
        self.url = url
        var before = stat()
        guard lstat(url.path, &before) == 0 else { throw finalizePOSIX("lstat \(url.path)") }
        guard before.st_mode & S_IFMT == S_IFDIR else { throw FinalizeSafetyError("Not a real directory: \(url.path)") }
        let opened = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard opened >= 0 else { throw finalizePOSIX("open \(url.path)") }
        var pinned = stat()
        guard fstat(opened, &pinned) == 0,
              FinalizeIdentity(before).sameObject(FinalizeIdentity(pinned)) else {
            close(opened); throw FinalizeSafetyError("Directory replaced while opening: \(url.path)")
        }
        fd = opened; identity = FinalizeIdentity(pinned)
        if lock {
            guard directoryFlock(fd, LOCK_EX | LOCK_NB) == 0 else {
                let code = errno
                close(fd)
                if code == EWOULDBLOCK { throw FinalizeSafetyError("Another Finalize owns \(url.path)") }
                throw finalizePOSIX("Cannot lock session; refusing Finalize \(url.path)", code: code)
            }
            locked = true
        }
    }
    func releaseLock() {
        if locked { _ = directoryFlock(fd, LOCK_UN); locked = false }
    }
    deinit { releaseLock(); close(fd) }
    var currentPath: String {
        var bytes = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        return fcntl(fd, F_GETPATH, &bytes) == 0 ? String(cString: bytes) : url.path
    }
    func verifyVisible() throws {
        var st = stat()
        guard lstat(url.path, &st) == 0, identity.sameObject(FinalizeIdentity(st)) else {
            throw FinalizeSafetyError("Directory renamed/replaced; retained pinned directory: \(currentPath); visible path: \(url.path)")
        }
    }
    static func basename(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.utf8.contains(0) else {
            throw FinalizeSafetyError("Invalid filename component")
        }
    }
    func readIdentity(_ name: String, regular: Bool = true) throws -> FinalizeIdentity {
        try Self.basename(name)
        var st = stat()
        guard fstatat(fd, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else { throw finalizePOSIX("stat \(currentPath)/\(name)") }
        let value = FinalizeIdentity(st)
        guard !regular || value.type == S_IFREG else { throw FinalizeSafetyError("Not a regular non-symlink input: \(currentPath)/\(name)") }
        return value
    }
    func verify(_ name: String, _ expected: FinalizeIdentity) throws {
        guard try readIdentity(name) == expected else { throw FinalizeSafetyError("Input changed: \(currentPath)/\(name)") }
    }
    func move(_ name: String, to destination: FinalizeDirectory, name newName: String) throws {
        try Self.basename(name); try Self.basename(newName)
        guard renameatx_np(fd, name, destination.fd, newName, UInt32(RENAME_EXCL)) == 0 else {
            throw finalizePOSIX("exclusive rename \(currentPath)/\(name) -> \(destination.currentPath)/\(newName)")
        }
    }
    func privateDirectory(_ prefix: String) throws -> FinalizeDirectory {
        try verifyVisible()
        let name = prefix + UUID().uuidString
        guard mkdirat(fd, name, 0o700) == 0 else { throw finalizePOSIX("mkdir private directory") }
        let child = try FinalizeDirectory(url.appendingPathComponent(name))
        let anchored = try readIdentity(name, regular: false)
        guard anchored.sameObject(child.identity) else { throw FinalizeSafetyError("Private directory replaced") }
        return child
    }
    func removeEmptyChild(_ child: FinalizeDirectory, requireVisible: Bool = true) throws {
        if requireVisible { try verifyVisible(); try child.verifyVisible() }
        guard try readIdentity(child.url.lastPathComponent, regular: false).sameObject(child.identity) else {
            throw FinalizeSafetyError("Private directory changed")
        }
        guard unlinkat(fd, child.url.lastPathComponent, AT_REMOVEDIR) == 0 else { throw finalizePOSIX("remove empty \(child.currentPath)") }
    }
    func unlink(_ name: String) throws {
        try Self.basename(name)
        guard unlinkat(fd, name, 0) == 0 else { throw finalizePOSIX("unlink \(currentPath)/\(name)") }
    }
}

struct FinalizeSidecar: Equatable {
    let identity: FinalizeIdentity?
    let bytes: Data?
    static func capture(_ directory: FinalizeDirectory) throws -> Self {
        let name = Session.fileName
        var st = stat()
        if fstatat(directory.fd, name, &st, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return Self(identity: nil, bytes: nil) }
            throw finalizePOSIX("read sidecar metadata")
        }
        let expected = FinalizeIdentity(st)
        guard expected.type == S_IFREG else { throw FinalizeSafetyError("Sidecar is not a regular non-symlink file") }
        let fd = openat(directory.fd, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw finalizePOSIX("open sidecar") }
        defer { close(fd) }
        guard fstat(fd, &st) == 0, FinalizeIdentity(st) == expected else { throw FinalizeSafetyError("Sidecar replaced while opening") }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 { if errno == EINTR { continue }; throw finalizePOSIX("read sidecar") }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard fstat(fd, &st) == 0, FinalizeIdentity(st) == expected else { throw FinalizeSafetyError("Sidecar changed while reading") }
        try directory.verify(name, expected)
        return Self(identity: expected, bytes: data)
    }
    func session() throws -> Session { try bytes.map { try Session.decode(data: $0, strict: true) } ?? Session.fresh() }
    func verify(_ directory: FinalizeDirectory) throws {
        try directory.verifyVisible()
        guard try Self.capture(directory) == self else { throw FinalizeSafetyError("Sidecar changed; preserved at \(directory.currentPath)/\(Session.fileName)") }
    }
}

/// Durable initial plan; retries require manual inspection. No automatic rollback of completed effects.
final class FinalizeRecovery {
    static let name = ".photocull-recovery.json"
    let directory: FinalizeDirectory
    let claims: FinalizeDirectory
    let fd: Int32
    private(set) var identity: FinalizeIdentity
    private let progressFD: Int32
    private let progressIdentity: FinalizeIdentity
    private let document: [String: Any]
    private static let progressName = ".progress.jsonl"

    init(directory: FinalizeDirectory, claims: FinalizeDirectory, invocation: String, plans: [[String: Any]]) throws {
        self.directory = directory; self.claims = claims
        document = ["invocation": invocation, "sources": plans,
                    "progress": claims.url.appendingPathComponent(Self.progressName).path,
                    "policy": "Manual inspect/repair only; a pair may be partially completed."]
        let journal = openat(claims.fd, Self.progressName, O_WRONLY | O_CREAT | O_EXCL | O_APPEND | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard journal >= 0 else { throw finalizePOSIX("create owned progress journal") }
        var journalStat = stat()
        guard fstat(journal, &journalStat) == 0 else { close(journal); throw finalizePOSIX("stat progress journal") }
        progressFD = journal; progressIdentity = FinalizeIdentity(journalStat)
        fd = openat(directory.fd, Self.name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { close(progressFD); throw finalizePOSIX("create recovery record \(directory.currentPath)/\(Self.name)") }
        var st = stat()
        guard fstat(fd, &st) == 0 else { close(fd); close(progressFD); throw finalizePOSIX("stat recovery record") }
        identity = FinalizeIdentity(st)
        do {
            try writeDocument()
            guard fstat(fd, &st) == 0 else { throw finalizePOSIX("stat durable recovery record") }
            identity = FinalizeIdentity(st)
        } catch { close(fd); close(progressFD); throw error }
    }
    deinit { close(fd); close(progressFD) }
    private func writeDocument() throws {
        let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys, .prettyPrinted])
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = pwrite(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, off_t(offset))
                if n < 0 { if errno == EINTR { continue }; throw finalizePOSIX("write recovery record") }
                guard n > 0 else { throw FinalizeSafetyError("Short recovery write") }
                offset += n
            }
        }
        guard ftruncate(fd, off_t(data.count)) == 0, fsync(fd) == 0, fsync(progressFD) == 0,
              fsync(claims.fd) == 0, fsync(directory.fd) == 0 else {
            throw finalizePOSIX("sync recovery record")
        }
    }
    func completed(_ source: URL, at destination: URL?, action: String) throws {
        // Keep the complete initial plan immutable. A crash can truncate the last progress line,
        // but cannot tear a rewrite of the recovery plan that preceded the source claims.
        var data = try JSONSerialization.data(withJSONObject: ["source": source.path,
            "location": destination?.path ?? "native Trash (path unavailable)", "action": action], options: [.sortedKeys])
        data.append(10)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.write(progressFD, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if n < 0 { if errno == EINTR { continue }; throw finalizePOSIX("write progress journal") }
                guard n > 0 else { throw FinalizeSafetyError("Short progress write") }
                offset += n
            }
        }
        guard fsync(progressFD) == 0 else { throw finalizePOSIX("sync progress journal") }
    }
    var currentPath: String {
        var bytes = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        return fcntl(fd, F_GETPATH, &bytes) == 0 ? String(cString: bytes) : directory.url.appendingPathComponent(Self.name).path
    }
    func removeOwned() throws {
        try directory.verifyVisible(); try claims.verifyVisible()
        // Atomically claim the mutable record name, then verify before deleting ANY recovery metadata.
        try directory.move(Self.name, to: claims, name: "recovery-metadata")
        let claimed = try claims.readIdentity("recovery-metadata")
        guard claimed == identity else {
            throw FinalizeSafetyError("Recovery record replaced; replacement retained at \(claims.currentPath)/recovery-metadata; owned plan at \(currentPath)")
        }
        guard try claims.readIdentity(Self.progressName).sameObject(progressIdentity) else {
            throw FinalizeSafetyError("Owned progress journal replaced; retained at \(claims.currentPath)")
        }
        try claims.unlink(Self.progressName)
        try claims.unlink("recovery-metadata")
        guard fsync(directory.fd) == 0 else { throw finalizePOSIX("sync record removal") }
    }
}

/// Only per-invocation seams. Production never reads a Trash override from config/environment.
package struct FinalizeHooks {
    package var boundary: ((String, URL) throws -> Void)?
    package var trash: ((URL) throws -> URL?)?
    package init(boundary: ((String, URL) throws -> Void)? = nil, trash: ((URL) throws -> URL?)? = nil) {
        self.boundary = boundary; self.trash = trash
    }
}

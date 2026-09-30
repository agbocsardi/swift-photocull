import AppKit
import SwiftUI

/// `PhotoCull --snapshot <path>` — render the app's own window to a PNG and quit.
///
/// An app may snapshot its own window without Screen Recording permission, which
/// makes this the only way to inspect the UI from a headless/agent context.
enum Snapshot {
    static var requestedPath: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `--appearance dark|light` forces an appearance so both modes can be checked.
    static func applyRequestedAppearance() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--appearance"), i + 1 < args.count else { return }
        switch args[i + 1].lowercased() {
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }

    /// Wait for the window to be laid out and the photo to decode, then capture it.
    static func scheduleIfRequested() {
        guard let path = requestedPath else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            let ok = capture(to: path)
            exit(ok ? 0 : 1)
        }
    }

    @discardableResult
    static func capture(to path: String) -> Bool {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible })
                ?? NSApp.windows.first(where: { $0.canBecomeMain }) else {
            FileHandle.standardError.write(Data("snapshot: no window\n".utf8))
            return false
        }

        // Capture the whole frame (title bar + toolbar + content), not just contentView.
        let view = window.contentView?.superview ?? window.contentView
        guard let target = view else { return false }

        target.layoutSubtreeIfNeeded()
        guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else {
            FileHandle.standardError.write(Data("snapshot: no bitmap rep\n".utf8))
            return false
        }
        target.cacheDisplay(in: target.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            FileHandle.standardError.write(Data("snapshot: wrote \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh))\n".utf8))
            return true
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
            return false
        }
    }
}

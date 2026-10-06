import Foundation
import PhotoCullCore

/// Resolved before SwiftUI/AppState or either ordinary headless diagnostic can run.
struct StartupConfiguration {
    static let fixtureIdentifierPrefix = "local.photocull.fixture."
    let fixtureConfig: PCConfig?
    var isFixture: Bool { fixtureConfig != nil }
    @MainActor static var current = StartupConfiguration(fixtureConfig: nil)

    static func resolve(arguments: [String], bundleIdentifier: String?) throws -> StartupConfiguration {
        let identified = bundleIdentifier == "local.photocull.fixture" ||
            bundleIdentifier?.hasPrefix(fixtureIdentifierPrefix) == true
        let requested = arguments.contains { $0.hasPrefix("--fixture-config") }
        if !identified && !requested { return StartupConfiguration(fixtureConfig: nil) }
        guard let id = bundleIdentifier, id.hasPrefix(fixtureIdentifierPrefix),
              UUID(uuidString: String(id.dropFirst(fixtureIdentifierPrefix.count))) != nil,
              arguments.count == 2, arguments[0] == "--fixture-config" else {
            throw NSError(domain: "PhotoCull.Fixture", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "Fixture launch requires a unique local.photocull.fixture.<UUID> bundle and only --fixture-config <canonical-file>; no diagnostics/snapshot/other flags"])
        }
        return StartupConfiguration(fixtureConfig: try PCConfig.loadFixture(from: arguments[1]))
    }

    @MainActor func makeAppState() -> AppState {
        AppState(cfg: fixtureConfig, fixtureMode: isFixture)
    }
}

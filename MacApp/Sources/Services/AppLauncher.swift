import Foundation
import AppKit

actor AppLauncher {
    static let shared = AppLauncher()
    private init() {}

    @discardableResult
    func launch(bundleId: String) async -> Bool {
        return await Task.detached(priority: .userInitiated) {
            // Use NSWorkspace to open the app by bundle identifier
            let workspace = NSWorkspace.shared
            if let url = workspace.urlForApplication(withBundleIdentifier: bundleId) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                do {
                    try await workspace.openApplication(at: url, configuration: config)
                    return true
                } catch {
                    print("Launch error for \(bundleId): \(error)")
                    return false
                }
            }
            return false
        }.value
    }
}

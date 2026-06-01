import Foundation
import AppKit

struct InstalledApp {
    let name: String
    let bundleId: String
    let bundleURL: URL
}

actor AppScanner {
    static let shared = AppScanner()
    private init() {}

    private var cache: [InstalledApp]?
    private var cacheDate: Date?
    private let cacheTTL: TimeInterval = 30

    func installedApps() async -> [InstalledApp] {
        if let cache, let date = cacheDate, Date().timeIntervalSince(date) < cacheTTL {
            return cache
        }
        let apps = await Task.detached(priority: .userInitiated) { self.scanApps() }.value
        self.cache = apps
        self.cacheDate = Date()
        return apps
    }

    private nonisolated func scanApps() -> [InstalledApp] {
        var result: [InstalledApp] = []
        let searchPaths: [String] = ["/Applications", "\(NSHomeDirectory())/Applications"]

        for searchPath in searchPaths {
            let url = URL(fileURLWithPath: searchPath)
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isApplicationKey, .nameKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "app" else { continue }
                if let app = makeInstalledApp(from: fileURL) {
                    result.append(app)
                }
            }
        }

        // Also grab apps from the workspace (catches App Store apps in /Applications)
        let runningApps = NSWorkspace.shared.runningApplications.compactMap { app -> InstalledApp? in
            guard let url = app.bundleURL,
                  let bundleId = app.bundleIdentifier,
                  let name = app.localizedName,
                  !bundleId.hasPrefix("com.apple."),
                  url.pathExtension == "app" else { return nil }
            return InstalledApp(name: name, bundleId: bundleId, bundleURL: url)
        }

        // Merge, dedup by bundleId
        var seen = Set(result.map(\.bundleId))
        for app in runningApps where !seen.contains(app.bundleId) {
            result.append(app)
            seen.insert(app.bundleId)
        }

        return result.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private nonisolated func makeInstalledApp(from url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier,
              let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
                      ?? bundle.infoDictionary?["CFBundleName"] as? String
                      ?? url.deletingPathExtension().lastPathComponent as String?
        else { return nil }
        return InstalledApp(name: name, bundleId: bundleId, bundleURL: url)
    }
}

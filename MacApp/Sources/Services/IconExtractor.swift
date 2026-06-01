import Foundation
import AppKit

actor IconExtractor {
    static let shared = IconExtractor()
    private init() {}

    private var cache: [String: String] = [:]   // bundleId → base64 PNG

    /// Returns a base64-encoded PNG of the app icon, resized to `size`.
    func iconBase64(for bundleURL: URL, size: CGSize) async -> String? {
        let key = bundleURL.path + "\(size.width)"
        if let cached = cache[key] { return cached }

        let result = await Task.detached(priority: .utility) {
            self.extractIcon(from: bundleURL, size: size)
        }.value

        if let result { cache[key] = result }
        return result
    }

    private nonisolated func extractIcon(from bundleURL: URL, size: CGSize) -> String? {
        let workspace = NSWorkspace.shared
        let icon = workspace.icon(forFile: bundleURL.path)
        icon.size = size

        guard let tiff = icon.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        else { return nil }

        return jpeg.base64EncodedString()
    }
}

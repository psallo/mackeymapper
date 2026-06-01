import Foundation
import SwiftUI
import UIKit
import Combine
import Network

// MARK: - Connection State
enum ConnectionState: Equatable {
    case idle
    case discovering
    case connecting
    case pairing
    case connected
    case failed(String)

    var isConnected: Bool { self == .connected }
    var displayText: String {
        switch self {
        case .idle:            return "Not Connected"
        case .discovering:     return "Searching for Mac…"
        case .connecting:      return "Connecting…"
        case .pairing:         return "Waiting for PIN…"
        case .connected:       return "Connected"
        case .failed(let msg): return "Error: \(msg)"
        }
    }
    var color: Color {
        switch self {
        case .connected:        return .green
        case .failed:           return .red
        case .idle:             return .secondary
        default:                return .orange
        }
    }
}

// MARK: - Discovered Server
struct DiscoveredServer: Identifiable, Equatable {
    let id: String   // endpoint description
    let name: String
    let endpoint: NWEndpoint
}

// MARK: - App State
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    private init() {}

    // Connection
    @Published var connectionState: ConnectionState = .idle
    @Published var discoveredServers: [DiscoveredServer] = []
    @Published var selectedServer: DiscoveredServer?
    @Published var connectedMacName: String = ""

    // Apps
    @Published var remoteApps: [RemoteApp] = []
    @Published var isLoadingApps = false

    // Onboarding
    @Published var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "onboardingDone")

    // Premium / Ads
    @Published var isPremium: Bool = UserDefaults.standard.bool(forKey: "isPremium")

    // Custom wallpaper (premium only) — 앱 시작 시 디스크에서 로드
    @Published var customWallpaper: UIImage? = WallpaperManager.load()

    // Error / feedback
    @Published var launchFeedback: LaunchFeedback?

    // Pairing
    @Published var isPairingSheetPresented = false
    var isAutoAuthPending = false
    @Published var serverCertFingerprint: String = ""
    @Published var storedCertFingerprint: String? {
        didSet { UserDefaults.standard.set(storedCertFingerprint, forKey: "certFingerprint") }
    }

    // Networking actors
    let browser = BonjourBrowser()
    var connection: RemoteConnection?

    // MARK: - Lifecycle

    func start() {
        storedCertFingerprint = UserDefaults.standard.string(forKey: "certFingerprint")
        Task { await browser.start(delegate: self) }
    }

    // MARK: - Connect

    func connect(to server: DiscoveredServer) {
        selectedServer = server
        connectionState = .connecting
        let conn = RemoteConnection()
        self.connection = conn
        Task { await conn.connect(to: server.endpoint, delegate: self) }

        // 10초 내 연결 안 되면 타임아웃 안내
        Task {
            try? await Task.sleep(for: .seconds(10))
            guard case .connecting = connectionState else { return }
            await connection?.disconnect()
            connection = nil
            connectionState = .failed(
                "Could not connect to \(server.name). " +
                "Make sure both devices are on the same Wi-Fi network. " +
                "Public Wi-Fi may block device connections."
            )
        }
    }

    func disconnect() {
        Task { await connection?.disconnect() }
        connection = nil
        connectionState = .idle
        remoteApps = []
        connectedMacName = ""
    }

    // MARK: - Pairing

    func submitPIN(_ pin: String) {
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let deviceName = DeviceInfo.displayName
        Task {
            await connection?.sendAuth(pin: pin, deviceId: deviceId, deviceName: deviceName)
        }
    }

    // MARK: - App Actions

    func refreshApps() {
        guard connectionState.isConnected, !isLoadingApps else { return }
        isLoadingApps = true
        remoteApps = []
        Task { await connection?.sendGetApps(iconPixelSize: AppState.homeScreenIconPixels) }
    }

    func launch(app: RemoteApp) {
        Task { await connection?.sendLaunch(bundleId: app.id) }
        launchFeedback = LaunchFeedback(appName: app.name)
    }

    // MARK: - Helpers

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "onboardingDone")
    }

    func unlockPremium() {
        isPremium = true
        UserDefaults.standard.set(true, forKey: "isPremium")
    }

    func setWallpaper(_ image: UIImage) {
        WallpaperManager.save(image)
        customWallpaper = image
    }

    func removeWallpaper() {
        WallpaperManager.remove()
        customWallpaper = nil
    }

    func purchasePremium() {
        Task { await PurchaseManager.shared.purchase() }
    }

    // MARK: - Home screen icon sizing (adapts to connected device)

    /// iOS 홈 화면 앱 아이콘 크기 (pt) — 기기 폼팩터에 따라 결정
    static var homeScreenIconPt: CGFloat {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: return 60
        case .pad:
            let shortSide = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
            return shortSide >= 1024 ? 83.5 : 76   // iPad Pro 12.9" vs 일반 iPad
        default: return 60
        }
    }

    /// Mac에 요청할 아이콘 픽셀 크기 = pt × 화면 배율
    static var homeScreenIconPixels: Int {
        Int((homeScreenIconPt * UIScreen.main.scale).rounded())
    }

    /// iOS 아이콘 squircle 코너 반지름 = pt × 0.2236
    static var homeScreenIconCornerRadius: CGFloat {
        homeScreenIconPt * 0.2236
    }

    var freeAppLimit: Int { 4 }
    var displayedApps: [RemoteApp] {
        isPremium ? remoteApps : Array(remoteApps.prefix(freeAppLimit))
    }
    var lockedApps: [RemoteApp] {
        guard !isPremium, remoteApps.count > freeAppLimit else { return [] }
        return Array(remoteApps.dropFirst(freeAppLimit))
    }
}

// MARK: - Launch Feedback
struct LaunchFeedback: Identifiable {
    let id = UUID()
    let appName: String
}

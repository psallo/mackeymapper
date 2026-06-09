import SwiftUI
import UIKit
import AppTrackingTransparency

private let panelBgColor = Color(red: 0.04, green: 0.04, blue: 0.14, opacity: 0.90)

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: landscape ? 5 : 4)
            VStack(spacing: 0) {
                ScrollView {
                    AppContentView(columns: columns)
                }
                BottomPanel(
                    showSettings: $showSettings,
                    availableWidth: geo.size.width,
                    compact: landscape
                )
            }
            .background(WallpaperView(customImage: appState.customWallpaper).ignoresSafeArea())
            .preferredColorScheme(.dark)
            .sheet(isPresented: $appState.isPairingSheetPresented) {
                PairingView().interactiveDismissDisabled()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .overlay(alignment: .bottom) {
                if let feedback = appState.launchFeedback {
                    LaunchToastView(appName: feedback.appName)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: feedback.id) {
                            try? await Task.sleep(for: .seconds(3))
                            withAnimation { appState.launchFeedback = nil }
                        }
                }
            }
            .animation(.spring(), value: appState.launchFeedback?.id)
            .task {
                guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
                try? await Task.sleep(for: .seconds(1))
                await ATTrackingManager.requestTrackingAuthorization()
            }
        }
    }
}

// MARK: - Wallpaper

private struct WallpaperView: View {
    var customImage: UIImage? = nil

    var body: some View {
        if let uiImage = customImage {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                // 아이콘·텍스트 가독성을 위한 어두운 오버레이
                .overlay(Color.black.opacity(0.40))
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.12, blue: 0.40),
                        Color(red: 0.22, green: 0.10, blue: 0.48),
                        Color(red: 0.04, green: 0.06, blue: 0.28),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color(red: 0.45, green: 0.28, blue: 0.85).opacity(0.35))
                    .frame(width: 320).blur(radius: 90).offset(x: 130, y: -200)
                Circle()
                    .fill(Color(red: 0.10, green: 0.35, blue: 0.75).opacity(0.30))
                    .frame(width: 260).blur(radius: 70).offset(x: -100, y: 280)
            }
        }
    }
}

// MARK: - Bottom Panel

private struct BottomPanel: View {
    @EnvironmentObject var appState: AppState
    @Binding var showSettings: Bool
    let availableWidth: CGFloat
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if !appState.isPremium {
                AdBannerView(availableWidth: availableWidth, isLandscape: compact)
            }
            HomeDock(showSettings: $showSettings, compact: compact)
        }
        .background(panelBgColor, ignoresSafeAreaEdges: .bottom)
    }
}

// MARK: - App Content

private struct AppContentView: View {
    @EnvironmentObject var appState: AppState
    let columns: [GridItem]

    var body: some View {
        Group {
            if appState.isLoadingApps {
                HomeLoadingView()
            } else if !appState.connectionState.isConnected {
                HomeDisconnectedView()
            } else if appState.remoteApps.isEmpty {
                HomeEmptyView()
            } else {
                AppGridView(columns: columns)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Home Dock

private struct HomeDock: View {
    @EnvironmentObject var appState: AppState
    @Binding var showSettings: Bool
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.connectionState.color)
                    .frame(width: 7, height: 7)
                    .animation(.easeInOut, value: appState.connectionState)
                Text(appState.connectionState.isConnected
                     ? appState.connectedMacName
                     : appState.connectionState.displayText)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if appState.connectionState.isConnected {
                Button { appState.refreshApps() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                }
            }

            Button { showSettings = true } label: {
                Image(systemName: "gear")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, compact ? 8 : 12)
    }
}

// MARK: - State Views

private struct HomeLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().tint(.white).scaleEffect(1.3)
            Text("Loading apps…").font(.callout).foregroundColor(.white.opacity(0.8))
        }
        .padding(48)
    }
}

private struct HomeDisconnectedView: View {
    @EnvironmentObject var appState: AppState

    private var isFailed: Bool {
        if case .failed = appState.connectionState { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: isFailed ? "wifi.exclamationmark" : "desktopcomputer.slash")
                    .font(.system(size: 56))
                    .foregroundColor(isFailed ? .orange.opacity(0.85) : .white.opacity(0.6))

                Text(isFailed ? "Connection Failed" : "No Mac Found")
                    .font(.title3.bold()).foregroundColor(.white)

                Text(appState.connectionState.displayText)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .font(.callout)

                if isFailed {
                    VStack(alignment: .leading, spacing: 0) {
                        // 핫스팟 안내
                        HStack(alignment: .top, spacing: 12) {
                            Text("📡")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Try iPhone Personal Hotspot")
                                    .font(.callout.bold())
                                    .foregroundColor(.white)
                                Text("1. Connect iPhone to Mac with a USB cable\n2. Enable Settings → Personal Hotspot\n3. Tap ↺ to reconnect")
                                    .font(.footnote)
                                    .foregroundColor(.white.opacity(0.65))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16)

                        Divider().background(Color.white.opacity(0.1))

                        // 데이터 경고
                        HStack(alignment: .top, spacing: 12) {
                            Text("⚠️")
                                .font(.title3)
                            Text("When using Personal Hotspot, your Mac's internet traffic routes through your iPhone's cellular data. Pause cloud sync or large downloads to avoid unexpected usage.")
                                .font(.footnote)
                                .foregroundColor(.orange.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                    }
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 4)
                }

                if !appState.discoveredServers.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(appState.discoveredServers) { server in
                            Button(server.name) { appState.connect(to: server) }
                                .buttonStyle(.bordered).tint(.white)
                        }
                    }
                }
            }
            .padding(32)
        }
    }
}

private struct HomeEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3.slash")
                .font(.system(size: 56)).foregroundColor(.white.opacity(0.6))
            Text("No Apps Configured").font(.title3.bold()).foregroundColor(.white)
            Text("Select apps to share in MacLauncher Remote on your Mac.")
                .foregroundColor(.white.opacity(0.6)).multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Launch Toast

private struct LaunchToastView: View {
    let appName: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text("Launching \(appName)…").font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 100)
    }
}

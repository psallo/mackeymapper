import SwiftUI
import GoogleMobileAds

@main
struct MacLauncherApp: App {
    @StateObject private var appState = AppState.shared

    init() {
        // AdMob SDK 초기화 (앱 실행 직후 최대한 빨리 호출)
        GADMobileAds.sharedInstance().start(completionHandler: nil)
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .onAppear { appState.start() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                // 앱 목록이 없을 때만 재요청 — 목록이 있으면 유지 (사용자가 원하면 ↺ 버튼으로 수동 갱신)
                if appState.remoteApps.isEmpty {
                    appState.refreshApps()
                }
                UIApplication.shared.isIdleTimerDisabled = true
            } else if phase == .background {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }
}

// MARK: - Root router
private struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.hasCompletedOnboarding {
            MainView()
        } else {
            OnboardingView()
        }
    }
}

import SwiftUI
import GoogleMobileAds
import AppTrackingTransparency

@main
struct MacLauncherApp: App {
    @StateObject private var appState = AppState.shared

    init() {
        GADMobileAds.sharedInstance().start(completionHandler: nil)
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .onAppear {
                    appState.start()
                    PurchaseManager.shared.startTransactionObserver()
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
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

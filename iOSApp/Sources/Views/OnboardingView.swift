import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            OnboardingPage(
                systemImage: "desktopcomputer.and.arrow.down",
                title: "Download the Mac App",
                description: "First, install MacLauncher Remote on your Mac. It's a tiny menu bar app — no Dock icon.",
                action: {
                    if let url = URL(string: "https://www.mackeymapper.com/") {
                        UIApplication.shared.open(url)
                    }
                },
                actionLabel: "Download Mac App",
                page: $page, index: 0, total: 4
            )
            .tag(0)

            OnboardingPage(
                systemImage: "gear.badge.checkmark",
                title: "Install the Mac App",
                description: "Open the downloaded .dmg file and drag MacKeymapper to your Applications folder.\n\nDouble-click to launch — no extra steps needed.",
                action: nil, actionLabel: nil,
                page: $page, index: 1, total: 4
            )
            .tag(1)

            OnboardingPage(
                systemImage: "wifi",
                title: "Same Wi-Fi Network",
                description: "Make sure your iPhone and Mac are on the same Wi-Fi network. The app uses Bonjour for automatic discovery — no IP addresses needed.\n\nNo Wi-Fi available? Connect your iPhone to your Mac via USB cable and enable Personal Hotspot — it works the same way.\n\n⚠️ When using Personal Hotspot, your Mac's internet traffic will go through your iPhone's cellular data.",
                action: nil, actionLabel: nil,
                page: $page, index: 2, total: 4
            )
            .tag(2)

            OnboardingPage(
                systemImage: "iphone.and.arrow.forward",
                title: "Pair & Launch",
                description: "MacKeymapper will find your Mac automatically. Enter the 4-digit PIN shown in the Mac app's menu bar to pair.",
                action: { appState.completeOnboarding() },
                actionLabel: "Get Started",
                page: $page, index: 3, total: 4
            )
            .tag(3)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .animation(.easeInOut, value: page)
    }
}

private struct OnboardingPage: View {
    let systemImage: String
    let title: String
    let description: String
    let action: (() -> Void)?
    let actionLabel: String?
    @Binding var page: Int
    let index: Int
    let total: Int

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: systemImage)
                .font(.system(size: 72, weight: .thin))
                .foregroundColor(.accentColor)
                .padding(.bottom, 8)

            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 32)
            } else if index < total - 1 {
                Button("Next") { withAnimation { page = index + 1 } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 32)
            }

            Spacer().frame(height: 48)
        }
    }
}

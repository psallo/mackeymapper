import SwiftUI

// MARK: - App Grid

struct AppGridView: View {
    @EnvironmentObject var appState: AppState
    let columns: [GridItem]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(Array(appState.remoteApps.enumerated()), id: \.element.id) { index, app in
                if appState.isPremium || index < appState.freeAppLimit {
                    AppButtonView(app: app)
                } else {
                    LockedAppButtonView(app: app)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
}

// MARK: - App Button

struct AppButtonView: View {
    @EnvironmentObject var appState: AppState
    let app: RemoteApp

    private let iconSize = AppState.homeScreenIconPt
    private let cornerRadius = AppState.homeScreenIconCornerRadius

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            appState.launch(app: app)
        } label: {
            VStack(spacing: 6) {
                app.icon
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

                Text(app.name)
                    .font(.system(size: 11, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .frame(maxWidth: iconSize + 14)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppIconButtonStyle())
    }
}

private struct AppIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Locked App Button

private struct LockedAppButtonView: View {
    @EnvironmentObject var appState: AppState
    let app: RemoteApp
    @State private var showUpgradeAlert = false

    private let iconSize = AppState.homeScreenIconPt
    private let cornerRadius = AppState.homeScreenIconCornerRadius

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showUpgradeAlert = true
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    app.icon
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .blur(radius: 2)
                        .opacity(0.5)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: iconSize, height: iconSize)

                    Image(systemName: "lock.fill")
                        .font(.system(size: iconSize * 0.33, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }

                Text(app.name)
                    .font(.system(size: 11, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.white.opacity(0.45))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .frame(maxWidth: iconSize + 14)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alert("Premium Feature", isPresented: $showUpgradeAlert) {
            Button("Upgrade") { appState.purchasePremium() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unlock unlimited apps and remove ads with a one-time purchase.")
        }
    }
}

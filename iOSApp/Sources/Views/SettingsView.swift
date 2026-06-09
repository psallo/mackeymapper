import SwiftUI
import StoreKit
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var store = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var wallpaperItem: PhotosPickerItem?
    @State private var isPickingWallpaper = false

    var body: some View {
        NavigationStack {
            List {
                // Connection
                Section("Connection") {
                    LabeledContent("Status", value: appState.connectionState.displayText)
                    if appState.connectionState.isConnected {
                        LabeledContent("Mac", value: appState.connectedMacName)
                        Button("Disconnect", role: .destructive) { appState.disconnect() }
                    }
                }

                // Premium
                if !appState.isPremium {
                    Section("Premium") {
                        PremiumUpsellRow(store: store)
                    }
                } else {
                    Section("Premium") {
                        Label("Unlimited apps unlocked", systemImage: "checkmark.seal.fill")
                            .foregroundColor(.green)

                        // 배경화면 선택
                        PhotosPicker(
                            selection: $wallpaperItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("Change Wallpaper", systemImage: "photo.on.rectangle")
                        }
                        .onChange(of: wallpaperItem) { newItem in
                            guard let newItem else { return }
                            Task {
                                if let data = try? await newItem.loadTransferable(type: Data.self),
                                   let image = UIImage(data: data) {
                                    await MainActor.run { appState.setWallpaper(image) }
                                }
                                wallpaperItem = nil
                            }
                        }

                        if appState.customWallpaper != nil {
                            Button("Reset to Default Wallpaper", role: .destructive) {
                                appState.removeWallpaper()
                            }
                        }
                    }
                }

                // Mac App
                Section("Mac App") {
                    Link(destination: URL(string: "https://www.mackeymapper.com/")!) {
                        Label("Download Mac App", systemImage: "arrow.down.circle")
                    }
                }

                // About
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.shortVersionString)
                    Link("Privacy Policy", destination: URL(string: "https://www.mackeymapper.com/")!)
                    Link("Support", destination: URL(string: "mailto:treasure0613@gmail.com")!)
                    Button("Reset Onboarding") {
                        UserDefaults.standard.removeObject(forKey: "onboardingDone")
                        UserDefaults.standard.removeObject(forKey: "certFingerprint")
                        appState.hasCompletedOnboarding = false
                    }
                    .foregroundColor(.red)
                }

                #if DEBUG
                Section("Developer") {
                    if appState.isPremium {
                        Button("Revoke Premium (Debug)", role: .destructive) {
                            UserDefaults.standard.set(false, forKey: "isPremium")
                            appState.isPremium = false
                        }
                    } else {
                        Button("Unlock Premium (Debug)") {
                            UserDefaults.standard.set(true, forKey: "isPremium")
                            appState.isPremium = true
                        }
                        .foregroundColor(.orange)
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await store.loadProducts() }
    }
}

private struct PremiumUpsellRow: View {
    @ObservedObject var store: PurchaseManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MacKeymapper Premium")
                .font(.headline)
            Text("• Unlimited app shortcuts\n• Custom wallpaper\n• No ads\n• One-time purchase")
                .font(.callout)
                .foregroundColor(.secondary)

            HStack {
                Button {
                    Task { await store.purchase() }
                } label: {
                    if store.isLoading {
                        ProgressView()
                    } else {
                        Text("Unlock — \(store.formattedPrice)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading || store.product == nil)

                Spacer()

                Button("Restore") {
                    Task { await store.restorePurchases() }
                }
                .foregroundColor(.accentColor)
            }

            if store.product == nil && !store.isLoading {
                HStack {
                    Text("상품 정보를 가져오지 못했습니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("다시 시도") {
                        Task { await store.loadProducts() }
                    }
                    .font(.caption)
                }
            }

            if let error = store.purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Store modal (also accessible from PremiumUpsellBanner)
struct StoreView: View {
    @StateObject private var store = PurchaseManager.shared
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.yellow)
                Text("Go Premium")
                    .font(.largeTitle.bold())
                Text("Unlock unlimited app shortcuts,\ncustom wallpaper, and remove ads.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
                Button {
                    Task { await store.purchase() }
                } label: {
                    if store.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Purchase — \(store.formattedPrice)")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .disabled(store.isLoading || store.product == nil)

                if store.product == nil && !store.isLoading {
                    Text("상품 정보를 불러오는 중입니다.\n잠시 후 다시 시도해주세요.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("Restore Purchases") {
                    Task { await store.restorePurchases() }
                }
                .foregroundColor(.secondary)
                Spacer().frame(height: 16)
            }
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .task { await store.loadProducts() }
    }
}

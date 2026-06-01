import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @State private var pin: String = SettingsManager.shared.pin
    @State private var launchAtLogin: Bool = SettingsManager.shared.launchAtLogin
    @State private var allowedDevices: [String] = []
    @State private var showPINAlert = false

    var body: some View {
        TabView {
            GeneralTab(
                pin: $pin,
                launchAtLogin: $launchAtLogin,
                showPINAlert: $showPINAlert,
                onRegeneratePIN: regeneratePIN
            )
            .tabItem { Label("General", systemImage: "gear") }

            DevicesTab(devices: $allowedDevices, onRemove: removeDevice)
                .tabItem { Label("Devices", systemImage: "iphone") }

            AppsTab()
                .tabItem { Label("Apps", systemImage: "square.grid.3x3") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 440)
        .padding()
        .onAppear { loadState() }
        .alert("PIN Updated", isPresented: $showPINAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("New PIN: \(pin)\n\nShare this PIN with your iOS device to pair.")
        }
    }

    private func loadState() {
        pin = SettingsManager.shared.pin
        launchAtLogin = SettingsManager.shared.launchAtLogin
        allowedDevices = Array(SettingsManager.shared.allowedDeviceIDs)
    }

    private func regeneratePIN() {
        SettingsManager.shared.regeneratePIN()
        pin = SettingsManager.shared.pin
        showPINAlert = true
    }

    private func removeDevice(_ id: String) {
        SettingsManager.shared.removeAllowedDevice(id)
        allowedDevices.removeAll { $0 == id }
    }
}

// MARK: - General Tab
private struct GeneralTab: View {
    @Binding var pin: String
    @Binding var launchAtLogin: Bool
    @Binding var showPINAlert: Bool
    let onRegeneratePIN: () -> Void

    var body: some View {
        Form {
            Section("Pairing PIN") {
                HStack {
                    Text("Current PIN:")
                    Text(pin)
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundColor(.accentColor)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(pin, forType: .string)
                    }
                    Button("Regenerate") { onRegeneratePIN() }
                }
                Text("Enter this PIN in the iOS app to pair your iPhone.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { new in
                        SettingsManager.shared.launchAtLogin = new
                    }
            }

            Section("Network") {
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Bonjour service running on port 7642")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Devices Tab
private struct DevicesTab: View {
    @Binding var devices: [String]
    let onRemove: (String) -> Void

    private func name(for id: String) -> String {
        SettingsManager.shared.deviceName(for: id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if devices.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No Paired Devices")
                        .font(.headline)
                    Text("Pair your iPhone using the iOS app.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(devices, id: \.self) { deviceId in
                        HStack(spacing: 10) {
                            Image(systemName: "iphone")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name(for: deviceId))
                                    .fontWeight(.medium)
                                Text(deviceId)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button("Remove") { onRemove(deviceId) }
                                .buttonStyle(.borderless)
                                .foregroundColor(.red)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: SettingsManager.devicesDidChangeNotification)) { _ in
            devices = Array(SettingsManager.shared.allowedDeviceIDs)
        }
    }
}

// MARK: - Apps Tab
private struct AppsTab: View {
    @State private var pinnedBundleIds: [String] = SettingsManager.shared.pinnedAppBundleIds
    @State private var allApps: [InstalledApp] = []
    @State private var showPicker = false

    private var pinnedApps: [InstalledApp] {
        let byId = Dictionary(uniqueKeysWithValues: allApps.map { ($0.bundleId, $0) })
        return pinnedBundleIds.compactMap { byId[$0] }
    }

    var body: some View {
        VStack(spacing: 0) {
            if pinnedBundleIds.isEmpty {
                emptyState
            } else {
                pinnedList
                HStack {
                    Spacer()
                    Button("Add Apps…") { showPicker = true }
                        .padding([.horizontal, .bottom], 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { allApps = await AppScanner.shared.installedApps() }
        .sheet(isPresented: $showPicker) {
            AppPickerSheet(pinnedBundleIds: $pinnedBundleIds) {
                SettingsManager.shared.pinnedAppBundleIds = pinnedBundleIds
                showPicker = false
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "square.grid.3x3.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No Apps Selected")
                .font(.headline)
            Text("Choose which apps appear on your iPhone.\nThe list is saved and reused on every reconnect.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Apps…") { showPicker = true }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }

    private var pinnedList: some View {
        List {
            ForEach(pinnedApps, id: \.bundleId) { app in
                HStack(spacing: 8) {
                    appIcon(for: app)
                    Text(app.name)
                    Spacer()
                    Button {
                        pinnedBundleIds.removeAll { $0 == app.bundleId }
                        SettingsManager.shared.pinnedAppBundleIds = pinnedBundleIds
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .onMove { indices, offset in
                pinnedBundleIds.move(fromOffsets: indices, toOffset: offset)
                SettingsManager.shared.pinnedAppBundleIds = pinnedBundleIds
            }
        }
    }

    @ViewBuilder
    private func appIcon(for app: InstalledApp) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
            .resizable()
            .frame(width: 22, height: 22)
    }
}

// MARK: - App Picker Sheet
private struct AppPickerSheet: View {
    @Binding var pinnedBundleIds: [String]
    let onDone: () -> Void

    @State private var allApps: [InstalledApp] = []
    @State private var isLoading = true
    @State private var search = ""

    private var filtered: [InstalledApp] {
        guard !search.isEmpty else { return allApps }
        return allApps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Apps")
                    .font(.headline)
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            if isLoading {
                Spacer()
                ProgressView("Loading apps…")
                Spacer()
            } else {
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                List(filtered, id: \.bundleId) { app in
                    let selected = pinnedBundleIds.contains(app.bundleId)
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                            .resizable()
                            .frame(width: 22, height: 22)
                        Text(app.name)
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selected {
                            pinnedBundleIds.removeAll { $0 == app.bundleId }
                        } else {
                            pinnedBundleIds.append(app.bundleId)
                        }
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
        .task {
            allApps = await AppScanner.shared.installedApps()
            isLoading = false
        }
    }
}

// MARK: - About Tab
private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("MacLauncher Remote")
                .font(.title2.bold())
            Text("Version \(Bundle.main.shortVersionString ?? "1.0")")
                .foregroundColor(.secondary)
            Divider()
            Text("Control your Mac apps from your iPhone over Wi-Fi.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Spacer()
            Link("Download iOS App", destination: URL(string: "https://apps.apple.com/app/id-REPLACE")!)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

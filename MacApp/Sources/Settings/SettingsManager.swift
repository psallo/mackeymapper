import Foundation
import AppKit
import ServiceManagement

final class SettingsManager {
    static let shared = SettingsManager()
    private init() {}

    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Key {
        static let pin = "serverPIN"
        static let allowedDevices = "allowedDeviceIDs"
        static let allowedDeviceNames = "allowedDeviceNames"
        static let launchAtLogin = "launchAtLogin"
        static let pinnedCertFingerprints = "pinnedCertFingerprints"
        static let pinnedAppBundleIds = "pinnedAppBundleIds"
    }

    static let devicesDidChangeNotification = Notification.Name("SettingsManagerDevicesDidChange")

    // MARK: - Properties
    var pin: String {
        get { defaults.string(forKey: Key.pin) ?? generateDefaultPIN() }
        set { defaults.set(newValue, forKey: Key.pin) }
    }

    var allowedDeviceIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.allowedDevices) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.allowedDevices) }
    }

    // deviceId → deviceName
    var allowedDeviceNames: [String: String] {
        get { defaults.dictionary(forKey: Key.allowedDeviceNames) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.allowedDeviceNames) }
    }

    func deviceName(for deviceId: String) -> String {
        allowedDeviceNames[deviceId] ?? "Unknown Device"
    }

    // Ordered list of bundle IDs to send to iPhone. Empty = legacy full scan.
    var pinnedAppBundleIds: [String] {
        get { defaults.stringArray(forKey: Key.pinnedAppBundleIds) ?? [] }
        set { defaults.set(newValue, forKey: Key.pinnedAppBundleIds) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set {
            defaults.set(newValue, forKey: Key.launchAtLogin)
            applyLaunchAtLogin(newValue)
        }
    }

    // MARK: - Lifecycle
    func load() {
        if defaults.string(forKey: Key.pin) == nil {
            defaults.set(generateDefaultPIN(), forKey: Key.pin)
        }
    }

    func addAllowedDevice(_ deviceId: String, name: String = "") {
        var ids = allowedDeviceIDs
        ids.insert(deviceId)
        allowedDeviceIDs = ids
        if !name.isEmpty {
            var names = allowedDeviceNames
            names[deviceId] = name
            allowedDeviceNames = names
        }
        NotificationCenter.default.post(name: Self.devicesDidChangeNotification, object: nil)
    }

    func removeAllowedDevice(_ deviceId: String) {
        var ids = allowedDeviceIDs
        ids.remove(deviceId)
        allowedDeviceIDs = ids
        var names = allowedDeviceNames
        names.removeValue(forKey: deviceId)
        allowedDeviceNames = names
        NotificationCenter.default.post(name: Self.devicesDidChangeNotification, object: nil)
    }

    func isDeviceAllowed(_ deviceId: String) -> Bool {
        return allowedDeviceIDs.contains(deviceId)
    }

    func regeneratePIN() {
        defaults.set(generateDefaultPIN(), forKey: Key.pin)
        allowedDeviceIDs = []
        allowedDeviceNames = [:]
        NotificationCenter.default.post(name: Self.devicesDidChangeNotification, object: nil)
    }

    // MARK: - Private
    private func generateDefaultPIN() -> String {
        let pin = String(format: "%04d", Int.random(in: 1000...9999))
        defaults.set(pin, forKey: Key.pin)
        return pin
    }

    private func applyLaunchAtLogin(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Launch at login error: \(error)")
            }
        }
    }
}

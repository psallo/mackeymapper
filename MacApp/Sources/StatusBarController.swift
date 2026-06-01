import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem
    private var server: BonjourServer?
    private var settingsWindow: NSWindow?
    private let updaterController: (any AnyObject)?   // Sparkle 제거됨 (테스트용)

    // Observable state for the menu
    private var connectedCount = 0
    private var isServerRunning = false

    init(updaterController: (any AnyObject)?) {
        self.updaterController = updaterController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItem()
        startServer()
    }

    // MARK: - Status Item
    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: "MacLauncher Remote")
            button.image?.isTemplate = true
        }
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        // Status header
        let statusItem = NSMenuItem(title: menuTitle(), action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(.separator())

        // PIN display
        let pin = SettingsManager.shared.pin
        let pinItem = NSMenuItem(title: "Pairing PIN:  \(pin)", action: #selector(copyPIN), keyEquivalent: "")
        pinItem.target = self
        menu.addItem(pinItem)

        // Regenerate PIN
        let regenItem = NSMenuItem(title: "Regenerate PIN", action: #selector(regeneratePIN), keyEquivalent: "")
        regenItem.target = self
        menu.addItem(regenItem)

        menu.addItem(.separator())

        // Connected devices
        let devicesItem = NSMenuItem(title: "Connected Devices: \(connectedCount)", action: nil, keyEquivalent: "")
        devicesItem.isEnabled = false
        menu.addItem(devicesItem)

        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit MacLauncher Remote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    private func menuTitle() -> String {
        if isServerRunning {
            return connectedCount > 0 ? "● Connected (\(connectedCount))" : "● Running"
        }
        return "○ Stopped"
    }

    // MARK: - Server
    private func startServer() {
        let srv = BonjourServer()
        server = srv
        Task {
            await srv.configure(delegate: self)
            do {
                try await srv.start()
                isServerRunning = true
                buildMenu()
            } catch {
                isServerRunning = false
                buildMenu()
                showError("서버 시작 실패: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Actions
    @objc private func copyPIN() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SettingsManager.shared.pin, forType: .string)
    }

    @objc private func regeneratePIN() {
        SettingsManager.shared.regeneratePIN()
        buildMenu()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView()
            let hostingView = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "MacLauncher Remote — Settings"
            window.contentView = hostingView
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "MacLauncher Remote Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

// MARK: - BonjourServerDelegate
extension StatusBarController: BonjourServerDelegate {
    nonisolated func serverDidChangeConnectionCount(_ count: Int) {
        Task { @MainActor in
            self.connectedCount = count
            self.buildMenu()
        }
    }

    nonisolated func serverDidEncounterError(_ error: Error) {
        Task { @MainActor in
            self.showError(error.localizedDescription)
        }
    }
}

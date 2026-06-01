import Foundation
import SwiftUI

// MARK: - BonjourBrowserDelegate
extension AppState: BonjourBrowserDelegate {
    func browser(didFind server: DiscoveredServer) {
        if !discoveredServers.contains(server) {
            discoveredServers.append(server)
        }
        // Auto-connect if only one server and not yet connected
        if discoveredServers.count == 1 && !connectionState.isConnected {
            connect(to: server)
        }
    }

    func browser(didLose server: DiscoveredServer) {
        discoveredServers.removeAll { $0.id == server.id }
        if selectedServer?.id == server.id {
            disconnect()
        }
    }

    func browserDidUpdateResults(_ servers: [DiscoveredServer]) {
        discoveredServers = servers
    }
}

// MARK: - RemoteConnectionDelegate
extension AppState: RemoteConnectionDelegate {
    func connectionDidReceiveServerInfo(_ info: ServerInfoMessage) {
        connectedMacName = info.macName
        serverCertFingerprint = info.certFingerprint
        connectionState = .connecting

        // 등록된 기기는 빈 PIN으로 자동 재연결 시도 (Mac이 기기 ID로 승인)
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let deviceName = DeviceInfo.displayName
        isAutoAuthPending = true
        Task { await connection?.sendAuth(pin: "", deviceId: deviceId, deviceName: deviceName) }
    }

    func connectionAuthDidSucceed(sessionToken: String, certFingerprint: String) {
        isAutoAuthPending = false
        connectionState = .connected
        isPairingSheetPresented = false
        if storedCertFingerprint == nil {
            storedCertFingerprint = certFingerprint
        }
        refreshApps()
    }

    func connectionAuthDidFail(reason: String) {
        if isAutoAuthPending {
            // 자동 인증 실패 → 신규 기기: PIN 입력창 표시
            isAutoAuthPending = false
            connectionState = .pairing
            isPairingSheetPresented = true
        } else {
            connectionState = .failed(reason)
            isPairingSheetPresented = false
        }
    }

    func connectionDidReceiveApps(_ apps: [AppInfoPayload], isFinal: Bool) {
        let newApps = apps.map { payload in
            let data = payload.iconBase64.flatMap { Data(base64Encoded: $0) }
            return RemoteApp(id: payload.bundleId, name: payload.name, iconData: data, orderIndex: payload.orderIndex)
        }
        remoteApps.append(contentsOf: newApps)

        if isFinal {
            // pinned(orderIndex 있음): 지정 순서 / 미지정: 이름순
            if remoteApps.allSatisfy({ $0.orderIndex != nil }) {
                remoteApps.sort { ($0.orderIndex ?? 0) < ($1.orderIndex ?? 0) }
            } else {
                remoteApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
            isLoadingApps = false
        }
    }

    func connectionDidReceiveLaunchResult(success: Bool) {
        if !success {
            launchFeedback = LaunchFeedback(appName: "App")
        }
    }

    func connectionDidDisconnect() {
        connectionState = .idle
        remoteApps = []
        isLoadingApps = false
        connection = nil
        connectedMacName = ""
        Task { await browser.start(delegate: self) }
    }
}

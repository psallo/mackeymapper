import Foundation
import Network

private let kServiceType = "_maclauncher._tcp."
private let kPort: NWEndpoint.Port = 7642

// MARK: - Delegate
@MainActor
protocol BonjourServerDelegate: AnyObject {
    func serverDidChangeConnectionCount(_ count: Int)
    func serverDidEncounterError(_ error: Error)
}

// MARK: - Server
actor BonjourServer: ClientSessionDelegate {
    private weak var delegate: BonjourServerDelegate?

    func configure(delegate: any BonjourServerDelegate) {
        self.delegate = delegate
    }

    private var listener: NWListener?
    private var sessions: [String: ClientSession] = [:]   // sessionToken → session

    private let settings = SettingsManager.shared
    private let scanner  = AppScanner.shared
    private let extractor = IconExtractor.shared
    private let launcher  = AppLauncher.shared
    private let certMgr   = CertificateManager.shared

    // MARK: - Start / Stop

    func start() throws {
        NSLog("✅ BonjourServer.start() 진입")
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        let listener = try NWListener(using: params, on: kPort)

        let macName = Host.current().localizedName ?? "Mac"
        listener.service = NWListener.Service(
            name: "MacLauncherRemote-\(macName)",
            type:  kServiceType
        )

        listener.newConnectionHandler = { [weak self] conn in
            Task { [weak self] in await self?.acceptConnection(conn) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in await self?.handleListenerState(state) }
        }

        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
        NSLog("✅ NWListener.start() 호출 완료 — 포트 7642")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        Task {
            for session in sessions.values { await session.close() }
            sessions.removeAll()
        }
    }

    // MARK: - Connection handling

    private func acceptConnection(_ connection: NWConnection) async {
        // Send server info immediately (before auth)
        let fingerprint = ""  // TLS 비활성화 중 — 배포 전 복원
        let info = ServerInfoMessage(
            macName: Host.current().localizedName ?? "Mac",
            version: Bundle.main.shortVersionString,
            certFingerprint: fingerprint
        )
        if let data = try? MessageFramer.frame(info) {
            connection.send(content: data, completion: .contentProcessed({ _ in }))
        }

        // Create an unauthenticated session (deviceId/Name filled in after auth)
        let session = ClientSession(connection: connection, deviceId: "", deviceName: "pending")
        await session.configure(delegate: self)
        sessions[session.id] = session
        await session.start()

        await notifyCountChanged()
    }

    // MARK: - ClientSessionDelegate

    func session(_ session: ClientSession, didReceiveData data: Data) async {
        do {
            let msg = try MessageDecoder.decode(data: data)
            await dispatch(msg, session: session)
        } catch {
            let errMsg = ErrorMessage(code: "decode_error", message: error.localizedDescription)
            if let reply = try? MessageFramer.frame(errMsg) { await session.send(reply) }
        }
    }

    func sessionDidDisconnect(_ session: ClientSession) async {
        sessions.removeValue(forKey: session.id)
        await notifyCountChanged()
    }

    // MARK: - Message dispatch

    private func dispatch(_ message: Any, session: ClientSession) async {
        switch message {
        case let req as AuthRequestMessage:
            await handleAuth(req, session: session)

        case let req as GetAppsMessage:
            guard await validate(token: req.sessionToken, session: session) else { return }
            await handleGetApps(req: req, session: session)

        case let req as LaunchAppMessage:
            guard await validate(token: req.sessionToken, session: session) else { return }
            await handleLaunch(req.bundleId, session: session)

        case is PingMessage:
            if let reply = try? MessageFramer.frame(PongMessage()) { await session.send(reply) }

        default:
            break
        }
    }

    // MARK: - Auth

    private func handleAuth(_ req: AuthRequestMessage, session: ClientSession) async {
        // 이미 등록된 기기: PIN 없이 자동 승인 + 이름 갱신
        if settings.isDeviceAllowed(req.deviceId) {
            settings.addAllowedDevice(req.deviceId, name: req.deviceName)
            await session.markAuthenticated()
            let resp = AuthResponseMessage(success: true, error: nil, sessionToken: session.id, certFingerprint: "")
            if let data = try? MessageFramer.frame(resp) { await session.send(data) }
            return
        }

        // 신규 기기: PIN 검증
        guard req.pin == settings.pin else {
            let resp = AuthResponseMessage(success: false, error: "Invalid PIN", sessionToken: nil, certFingerprint: nil)
            if let data = try? MessageFramer.frame(resp) { await session.send(data) }
            return
        }

        settings.addAllowedDevice(req.deviceId, name: req.deviceName)
        await session.markAuthenticated()
        let resp = AuthResponseMessage(success: true, error: nil, sessionToken: session.id, certFingerprint: "")
        if let data = try? MessageFramer.frame(resp) { await session.send(data) }
    }

    // MARK: - Get Apps

    private func handleGetApps(req: GetAppsMessage, session: ClientSession) async {
        let allApps = await scanner.installedApps()
        let pinnedIds = settings.pinnedAppBundleIds

        let source: [InstalledApp]
        let preserveOrder: Bool
        if pinnedIds.isEmpty {
            source = Array(allApps.prefix(20))
            preserveOrder = false
        } else {
            let byId = Dictionary(uniqueKeysWithValues: allApps.map { ($0.bundleId, $0) })
            source = pinnedIds.compactMap { byId[$0] }
            preserveOrder = true
        }

        guard !source.isEmpty else {
            let resp = AppsResponseMessage(apps: [], isFinal: true)
            if let data = try? MessageFramer.frame(resp) { await session.send(data) }
            return
        }

        let iconSize = CGSize(width: CGFloat(req.iconPixelSize ?? 120),
                              height: CGFloat(req.iconPixelSize ?? 120))
        let extractor = self.extractor

        // 병렬 추출 후 완료되는 순서대로 즉시 전송
        var remaining = source.count
        await withTaskGroup(of: AppInfoPayload.self) { group in
            for (index, app) in source.enumerated() {
                group.addTask {
                    let icon = await extractor.iconBase64(for: app.bundleURL, size: iconSize)
                    return AppInfoPayload(
                        bundleId: app.bundleId,
                        name: app.name,
                        iconBase64: icon,
                        orderIndex: preserveOrder ? index : nil
                    )
                }
            }

            for await payload in group {
                remaining -= 1
                let resp = AppsResponseMessage(apps: [payload], isFinal: remaining == 0)
                if let data = try? MessageFramer.frame(resp) { await session.send(data) }
            }
        }
    }

    // MARK: - Launch

    private func handleLaunch(_ bundleId: String, session: ClientSession) async {
        let success = await launcher.launch(bundleId: bundleId)
        let resp = LaunchResponseMessage(success: success, error: success ? nil : "Launch failed")
        if let data = try? MessageFramer.frame(resp) { await session.send(data) }
    }

    // MARK: - Helpers

    private func validate(token: String, session: ClientSession) async -> Bool {
        let ok = await session.authenticated && sessions[token] != nil
        if !ok {
            let err = ErrorMessage(code: "unauthorized", message: "Not authenticated")
            if let data = try? MessageFramer.frame(err) { await session.send(data) }
        }
        return ok
    }

    private func notifyCountChanged() async {
        let count = sessions.count
        await delegate?.serverDidChangeConnectionCount(count)
    }

    private func handleListenerState(_ state: NWListener.State) async {
        switch state {
        case .failed(let err):
            await delegate?.serverDidEncounterError(err)
        default:
            break
        }
    }
}


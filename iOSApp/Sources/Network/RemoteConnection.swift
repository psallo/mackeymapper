import Foundation
import Network
import CommonCrypto

// MARK: - Delegate
@MainActor
protocol RemoteConnectionDelegate: AnyObject {
    func connectionDidReceiveServerInfo(_ info: ServerInfoMessage)
    func connectionAuthDidSucceed(sessionToken: String, certFingerprint: String)
    func connectionAuthDidFail(reason: String)
    func connectionDidReceiveApps(_ apps: [AppInfoPayload], isFinal: Bool)
    func connectionDidReceiveLaunchResult(success: Bool)
    func connectionDidDisconnect()
}

// MARK: - Connection
actor RemoteConnection {
    private var connection: NWConnection?
    private var sessionToken: String?
    private var receiveBuffer: [UInt8] = []
    private weak var delegate: RemoteConnectionDelegate?
    private var pinnedFingerprint: String?

    // Heartbeat: 5초마다 Ping, 10초 내 Pong 없으면 연결 끊김 처리
    private var heartbeatTask: Task<Void, Never>?
    private var lastPongDate: Date = .distantPast
    private let pingInterval: TimeInterval = 5
    private let pongTimeout: TimeInterval = 10

    // MARK: - Connect

    func connect(to endpoint: NWEndpoint, delegate: RemoteConnectionDelegate) async {
        self.delegate = delegate
        self.pinnedFingerprint = await MainActor.run { AppState.shared.storedCertFingerprint }

        // TODO: 배포 전 TLS 복원
        // let tlsOptions = makeClientTLSOptions()
        // let params = NWParameters(tls: tlsOptions)
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        let conn = NWConnection(to: endpoint, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in await self?.handleState(state) }
        }
        conn.start(queue: .global(qos: .userInitiated))
        scheduleReceive(conn)
    }

    func disconnect() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        connection?.cancel()
        connection = nil
    }

    // MARK: - Send

    func sendAuth(pin: String, deviceId: String, deviceName: String) async {
        let msg = AuthRequestMessage(pin: pin, deviceId: deviceId, deviceName: deviceName)
        send(msg)
    }

    func sendGetApps(iconPixelSize: Int = 120) async {
        guard let token = sessionToken else { return }
        let msg = GetAppsMessage(sessionToken: token, iconPixelSize: iconPixelSize)
        send(msg)
    }

    func sendLaunch(bundleId: String) async {
        guard let token = sessionToken else { return }
        let msg = LaunchAppMessage(sessionToken: token, bundleId: bundleId)
        send(msg)
    }

    // MARK: - TLS

    private func makeClientTLSOptions() -> NWProtocolTLS.Options {
        let opts = NWProtocolTLS.Options()
        let pinned = pinnedFingerprint
        sec_protocol_options_set_verify_block(
            opts.securityProtocolOptions,
            { metadata, trust, complete in
                if let pinned {
                    // After first pairing, verify cert fingerprint
                    let fingerprint = Self.fingerprintForTrust(trust)
                    complete(fingerprint == pinned)
                } else {
                    // First connection (pairing): accept any cert from local network
                    complete(true)
                }
            },
            .global(qos: .userInitiated)
        )
        return opts
    }

    private static func fingerprintForTrust(_ trust: sec_trust_t) -> String {
        let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
        let certCount = SecTrustGetCertificateCount(secTrust)
        guard certCount > 0 else { return "" }
        guard let cert = SecTrustGetCertificateAtIndex(secTrust, 0) else { return "" }
        let data = SecCertificateCopyData(cert) as Data
        return CryptoHelper.sha256Hex(data)
    }

    // MARK: - Receive loop

    private func scheduleReceive(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4 * 1024 * 1024) { [weak self] data, _, isDone, error in
            Task { [weak self] in
                guard let self else { return }
                if let data { await self.appendAndDrain(data) }
                if isDone || error != nil {
                    await self.delegate?.connectionDidDisconnect()
                } else if let current = await self.connection, current === conn {
                    self.scheduleReceive(conn)
                }
            }
        }
    }

    private func appendAndDrain(_ incoming: Data) async {
        receiveBuffer.append(contentsOf: incoming)
        while receiveBuffer.count >= 4 {
            // 명시적 바이트 조합 — Data.subdata 범위 문제 방지
            let length = (UInt32(receiveBuffer[0]) << 24)
                       | (UInt32(receiveBuffer[1]) << 16)
                       | (UInt32(receiveBuffer[2]) << 8)
                       |  UInt32(receiveBuffer[3])

            guard length > 0, length < 10_000_000 else {
                receiveBuffer.removeAll()  // 잘못된 길이 → 버퍼 초기화
                break
            }

            let totalNeeded = 4 + Int(length)
            guard receiveBuffer.count >= totalNeeded else { break }

            let messageData = Data(receiveBuffer[4..<totalNeeded])
            receiveBuffer.removeFirst(totalNeeded)
            await handleMessage(data: messageData)
        }
    }

    private func handleMessage(data: Data) async {
        guard let msg = try? MessageDecoder.decode(data: data) else { return }
        switch msg {
        case let info as ServerInfoMessage:
            await delegate?.connectionDidReceiveServerInfo(info)

        case let resp as AuthResponseMessage:
            if resp.success, let token = resp.sessionToken {
                sessionToken = token
                lastPongDate = Date()
                startHeartbeat()
                let fingerprint = resp.certFingerprint ?? ""
                await delegate?.connectionAuthDidSucceed(sessionToken: token, certFingerprint: fingerprint)
            } else {
                await delegate?.connectionAuthDidFail(reason: resp.error ?? "Authentication failed")
            }

        case let resp as AppsResponseMessage:
            await delegate?.connectionDidReceiveApps(resp.apps, isFinal: resp.isFinal)

        case let resp as LaunchResponseMessage:
            await delegate?.connectionDidReceiveLaunchResult(success: resp.success)

        case is PingMessage:
            send(PongMessage())

        case is PongMessage:
            lastPongDate = Date()

        default:
            break
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pingInterval))
                guard !Task.isCancelled else { break }
                send(PingMessage())
                if Date().timeIntervalSince(lastPongDate) > pongTimeout {
                    await delegate?.connectionDidDisconnect()
                    break
                }
            }
        }
    }

    private func handleState(_ state: NWConnection.State) async {
        switch state {
        case .failed, .cancelled:
            await delegate?.connectionDidDisconnect()
        default:
            break
        }
    }

    // MARK: - Helpers

    private func send(_ msg: some Encodable) {
        guard let conn = connection, let data = try? MessageFramer.frame(msg) else { return }
        conn.send(content: data, completion: .contentProcessed({ _ in }))
    }
}

// MARK: - SHA-256 helper (avoid CryptoKit import in actor)
enum CryptoHelper {
    static func sha256Hex(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

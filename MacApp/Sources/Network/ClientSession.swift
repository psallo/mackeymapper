import Foundation
import Network

// Represents one authenticated iPhone connection.
actor ClientSession {
    let id: String           // stable session token
    let deviceId: String
    let deviceName: String
    private let connection: NWConnection
    private var receiveBuffer: [UInt8] = []
    private var isAuthenticated = false

    private weak var delegate: ClientSessionDelegate?

    init(connection: NWConnection, deviceId: String, deviceName: String) {
        self.connection = connection
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.id = UUID().uuidString
    }

    func configure(delegate: any ClientSessionDelegate) {
        self.delegate = delegate
    }

    // MARK: - Lifecycle

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in await self?.handleState(state) }
        }
        connection.start(queue: .global(qos: .userInitiated))
        scheduleReceive()
    }

    func send(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed({ _ in }))
    }

    func close() {
        connection.cancel()
    }

    func markAuthenticated() {
        isAuthenticated = true
    }

    var authenticated: Bool { isAuthenticated }

    // MARK: - Private receive loop

    private func scheduleReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4 * 1024 * 1024) { [weak self] data, _, isDone, error in
            Task { [weak self] in
                guard let self else { return }
                if let data {
                    await self.appendAndDrain(data)
                }
                if isDone || error != nil {
                    await self.delegate?.sessionDidDisconnect(self)
                } else {
                    await self.scheduleReceive()
                }
            }
        }
    }

    private func appendAndDrain(_ incoming: Data) async {
        receiveBuffer.append(contentsOf: incoming)
        while receiveBuffer.count >= 4 {
            let length = (UInt32(receiveBuffer[0]) << 24)
                       | (UInt32(receiveBuffer[1]) << 16)
                       | (UInt32(receiveBuffer[2]) << 8)
                       |  UInt32(receiveBuffer[3])

            guard length > 0, length < 10_000_000 else {
                receiveBuffer.removeAll()
                break
            }

            let totalNeeded = 4 + Int(length)
            guard receiveBuffer.count >= totalNeeded else { break }

            let messageData = Data(receiveBuffer[4..<totalNeeded])
            receiveBuffer.removeFirst(totalNeeded)
            await delegate?.session(self, didReceiveData: messageData)
        }
    }

    private func handleState(_ state: NWConnection.State) async {
        switch state {
        case .failed, .cancelled:
            await delegate?.sessionDidDisconnect(self)
        default:
            break
        }
    }
}

// MARK: - Delegate
protocol ClientSessionDelegate: AnyObject {
    func session(_ session: ClientSession, didReceiveData data: Data) async
    func sessionDidDisconnect(_ session: ClientSession) async
}

import Foundation
import Network

private let kServiceType = "_maclauncher._tcp."

// MARK: - Delegate
@MainActor
protocol BonjourBrowserDelegate: AnyObject {
    func browser(didFind server: DiscoveredServer)
    func browser(didLose server: DiscoveredServer)
    func browserDidUpdateResults(_ servers: [DiscoveredServer])
}

// MARK: - Browser
actor BonjourBrowser {
    private var nwBrowser: NWBrowser?
    private weak var delegate: BonjourBrowserDelegate?
    private var discovered: [String: DiscoveredServer] = [:]

    func start(delegate: BonjourBrowserDelegate) async {
        self.delegate = delegate
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: kServiceType, domain: nil), using: params)
        self.nwBrowser = browser

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { [weak self] in await self?.handleChanges(changes) }
        }
        browser.stateUpdateHandler = { _ in }
        browser.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        nwBrowser?.cancel()
        nwBrowser = nil
    }

    // MARK: - Private

    private func handleChanges(_ changes: Set<NWBrowser.Result.Change>) async {
        for change in changes {
            switch change {
            case .added(let result):
                if let server = makeServer(from: result) {
                    discovered[server.id] = server
                    await delegate?.browser(didFind: server)
                }
            case .removed(let result):
                let key = result.endpoint.debugDescription
                if let server = discovered.removeValue(forKey: key) {
                    await delegate?.browser(didLose: server)
                }
            default:
                break
            }
        }
        let all = Array(discovered.values)
        await delegate?.browserDidUpdateResults(all)
    }

    private func makeServer(from result: NWBrowser.Result) -> DiscoveredServer? {
        let key = result.endpoint.debugDescription
        var name = "Mac"
        if case .bonjour(let record) = result.metadata {
            _ = record  // TXT record if needed in future
        }
        // Extract readable name from endpoint
        if case .service(let svcName, _, _, _) = result.endpoint {
            name = svcName
                .replacingOccurrences(of: "MacLauncherRemote-", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        return DiscoveredServer(id: key, name: name, endpoint: result.endpoint)
    }
}

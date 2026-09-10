import Foundation
import Network
import Observation
import os

/// Asks macOS for Local Network access explicitly.
@Observable
@MainActor
final class LocalNetworkPermission {
    enum Status: Equatable {
        case unknown
        case requesting
        case granted
        case denied(String)
    }

    private(set) var status: Status = .unknown
    private var browser: NWBrowser?
    private let logger = Logger(subsystem: "com.unblu.UnbluMeet", category: "LocalNetwork")

    func request() {
        browser?.cancel()
        status = .requesting

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: parameters)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    // Browsing started, so the local network is reachable to us.
                    self.status = .granted
                    self.logger.info("Local network browse ready — access granted")
                case .waiting(let error), .failed(let error):
                    self.status = .denied("\(error)")
                    self.logger.error("Local network browse blocked: \(error.localizedDescription, privacy: .public)")
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { _, _ in }
        browser.start(queue: .main)

        // The prompt appears while browsing; a few seconds is plenty, and
        // leaving it running would keep scanning the network for nothing.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.browser?.cancel()
            self?.browser = nil
        }
    }
}

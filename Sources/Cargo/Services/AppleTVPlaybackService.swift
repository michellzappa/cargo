import Foundation
import ItsytvCore
import Observation

/// The small Apple TV surface Cargo needs: discover/pair a TV and send an
/// Infuse library deep link to it. The Companion protocol calls its URL field
/// `_bundleID`; ItsytvCore exposes that wire value as `launchApp(bundleID:)`,
/// and tvOS accepts both bundle identifiers and app URLs there.
@MainActor
final class AppleTVPlaybackService {
    enum PlayResult {
        case sent
        case needsSetup
    }

    let manager = AppleTVManager()
    var onChange: (() -> Void)?
    private var hasStarted = false

    init() {
        observeManager()
    }

    var devices: [AppleTVDevice] {
        manager.discoveredDevices.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var connectedDeviceName: String? { manager.connectedDeviceName }

    var isConnected: Bool {
        manager.connectionStatus == .connected
    }

    var statusText: String {
        switch manager.connectionStatus {
        case .disconnected:
            return hasStarted ? (devices.isEmpty ? "Looking for Apple TVs…" : "Not connected") : "Not configured"
        case .connecting:
            return connectedDeviceName.map { "Connecting to \($0)…" } ?? "Connecting…"
        case .pairing:
            return connectedDeviceName.map { "Enter the PIN shown on \($0)" } ?? "Enter the PIN shown on Apple TV"
        case .connected:
            return connectedDeviceName.map { "Connected to \($0) · Ready" } ?? "Connected · Ready"
        case .error(let message):
            return message
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        // Unit tests must not scan the local network or read Apple TV Keychain credentials.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        manager.startScanning()
        if manager.lastConnectedDeviceID != nil {
            _ = manager.connectToLastConnectedDevice()
        }
        notifyChange()
    }

    func refresh() {
        start()
        manager.refreshScanning()
        notifyChange()
    }

    func connect(to device: AppleTVDevice) {
        manager.connect(to: device)
        notifyChange()
    }

    func submitPIN(_ pin: String) {
        let normalized = pin.filter(\.isNumber)
        guard normalized.count == 4 else {
            return
        }
        manager.submitPIN(normalized)
        notifyChange()
    }

    func disconnect() {
        manager.disconnect()
        notifyChange()
    }

    func play(metadata: TMDBMetadata) -> PlayResult {
        play(metadata: metadata, season: nil, episode: nil)
    }

    func play(metadata: TMDBMetadata, season: Int?, episode: Int?) -> PlayResult {
        start()
        // A saved device ID is not proof that the current Companion session is
        // alive. Returning `.sent` here used to make the phone button appear
        // to work while the command was merely queued or dropped.
        guard isConnected else {
            return .needsSetup
        }

        let kind = metadata.mediaType == .movie ? "movie" : "series"
        // Firecore documents `?play` as the autoplay flag for TMDB deep links.
        let suffix: String
        if let season, let episode, metadata.mediaType == .tv {
            suffix = "-\(season)-\(episode)"
        } else {
            suffix = ""
        }
        let deepLink = "infuse://\(kind)/\(metadata.tmdbID)\(suffix)?play"
        manager.launchURL(deepLink)
        return .sent
    }

    private func notifyChange() {
        onChange?()
    }

    private func observeManager() {
        withObservationTracking {
            _ = manager.connectionStatus
            _ = manager.discoveredDevices
            _ = manager.connectedDeviceName
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.notifyChange()
                self.observeManager()
            }
        }
    }
}

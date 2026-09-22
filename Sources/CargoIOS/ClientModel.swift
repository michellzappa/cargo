import CargoRemoteKit
import Foundation
import Observation
import Security

enum CargoStartTab: String, CaseIterable, Identifiable {
    case transfers
    case files
    case library
    case discover
    case watchlist
    case inbox
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transfers: "Transfers"
        case .files: "Files"
        case .library: "Library"
        case .discover: "Discover"
        case .watchlist: "Watchlist"
        case .inbox: "Inbox"
        case .history: "History"
        case .settings: "Settings"
        }
    }
}

@MainActor
@Observable
final class CargoClientModel {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(String)
        case failed(String)

        var label: String {
            switch self {
            case .disconnected: "Not connected"
            case .connecting: "Connecting…"
            case .connected(let resident): "Connected to \(resident)"
            case .failed(let message): message
            }
        }
    }

    var snapshot: CargoRemoteSnapshot?
    var searchState: CargoRemoteSearchState?
    var connectionState: ConnectionState = .disconnected
    var residentAddress = ""
    var startTab: CargoStartTab
    var lastError: String?
    var actionError: String?

    private(set) var hasSavedToken = false
    private var api: CargoRemoteAPIClient?
    private var presence: CargoRemotePresence?
    private var eventRevision: UInt64?
    private var pollTask: Task<Void, Never>?
    private var restoreAttempted = false
    private let credentials = CargoIOSCredentials()
    private let clientID: UUID
    private let defaultClientName = "Cargo iPhone"
    private let snapshotCacheURL: URL

    init() {
        residentAddress = UserDefaults.standard.string(forKey: "residentAddress") ?? ""
        startTab = CargoStartTab(rawValue: UserDefaults.standard.string(forKey: "startTab") ?? "") ?? .transfers
        clientID = UserDefaults.standard.string(forKey: "clientID").flatMap(UUID.init) ?? UUID()
        UserDefaults.standard.set(clientID.uuidString, forKey: "clientID")
        hasSavedToken = credentials.readToken() != nil
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        snapshotCacheURL = applicationSupport.appendingPathComponent("CargoIOS/snapshot.json")
        snapshot = Self.readSnapshot(from: snapshotCacheURL)
    }

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var hasSavedResident: Bool {
        hasSavedToken && !residentAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func displayTitle(for rawName: String) -> String {
        CargoRemoteMediaTitle.clean(rawName)
    }

    func posterURL(for rawName: String) -> String? {
        let wanted = normalize(displayTitle(for: rawName))
        guard !wanted.isEmpty else { return nil }
        return snapshot?.library.compactMap { item -> String? in
            guard let poster = item.metadata?.posterURL else { return nil }
            let candidate = normalize([item.title, item.year.map(String.init)].compactMap { $0 }.joined(separator: " "))
            return candidate == wanted || candidate.contains(wanted) || wanted.contains(candidate) ? poster : nil
        }.first
    }

    func setStartTab(_ tab: CargoStartTab) {
        startTab = tab
        UserDefaults.standard.set(tab.rawValue, forKey: "startTab")
    }

    private func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }

    func restoreConnection() async {
        guard !restoreAttempted else { return }
        restoreAttempted = true
        guard !residentAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              hasSavedToken else { return }
        await connect(address: residentAddress, token: "", clearSnapshot: false)
    }

    func retrySavedConnection() async {
        restoreAttempted = false
        await restoreConnection()
    }

    func connect(address: String, token: String, clientName: String = "", clearSnapshot: Bool = true) async {
        await disconnect(clearSnapshot: clearSnapshot)
        connectionState = .connecting
        lastError = nil

        var address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        var suppliedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pairing = CargoPairingLink(parsing: address) {
            address = pairing.serverURL
            suppliedToken = pairing.token
        }
        guard let baseURL = Self.baseURL(from: address) else {
            fail("Enter a valid http:// or https:// Cargo address.")
            return
        }
        let resolvedToken = suppliedToken.isEmpty ? credentials.readToken() : suppliedToken
        guard let resolvedToken, !resolvedToken.isEmpty else {
            fail("Paste the resident Cargo token or open a pairing link.")
            return
        }

        let remote = CargoRemoteAPIClient(baseURL: baseURL, token: resolvedToken)
        do {
            let health = try await remote.health()
            guard health.apiVersion == "v1" else {
                fail("This resident uses an unsupported Cargo API version.")
                return
            }
            let name = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
            let registration = CargoRemotePresenceRegistration(
                id: clientID,
                name: name.isEmpty ? defaultClientName : name,
                platform: "iOS"
            )
            let remotePresence = try await remote.registerPresence(registration)
            let remoteSnapshot = try await remote.snapshot()

            api = remote
            presence = remotePresence
            updateSnapshot(remoteSnapshot)
            eventRevision = nil
            residentAddress = baseURL.absoluteString
            UserDefaults.standard.set(residentAddress, forKey: "residentAddress")
            try credentials.saveToken(resolvedToken)
            hasSavedToken = true
            connectionState = .connected(remotePresence.residentName)
            startPolling()
        } catch {
            fail(error.localizedDescription)
        }
    }

    func connect(pairingURL: URL) async {
        guard let link = CargoPairingLink(parsing: pairingURL) else { return }
        await connect(address: link.serverURL, token: link.token)
    }

    func disconnect(clearSnapshot: Bool = true) async {
        pollTask?.cancel()
        pollTask = nil
        if let api, presence != nil {
            _ = try? await api.unregisterPresence(clientID: clientID)
        }
        api = nil
        presence = nil
        eventRevision = nil
        connectionState = .disconnected
        if clearSnapshot { snapshot = nil }
    }

    func refresh() async {
        guard let api else { return }
        do {
            async let remotePresence = api.presence()
            async let remoteSnapshot = api.snapshot()
            presence = try await remotePresence
            updateSnapshot(try await remoteSnapshot)
            connectionState = .connected(presence?.residentName ?? "Cargo")
            lastError = nil
        } catch {
            fail(error.localizedDescription)
        }
    }

    func execute(_ command: CargoRemoteCommand) async {
        guard let api else { return }
        do {
            updateSnapshot(try await api.execute(command))
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    func search(query: String) async {
        guard let api else { return }
        do {
            searchState = try await api.search(query: query)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    func setActive(_ active: Bool) {
        if active {
            if isConnected {
                startPolling()
                Task { await refresh() }
            }
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self else { return }
                await self.pollOnce()
            }
        }
    }

    private func pollOnce() async {
        guard let api else { return }
        do {
            do {
                presence = try await api.heartbeatPresence(clientID: clientID)
            } catch CargoRemoteAPIClient.ClientError.api(let error) where error.code == "presence_peer_not_found" {
                let registration = CargoRemotePresenceRegistration(id: clientID, name: defaultClientName, platform: "iOS")
                presence = try await api.registerPresence(registration)
                eventRevision = nil
            }
            let event = try await api.events(since: eventRevision)
            eventRevision = event.revision
            if event.changed {
                if let eventSnapshot = event.snapshot {
                    updateSnapshot(eventSnapshot)
                } else {
                    updateSnapshot(try await api.snapshot())
                }
            }
            connectionState = .connected(presence?.residentName ?? "Cargo")
        } catch {
            fail("Connection lost: \(error.localizedDescription)")
        }
    }

    private func fail(_ message: String) {
        connectionState = .failed(message)
        lastError = message
    }

    private func updateSnapshot(_ value: CargoRemoteSnapshot) {
        snapshot = value
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: snapshotCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(value).write(to: snapshotCacheURL, options: .atomic)
        } catch {
            // A cache failure must never make a successful resident request fail.
        }
    }

    private static func readSnapshot(from url: URL) -> CargoRemoteSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CargoRemoteSnapshot.self, from: data)
    }

    private static func baseURL(from value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil else { return nil }
        return url
    }
}

private struct CargoIOSCredentials {
    private let service = "app.cargo.CargoIOS"
    private let account = "resident-token"

    func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CredentialsError.saveFailed }
        } else if status != errSecSuccess {
            throw CredentialsError.saveFailed
        }
    }

    private enum CredentialsError: LocalizedError {
        case saveFailed

        var errorDescription: String? { "Cargo could not save the resident token." }
    }
}

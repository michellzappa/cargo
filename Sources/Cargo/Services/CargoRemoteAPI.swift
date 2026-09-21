import Foundation
import os

struct CargoAPIRequest: Sendable {
    let method: String
    let uri: String
    let headers: [String: String]
    let body: Data

    var path: String {
        uri.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? uri
    }
}

struct CargoAPIResponse: Sendable {
    let statusCode: Int
    let requestID: String
    let body: Data
}

struct CargoAPIError: Codable, Equatable, Sendable {
    let code: String
    let message: String
}

struct CargoAPIEnvelope<Payload: Codable>: Codable {
    let ok: Bool
    let requestID: String
    let data: Payload?
    let error: CargoAPIError?

    static func success(_ payload: Payload, requestID: String) -> Self {
        Self(ok: true, requestID: requestID, data: payload, error: nil)
    }

    static func failure(_ error: CargoAPIError, requestID: String) -> Self {
        Self(ok: false, requestID: requestID, data: nil, error: error)
    }
}

struct CargoAPIHealth: Codable, Equatable, Sendable {
    let status: String
    let apiVersion: String
    let generatedAt: Date
}

struct CargoAPISearchRequest: Codable, Equatable, Sendable {
    let query: String
}

struct CargoRemoteEvent: Codable, Equatable, Sendable {
    let revision: UInt64
    let changed: Bool
    let snapshot: CargoRemoteSnapshot?
}

/// A monotonic change token shared by the resident API and its future
/// streaming transport. The current HTTP transport exposes it as a small,
/// pollable event feed.
@MainActor
final class CargoRemoteEventFeed {
    private(set) var revision: UInt64 = 0

    func publish() {
        revision &+= 1
    }

    func event(since: UInt64?, snapshot: CargoRemoteSnapshot) -> CargoRemoteEvent {
        let changed = since.map { $0 != revision } ?? true
        return CargoRemoteEvent(
            revision: revision,
            changed: changed,
            snapshot: changed ? snapshot : nil
        )
    }
}

enum CargoRemoteAPIError: Error, Equatable, Sendable {
    case unauthorized
    case badRequest(String)
    case notFound
    case commandTargetNotFound(String)
    case presencePeerNotFound(UUID)
    case commandFailed(String)
    case methodNotAllowed
    case requestTooLarge
    case internalFailure

    var response: (statusCode: Int, code: String, message: String) {
        switch self {
        case .unauthorized:
            (401, "unauthorized", "A bearer token is required.")
        case .badRequest(let message):
            (400, "bad_request", message)
        case .notFound:
            (404, "not_found", "The requested API route does not exist.")
        case .commandTargetNotFound(let target):
            (404, "command_target_not_found", "Cargo could not find \(target). Refresh and try again.")
        case .presencePeerNotFound(let id):
            (404, "presence_peer_not_found", "Cargo does not have a connected client with id \(id.uuidString.lowercased()).")
        case .commandFailed(let message):
            (409, "command_failed", message)
        case .methodNotAllowed:
            (405, "method_not_allowed", "The HTTP method is not supported for this route.")
        case .requestTooLarge:
            (413, "request_too_large", "The request body is too large.")
        case .internalFailure:
            (500, "internal_error", "Cargo could not complete the request.")
        }
    }
}

/// Routes API requests to the remote-control boundary. This type has no
/// knowledge of NIO or sockets, which keeps the API contract directly
/// testable without starting Cargo or opening a port.
@MainActor
final class CargoRemoteAPIRouter {
    private let controller: CargoRemoteControlling
    private let token: String
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private let eventFeed: CargoRemoteEventFeed
    private let presenceRegistry: CargoRemotePresenceRegistry
    private let logger = Logger(subsystem: "app.cargo.Cargo", category: "remote-api")

    init(
        controller: CargoRemoteControlling,
        token: String,
        eventFeed: CargoRemoteEventFeed = CargoRemoteEventFeed(),
        presenceRegistry: CargoRemotePresenceRegistry = CargoRemotePresenceRegistry()
    ) {
        self.controller = controller
        self.token = token
        self.eventFeed = eventFeed
        self.presenceRegistry = presenceRegistry
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func handle(_ request: CargoAPIRequest) async -> CargoAPIResponse {
        let requestID = UUID().uuidString.lowercased()
        let response: CargoAPIResponse
        do {
            guard isAuthorized(request) || isPublicDiscovery(request) else {
                throw CargoRemoteAPIError.unauthorized
            }
            response = try await route(request, requestID: requestID)
        } catch let error as CargoRemoteAPIError {
            response = failure(error, requestID: requestID)
        } catch {
            logger.error("request \(requestID, privacy: .public) failed with an unexpected error")
            response = failure(.internalFailure, requestID: requestID)
        }

        logger.info(
            "request \(requestID, privacy: .public) \(request.method, privacy: .public) \(request.path, privacy: .public) -> \(response.statusCode, privacy: .public)"
        )
        return response
    }

    private func route(_ request: CargoAPIRequest, requestID: String) async throws -> CargoAPIResponse {
        switch (request.path) {
        case "/v1/discovery":
            guard request.method == "GET" else { throw CargoRemoteAPIError.methodNotAllowed }
            let resident = presenceRegistry.snapshot()
            return success(
                CargoRemoteDiscovery(
                    service: "Cargo",
                    apiVersion: "v1",
                    instanceID: presenceRegistry.residentID,
                    name: resident.residentName,
                    port: CargoHTTPServer.Configuration.defaultPort
                ),
                requestID: requestID
            )
        case "/v1/health":
            guard request.method == "GET" else { throw CargoRemoteAPIError.methodNotAllowed }
            return success(
                CargoAPIHealth(status: "ok", apiVersion: "v1", generatedAt: Date()),
                requestID: requestID
            )
        case "/v1/state":
            guard request.method == "GET" else { throw CargoRemoteAPIError.methodNotAllowed }
            return success(controller.snapshot(), requestID: requestID)
        case "/v1/events":
            guard request.method == "GET" else { throw CargoRemoteAPIError.methodNotAllowed }
            return try events(request, requestID: requestID)
        case "/v1/presence":
            guard request.method == "GET" else { throw CargoRemoteAPIError.methodNotAllowed }
            return success(presenceRegistry.snapshot(), requestID: requestID)
        case "/v1/presence/register":
            guard request.method == "POST" else { throw CargoRemoteAPIError.methodNotAllowed }
            return try registerPresence(request, requestID: requestID)
        case "/v1/presence/heartbeat":
            guard request.method == "POST" else { throw CargoRemoteAPIError.methodNotAllowed }
            return try heartbeatPresence(request, requestID: requestID)
        case "/v1/presence/unregister":
            guard request.method == "POST" else { throw CargoRemoteAPIError.methodNotAllowed }
            return try unregisterPresence(request, requestID: requestID)
        case "/v1/transfers":
            guard request.method == "GET" else { throw CargoRemoteAPIError.methodNotAllowed }
            return success(controller.snapshot().transfers, requestID: requestID)
        case "/v1/files":
            guard request.method == "GET" else { throw CargoRemoteAPIError.methodNotAllowed }
            return success(controller.snapshot().files, requestID: requestID)
        case "/v1/inbox":
            guard request.method == "GET" else { throw CargoRemoteAPIError.methodNotAllowed }
            return success(controller.snapshot().syncJobs, requestID: requestID)
        case "/v1/library":
            guard request.method == "GET" else { throw CargoRemoteAPIError.methodNotAllowed }
            return success(controller.snapshot().library, requestID: requestID)
        case "/v1/watchlist":
            guard request.method == "GET" else { throw CargoRemoteAPIError.methodNotAllowed }
            return success(controller.snapshot().watchlist, requestID: requestID)
        case "/v1/discover/catalog":
            guard request.method == "GET" else { throw CargoRemoteAPIError.methodNotAllowed }
            return success(controller.snapshot().chillCatalog, requestID: requestID)
        case "/v1/discover/search":
            guard request.method == "POST" else { throw CargoRemoteAPIError.methodNotAllowed }
            return try await search(request, requestID: requestID)
        case "/v1/commands":
            guard request.method == "POST" else { throw CargoRemoteAPIError.methodNotAllowed }
            return try await command(request, requestID: requestID)
        default:
            throw CargoRemoteAPIError.notFound
        }
    }

    private func search(_ request: CargoAPIRequest, requestID: String) async throws -> CargoAPIResponse {
        guard request.body.count <= 64 * 1024 else {
            throw CargoRemoteAPIError.requestTooLarge
        }
        let payload: CargoAPISearchRequest
        do {
            payload = try decoder.decode(CargoAPISearchRequest.self, from: request.body)
        } catch {
            throw CargoRemoteAPIError.badRequest("Expected a JSON body with a query string.")
        }
        let query = payload.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw CargoRemoteAPIError.badRequest("The query cannot be empty.")
        }
        let snapshot = try await controller.execute(.searchChill(query: query))
        return success(snapshot.chillSearch, requestID: requestID)
    }

    private func events(_ request: CargoAPIRequest, requestID: String) throws -> CargoAPIResponse {
        let since: UInt64?
        if let value = URLComponents(string: "http://cargo.local\(request.uri)")?.queryItems?.first(where: { $0.name == "since" })?.value {
            guard let parsed = UInt64(value) else {
                throw CargoRemoteAPIError.badRequest("The since value must be an unsigned integer.")
            }
            since = parsed
        } else {
            since = nil
        }
        return success(
            eventFeed.event(since: since, snapshot: controller.snapshot()),
            requestID: requestID
        )
    }

    private func command(_ request: CargoAPIRequest, requestID: String) async throws -> CargoAPIResponse {
        guard request.body.count <= 64 * 1024 else {
            throw CargoRemoteAPIError.requestTooLarge
        }

        let command: CargoRemoteCommand
        do {
            command = try decoder.decode(CargoRemoteCommand.self, from: request.body)
        } catch {
            throw CargoRemoteAPIError.badRequest("Expected a JSON remote command.")
        }

        do {
            let snapshot = try await controller.execute(command)
            return success(snapshot, requestID: requestID)
        } catch let error as CargoRemoteControlError {
            switch error {
            case .targetNotFound(let target):
                throw CargoRemoteAPIError.commandTargetNotFound(target)
            }
        } catch let error as LocalizedError {
            throw CargoRemoteAPIError.commandFailed(error.errorDescription ?? "Cargo rejected the command.")
        }
    }

    private func registerPresence(_ request: CargoAPIRequest, requestID: String) throws -> CargoAPIResponse {
        let registration: CargoRemotePresenceRegistration = try decodePresenceBody(
            request,
            message: "Expected a JSON Cargo client registration."
        )
        let name = registration.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120 else {
            throw CargoRemoteAPIError.badRequest("The Cargo client name must be between 1 and 120 characters.")
        }
        return success(
            presenceRegistry.register(CargoRemotePresenceRegistration(
                id: registration.id,
                name: name,
                platform: registration.platform
            )),
            requestID: requestID
        )
    }

    private func heartbeatPresence(_ request: CargoAPIRequest, requestID: String) throws -> CargoAPIResponse {
        let heartbeat: CargoRemotePresenceHeartbeat = try decodePresenceBody(
            request,
            message: "Expected a JSON Cargo client heartbeat."
        )
        guard let presence = presenceRegistry.heartbeat(heartbeat) else {
            throw CargoRemoteAPIError.presencePeerNotFound(heartbeat.id)
        }
        return success(presence, requestID: requestID)
    }

    private func unregisterPresence(_ request: CargoAPIRequest, requestID: String) throws -> CargoAPIResponse {
        let heartbeat: CargoRemotePresenceHeartbeat = try decodePresenceBody(
            request,
            message: "Expected a JSON Cargo client identity."
        )
        guard let presence = presenceRegistry.unregister(heartbeat) else {
            throw CargoRemoteAPIError.presencePeerNotFound(heartbeat.id)
        }
        return success(presence, requestID: requestID)
    }

    private func decodePresenceBody<Payload: Decodable>(
        _ request: CargoAPIRequest,
        message: String
    ) throws -> Payload {
        guard request.body.count <= 64 * 1024 else {
            throw CargoRemoteAPIError.requestTooLarge
        }
        do {
            return try decoder.decode(Payload.self, from: request.body)
        } catch {
            throw CargoRemoteAPIError.badRequest(message)
        }
    }

    private func isAuthorized(_ request: CargoAPIRequest) -> Bool {
        guard let authorization = request.headers["authorization"] else { return false }
        let parts = authorization.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return false }
        return constantTimeEquals(parts[1], token)
    }

    private func isPublicDiscovery(_ request: CargoAPIRequest) -> Bool {
        request.path == "/v1/discovery" && request.method == "GET"
    }

    private func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }

    private func success<Payload: Codable>(
        _ payload: Payload,
        requestID: String
    ) -> CargoAPIResponse {
        let envelope = CargoAPIEnvelope.success(payload, requestID: requestID)
        return response(statusCode: 200, envelope: envelope, requestID: requestID)
    }

    private func failure(_ error: CargoRemoteAPIError, requestID: String) -> CargoAPIResponse {
        let details = error.response
        let envelope = CargoAPIEnvelope<EmptyPayload>.failure(
            CargoAPIError(code: details.code, message: details.message),
            requestID: requestID
        )
        return response(statusCode: details.statusCode, envelope: envelope, requestID: requestID)
    }

    private func response<Payload: Codable>(
        statusCode: Int,
        envelope: CargoAPIEnvelope<Payload>,
        requestID: String
    ) -> CargoAPIResponse {
        let body = (try? encoder.encode(envelope)) ?? Data(
            #"{"ok":false,"requestID":"\#(requestID)","data":null,"error":{"code":"internal_error","message":"Cargo could not encode the response."}}"#.utf8
        )
        return CargoAPIResponse(statusCode: statusCode, requestID: requestID, body: body)
    }

    private struct EmptyPayload: Codable {}
}

/// Small transport client for a future remote UI or companion app. It speaks
/// the same envelope and command contract as CargoRemoteAPIRouter.
final class CargoRemoteAPIClient: @unchecked Sendable {
    enum ClientError: LocalizedError {
        case invalidResponse
        case api(CargoAPIError)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Cargo returned an invalid HTTP response."
            case .api(let error):
                "Cargo API error \(error.code): \(error.message)"
            case .malformedResponse:
                "Cargo returned malformed API data."
            }
        }
    }

    let baseURL: URL
    private let token: String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    static func discover(at baseURL: URL, session: URLSession = .shared) async throws -> CargoRemoteDiscovery {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/discovery"))
        request.httpMethod = "GET"
        request.timeoutInterval = 0.8
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 300 else {
            throw ClientError.invalidResponse
        }
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(CargoAPIEnvelope<CargoRemoteDiscovery>.self, from: data)
        guard envelope.ok, let discovery = envelope.data, discovery.service == "Cargo" else {
            throw ClientError.malformedResponse
        }
        return discovery
    }

    func health() async throws -> CargoAPIHealth {
        try await get("/v1/health")
    }

    func snapshot() async throws -> CargoRemoteSnapshot {
        try await get("/v1/state")
    }

    func events(since: UInt64? = nil) async throws -> CargoRemoteEvent {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/events"), resolvingAgainstBaseURL: false)
        if let since {
            components?.queryItems = [URLQueryItem(name: "since", value: String(since))]
        }
        guard let url = components?.url else { throw ClientError.invalidResponse }
        return try await request(url: url)
    }

    func presence() async throws -> CargoRemotePresence {
        try await get("/v1/presence")
    }

    func registerPresence(_ registration: CargoRemotePresenceRegistration) async throws -> CargoRemotePresence {
        try await post("/v1/presence/register", body: registration)
    }

    func heartbeatPresence(clientID: UUID) async throws -> CargoRemotePresence {
        try await post(
            "/v1/presence/heartbeat",
            body: CargoRemotePresenceHeartbeat(id: clientID)
        )
    }

    func unregisterPresence(clientID: UUID) async throws -> CargoRemotePresence {
        try await post(
            "/v1/presence/unregister",
            body: CargoRemotePresenceHeartbeat(id: clientID)
        )
    }

    func execute(_ command: CargoRemoteCommand) async throws -> CargoRemoteSnapshot {
        let body = try encoder.encode(command)
        return try await request(
            url: baseURL.appendingPathComponent("v1/commands"),
            method: "POST",
            body: body
        )
    }

    private func get<Payload: Codable>(_ path: String) async throws -> Payload {
        try await request(url: baseURL.appendingPathComponent(path))
    }

    private func post<Body: Encodable, Payload: Codable>(_ path: String, body: Body) async throws -> Payload {
        try await request(
            url: baseURL.appendingPathComponent(path),
            method: "POST",
            body: encoder.encode(body)
        )
    }

    private func request<Payload: Codable>(
        url: URL,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> Payload {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        let envelope: CargoAPIEnvelope<Payload>
        do {
            envelope = try decoder.decode(CargoAPIEnvelope<Payload>.self, from: data)
        } catch {
            throw ClientError.malformedResponse
        }
        guard http.statusCode < 300, envelope.ok, let payload = envelope.data else {
            throw ClientError.api(
                envelope.error ?? CargoAPIError(code: "invalid_response", message: "Cargo returned an unsuccessful response.")
            )
        }
        return payload
    }
}

struct CargoTailscaleServer: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let address: String
    let platform: String

    var displayName: String { "\(name) · \(address)" }
}

enum CargoTailscaleDiscoveryError: LocalizedError, Equatable {
    case notInstalled
    case unavailable
    case invalidStatus
    case commandFailed

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Tailscale is not installed on this Mac."
        case .unavailable:
            "Tailscale is not connected or its peer list is unavailable."
        case .invalidStatus:
            "Tailscale returned an unrecognized peer list."
        case .commandFailed:
            "Cargo could not read the Tailscale peer list."
        }
    }
}

/// Finds Cargo peers through Tailscale's local CLI, then verifies each peer by
/// asking for Cargo's low-information discovery response. MagicDNS names are
/// preferred, with the peer's 100.x address as a fallback.
@MainActor
final class CargoTailscaleDiscovery {
    private struct Status: Decodable {
        let selfNode: Node?
        let peers: [String: Node]?

        enum CodingKeys: String, CodingKey {
            case selfNode = "Self"
            case peers = "Peer"
        }
    }

    private struct Node: Decodable {
        let dnsName: String?
        let hostName: String?
        let operatingSystem: String?
        let online: Bool?
        let tailscaleIPs: [String]?

        enum CodingKeys: String, CodingKey {
            case dnsName = "DNSName"
            case hostName = "HostName"
            case operatingSystem = "OS"
            case online = "Online"
            case tailscaleIPs = "TailscaleIPs"
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func findServers() async throws -> [CargoTailscaleServer] {
        let data = try await Self.runStatus()
        let status: Status
        do {
            status = try JSONDecoder().decode(Status.self, from: data)
        } catch {
            throw CargoTailscaleDiscoveryError.invalidStatus
        }

        let selfNames = Set([
            status.selfNode?.dnsName,
            status.selfNode?.hostName
        ].compactMap { $0?.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() })
        let candidates = (status.peers ?? [:]).compactMap { _, node -> (String, Node)? in
            guard node.online != false else { return nil }
            let dnsName = node.dnsName?.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let hostName = node.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard let host = dnsName ?? hostName,
                  !selfNames.contains(host.lowercased()) else { return nil }
            return (host, node)
        }

        return await withTaskGroup(of: CargoTailscaleServer?.self) { group in
            for (host, node) in candidates {
                group.addTask { [session] in
                    let hosts = [host] + (node.tailscaleIPs ?? []).filter { $0 != host }
                    for candidate in hosts {
                        guard let url = URL(string: "http://\(candidate):\(CargoHTTPServer.Configuration.defaultPort)") else { continue }
                        guard let discovery = try? await CargoRemoteAPIClient.discover(at: url, session: session) else { continue }
                        return CargoTailscaleServer(
                            id: discovery.instanceID,
                            name: discovery.name,
                            address: "http://\(candidate):\(discovery.port)",
                            platform: node.operatingSystem ?? "Tailscale peer"
                        )
                    }
                    return nil
                }
            }

            var seen = Set<UUID>()
            var servers: [CargoTailscaleServer] = []
            for await server in group {
                guard let server, seen.insert(server.id).inserted else { continue }
                servers.append(server)
            }
            return servers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    nonisolated static func parseStatus(_ data: Data) throws -> [(name: String, address: String, platform: String)] {
        let status: Status
        do {
            status = try JSONDecoder().decode(Status.self, from: data)
        } catch {
            throw CargoTailscaleDiscoveryError.invalidStatus
        }
        return (status.peers ?? [:]).compactMap { _, node in
            guard let name = node.dnsName ?? node.hostName,
                  let address = node.tailscaleIPs?.first else { return nil }
            return (name: name, address: address, platform: node.operatingSystem ?? "")
        }
    }

    private static func runStatus() async throws -> Data {
        guard let executable = executablePath() else {
            throw CargoTailscaleDiscoveryError.notInstalled
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = ["status", "--json"]
                process.standardOutput = output
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else {
                        continuation.resume(throwing: CargoTailscaleDiscoveryError.unavailable)
                        return
                    }
                    continuation.resume(returning: output.fileHandleForReading.readDataToEndOfFile())
                } catch {
                    continuation.resume(throwing: CargoTailscaleDiscoveryError.commandFailed)
                }
            }
        }
    }

    private static func executablePath() -> String? {
        let candidates = [
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
            "/opt/homebrew/bin/tailscale",
            "/usr/local/bin/tailscale"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// A client-mode session used by the same Cargo app when it connects to a
/// resident Cargo. The session owns presence registration and heartbeats; the
/// eventual remote dashboard can consume `snapshot` and `presence` directly.
@MainActor
final class CargoRemoteClientSession {
    static let didChange = Notification.Name("CargoRemoteClientSession.didChange")

    let clientID: UUID
    let defaultClientName: String
    private let keychain: KeychainStore
    private(set) var client: CargoRemoteAPIClient?
    private(set) var presence: CargoRemotePresence?
    private(set) var snapshot: CargoRemoteSnapshot?
    private(set) var status = "Not connected"
    private var heartbeatTask: Task<Void, Never>?
    private var eventRevision: UInt64?

    var isConnected: Bool { client != nil && presence != nil }

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
        self.clientID = (try? keychain.ensureRemoteClientID()) ?? UUID()
        self.defaultClientName = Host.current().localizedName ?? "Cargo"
    }

    deinit {
        heartbeatTask?.cancel()
    }

    func connect(baseURLString: String, token: String, clientName: String? = nil) async {
        await disconnect()

        guard let baseURL = Self.baseURL(from: baseURLString) else {
            status = "Enter a valid http:// or https:// Cargo address"
            notifyChange()
            return
        }

        let resolvedToken = token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? keychain.readRemoteClientToken()
            : token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolvedToken, !resolvedToken.isEmpty else {
            status = "Paste the resident Cargo token"
            notifyChange()
            return
        }

        do {
            try keychain.saveRemoteClientToken(resolvedToken)
            let remoteClient = CargoRemoteAPIClient(baseURL: baseURL, token: resolvedToken)
            _ = try await remoteClient.health()
            let resolvedName = clientName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let registration = CargoRemotePresenceRegistration(
                id: clientID,
                name: resolvedName.flatMap { $0.isEmpty ? nil : $0 } ?? defaultClientName,
                platform: "macOS"
            )
            let remotePresence = try await remoteClient.registerPresence(registration)
            let remoteSnapshot = try await remoteClient.snapshot()
            client = remoteClient
            presence = remotePresence
            snapshot = remoteSnapshot
            eventRevision = nil
            status = "Connected to \(remotePresence.residentName)"
            notifyChange()
            startHeartbeat()
        } catch {
            client = nil
            presence = nil
            snapshot = nil
            status = error.localizedDescription
            notifyChange()
        }
    }

    func refresh() async {
        guard let client else { return }
        do {
            async let remotePresence = client.presence()
            async let remoteSnapshot = client.snapshot()
            presence = try await remotePresence
            snapshot = try await remoteSnapshot
            status = "Connected to \(presence?.residentName ?? "Cargo")"
        } catch {
            status = error.localizedDescription
        }
        notifyChange()
    }

    func execute(_ command: CargoRemoteCommand) async throws -> CargoRemoteSnapshot {
        guard let client else { throw CargoRemoteAPIClient.ClientError.invalidResponse }
        let remoteSnapshot = try await client.execute(command)
        snapshot = remoteSnapshot
        notifyChange()
        return remoteSnapshot
    }

    func disconnect() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        if let client, presence != nil {
            _ = try? await client.unregisterPresence(clientID: clientID)
        }
        client = nil
        presence = nil
        snapshot = nil
        eventRevision = nil
        status = "Not connected"
        notifyChange()
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, let client = self.client else { return }
                do {
                    self.presence = try await client.heartbeatPresence(clientID: self.clientID)
                    let event = try await client.events(since: self.eventRevision)
                    self.eventRevision = event.revision
                    if event.changed {
                        if let eventSnapshot = event.snapshot {
                            self.snapshot = eventSnapshot
                        } else {
                            self.snapshot = try await client.snapshot()
                        }
                    }
                    self.status = "Connected to \(self.presence?.residentName ?? "Cargo")"
                } catch {
                    self.status = "Connection lost: \(error.localizedDescription)"
                }
                self.notifyChange()
            }
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private static func baseURL(from value: String) -> URL? {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if !normalized.contains("://") { normalized = "http://\(normalized)" }
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else { return nil }
        return url
    }
}

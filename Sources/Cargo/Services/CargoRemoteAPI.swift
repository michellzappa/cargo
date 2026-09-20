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

struct CargoAPIEnvelope<Payload: Encodable>: Encodable {
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

enum CargoRemoteAPIError: Error, Equatable, Sendable {
    case unauthorized
    case badRequest(String)
    case notFound
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
    private let logger = Logger(subsystem: "app.cargo.Cargo", category: "remote-api")

    init(controller: CargoRemoteControlling, token: String) {
        self.controller = controller
        self.token = token
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func handle(_ request: CargoAPIRequest) async -> CargoAPIResponse {
        let requestID = UUID().uuidString.lowercased()
        let response: CargoAPIResponse
        do {
            guard isAuthorized(request) else {
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
        case "/v1/health":
            guard request.method == "GET" else { throw CargoRemoteAPIError.methodNotAllowed }
            return success(
                CargoAPIHealth(status: "ok", apiVersion: "v1", generatedAt: Date()),
                requestID: requestID
            )
        case "/v1/state":
            guard request.method == "GET" else { throw CargoRemoteAPIError.methodNotAllowed }
            return success(controller.snapshot(), requestID: requestID)
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

    private func isAuthorized(_ request: CargoAPIRequest) -> Bool {
        guard let authorization = request.headers["authorization"] else { return false }
        let parts = authorization.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return false }
        return constantTimeEquals(parts[1], token)
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

    private func success<Payload: Encodable>(
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

    private func response<Payload: Encodable>(
        statusCode: Int,
        envelope: CargoAPIEnvelope<Payload>,
        requestID: String
    ) -> CargoAPIResponse {
        let body = (try? encoder.encode(envelope)) ?? Data(
            #"{"ok":false,"requestID":"\#(requestID)","data":null,"error":{"code":"internal_error","message":"Cargo could not encode the response."}}"#.utf8
        )
        return CargoAPIResponse(statusCode: statusCode, requestID: requestID, body: body)
    }

    private struct EmptyPayload: Encodable {}
}

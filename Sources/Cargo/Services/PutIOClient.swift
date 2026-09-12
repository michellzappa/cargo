import Foundation

protocol PutIOClient: Sendable {
    func fetchAccount() async throws -> PutIOAccountSummary
    func fetchTransfers() async throws -> [RemoteTransfer]
    func fetchFiles(parentID: Int) async throws -> [RemoteFile]
    func downloadFile(fileID: Int, to destinationURL: URL) async throws
    func deleteFile(fileID: Int) async throws
}

struct UnconfiguredPutIOClient: PutIOClient {
    enum ClientError: LocalizedError {
        case notConfigured

        var errorDescription: String? {
            "Put.io is not connected yet."
        }
    }

    func fetchAccount() async throws -> PutIOAccountSummary {
        throw ClientError.notConfigured
    }

    func fetchTransfers() async throws -> [RemoteTransfer] {
        throw ClientError.notConfigured
    }

    func fetchFiles(parentID: Int) async throws -> [RemoteFile] {
        throw ClientError.notConfigured
    }

    func downloadFile(fileID: Int, to destinationURL: URL) async throws {
        throw ClientError.notConfigured
    }

    func deleteFile(fileID: Int) async throws {
        throw ClientError.notConfigured
    }
}

struct PutIOAccountSummary: Sendable, Equatable {
    let id: Int
    let username: String
}

struct PutIOAPIClient: PutIOClient {
    enum ClientError: LocalizedError {
        case missingToken
        case invalidResponse
        case requestFailed(String)
        case api(statusCode: Int, message: String)
        case destinationAlreadyExists

        var errorDescription: String? {
            switch self {
            case .missingToken:
                "Put.io access token is missing."
            case .invalidResponse:
                "Put.io returned an invalid response."
            case .requestFailed(let message):
                message
            case .api(let statusCode, let message):
                "Put.io returned HTTP \(statusCode): \(message)"
            case .destinationAlreadyExists:
                "A file already exists at the local destination."
            }
        }
    }

    private let token: String
    private let baseURL: URL
    private let session: URLSession

    init(
        token: String,
        baseURL: URL = URL(string: "https://api.put.io/v2")!,
        session: URLSession = .shared
    ) {
        self.token = token
        self.baseURL = baseURL
        self.session = session
    }

    func fetchAccount() async throws -> PutIOAccountSummary {
        let envelope: PutIOAccountEnvelope = try await request(path: "account/info")
        return PutIOAccountSummary(id: envelope.info.userID, username: envelope.info.username)
    }

    func fetchTransfers() async throws -> [RemoteTransfer] {
        let envelope: PutIOTransferListEnvelope = try await request(
            path: "transfers/list",
            queryItems: [URLQueryItem(name: "per_page", value: "100")]
        )
        return envelope.transfers.map(Self.mapTransfer)
    }

    func fetchFiles(parentID: Int) async throws -> [RemoteFile] {
        let envelope: PutIOFileListEnvelope = try await request(
            path: "files/list",
            queryItems: [
                URLQueryItem(name: "parent_id", value: String(parentID)),
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "no_cursor", value: "1")
            ]
        )
        return envelope.files.map(Self.mapFile)
    }

    func downloadFile(fileID: Int, to destinationURL: URL) async throws {
        guard !token.isEmpty else { throw ClientError.missingToken }

        let url = baseURL.appendingPathComponent("files/\(fileID)/download")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60 * 60
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let temporaryURL: URL
        let response: URLResponse
        do {
            (temporaryURL, response) = try await session.download(for: request)
        } catch {
            throw ClientError.requestFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.api(statusCode: httpResponse.statusCode, message: "Download failed.")
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: temporaryURL)
            throw ClientError.destinationAlreadyExists
        }

        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw ClientError.requestFailed("Could not place the downloaded file on the SSD.")
        }
    }

    func deleteFile(fileID: Int) async throws {
        guard !token.isEmpty else { throw ClientError.missingToken }

        let url = baseURL.appendingPathComponent("files/delete")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data("file_ids=\(fileID)".utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientError.requestFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = Self.apiErrorMessage(from: data) ?? "Delete failed."
            throw ClientError.api(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        guard !token.isEmpty else { throw ClientError.missingToken }

        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw ClientError.invalidResponse
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else { throw ClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientError.requestFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = Self.apiErrorMessage(from: data) ?? "Request failed."
            throw ClientError.api(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ClientError.requestFailed("Could not decode the Put.io response.")
        }
    }

    static func mapTransfer(_ transfer: PutIOTransferPayload) -> RemoteTransfer {
        let rawProgress = transfer.percentDone ?? transfer.completionPercent ?? 0
        let progress = rawProgress > 1 ? rawProgress / 100 : rawProgress
        let boundedProgress = min(max(progress, 0), 1)

        return RemoteTransfer(
            id: transfer.id,
            name: transfer.name,
            status: mapStatus(transfer.status),
            progress: boundedProgress,
            sizeBytes: Int64(max(transfer.size ?? 0, 0)),
            updatedAt: Self.date(from: transfer.finishedAt ?? transfer.createdAt)
        )
    }

    static func mapFile(_ file: PutIOFilePayload) -> RemoteFile {
        RemoteFile(
            id: file.id,
            name: file.name,
            type: mapFileType(file.fileType),
            parentID: file.parentID ?? 0,
            sizeBytes: max(file.size ?? 0, 0),
            createdAt: Self.date(from: file.createdAt)
        )
    }

    private static func mapFileType(_ rawType: String) -> RemoteFileType {
        switch rawType.uppercased() {
        case "FOLDER": .folder
        case "VIDEO": .video
        case "AUDIO": .audio
        case "IMAGE": .image
        case "PDF": .pdf
        case "OTHER": .other
        default: .unknown
        }
    }

    private static func mapStatus(_ rawStatus: String) -> RemoteTransferStatus {
        switch rawStatus.uppercased() {
        case "COMPLETED":
            .completed
        case "ERROR":
            .failed
        case "SEEDING":
            .seeding
        case "WAITING", "PREPARING_DOWNLOAD", "IN_QUEUE", "WAITING_FOR_COMPLETE_QUEUE",
            "WAITING_FOR_DOWNLOADER", "STOPPING", "PREPARING_SEED":
            .waiting
        case "DOWNLOADING", "COMPLETING":
            .downloading
        default:
            .unknown
        }
    }

    private static func date(from value: String?) -> Date {
        guard let value, !value.isEmpty else { return Date() }
        return ISO8601DateFormatter().date(from: value) ?? Date()
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return object["error_message"] as? String
            ?? object["error"] as? String
            ?? object["message"] as? String
    }
}

struct PutIOAccountEnvelope: Decodable {
    let info: PutIOAccountPayload
}

struct PutIOAccountPayload: Decodable {
    let userID: Int
    let username: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
    }
}

struct PutIOTransferListEnvelope: Decodable {
    let transfers: [PutIOTransferPayload]
}

struct PutIOFileListEnvelope: Decodable {
    let files: [PutIOFilePayload]
}

struct PutIOFilePayload: Decodable {
    let id: Int
    let name: String
    let fileType: String
    let parentID: Int?
    let size: Int64?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fileType = "file_type"
        case parentID = "parent_id"
        case size
        case createdAt = "created_at"
    }
}

struct PutIOTransferPayload: Decodable {
    let id: Int
    let name: String
    let status: String
    let size: Double?
    let percentDone: Double?
    let completionPercent: Double?
    let createdAt: String?
    let finishedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case size
        case percentDone = "percent_done"
        case completionPercent = "completion_percent"
        case createdAt = "created_at"
        case finishedAt = "finished_at"
    }
}

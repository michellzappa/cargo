import Foundation

typealias PutIODownloadProgress = @Sendable (_ received: Int64, _ total: Int64?) -> Void

extension PutIOClient {
    func downloadFile(fileID: Int, to destinationURL: URL) async throws {
        try await downloadFile(fileID: fileID, to: destinationURL, progress: nil)
    }
}

protocol PutIOClient: Sendable {
    func fetchAccount() async throws -> PutIOAccountSummary
    func fetchTransfers() async throws -> [RemoteTransfer]
    /// `types` filters server-side (Put.io names: VIDEO, FOLDER, ARCHIVE…); nil lists everything.
    func fetchFiles(parentID: Int, types: [String]?) async throws -> [RemoteFile]
    /// Streams into `<destination>.part` and resumes from it when present;
    /// `progress` gets (bytes on disk, total bytes if known). The final file
    /// only appears at `destinationURL` once every byte has landed.
    func downloadFile(fileID: Int, to destinationURL: URL, progress: PutIODownloadProgress?) async throws
    /// `skipTrash` deletes for good; otherwise the file lands in Put.io's trash.
    func deleteFile(fileID: Int, skipTrash: Bool) async throws

    // Transfer management
    func addTransfer(url: String) async throws -> RemoteTransfer
    func cancelTransfers(ids: [Int]) async throws
    func retryTransfer(id: Int) async throws
    func cleanFinishedTransfers() async throws

    // File extras
    func downloadURL(fileID: Int) async throws -> URL
    func fetchSubtitles(fileID: Int) async throws -> [PutIOSubtitle]
    func downloadSubtitle(fileID: Int, key: String, to destinationURL: URL) async throws

    /// `files/search`: everything in the account matching `query`, any folder.
    func searchFiles(query: String) async throws -> [RemoteFile]

    // Activity, archives, trash
    func fetchEvents() async throws -> [PutIOEvent]
    func extractFiles(ids: [Int]) async throws
    func fetchExtractions() async throws -> [PutIOExtraction]
    func fetchTrash() async throws -> PutIOTrashSummary
    func emptyTrash() async throws
}

/// Defaults so lightweight clients (stubs, unconfigured) only implement the core surface.
extension PutIOClient {
    func addTransfer(url: String) async throws -> RemoteTransfer { throw UnconfiguredPutIOClient.ClientError.notConfigured }
    func cancelTransfers(ids: [Int]) async throws { throw UnconfiguredPutIOClient.ClientError.notConfigured }
    func retryTransfer(id: Int) async throws { throw UnconfiguredPutIOClient.ClientError.notConfigured }
    func cleanFinishedTransfers() async throws { throw UnconfiguredPutIOClient.ClientError.notConfigured }
    func downloadURL(fileID: Int) async throws -> URL { throw UnconfiguredPutIOClient.ClientError.notConfigured }
    func fetchSubtitles(fileID: Int) async throws -> [PutIOSubtitle] { throw UnconfiguredPutIOClient.ClientError.notConfigured }
    func downloadSubtitle(fileID: Int, key: String, to destinationURL: URL) async throws {
        throw UnconfiguredPutIOClient.ClientError.notConfigured
    }
    func searchFiles(query: String) async throws -> [RemoteFile] { [] }
    func fetchEvents() async throws -> [PutIOEvent] { [] }
    func extractFiles(ids: [Int]) async throws { throw UnconfiguredPutIOClient.ClientError.notConfigured }
    func fetchExtractions() async throws -> [PutIOExtraction] { [] }
    func fetchTrash() async throws -> PutIOTrashSummary { PutIOTrashSummary(count: 0, bytes: 0) }
    func emptyTrash() async throws { throw UnconfiguredPutIOClient.ClientError.notConfigured }

    func fetchFiles(parentID: Int) async throws -> [RemoteFile] { try await fetchFiles(parentID: parentID, types: nil) }
    func deleteFile(fileID: Int) async throws { try await deleteFile(fileID: fileID, skipTrash: false) }
}

/// One line of Put.io's activity feed (`events/list`).
struct PutIOEvent: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable { case transferCompleted, transferError, other }
    let id: Int
    let kind: Kind
    let name: String
    let fileID: Int?
    let createdAt: Date
}

/// A server-side archive extraction (`files/extractions`).
struct PutIOExtraction: Sendable, Equatable {
    enum Status: String, Sendable { case inProgress, completed, error, unknown }
    let id: Int
    let name: String
    let status: Status
    let message: String?
}

struct PutIOTrashSummary: Sendable, Equatable {
    let count: Int
    let bytes: Int64
}

struct PutIOSubtitle: Sendable, Equatable, Identifiable {
    let key: String
    let language: String
    let name: String
    let source: String

    var id: String { key }
}

struct PutIODiskUsage: Sendable, Equatable {
    let availableBytes: Int64
    let usedBytes: Int64
    let totalBytes: Int64

    var fraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }
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

    func fetchFiles(parentID: Int, types: [String]?) async throws -> [RemoteFile] {
        throw ClientError.notConfigured
    }

    func downloadFile(fileID: Int, to destinationURL: URL, progress: PutIODownloadProgress?) async throws {
        throw ClientError.notConfigured
    }

    func deleteFile(fileID: Int, skipTrash: Bool) async throws {
        throw ClientError.notConfigured
    }
}

struct PutIOAccountSummary: Sendable, Equatable {
    let id: Int
    let username: String
    var disk: PutIODiskUsage? = nil
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
        let disk = envelope.info.disk.map {
            PutIODiskUsage(availableBytes: $0.avail, usedBytes: $0.used, totalBytes: $0.size)
        }
        return PutIOAccountSummary(id: envelope.info.userID, username: envelope.info.username, disk: disk)
    }

    func fetchTransfers() async throws -> [RemoteTransfer] {
        let envelope: PutIOTransferListEnvelope = try await request(
            path: "transfers/list",
            queryItems: [URLQueryItem(name: "per_page", value: "100")]
        )
        return envelope.transfers.map(Self.mapTransfer)
    }

    func fetchFiles(parentID: Int, types: [String]?) async throws -> [RemoteFile] {
        var queryItems = [
            URLQueryItem(name: "parent_id", value: String(parentID)),
            URLQueryItem(name: "per_page", value: "1000"),
            URLQueryItem(name: "no_cursor", value: "1")
        ]
        if let types, !types.isEmpty {
            queryItems.append(URLQueryItem(name: "file_type", value: types.joined(separator: ",")))
        }
        let envelope: PutIOFileListEnvelope = try await request(path: "files/list", queryItems: queryItems)
        return envelope.files.map(Self.mapFile)
    }

    static func partialURL(for destinationURL: URL) -> URL {
        destinationURL.appendingPathExtension("part")
    }

    func downloadFile(fileID: Int, to destinationURL: URL, progress: PutIODownloadProgress?) async throws {
        guard !token.isEmpty else { throw ClientError.missingToken }
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw ClientError.destinationAlreadyExists
        }
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let partialURL = Self.partialURL(for: destinationURL)
        var resumeOffset: Int64 = 0
        if let size = try? fileManager.attributesOfItem(atPath: partialURL.path)[.size] as? NSNumber {
            resumeOffset = size.int64Value
        }

        let url = baseURL.appendingPathComponent("files/\(fileID)/download")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 120
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if resumeOffset > 0 {
            request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
        }

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw ClientError.requestFailed(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        // 206: the server honoured the range, append. 200: it did not (or we
        // asked for nothing), start over. 416: our partial is already the
        // whole file. Anything else is a real failure.
        let handle: FileHandle
        var received: Int64
        var total: Int64?
        switch httpResponse.statusCode {
        case 206:
            handle = try FileHandle(forWritingTo: partialURL)
            try handle.seekToEnd()
            received = resumeOffset
            total = Self.totalLength(fromContentRange: httpResponse.value(forHTTPHeaderField: "Content-Range"))
        case 200..<300:
            fileManager.createFile(atPath: partialURL.path, contents: nil)
            handle = try FileHandle(forWritingTo: partialURL)
            try handle.truncate(atOffset: 0)
            received = 0
            total = httpResponse.expectedContentLength > 0 ? httpResponse.expectedContentLength : nil
        case 416:
            try fileManager.moveItem(at: partialURL, to: destinationURL)
            progress?(resumeOffset, resumeOffset)
            return
        default:
            throw ClientError.api(statusCode: httpResponse.statusCode, message: "Download failed.")
        }
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        var lastReport = Date.distantPast
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 1 << 20 {
                    try handle.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if Date().timeIntervalSince(lastReport) > 1 {
                        lastReport = Date()
                        progress?(received, total)
                    }
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
            }
        } catch {
            // Keep the .part, including what was still buffered: the next
            // attempt continues from here.
            if !buffer.isEmpty, (try? handle.write(contentsOf: buffer)) != nil {
                received += Int64(buffer.count)
            }
            throw ClientError.requestFailed("Download interrupted at \(received) bytes: \(error.localizedDescription)")
        }
        try handle.close()
        if let total, received != total {
            throw ClientError.requestFailed("Download ended early at \(received) of \(total) bytes; it will resume.")
        }
        progress?(received, total ?? received)
        do {
            try fileManager.moveItem(at: partialURL, to: destinationURL)
        } catch {
            throw ClientError.requestFailed("Could not place the downloaded file on the SSD.")
        }
    }

    /// `bytes 1000-9999/10000` → 10000.
    private static func totalLength(fromContentRange header: String?) -> Int64? {
        guard let header, let slash = header.lastIndex(of: "/") else { return nil }
        return Int64(header[header.index(after: slash)...].trimmingCharacters(in: .whitespaces))
    }

    func deleteFile(fileID: Int, skipTrash: Bool) async throws {
        var form = ["file_ids": String(fileID)]
        if skipTrash { form["skip_trash"] = "true" }
        _ = try await post(path: "files/delete", form: form, failure: "Delete failed.")
    }

    func searchFiles(query: String) async throws -> [RemoteFile] {
        let envelope: PutIOFileListEnvelope = try await request(
            path: "files/search",
            queryItems: [URLQueryItem(name: "query", value: query), URLQueryItem(name: "per_page", value: "100")]
        )
        return envelope.files.map(Self.mapFile)
    }

    func fetchEvents() async throws -> [PutIOEvent] {
        let envelope: PutIOEventListEnvelope = try await request(path: "events/list")
        return envelope.events.map { event in
            let kind: PutIOEvent.Kind = switch event.type {
            case "transfer_completed": .transferCompleted
            case "transfer_error": .transferError
            default: .other
            }
            return PutIOEvent(
                id: event.id,
                kind: kind,
                name: event.transferName ?? event.fileName ?? event.type,
                fileID: event.fileID,
                createdAt: Self.date(from: event.createdAt)
            )
        }
    }

    func extractFiles(ids: [Int]) async throws {
        let list = ids.map(String.init).joined(separator: ",")
        _ = try await post(path: "files/extract", form: ["file_ids": list], failure: "Could not start extraction.")
    }

    func fetchExtractions() async throws -> [PutIOExtraction] {
        let envelope: PutIOExtractionListEnvelope = try await request(path: "files/extractions")
        return envelope.extractions.map { extraction in
            let status: PutIOExtraction.Status = switch extraction.status?.uppercased() {
            case "IN_PROGRESS", "WAITING", "STARTED": .inProgress
            case "COMPLETED", "DONE": .completed
            case "ERROR", "FAILED": .error
            default: .unknown
            }
            return PutIOExtraction(id: extraction.id, name: extraction.name ?? "", status: status, message: extraction.message)
        }
    }

    func fetchTrash() async throws -> PutIOTrashSummary {
        let envelope: PutIOTrashListEnvelope = try await request(
            path: "trash/list",
            queryItems: [URLQueryItem(name: "per_page", value: "1000")]
        )
        return PutIOTrashSummary(
            count: envelope.total ?? envelope.files.count,
            bytes: envelope.files.reduce(0) { $0 + max($1.size ?? 0, 0) }
        )
    }

    func emptyTrash() async throws {
        _ = try await post(path: "trash/empty", form: [:], failure: "Could not empty the trash.")
    }

    func addTransfer(url: String) async throws -> RemoteTransfer {
        let data = try await post(path: "transfers/add", form: ["url": url], failure: "Could not add transfer.")
        let envelope = try decode(PutIOTransferEnvelope.self, from: data)
        return Self.mapTransfer(envelope.transfer)
    }

    func cancelTransfers(ids: [Int]) async throws {
        let list = ids.map(String.init).joined(separator: ",")
        _ = try await post(path: "transfers/cancel", form: ["transfer_ids": list], failure: "Could not cancel transfer.")
    }

    func retryTransfer(id: Int) async throws {
        _ = try await post(path: "transfers/retry", form: ["id": String(id)], failure: "Could not retry transfer.")
    }

    func cleanFinishedTransfers() async throws {
        _ = try await post(path: "transfers/clean", form: [:], failure: "Could not clean transfers.")
    }

    func downloadURL(fileID: Int) async throws -> URL {
        let envelope: PutIODownloadURLEnvelope = try await request(path: "files/\(fileID)/url")
        guard let url = URL(string: envelope.url) else { throw ClientError.invalidResponse }
        return url
    }

    func fetchSubtitles(fileID: Int) async throws -> [PutIOSubtitle] {
        let envelope: PutIOSubtitleListEnvelope = try await request(path: "files/\(fileID)/subtitles")
        return envelope.subtitles.map {
            PutIOSubtitle(key: $0.key, language: $0.language ?? "Unknown", name: $0.name, source: $0.source ?? "")
        }
    }

    func downloadSubtitle(fileID: Int, key: String, to destinationURL: URL) async throws {
        guard !token.isEmpty else { throw ClientError.missingToken }
        var request = URLRequest(url: baseURL.appendingPathComponent("files/\(fileID)/subtitles/\(key)"))
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await perform(request, failure: "Subtitle download failed.")
        _ = response
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destinationURL, options: .atomic)
    }

    // MARK: - Transport

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

        let (data, _) = try await perform(request, failure: "Request failed.")
        return try decode(Response.self, from: data)
    }

    private func post(path: String, form: [String: String], failure: String) async throws -> Data {
        guard !token.isEmpty else { throw ClientError.missingToken }

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)

        let (data, _) = try await perform(request, failure: failure)
        return data
    }

    private func perform(_ request: URLRequest, failure: String) async throws -> (Data, HTTPURLResponse) {
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
            let message = Self.apiErrorMessage(from: data) ?? failure
            throw ClientError.api(statusCode: httpResponse.statusCode, message: message)
        }
        return (data, httpResponse)
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
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
        case "ARCHIVE": .archive
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

        // Put.io normally returns RFC 3339 timestamps, sometimes with fractional
        // seconds. ISO8601DateFormatter requires the fractional-seconds option to
        // be enabled for the latter form, so try both variants before falling back.
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        // Keep compatibility with older responses that use a space instead of T.
        let legacyFormatter = DateFormatter()
        legacyFormatter.locale = Locale(identifier: "en_US_POSIX")
        legacyFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd HH:mm:ss.SSSXXXXX", "yyyy-MM-dd HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss"] {
            legacyFormatter.dateFormat = format
            if let date = legacyFormatter.date(from: value) {
                return date
            }
        }

        return Date()
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
    let disk: PutIODiskPayload?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case disk
    }
}

struct PutIODiskPayload: Decodable {
    let avail: Int64
    let used: Int64
    let size: Int64
}

struct PutIOTransferEnvelope: Decodable {
    let transfer: PutIOTransferPayload
}

struct PutIODownloadURLEnvelope: Decodable {
    let url: String
}

struct PutIOSubtitleListEnvelope: Decodable {
    let subtitles: [PutIOSubtitlePayload]
}

struct PutIOSubtitlePayload: Decodable {
    let key: String
    let language: String?
    let name: String
    let source: String?
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

struct PutIOEventListEnvelope: Decodable {
    let events: [PutIOEventPayload]
}

struct PutIOEventPayload: Decodable {
    let id: Int
    let type: String
    let transferName: String?
    let fileName: String?
    let fileID: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case transferName = "transfer_name"
        case fileName = "file_name"
        case fileID = "file_id"
        case createdAt = "created_at"
    }
}

struct PutIOExtractionListEnvelope: Decodable {
    let extractions: [PutIOExtractionPayload]
}

struct PutIOExtractionPayload: Decodable {
    let id: Int
    let name: String?
    let status: String?
    let message: String?
}

struct PutIOTrashListEnvelope: Decodable {
    let files: [PutIOFilePayload]
    let total: Int?
}

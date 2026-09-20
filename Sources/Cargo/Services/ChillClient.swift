import Foundation

/// Chill's provider-specific TV catalog sources. The aggregated request is
/// intentionally small; fetching these sources gives the Discover page a
/// useful tail for each provider filter.
enum ChillTVCatalogSource: String, CaseIterable, Codable, Sendable {
    case netflix = "TV_SHOWS_SOURCE_NETFLIX"
    case hboMax = "TV_SHOWS_SOURCE_HBO_MAX"
    case appleTVPlus = "TV_SHOWS_SOURCE_APPLE_TV_PLUS"
    case primeVideo = "TV_SHOWS_SOURCE_PRIME_VIDEO"
    case disneyPlus = "TV_SHOWS_SOURCE_DISNEY_PLUS"
    case hulu = "TV_SHOWS_SOURCE_HULU"
    case paramountPlus = "TV_SHOWS_SOURCE_PARAMOUNT_PLUS"
    case amcPlus = "TV_SHOWS_SOURCE_AMC_PLUS"
    case peacock = "TV_SHOWS_SOURCE_PEACOCK"

    var displayName: String {
        switch self {
        case .netflix: "Netflix"
        case .hboMax: "HBO Max"
        case .appleTVPlus: "Apple TV+"
        case .primeVideo: "Prime Video"
        case .disneyPlus: "Disney+"
        case .hulu: "Hulu"
        case .paramountPlus: "Paramount+"
        case .amcPlus: "AMC+"
        case .peacock: "Peacock"
        }
    }
}

/// The user-facing part of chill.institute that Cargo needs: discovery and
/// sending a selected release to the user's Put.io account.
protocol ChillClient: Sendable {
    func fetchProfile() async throws -> ChillProfile
    func search(query: String) async throws -> [ChillSearchResult]
    func fetchMovies() async throws -> [ChillMovie]
    func fetchTVShows() async throws -> [ChillTVShow]
    func fetchTVShows(source: ChillTVCatalogSource) async throws -> [ChillTVShow]
    func addTransfer(url: String) async throws -> ChillTransferResponse
    func episodeDownload(imdbID: String, season: Int, episode: Int) async throws -> ChillEpisodeDownload?
}

extension ChillClient {
    func fetchProfile() async throws -> ChillProfile { throw UnconfiguredChillClient.ClientError.notConfigured }
    func search(query: String) async throws -> [ChillSearchResult] { throw UnconfiguredChillClient.ClientError.notConfigured }
    func fetchMovies() async throws -> [ChillMovie] { throw UnconfiguredChillClient.ClientError.notConfigured }
    func fetchTVShows() async throws -> [ChillTVShow] { throw UnconfiguredChillClient.ClientError.notConfigured }
    func fetchTVShows(source: ChillTVCatalogSource) async throws -> [ChillTVShow] { try await fetchTVShows() }
    func addTransfer(url: String) async throws -> ChillTransferResponse { throw UnconfiguredChillClient.ClientError.notConfigured }
    func episodeDownload(imdbID: String, season: Int, episode: Int) async throws -> ChillEpisodeDownload? {
        throw UnconfiguredChillClient.ClientError.notConfigured
    }
}

struct ChillProfile: Codable, Equatable, Sendable {
    let userID: String
    let username: String

    enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case username
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = container.decodeString(.userID)
        username = container.decodeString(.username)
    }
}

struct ChillReleaseInfo: Codable, Equatable, Sendable {
    let title: String
    let year: Int?
    let season: Int?
    let episode: Int?
    let episodeEnd: Int?
    let resolution: String
    let quality: String
    let source: String
    let codec: String
    let hdr: String
    let audio: String
    let group: String
    let container: String
    let language: String
    let region: String
    let size: String
    let bitDepth: String
    let edition: String
    let complete: Bool

    enum CodingKeys: String, CodingKey {
        case title, year, season, episode
        case episodeEnd = "episodeEnd"
        case resolution, quality, source, codec, hdr, audio, group, container
        case language, region, size
        case bitDepth = "bitDepth"
        case edition, complete
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = values.decodeString(.title)
        year = values.decodeOptionalInt(.year)
        season = values.decodeOptionalInt(.season)
        episode = values.decodeOptionalInt(.episode)
        episodeEnd = values.decodeOptionalInt(.episodeEnd)
        resolution = values.decodeString(.resolution)
        quality = values.decodeString(.quality)
        source = values.decodeString(.source)
        codec = values.decodeString(.codec)
        hdr = values.decodeString(.hdr)
        audio = values.decodeString(.audio)
        group = values.decodeString(.group)
        container = values.decodeString(.container)
        language = values.decodeString(.language)
        region = values.decodeString(.region)
        size = values.decodeString(.size)
        bitDepth = values.decodeString(.bitDepth)
        edition = values.decodeString(.edition)
        complete = values.decodeBool(.complete)
    }

    var displayTraits: String {
        [resolution, quality, codec, hdr].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct ChillSearchResult: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let indexer: String
    let link: String
    let imdbID: String?
    let peers: Int64
    let seeders: Int64
    let size: Int64
    let source: String
    let uploadedAt: String
    let releaseInfo: ChillReleaseInfo?

    enum CodingKeys: String, CodingKey {
        case id, title, indexer, link, peers, seeders, size, source
        case imdbID = "imdbId"
        case uploadedAt = "uploadedAt"
        case releaseInfo = "releaseInfo"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeString(.id)
        title = container.decodeString(.title)
        indexer = container.decodeString(.indexer)
        link = container.decodeString(.link)
        imdbID = try container.decodeIfPresent(String.self, forKey: .imdbID)
        peers = container.decodeInt64(.peers)
        seeders = container.decodeInt64(.seeders)
        size = container.decodeInt64(.size)
        source = container.decodeString(.source)
        uploadedAt = container.decodeString(.uploadedAt)
        releaseInfo = try container.decodeIfPresent(ChillReleaseInfo.self, forKey: .releaseInfo)
    }

    var displayTraits: String {
        let traits = releaseInfo?.displayTraits ?? ""
        let availability = "\(seeders) seeders · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
        return [indexer, traits, availability].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var releaseTitle: String {
        if let releaseTitle = releaseInfo?.title, !releaseTitle.isEmpty {
            return releaseTitle
        }
        return title
    }
}

struct ChillMovie: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let year: Int
    let titlePretty: String
    let link: String
    let peers: Int64
    let seeders: Int64
    let size: Int64
    let uploadedAt: String
    let posterURL: String
    let rating: Double
    let externalURL: String
    let overview: String
    let genres: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, year, link, peers, seeders, size, rating, overview, genres
        case titlePretty = "titlePretty"
        case uploadedAt = "uploadedAt"
        case posterURL = "posterUrl"
        case externalURL = "externalUrl"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeString(.id)
        title = container.decodeString(.title)
        year = container.decodeInt(.year)
        titlePretty = container.decodeString(.titlePretty)
        link = container.decodeString(.link)
        peers = container.decodeInt64(.peers)
        seeders = container.decodeInt64(.seeders)
        size = container.decodeInt64(.size)
        uploadedAt = container.decodeString(.uploadedAt)
        posterURL = container.decodeString(.posterURL)
        rating = container.decodeDouble(.rating)
        externalURL = container.decodeString(.externalURL)
        overview = container.decodeString(.overview)
        genres = (try? container.decode([String].self, forKey: .genres)) ?? []
    }

    var displayTitle: String { titlePretty.isEmpty ? title : titlePretty }
    var posterLink: URL? { URL(string: posterURL) }
    var externalLink: URL? { URL(string: externalURL) }
    var displayTraits: String {
        let yearText = year > 0 ? String(year) : ""
        let ratingText = rating > 0 ? String(format: "%.1f ★", rating) : ""
        let availability = seeders > 0
            ? "\(seeders) seeders · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
            : "No seeders"
        return [yearText, ratingText, availability].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct ChillTVShow: Codable, Equatable, Identifiable, Sendable {
    let imdbID: String
    let title: String
    let year: Int
    let source: ChillTVCatalogSource?
    let posterURL: String
    let rating: Double
    let overview: String
    let externalURL: String
    let seasonCount: Int
    let status: Int
    let networks: [String]

    var id: String { imdbID.isEmpty ? "\(title)-\(year)" : imdbID }

    enum CodingKeys: String, CodingKey {
        case title, year, rating, overview, networks, source
        case imdbID = "imdbId"
        case posterURL = "posterUrl"
        case externalURL = "externalUrl"
        case seasonCount = "seasonCount"
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imdbID = container.decodeString(.imdbID)
        title = container.decodeString(.title)
        year = container.decodeInt(.year)
        source = container.decodeTVCatalogSource(.source)
        posterURL = container.decodeString(.posterURL)
        rating = container.decodeDouble(.rating)
        overview = container.decodeString(.overview)
        externalURL = container.decodeString(.externalURL)
        seasonCount = container.decodeInt(.seasonCount)
        status = container.decodeEnumInt(.status)
        networks = (try? container.decode([String].self, forKey: .networks)) ?? []
    }

    var posterLink: URL? { URL(string: posterURL) }
    var externalLink: URL? { URL(string: externalURL) }
    var statusLabel: String {
        switch status {
        case 1: "Returning"
        case 2: "Ended"
        case 3: "Canceled"
        case 4: "In production"
        case 5: "Planned"
        default: ""
        }
    }
    var displayTraits: String {
        let yearText = year > 0 ? String(year) : ""
        let ratingText = rating > 0 ? String(format: "%.1f ★", rating) : ""
        let seasonsText = seasonCount > 0 ? "\(seasonCount) season\(seasonCount == 1 ? "" : "s")" : ""
        return [yearText, ratingText, seasonsText, statusLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct ChillTransferResponse: Codable, Equatable, Sendable {
    let status: String
    let transfer: ChillTransfer?

    enum CodingKeys: String, CodingKey {
        case status, transfer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = container.decodeString(.status)
        transfer = try container.decodeIfPresent(ChillTransfer.self, forKey: .transfer)
    }
}

struct ChillTransfer: Codable, Equatable, Sendable {
    let id: Int64
    let name: String
    let status: String
    let percentDone: Int
    let size: Int64

    enum CodingKeys: String, CodingKey {
        case id, name, status, size
        case percentDone = "percentDone"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeInt64(.id)
        name = container.decodeString(.name)
        status = container.decodeString(.status)
        percentDone = container.decodeInt(.percentDone)
        size = container.decodeInt64(.size)
    }
}

struct ChillEpisodeDownload: Codable, Equatable, Sendable {
    let title: String
    let link: String
    let size: Int64
    let seeders: Int64
    let resolution: String
    let codec: String
    let quality: String
    let indexer: String
    let seasonNumber: Int
    let episodeNumber: Int?

    enum CodingKeys: String, CodingKey {
        case title, link, size, seeders, resolution, codec, quality, indexer
        case seasonNumber = "seasonNumber"
        case episodeNumber = "episodeNumber"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = container.decodeString(.title)
        link = container.decodeString(.link)
        size = container.decodeInt64(.size)
        seeders = container.decodeInt64(.seeders)
        resolution = container.decodeString(.resolution)
        codec = container.decodeString(.codec)
        quality = container.decodeString(.quality)
        indexer = container.decodeString(.indexer)
        seasonNumber = container.decodeInt(.seasonNumber)
        episodeNumber = container.decodeOptionalInt(.episodeNumber)
    }
}

struct UnconfiguredChillClient: ChillClient {
    enum ClientError: LocalizedError {
        case notConfigured

        var errorDescription: String? {
            "Chill is not connected yet."
        }
    }
}

struct ChillAPIClient: ChillClient {
    enum ClientError: LocalizedError {
        case missingToken
        case invalidResponse
        case requestFailed(String)
        case api(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .missingToken:
                "Chill access token is missing."
            case .invalidResponse:
                "Chill returned an invalid response."
            case .requestFailed(let message):
                "Chill: \(message)"
            case .api(let statusCode, let message):
                "Chill returned HTTP \(statusCode): \(message)"
            }
        }
    }

    private let token: String
    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        token: String,
        baseURL: URL = URL(string: "https://api.chill.institute/v4")!,
        session: URLSession = .shared
    ) {
        self.token = token
        self.baseURL = baseURL
        self.session = session
    }

    func fetchProfile() async throws -> ChillProfile {
        try await request(path: "chill.v4.UserService/GetUserProfile", body: EmptyRequest())
    }

    func search(query: String) async throws -> [ChillSearchResult] {
        let response: ChillSearchResponse = try await request(
            path: "chill.v4.UserService/Search",
            body: SearchRequest(query: query)
        )
        return response.results
    }

    func fetchMovies() async throws -> [ChillMovie] {
        let response: ChillMoviesResponse = try await request(
            path: "chill.v4.UserService/GetMovies",
            body: EmptyRequest()
        )
        return response.movies
    }

    func fetchTVShows() async throws -> [ChillTVShow] {
        let response: ChillTVShowsResponse = try await request(
            path: "chill.v4.UserService/GetTVShows",
            body: EmptyRequest()
        )
        return response.shows
    }

    func fetchTVShows(source: ChillTVCatalogSource) async throws -> [ChillTVShow] {
        let response: ChillTVShowsResponse = try await request(
            path: "chill.v4.UserService/GetTVShows",
            body: TVShowsRequest(source: source.rawValue)
        )
        return response.shows
    }

    func addTransfer(url: String) async throws -> ChillTransferResponse {
        try await request(
            path: "chill.v4.UserService/AddTransfer",
            body: AddTransferRequest(url: url)
        )
    }

    func episodeDownload(imdbID: String, season: Int, episode: Int) async throws -> ChillEpisodeDownload? {
        let response: EpisodeDownloadResponse = try await request(
            path: "chill.v4.UserService/GetTVShowEpisodeDownload",
            body: EpisodeDownloadRequest(imdbID: imdbID, seasonNumber: season, episodeNumber: episode)
        )
        return response.download
    }

    private func request<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request
    ) async throws -> Response {
        guard !token.isEmpty else { throw ClientError.missingToken }
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw ClientError.requestFailed("Could not encode the request.")
        }

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
            let message = (try? decoder.decode(ChillErrorResponse.self, from: data))?.message
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw ClientError.api(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ClientError.requestFailed("Could not decode the Chill response.")
        }
    }

    private struct EmptyRequest: Encodable {}
    private struct SearchRequest: Encodable { let query: String }
    private struct TVShowsRequest: Encodable { let source: String }
    private struct AddTransferRequest: Encodable { let url: String }
    private struct EpisodeDownloadRequest: Encodable {
        let imdbID: String
        let seasonNumber: Int
        let episodeNumber: Int

        enum CodingKeys: String, CodingKey {
            case imdbID = "imdbId"
            case seasonNumber, episodeNumber
        }
    }
    private struct ChillSearchResponse: Decodable {
        let results: [ChillSearchResult]

        enum CodingKeys: String, CodingKey { case results }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            results = try container.decodeIfPresent([ChillSearchResult].self, forKey: .results) ?? []
        }
    }
    private struct ChillMoviesResponse: Decodable {
        let movies: [ChillMovie]

        enum CodingKeys: String, CodingKey { case movies }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            movies = try container.decodeIfPresent([ChillMovie].self, forKey: .movies) ?? []
        }
    }
    private struct ChillTVShowsResponse: Decodable {
        let shows: [ChillTVShow]

        enum CodingKeys: String, CodingKey { case shows }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            shows = try container.decodeIfPresent([ChillTVShow].self, forKey: .shows) ?? []
        }
    }
    private struct EpisodeDownloadResponse: Decodable { let download: ChillEpisodeDownload? }
    private struct ChillErrorResponse: Decodable { let message: String? }
}

private extension KeyedDecodingContainer {
    func decodeString(_ key: Key) -> String {
        (try? decode(String.self, forKey: key)) ?? ""
    }

    func decodeBool(_ key: Key) -> Bool {
        (try? decode(Bool.self, forKey: key)) ?? false
    }

    func decodeInt(_ key: Key) -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let text = try? decode(String.self, forKey: key), let value = Int(text) { return value }
        return 0
    }

    func decodeOptionalInt(_ key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let text = try? decode(String.self, forKey: key), let value = Int(text) { return value }
        return nil
    }

    func decodeInt64(_ key: Key) -> Int64 {
        if let value = try? decode(Int64.self, forKey: key) { return value }
        if let text = try? decode(String.self, forKey: key), let value = Int64(text) { return value }
        return 0
    }

    func decodeDouble(_ key: Key) -> Double {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let text = try? decode(String.self, forKey: key), let value = Double(text) { return value }
        return 0
    }

    func decodeEnumInt(_ key: Key) -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        guard let text = try? decode(String.self, forKey: key) else { return 0 }
        switch text {
        case "TV_SHOW_STATUS_RETURNING", "RETURNING": return 1
        case "TV_SHOW_STATUS_ENDED", "ENDED": return 2
        case "TV_SHOW_STATUS_CANCELED", "CANCELED": return 3
        case "TV_SHOW_STATUS_IN_PRODUCTION", "IN_PRODUCTION": return 4
        case "TV_SHOW_STATUS_PLANNED", "PLANNED": return 5
        default: return Int(text) ?? 0
        }
    }

    func decodeTVCatalogSource(_ key: Key) -> ChillTVCatalogSource? {
        if let text = try? decode(String.self, forKey: key) {
            if let source = ChillTVCatalogSource(rawValue: text) { return source }
            switch text {
            case "NETFLIX": return .netflix
            case "HBO_MAX", "HBO MAX": return .hboMax
            case "APPLE_TV_PLUS", "APPLE TV+": return .appleTVPlus
            case "PRIME_VIDEO", "PRIME VIDEO": return .primeVideo
            case "DISNEY_PLUS", "DISNEY+": return .disneyPlus
            case "HULU": return .hulu
            case "PARAMOUNT_PLUS", "PARAMOUNT+": return .paramountPlus
            case "AMC_PLUS", "AMC+": return .amcPlus
            case "PEACOCK": return .peacock
            default: return nil
            }
        }
        switch decodeInt(key) {
        case 1: return .netflix
        case 2: return .hboMax
        case 3: return .appleTVPlus
        case 4: return .primeVideo
        case 5: return .disneyPlus
        case 7: return .hulu
        case 8: return .paramountPlus
        case 9: return .amcPlus
        case 10: return .peacock
        default: return nil
        }
    }
}

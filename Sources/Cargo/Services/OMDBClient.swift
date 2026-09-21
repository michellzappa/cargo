import Foundation

/// Optional second-source ratings. OMDb exposes IMDb, Rotten Tomatoes and
/// Metacritic values in one lookup keyed by the IMDb title id.
struct OMDBRatings: Codable, Equatable, Sendable {
    let imdbRating: Double?
    let rottenTomatoes: Int?
    let metacritic: Int?
}

private struct OMDBRatingsCacheEntry: Codable, Sendable {
    let ratings: OMDBRatings
    let fetchedAt: Date

    var isFresh: Bool {
        Date().timeIntervalSince(fetchedAt) < 7 * 86_400
    }
}

/// Disk-backed cache for slow-changing title scores. The cache lives under
/// Caches rather than application state, so it is disposable and never needs
/// migration when the ratings payload changes.
@MainActor
final class OMDBRatingsCache {
    private var entries: [String: OMDBRatingsCacheEntry]
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = caches.appendingPathComponent("Cargo", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("omdb-ratings.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? decoder.decode([String: OMDBRatingsCacheEntry].self, from: data) {
            entries = saved.filter { $0.value.isFresh }
        } else {
            entries = [:]
        }
    }

    func ratings(for imdbID: String) -> OMDBRatings? {
        guard let entry = entries[imdbID], entry.isFresh else { return nil }
        return entry.ratings
    }

    func store(_ ratings: OMDBRatings, for imdbID: String) {
        entries[imdbID] = OMDBRatingsCacheEntry(ratings: ratings, fetchedAt: Date())
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

struct OMDBClient: Sendable {
    enum ClientError: LocalizedError {
        case missingKey
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: "No OMDb API key."
            case .requestFailed(let message): "OMDb: \(message)"
            }
        }
    }

    let apiKey: String
    private let endpoint = URL(string: "https://www.omdbapi.com/")!

    func ratings(imdbID: String) async throws -> OMDBRatings {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "i", value: imdbID),
            URLQueryItem(name: "plot", value: "short")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue("Cargo/0.8", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ClientError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        let payload = try JSONDecoder().decode(Response.self, from: data)
        guard payload.response.uppercased() == "TRUE" else {
            throw ClientError.requestFailed(payload.error ?? "No ratings found")
        }

        let rottenTomatoes = payload.ratings?.first {
            $0.source.caseInsensitiveCompare("Rotten Tomatoes") == .orderedSame
        }.flatMap { Self.percent($0.value) }
        let metacritic = Self.score(payload.metascore)

        return OMDBRatings(
            imdbRating: Self.decimal(payload.imdbRating),
            rottenTomatoes: rottenTomatoes,
            metacritic: metacritic
        )
    }

    private static func decimal(_ value: String?) -> Double? {
        guard let value, value != "N/A" else { return nil }
        return Double(value)
    }

    private static func score(_ value: String?) -> Int? {
        guard let value, value != "N/A" else { return nil }
        return Int(value)
    }

    private static func percent(_ value: String) -> Int? {
        Int(value.replacingOccurrences(of: "%", with: ""))
    }

    private struct Response: Decodable {
        let response: String
        let error: String?
        let imdbRating: String?
        let metascore: String?
        let ratings: [Rating]?

        enum CodingKeys: String, CodingKey {
            case response = "Response"
            case error = "Error"
            case imdbRating
            case metascore = "Metascore"
            case ratings = "Ratings"
        }

        struct Rating: Decodable {
            let source: String
            let value: String

            enum CodingKeys: String, CodingKey {
                case source = "Source"
                case value = "Value"
            }
        }
    }
}

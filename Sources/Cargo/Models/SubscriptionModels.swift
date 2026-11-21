import Foundation

/// Default timings from RFC #13 ("Decisions" table).
enum SubscriptionDefaults {
    /// Wait after an episode airs before searching for a release (6 hours).
    static let postAirWaitInterval: TimeInterval = 6 * 3600
    /// Retry window after air date before marking an episode `noRelease` (7 days).
    static let retryWindowInterval: TimeInterval = 7 * 86_400
    /// Minimum spacing between Chill requests during a background cycle (1 second).
    static let minimumChillRequestInterval: TimeInterval = 1
}

/// Preferred release quality for automatic episode selection.
///
/// One global profile lives in `CargoSettings`; a subscription may override it.
struct QualityProfile: Codable, Equatable, Sendable {
    /// Default size cap from RFC #13: 4 GB per episode (decimal, matching macOS file byte counts).
    static let defaultMaxSizeBytes: Int64 = 4_000_000_000
    /// Default seeder pool from RFC #13: pick the smallest file of the top three by seeders.
    static let defaultTopSeedersPoolSize = 3

    /// Preferred resolution label, such as `"1080p"` or `"2160p"`.
    var preferredResolution: String
    /// Maximum size per episode in bytes. Zero disables the cap.
    var maxSizeBytes: Int64
    /// Optional preferred video codec, such as `"x265"` or `"x264"`. Nil accepts any codec.
    var preferredCodec: String?
    /// Choose the smallest matching release from the top N results by seeders.
    var topSeedersPoolSize: Int

    static let `default` = QualityProfile(
        preferredResolution: "1080p",
        maxSizeBytes: defaultMaxSizeBytes,
        preferredCodec: nil,
        topSeedersPoolSize: defaultTopSeedersPoolSize
    )

    init(
        preferredResolution: String = "1080p",
        maxSizeBytes: Int64 = defaultMaxSizeBytes,
        preferredCodec: String? = nil,
        topSeedersPoolSize: Int = defaultTopSeedersPoolSize
    ) {
        self.preferredResolution = preferredResolution
        self.maxSizeBytes = maxSizeBytes
        self.preferredCodec = preferredCodec
        self.topSeedersPoolSize = topSeedersPoolSize
    }

    private enum CodingKeys: String, CodingKey {
        case preferredResolution
        case maxSizeBytes
        case preferredCodec
        case topSeedersPoolSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferredResolution = try container.decodeIfPresent(String.self, forKey: .preferredResolution) ?? "1080p"
        maxSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .maxSizeBytes) ?? Self.defaultMaxSizeBytes
        preferredCodec = try container.decodeIfPresent(String.self, forKey: .preferredCodec)
        topSeedersPoolSize = try container.decodeIfPresent(Int.self, forKey: .topSeedersPoolSize)
            ?? Self.defaultTopSeedersPoolSize
    }
}

/// Which episodes a new subscription should fetch.
///
/// Defaults to `newOnly` so subscribing never starts a flood of old transfers.
enum SubscriptionBackfillPolicy: String, Codable, CaseIterable, Equatable, Sendable {
    case newOnly
    case currentSeason
    case all

    var displayName: String {
        switch self {
        case .newOnly: "New episodes only"
        case .currentSeason: "Current season"
        case .all: "All episodes"
        }
    }
}

/// The two kinds of subscription supported by Cargo.
///
/// A `series` subscription follows a show by IMDb ID with its TMDB ID for air
/// dates. A `feed` subscription reads an RSS or Atom URL with keyword filters.
enum SubscriptionKind: Codable, Equatable, Sendable {
    case series(imdbID: String, tmdbID: Int, title: String, year: Int?)
    case feed(url: String, title: String, keywords: [String], unwantedKeywords: [String])

    private enum CodingKeys: String, CodingKey {
        case type
        case imdbID
        case tmdbID
        case title
        case year
        case url
        case keywords
        case unwantedKeywords
    }

    private enum Discriminator: String, Codable {
        case series
        case feed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Discriminator.self, forKey: .type) {
        case .series:
            self = .series(
                imdbID: try container.decode(String.self, forKey: .imdbID),
                tmdbID: try container.decode(Int.self, forKey: .tmdbID),
                title: try container.decode(String.self, forKey: .title),
                year: try container.decodeIfPresent(Int.self, forKey: .year)
            )
        case .feed:
            self = .feed(
                url: try container.decode(String.self, forKey: .url),
                title: try container.decode(String.self, forKey: .title),
                keywords: try container.decodeIfPresent([String].self, forKey: .keywords) ?? [],
                unwantedKeywords: try container.decodeIfPresent([String].self, forKey: .unwantedKeywords) ?? []
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .series(let imdbID, let tmdbID, let title, let year):
            try container.encode(Discriminator.series, forKey: .type)
            try container.encode(imdbID, forKey: .imdbID)
            try container.encode(tmdbID, forKey: .tmdbID)
            try container.encode(title, forKey: .title)
            try container.encodeIfPresent(year, forKey: .year)
        case .feed(let url, let title, let keywords, let unwantedKeywords):
            try container.encode(Discriminator.feed, forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encode(title, forKey: .title)
            try container.encode(keywords, forKey: .keywords)
            try container.encode(unwantedKeywords, forKey: .unwantedKeywords)
        }
    }
}

/// A followed series or RSS/Atom feed owned by Cargo.
struct Subscription: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var kind: SubscriptionKind
    /// Optional per-subscription quality override; nil uses `CargoSettings.qualityProfile`.
    var quality: QualityProfile?
    var backfill: SubscriptionBackfillPolicy
    var paused: Bool
    var createdAt: Date
    var lastCheckedAt: Date?
    var lastError: String?

    init(
        id: UUID = UUID(),
        kind: SubscriptionKind,
        quality: QualityProfile? = nil,
        backfill: SubscriptionBackfillPolicy = .newOnly,
        paused: Bool = false,
        createdAt: Date = Date(),
        lastCheckedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.quality = quality
        self.backfill = backfill
        self.paused = paused
        self.createdAt = createdAt
        self.lastCheckedAt = lastCheckedAt
        self.lastError = lastError
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case quality
        case backfill
        case paused
        case createdAt
        case lastCheckedAt
        case lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(SubscriptionKind.self, forKey: .kind)
        quality = try container.decodeIfPresent(QualityProfile.self, forKey: .quality)
        backfill = try container.decodeIfPresent(SubscriptionBackfillPolicy.self, forKey: .backfill) ?? .newOnly
        paused = try container.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }

    var title: String {
        switch kind {
        case .series(_, _, let title, _), .feed(_, let title, _, _):
            title
        }
    }

    var imdbID: String? {
        if case .series(let imdbID, _, _, _) = kind { return imdbID }
        return nil
    }

    var tmdbID: Int? {
        if case .series(_, let tmdbID, _, _) = kind { return tmdbID }
        return nil
    }

    var feedURL: String? {
        if case .feed(let url, _, _, _) = kind { return url }
        return nil
    }

    func effectiveQuality(default defaultProfile: QualityProfile) -> QualityProfile {
        quality ?? defaultProfile
    }
}

/// Lifecycle state of one episode in Cargo's episode ledger.
enum EpisodeLedgerState: String, Codable, CaseIterable, Equatable, Sendable {
    case wanted
    case searching
    case sent
    case onPutIO
    case downloaded
    case skipped
    case noRelease

    var displayName: String {
        switch self {
        case .wanted: "Wanted"
        case .searching: "Searching"
        case .sent: "Sent to Put.io"
        case .onPutIO: "On Put.io"
        case .downloaded: "Downloaded"
        case .skipped: "Skipped"
        case .noRelease: "No release"
        }
    }
}

/// One episode tracked across all subscription sources.
///
/// Keyed by normalized `(imdbID, season, episode)` so series and feed
/// subscriptions share one ledger and never fetch the same episode twice.
struct EpisodeLedgerEntry: Codable, Identifiable, Equatable, Sendable {
    var imdbID: String
    var season: Int
    var episode: Int
    var state: EpisodeLedgerState
    var subscriptionID: UUID?
    var releaseTitle: String?
    var putIOTransferID: Int?
    var airedAt: Date?
    var updatedAt: Date
    var attempts: Int
    var nextAttemptAt: Date?

    var id: String {
        Self.key(imdbID: imdbID, season: season, episode: episode)
    }

    var episodeCode: String {
        String(format: "S%02dE%02d", season, episode)
    }

    static func normalizeIMDbID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func key(imdbID: String, season: Int, episode: Int) -> String {
        "\(normalizeIMDbID(imdbID)):\(String(format: "S%02dE%02d", season, episode))"
    }

    init(
        imdbID: String,
        season: Int,
        episode: Int,
        state: EpisodeLedgerState,
        subscriptionID: UUID? = nil,
        releaseTitle: String? = nil,
        putIOTransferID: Int? = nil,
        airedAt: Date? = nil,
        updatedAt: Date = Date(),
        attempts: Int = 0,
        nextAttemptAt: Date? = nil
    ) {
        self.imdbID = Self.normalizeIMDbID(imdbID)
        self.season = season
        self.episode = episode
        self.state = state
        self.subscriptionID = subscriptionID
        self.releaseTitle = releaseTitle
        self.putIOTransferID = putIOTransferID
        self.airedAt = airedAt
        self.updatedAt = updatedAt
        self.attempts = attempts
        self.nextAttemptAt = nextAttemptAt
    }

    private enum CodingKeys: String, CodingKey {
        case imdbID
        case season
        case episode
        case state
        case subscriptionID
        case releaseTitle
        case putIOTransferID
        case airedAt
        case updatedAt
        case attempts
        case nextAttemptAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imdbID = Self.normalizeIMDbID(try container.decode(String.self, forKey: .imdbID))
        season = try container.decode(Int.self, forKey: .season)
        episode = try container.decode(Int.self, forKey: .episode)
        state = try container.decode(EpisodeLedgerState.self, forKey: .state)
        subscriptionID = try container.decodeIfPresent(UUID.self, forKey: .subscriptionID)
        releaseTitle = try container.decodeIfPresent(String.self, forKey: .releaseTitle)
        putIOTransferID = try container.decodeIfPresent(Int.self, forKey: .putIOTransferID)
        airedAt = try container.decodeIfPresent(Date.self, forKey: .airedAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        attempts = try container.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        nextAttemptAt = try container.decodeIfPresent(Date.self, forKey: .nextAttemptAt)
    }
}

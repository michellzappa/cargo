import AppKit

struct DiscoverTitle: Equatable, Sendable {
    enum Kind: String, Sendable {
        case movie
        case series

        var tmdbType: TMDBMetadata.MediaType {
            switch self {
            case .movie: .movie
            case .series: .tv
            }
        }
    }

    let id: String
    let title: String
    let year: Int?
    let kind: Kind
    let posterURL: URL?
    let overview: String?
    let rating: Double?
    let genres: [String]
    let networks: [String]
    let imdbID: String?
    let externalURL: URL?
    let searchQuery: String
}

@MainActor
final class DiscoverDetailViewController: NSViewController {
    private let coordinator: CargoCoordinator
    private let seed: DiscoverTitle
    private let onBack: () -> Void
    private let onSend: (() -> Void)?
    private let backButtonTitle: String

    private let scrollView = NSScrollView()
    private let contentStack = NSStackView()
    private let heroCard = NSVisualEffectView()
    private let backdropView = NSImageView()
    private let posterView = NSImageView()
    private let titleLabel = Theme.label(style: .pageTitle, wraps: true)
    private let metadataLabel = Theme.label(style: .body, color: .secondaryLabelColor, wraps: true)
    private let ratingsLabel = Theme.label(style: .detail, color: .secondaryLabelColor, wraps: false)
    private let genreLabel = Theme.label(style: .detail, color: .secondaryLabelColor, wraps: true)
    private let overviewLabel = Theme.label(style: .body, wraps: true)
    private let actionStack = NSStackView()
    private let sectionsStack = NSStackView()
    private let tmdbLinkButton = NSButton(title: "Open on TMDB", target: nil, action: nil)
    private let imdbLinkButton = NSButton(title: "Open on IMDb", target: nil, action: nil)
    private let searchButton = NSButton(title: "Search Releases", target: nil, action: nil)
    private let sendButton = NSButton(title: "Send to Put.io", target: nil, action: nil)
    private let statusLabel = Theme.label(style: .detail, color: .secondaryLabelColor, wraps: true)
    private var tmdbMetadata: TMDBMetadata?
    private var requestTask: Task<Void, Never>?
    private var ratingsTask: Task<Void, Never>?
    private var omdbRatings: OMDBRatings?

    init(
        seed: DiscoverTitle,
        coordinator: CargoCoordinator,
        onBack: @escaping () -> Void,
        onSend: (() -> Void)? = nil,
        backButtonTitle: String = "Back to Discover"
    ) {
        self.seed = seed
        self.coordinator = coordinator
        self.onBack = onBack
        self.onSend = onSend
        self.backButtonTitle = backButtonTitle
        super.init(nibName: nil, bundle: nil)
        title = seed.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        requestTask?.cancel()
        ratingsTask?.cancel()
    }

    override func loadView() {
        view = NSView()

        let topBar = NSStackView()
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 8
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let backButton = NSButton(title: backButtonTitle, target: self, action: #selector(back))
        backButton.bezelStyle = .rounded
        backButton.controlSize = .small
        topBar.addArrangedSubview(backButton)
        topBar.addArrangedSubview(NSView())
        let contextLabel = Theme.label(seed.kind == .series ? "Series" : "Movie", style: .caption, color: .secondaryLabelColor)
        topBar.addArrangedSubview(contextLabel)
        view.addSubview(topBar)

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.distribution = .fill
        contentStack.spacing = 10
        contentStack.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 18, right: 16)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentStack

        configureHero()
        configureActions()
        configureSections()
        contentStack.addArrangedSubview(heroCard)
        contentStack.addArrangedSubview(actionStack)
        contentStack.addArrangedSubview(statusLabel)
        contentStack.addArrangedSubview(sectionsStack)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 2),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            heroCard.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -32),
            actionStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -32),
            statusLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -32),
            sectionsStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -32)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        apply(seed: seed, metadata: nil)
        loadPoster(seed.posterURL, into: posterView)
        loadPoster(seed.posterURL, into: backdropView)
        loadMetadata()
        loadRatings()
    }

    private func configureHero() {
        heroCard.material = .contentBackground
        heroCard.blendingMode = .withinWindow
        heroCard.state = .active
        heroCard.wantsLayer = true
        heroCard.layer?.cornerRadius = 12
        heroCard.layer?.masksToBounds = true
        heroCard.setContentHuggingPriority(.required, for: .vertical)
        heroCard.setContentCompressionResistancePriority(.required, for: .vertical)
        heroCard.translatesAutoresizingMaskIntoConstraints = false

        backdropView.imageScaling = .scaleAxesIndependently
        backdropView.alphaValue = 0.16
        backdropView.wantsLayer = true
        backdropView.layer?.filters = [CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 18])].compactMap { $0 }
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        heroCard.addSubview(backdropView)

        posterView.imageScaling = .scaleProportionallyUpOrDown
        posterView.image = Theme.symbol("film", pointSize: 32, weight: .light)
        posterView.contentTintColor = .tertiaryLabelColor
        posterView.wantsLayer = true
        posterView.layer?.cornerRadius = 8
        posterView.layer?.masksToBounds = true
        posterView.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        posterView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        ratingsLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        ratingsLabel.isHidden = true
        metadataLabel.preferredMaxLayoutWidth = 520
        genreLabel.preferredMaxLayoutWidth = 520
        overviewLabel.preferredMaxLayoutWidth = 520
        overviewLabel.setContentHuggingPriority(.defaultLow, for: .vertical)
        overviewLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        let copyStack = NSStackView(views: [titleLabel, metadataLabel, ratingsLabel, genreLabel, overviewLabel])
        copyStack.orientation = .vertical
        copyStack.alignment = .leading
        copyStack.spacing = 5
        copyStack.setCustomSpacing(9, after: genreLabel)
        copyStack.translatesAutoresizingMaskIntoConstraints = false

        let heroContent = NSStackView(views: [posterView, copyStack])
        heroContent.orientation = .horizontal
        heroContent.alignment = .top
        heroContent.spacing = 18
        heroContent.setContentHuggingPriority(.required, for: .vertical)
        heroContent.setContentCompressionResistancePriority(.required, for: .vertical)
        heroContent.translatesAutoresizingMaskIntoConstraints = false
        heroCard.addSubview(heroContent)

        let compactHeight = heroCard.heightAnchor.constraint(equalTo: posterView.heightAnchor, constant: 32)
        compactHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            backdropView.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor),
            backdropView.topAnchor.constraint(equalTo: heroCard.topAnchor),
            backdropView.bottomAnchor.constraint(equalTo: heroCard.bottomAnchor),
            heroContent.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 16),
            heroContent.trailingAnchor.constraint(lessThanOrEqualTo: heroCard.trailingAnchor, constant: -16),
            heroContent.topAnchor.constraint(equalTo: heroCard.topAnchor, constant: 16),
            heroContent.bottomAnchor.constraint(equalTo: heroCard.bottomAnchor, constant: -16),
            posterView.widthAnchor.constraint(equalToConstant: 144),
            posterView.heightAnchor.constraint(equalToConstant: 216),
            copyStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            copyStack.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
            compactHeight
        ])
    }

    private func configureActions() {
        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = 6
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        for button in [searchButton, sendButton, tmdbLinkButton, imdbLinkButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
        }
        searchButton.target = self
        searchButton.action = #selector(searchReleases)
        sendButton.target = self
        sendButton.action = #selector(sendToPutIO)
        tmdbLinkButton.target = self
        tmdbLinkButton.action = #selector(openMetadataPage)
        imdbLinkButton.target = self
        imdbLinkButton.action = #selector(openIMDb)
        actionStack.addArrangedSubview(searchButton)
        actionStack.addArrangedSubview(sendButton)
        actionStack.addArrangedSubview(tmdbLinkButton)
        actionStack.addArrangedSubview(imdbLinkButton)
    }

    private func configureSections() {
        sectionsStack.orientation = .vertical
        sectionsStack.alignment = .leading
        sectionsStack.spacing = 12
        sectionsStack.translatesAutoresizingMaskIntoConstraints = false
    }

    private func loadMetadata() {
        guard coordinator.hasTMDBKey else {
            statusLabel.stringValue = "Showing Chill catalog data. Add a TMDB key in Settings → Library for full title details."
            return
        }

        statusLabel.stringValue = "Loading details from TMDB…"
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let metadata = try await coordinator.fetchDiscoverMetadata(
                    title: seed.title,
                    year: seed.year,
                    type: seed.kind.tmdbType,
                    imdbID: seed.imdbID
                )
                guard !Task.isCancelled else { return }
                tmdbMetadata = metadata
                apply(seed: seed, metadata: metadata)
                loadRatings()
                statusLabel.stringValue = "Metadata provided by TMDB."
            } catch {
                statusLabel.stringValue = "Showing Chill catalog data · TMDB lookup failed: \(error.localizedDescription)"
            }
        }
    }

    private func loadRatings() {
        guard coordinator.hasOMDBKey, let imdbID = resolvedIMDbID else { return }
        ratingsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let ratings = try await coordinator.fetchDiscoverRatings(imdbID: imdbID)
                guard !Task.isCancelled else { return }
                applyRatings(ratings)
            } catch {
                // Ratings are supplementary; a missing or expired OMDb lookup
                // should never prevent the TMDB title page from rendering.
            }
        }
    }

    private func apply(seed: DiscoverTitle, metadata: TMDBMetadata?) {
        let title = metadata?.title.isEmpty == false ? metadata!.title : seed.title
        titleLabel.stringValue = title
        var facts: [String] = []
        if let year = metadata?.year ?? seed.year { facts.append(String(year)) }
        if seed.kind == .series, let count = metadata?.episodeCounts.count, count > 0 {
            facts.append("\(count) seasons")
        }
        metadataLabel.stringValue = facts.joined(separator: "  ·  ")

        updateRatingsLabel()

        let genres = seed.genres
        genreLabel.stringValue = genres.isEmpty ? seed.networks.joined(separator: "  ·  ") : genres.joined(separator: "  ·  ")
        genreLabel.isHidden = genreLabel.stringValue.isEmpty
        overviewLabel.stringValue = metadata?.overview ?? seed.overview ?? "No synopsis available."
        loadPoster(metadata?.posterURL ?? seed.posterURL, into: posterView)
        loadPoster(metadata?.posterURL ?? seed.posterURL, into: backdropView)

        sendButton.isHidden = onSend == nil
        tmdbLinkButton.title = "Open on TMDB"
        tmdbLinkButton.isHidden = metadata == nil
        imdbLinkButton.isHidden = seed.externalURL == nil && seed.imdbID == nil

        rebuildDetailSections(metadata: metadata)
    }

    private func applyRatings(_ ratings: OMDBRatings) {
        omdbRatings = ratings
        updateRatingsLabel()
    }

    private func updateRatingsLabel() {
        var values: [String] = []
        if let rating = tmdbMetadata?.voteAverage ?? seed.rating, rating > 0 {
            values.append(String(format: "TMDB %.1f/10", rating))
        }
        if let rating = omdbRatings?.imdbRating { values.append(String(format: "IMDb %.1f/10", rating)) }
        if let rating = omdbRatings?.rottenTomatoes { values.append("Rotten Tomatoes \(rating)%") }
        if let rating = omdbRatings?.metacritic { values.append("Metacritic \(rating)/100") }
        ratingsLabel.stringValue = values.joined(separator: "  ·  ")
        ratingsLabel.isHidden = values.isEmpty
    }

    private func rebuildDetailSections(metadata: TMDBMetadata?) {
        sectionsStack.arrangedSubviews.forEach {
            sectionsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if let metadata, seed.kind == .series, !metadata.episodeCounts.isEmpty {
            sectionsStack.addArrangedSubview(makeCompletenessSection(metadata: metadata))
        }

        // The synopsis already lives in the hero. Repeating it in an About
        // section makes a movie page unnecessarily tall.
    }

    private func makeCompletenessSection(metadata: TMDBMetadata) -> NSView {
        let counts = metadata.episodeCounts
            .filter { $0.value > 0 }
            .sorted { $0.key < $1.key }
        let libraryItem = matchingLibraryItem(metadata: metadata)
        let ownedEpisodes = libraryItem?.episodes ?? [:]
        let total = counts.reduce(0) { $0 + $1.value }
        let owned = counts.reduce(0) { result, season in
            result + Set(ownedEpisodes[season.key] ?? []).filter { (1...season.value).contains($0) }.count
        }

        let heading = Theme.label("Completeness", style: .sectionHeader)
        let summary = Theme.label(
            libraryItem == nil
                ? "No matching show in your library"
                : "\(owned) of \(total) episodes on disk",
            style: .detail,
            color: .secondaryLabelColor
        )
        let legend = Theme.label("● On disk    ○ Missing", style: .caption, color: .secondaryLabelColor)
        let grid = EpisodeCompletenessGrid(seasonCounts: counts, ownedEpisodes: ownedEpisodes)

        let stack = NSStackView(views: [heading, summary, legend, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(8, after: legend)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func matchingLibraryItem(metadata: TMDBMetadata) -> LibraryItem? {
        let titles = Set([seed.title, metadata.title].map(TMDBClient.normalize))
        let candidates = coordinator.dashboardState.libraryItems.filter {
            $0.kind == .show && titles.contains(TMDBClient.normalize($0.title))
        }
        let expectedYear = metadata.year ?? seed.year
        return candidates.first(where: { $0.year == expectedYear }) ?? candidates.first
    }

    private func loadPoster(_ url: URL?, into imageView: NSImageView) {
        guard let url else {
            imageView.image = Theme.symbol("film", pointSize: 32, weight: .light)
            return
        }
        Task { @MainActor [weak imageView] in
            let image = await PosterCache.shared.image(for: url)
            guard let imageView else { return }
            imageView.image = image ?? Theme.symbol("film", pointSize: 32, weight: .light)
        }
    }

    private var resolvedIMDbID: String? {
        if let id = tmdbMetadata?.imdbID ?? seed.imdbID, id.hasPrefix("tt") { return id }
        guard let value = seed.externalURL?.absoluteString,
              let range = value.range(of: "tt[0-9]+", options: .regularExpression)
        else { return nil }
        return String(value[range])
    }

    @objc private func back() { onBack() }

    @objc private func searchReleases() {
        onBack()
        coordinator.requestChillSearch(query: seed.searchQuery)
    }

    @objc private func sendToPutIO() { onSend?() }

    @objc private func openMetadataPage() {
        guard let url = tmdbMetadata?.pageURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openIMDb() {
        if let url = seed.externalURL {
            NSWorkspace.shared.open(url)
        } else if let imdbID = seed.imdbID, let url = URL(string: "https://www.imdb.com/title/\(imdbID)/") {
            NSWorkspace.shared.open(url)
        }
    }
}

private enum EpisodeCompletenessCellState: Equatable {
    case owned
    case missing
    case notApplicable
}

@MainActor
private final class EpisodeCompletenessGrid: NSView {

    init(seasonCounts: [(key: Int, value: Int)], ownedEpisodes: [Int: [Int]]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let maxEpisode = seasonCounts.map(\.value).max() ?? 0
        guard maxEpisode > 0 else { return }

        var rows: [[NSView]] = []
        let header = [makeHeader("Season")] + (1...maxEpisode).map { makeHeader(String($0)) }
        rows.append(header)

        for season in seasonCounts {
            let have = Set(ownedEpisodes[season.key] ?? [])
            let cells = (1...maxEpisode).map { episode -> NSView in
                let state: EpisodeCompletenessCellState
                if episode > season.value {
                    state = .notApplicable
                } else if have.contains(episode) {
                    state = .owned
                } else {
                    state = .missing
                }
                return EpisodeCompletenessCell(
                    season: season.key,
                    episode: episode,
                    state: state
                )
            }
            rows.append([makeSeasonLabel(season.key)] + cells)
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 4
        grid.columnSpacing = 4
        grid.xPlacement = .leading
        grid.yPlacement = .center
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)

        grid.column(at: 0).width = 76
        for column in 1...maxEpisode {
            grid.column(at: column).width = 26
        }

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.topAnchor.constraint(equalTo: topAnchor),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func makeHeader(_ title: String) -> NSTextField {
        let label = Theme.label(title, style: .caption, color: .secondaryLabelColor)
        label.alignment = title == "Season" ? .left : .center
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    private func makeSeasonLabel(_ season: Int) -> NSTextField {
        let label = Theme.label("Season \(season)", style: .detail)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }
}

@MainActor
private final class EpisodeCompletenessCell: NSView {
    private let season: Int
    private let episode: Int
    private let state: EpisodeCompletenessCellState

    init(season: Int, episode: Int, state: EpisodeCompletenessCellState) {
        self.season = season
        self.episode = episode
        self.state = state
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 26),
            heightAnchor.constraint(equalToConstant: 26)
        ])
        toolTip = state == .notApplicable ? nil : "Season \(season), episode \(episode) — \(state == .owned ? "On disk" : "Missing")"
        setAccessibilityLabel(toolTip ?? "Not applicable")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard state != .notApplicable else { return }

        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        let accent = NSColor.controlAccentColor
        let fill = state == .owned
            ? accent.withAlphaComponent(0.78)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.72)
        let stroke = state == .owned
            ? accent.withAlphaComponent(0.95)
            : NSColor.separatorColor.withAlphaComponent(0.65)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()

        if state == .owned {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let mark = "✓"
            let size = mark.size(withAttributes: attributes)
            mark.draw(
                at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2 + 1),
                withAttributes: attributes
            )
        }
    }
}

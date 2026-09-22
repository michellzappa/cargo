import CargoRemoteKit
import SwiftUI

struct CargoRootView: View {
    @Environment(CargoClientModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.isConnected || model.hasSavedResident {
                CargoDashboardView()
            } else {
                CargoConnectView()
            }
        }
        .animation(.default, value: model.isConnected)
        .task { await model.restoreConnection() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !model.isConnected {
                Task { await model.restoreConnection() }
            }
        }
        .alert(
            "Cargo",
            isPresented: Binding(
                get: { model.actionError != nil },
                set: { if !$0 { model.actionError = nil } }
            )
        ) {
            Button("OK") { model.actionError = nil }
        } message: {
            Text(model.actionError ?? "The resident rejected the request.")
        }
    }
}

struct CargoConnectView: View {
    @Environment(CargoClientModel.self) private var model
    @State private var address = ""
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Pair with the Cargo resident Mac to control transfers and view its library. Put.io, Chill, metadata, and SSD settings stay on the resident.")
                        .foregroundStyle(.secondary)
                    Text("You can paste the complete cargo://pair link here; Cargo will extract the resident address and token.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Resident") {
                    TextField("Paste pairing link or server address", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if model.hasSavedToken {
                        Label("Resident token saved on this iPhone", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        SecureField("Resident token", text: $token)
                    }
                }

                Section {
                    Button {
                        Task { await model.connect(address: address, token: token) }
                    } label: {
                        HStack {
                            Spacer()
                            if case .connecting = model.connectionState { ProgressView() }
                            Text("Connect")
                            Spacer()
                        }
                    }
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.connectionState == .connecting)
                }

                if model.connectionState == .connecting, model.hasSavedToken {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Reconnecting to the resident…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Label(model.connectionState.label, systemImage: model.isConnected ? "checkmark.circle.fill" : "network")
                        .foregroundStyle(model.isConnected ? .green : .secondary)
                }

                if let lastError = model.lastError {
                    Section("Connection details") {
                        Text(lastError)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Cargo")
            .onAppear {
                address = model.residentAddress
            }
        }
    }
}

struct CargoDashboardView: View {
    @Environment(CargoClientModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: CargoStartTab = .transfers

    var body: some View {
        VStack(spacing: 0) {
            if !model.isConnected {
                HStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                    Text(model.connectionState.label)
                        .font(.footnote)
                        .lineLimit(2)
                    Spacer()
                    Button("Retry") {
                        Task { await model.retrySavedConnection() }
                    }
                    .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .foregroundStyle(.orange)
                .background(.orange.opacity(0.12))
            }

            TabView(selection: $selectedTab) {
                CargoTransfersView()
                    .tabItem { Label("Transfers", systemImage: "arrow.down.circle") }
                    .tag(CargoStartTab.transfers)
                CargoFilesView()
                    .tabItem { Label("Files", systemImage: "folder") }
                    .tag(CargoStartTab.files)
                CargoLibraryView()
                    .tabItem { Label("Library", systemImage: "film") }
                    .tag(CargoStartTab.library)
                CargoDiscoverView()
                    .tabItem { Label("Discover", systemImage: "sparkles") }
                    .tag(CargoStartTab.discover)
                CargoWatchlistView()
                    .tabItem { Label("Watchlist", systemImage: "star") }
                    .tag(CargoStartTab.watchlist)
                CargoInboxView()
                    .tabItem { Label("Inbox", systemImage: "tray") }
                    .tag(CargoStartTab.inbox)
                CargoHistoryView()
                    .tabItem { Label("History", systemImage: "clock") }
                    .tag(CargoStartTab.history)
                CargoSettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(CargoStartTab.settings)
            }
        }
        .onAppear { selectedTab = model.startTab }
        .onChange(of: model.startTab) { _, tab in selectedTab = tab }
        .onChange(of: scenePhase) { _, phase in
            model.setActive(phase == .active)
        }
    }
}

struct CargoTransfersView: View {
    @Environment(CargoClientModel.self) private var model
    @State private var showingAddTransfer = false

    var body: some View {
        NavigationStack {
            List {
                if let snapshot = model.snapshot, snapshot.transfers.isEmpty {
                    ContentUnavailableView("No transfers", systemImage: "arrow.down.circle", description: Text("Add a link or magnet from the resident.") )
                }
                ForEach(model.snapshot?.transfers ?? []) { transfer in
                    CargoTransferRow(transfer: transfer)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if transfer.status == .downloading || transfer.status == .waiting || transfer.status == .seeding {
                                Button(role: .destructive) {
                                    Task { await model.execute(.cancelTransfer(id: transfer.id)) }
                                } label: {
                                    Label("Cancel", systemImage: "xmark")
                                }
                            }
                            if transfer.status == .failed || transfer.status == .cancelled {
                                Button {
                                    Task { await model.execute(.retryTransfer(id: transfer.id)) }
                                } label: {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                }
                            }
                        }
                }
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Transfers")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await model.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddTransfer = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddTransfer) {
                CargoAddTransferSheet { url in
                    Task { await model.execute(.addTransfer(url: url)) }
                }
            }
        }
    }
}

private struct CargoTransferRow: View {
    @Environment(CargoClientModel.self) private var model
    let transfer: CargoRemoteTransfer

    var body: some View {
        CargoMediaLine(
            title: transfer.displayName ?? model.displayTitle(for: transfer.name),
            subtitle: ByteCountFormatter.string(fromByteCount: transfer.sizeBytes, countStyle: .file),
            posterURL: transfer.posterURL ?? model.posterURL(for: transfer.name),
            badge: transfer.statusLabel,
            progress: [.downloading, .waiting].contains(transfer.status) ? transfer.progress : nil
        )
    }
}

private struct CargoAddTransferSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    let onAdd: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Put.io link") {
                    TextField("Magnet or torrent/HTTP URL", text: $url, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Button("Add Transfer") {
                    onAdd(url.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("Add Transfer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private enum CargoLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case movies
    case shows
    case incomplete
    case unmatched

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .movies: "Movies"
        case .shows: "TV Shows"
        case .incomplete: "Incomplete"
        case .unmatched: "Unmatched"
        }
    }
}

struct CargoLibraryView: View {
    @Environment(CargoClientModel.self) private var model
    @State private var filter: CargoLibraryFilter = .all
    @State private var viewMode: CargoMediaViewMode = .posters
    @State private var selectedDetail: CargoTitleDetail?

    private var visibleItems: [CargoRemoteLibraryItem] {
        (model.snapshot?.library ?? []).filter { item in
            switch filter {
            case .all: true
            case .movies: item.kind == .movie
            case .shows: item.kind == .show
            case .incomplete: isIncomplete(item)
            case .unmatched: item.metadata == nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            libraryContent
            .refreshable { await model.refresh() }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(CargoLibraryFilter.allCases) { option in
                            Button {
                                filter = option
                            } label: {
                                if filter == option {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        Label(filter.title, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    CargoMediaViewModeMenu(selection: $viewMode)
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(item: $selectedDetail) { detail in
                CargoTitleDetailView(detail: detail) { _ in }
            }
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if viewMode == .posters {
            ScrollView {
                if visibleItems.isEmpty {
                    libraryEmptyState
                } else {
                    CargoPosterGrid {
                        ForEach(visibleItems) { item in
                            Button {
                                selectedDetail = detail(for: item)
                            } label: {
                                CargoPosterCard(
                                    title: item.title,
                                    subtitle: detail(for: item),
                                    posterURL: item.metadata?.posterURL,
                                    badge: badge(for: item)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        } else {
            List {
                if visibleItems.isEmpty {
                    libraryEmptyState
                } else {
                    ForEach(visibleItems) { item in
                        Button {
                            selectedDetail = detail(for: item)
                        } label: {
                            CargoMediaLine(
                                title: item.title,
                                subtitle: detail(for: item),
                                posterURL: item.metadata?.posterURL,
                                badge: badge(for: item)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var libraryEmptyState: some View {
        ContentUnavailableView(
            "No library titles",
            systemImage: "film.stack",
            description: Text(filter == .all ? "The resident library is empty." : "No titles match this filter.")
        )
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private func detail(for item: CargoRemoteLibraryItem) -> String {
        var result = item.kind == .movie ? "Movie" : "TV Show"
        if let year = item.year { result += " · \(year)" }
        if item.kind == .show { result += " · \(item.episodeCount) episodes" }
        return result
    }

    private func badge(for item: CargoRemoteLibraryItem) -> String? {
        if isIncomplete(item) { return "Incomplete" }
        if item.kind == .show, item.metadata?.episodeCounts.isEmpty == false { return "Complete" }
        return nil
    }

    private func isIncomplete(_ item: CargoRemoteLibraryItem) -> Bool {
        guard item.kind == .show, let episodeCounts = item.metadata?.episodeCounts, !episodeCounts.isEmpty else { return false }
        return episodeCounts.contains { season, expected in
            item.episodes[season, default: []].count < expected
        }
    }

    private func detail(for item: CargoRemoteLibraryItem) -> CargoTitleDetail {
        let metadata = item.metadata
        let metadataLine = [
            item.relativePath,
            item.kind == .show ? "\(item.seasonCount) seasons" : nil,
            ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file)
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        return CargoTitleDetail(
            id: "library-\(item.id)",
            title: item.title,
            subtitle: detail(for: item),
            posterURL: metadata?.posterURL,
            rating: metadata?.rating,
            overview: metadata?.overview,
            metadataLine: metadataLine,
            externalURL: metadata.flatMap { URL(string: $0.externalURL) },
            externalLabel: metadata == nil ? nil : "Open on TMDB",
            action: nil
        )
    }
}

struct CargoFilesView: View {
    @Environment(CargoClientModel.self) private var model
    @State private var fileToDelete: CargoRemoteFile?

    private var files: [CargoRemoteFile] {
        (model.snapshot?.files ?? []).filter { [.folder, .video, .archive].contains($0.type) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let disk = model.snapshot?.disk {
                    Section("Put.io storage") {
                        CargoDiskStatusView(disk: disk)
                    }
                }
                if files.isEmpty {
                    ContentUnavailableView("No files", systemImage: "folder", description: Text("The resident has no files in this Put.io folder."))
                }
                ForEach(files) { file in
                    fileRow(file)
                }
            }
            .refreshable { await model.refresh() }
            .navigationTitle(model.snapshot?.remoteFolderName ?? "Files")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if model.snapshot?.canGoBackRemoteFolder == true {
                        Button {
                            Task { await model.execute(.goBackRemoteFolder) }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .confirmationDialog(
                "Delete this Put.io file?",
                isPresented: Binding(
                    get: { fileToDelete != nil },
                    set: { if !$0 { fileToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let file = fileToDelete {
                        Task { await model.execute(.deleteRemoteFile(remoteFileID: file.id)) }
                    }
                    fileToDelete = nil
                }
            } message: {
                Text("This moves \(fileToDelete?.name ?? "the file") to Put.io's trash. Local library files are not affected.")
            }
        }
    }

    @ViewBuilder
    private func fileRow(_ file: CargoRemoteFile) -> some View {
        switch file.type {
        case .folder:
            Button {
                Task { await model.execute(.openRemoteFolder(remoteFolderID: file.id)) }
            } label: {
                Label {
                    VStack(alignment: .leading) {
                        Text(file.name).font(.headline)
                        Text("Folder").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .buttonStyle(.plain)
        case .video:
            mediaRow(file, icon: "film")
        case .archive:
            HStack {
                Label {
                    VStack(alignment: .leading) {
                        Text(file.name).font(.headline)
                        Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "archivebox.fill").foregroundStyle(.orange)
                }
                Spacer()
                Button("Extract") {
                    Task { await model.execute(.requestExtraction(remoteFileID: file.id)) }
                }
                .buttonStyle(.bordered)
                Button(role: .destructive) { fileToDelete = file } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        default:
            EmptyView()
        }
    }

    private func mediaRow(_ file: CargoRemoteFile, icon: String) -> some View {
        let job = model.snapshot?.syncJobs
            .filter { $0.remoteFileID == file.id }
            .max { $0.updatedAt < $1.updatedAt }
        let actionTitle: String
        if let job {
            actionTitle = job.status == .failed ? "Retry" : job.statusLabel
        } else {
            actionTitle = "Sync"
        }

        return HStack {
            CargoMediaLine(
                title: model.displayTitle(for: file.name),
                subtitle: ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file),
                posterURL: file.posterURL ?? model.posterURL(for: file.name),
                badge: job?.statusLabel,
                progress: job?.status == .downloading ? job?.progress : nil,
                error: job?.errorMessage
            )
            Spacer()
            Button {
                Task { await model.execute(.enqueueLocalSync(remoteFileID: file.id)) }
            } label: {
                Text(actionTitle)
            }
            .disabled(job.map { $0.status != .failed } ?? false)
            .buttonStyle(.bordered)
            Button(role: .destructive) { fileToDelete = file } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct CargoDiskStatusView: View {
    let disk: CargoRemoteDiskUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Put.io", systemImage: "externaldrive.fill")
                Spacer()
                Text("\(ByteCountFormatter.string(fromByteCount: disk.availableBytes, countStyle: .file)) free")
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: disk.fraction)
            Text("\(ByteCountFormatter.string(fromByteCount: disk.usedBytes, countStyle: .file)) used of \(ByteCountFormatter.string(fromByteCount: disk.totalBytes, countStyle: .file))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private enum CargoDiscoverCatalog: String, CaseIterable, Identifiable {
    case movies
    case series

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movies: "Top Movies"
        case .series: "Top Series"
        }
    }
}

private extension Array where Element == String {
    func uniquedCaseInsensitive() -> [String] {
        reduce(into: [String]()) { result, value in
            guard !result.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
            result.append(value)
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

struct CargoDiscoverView: View {
    @Environment(CargoClientModel.self) private var model
    @State private var query = ""
    @State private var selectedCatalog: CargoDiscoverCatalog = .movies
    @State private var selectedFilter = ""
    @State private var viewMode: CargoMediaViewMode = .posters
    @State private var selectedDetail: CargoTitleDetail?

    private var showingSearchResults: Bool {
        guard model.searchState != nil else { return false }
        return !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var catalogFilters: (lists: [String], genres: [String]) {
        guard let catalog = model.snapshot?.chillCatalog else { return ([], []) }

        switch selectedCatalog {
        case .movies:
            let lists = catalog.movies.compactMap(\.source).uniquedCaseInsensitive()
            let genres = catalog.movies.flatMap(\.genres).uniquedCaseInsensitive()
            return (lists, genres)
        case .series:
            let sources = catalog.series.compactMap(\.source)
            let lists = (sources.isEmpty ? catalog.series.flatMap(\.networks) : sources).uniquedCaseInsensitive()
            return (lists, [])
        }
    }

    private var activeFilter: String {
        (catalogFilters.lists + catalogFilters.genres).first {
            $0.caseInsensitiveCompare(selectedFilter) == .orderedSame
        } ?? ""
    }

    private var visibleMovies: [CargoRemoteMovie] {
        guard let movies = model.snapshot?.chillCatalog.movies else { return [] }
        return movies.filter { movie in
            matchesFilter([movie.source].compactMap { $0 } + movie.genres)
        }
    }

    private var visibleSeries: [CargoRemoteSeries] {
        guard let series = model.snapshot?.chillCatalog.series else { return [] }
        return series.filter { show in
            matchesFilter([show.source].compactMap { $0 } + show.networks)
        }
    }

    private var filterMenuTitle: String {
        if !activeFilter.isEmpty { return activeFilter }
        return selectedCatalog == .movies ? "All Lists & Genres" : "All Lists"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if showingSearchResults {
                        searchResults
                    } else {
                        catalogControls
                        catalogContent
                    }
                }
                .padding()
            }
            .navigationTitle("Discover")
            .searchable(text: $query, prompt: "Search releases")
            .onSubmit(of: .search) {
                Task { await model.search(query: query) }
            }
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !showingSearchResults {
                        CargoMediaViewModeMenu(selection: $viewMode)
                    }
                    Button {
                        Task { await model.execute(.refreshChillCatalog) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onChange(of: selectedCatalog) { _, _ in
                selectedFilter = ""
            }
            .sheet(item: $selectedDetail) { detail in
                CargoTitleDetailView(detail: detail) { action in
                    switch action {
                    case .sendMovie(let id):
                        Task { await model.execute(.sendChillMovie(id: id)) }
                    case .searchReleases(let query):
                        self.query = query
                        Task { await model.search(query: query) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var catalogControls: some View {
        Picker("Catalog", selection: $selectedCatalog) {
            ForEach(CargoDiscoverCatalog.allCases) { catalog in
                Text(catalog.title).tag(catalog)
            }
        }
        .pickerStyle(.segmented)

        filterMenu
    }

    @ViewBuilder
    private var filterMenu: some View {
        Menu {
            Button {
                selectedFilter = ""
            } label: {
                filterLabel("All", activeFilter.isEmpty)
            }

            if !catalogFilters.lists.isEmpty {
                Divider()
                Section("Lists") {
                    ForEach(catalogFilters.lists, id: \.self) { option in
                        Button {
                            selectedFilter = option
                        } label: {
                            filterLabel(option, activeFilter.caseInsensitiveCompare(option) == .orderedSame)
                        }
                    }
                }
            }

            if !catalogFilters.genres.isEmpty {
                Divider()
                Section("Genres") {
                    ForEach(catalogFilters.genres, id: \.self) { option in
                        Button {
                            selectedFilter = option
                        } label: {
                            filterLabel(option, activeFilter.caseInsensitiveCompare(option) == .orderedSame)
                        }
                    }
                }
            }
        } label: {
            Label(filterMenuTitle, systemImage: "line.3.horizontal.decrease.circle")
                .lineLimit(1)
        }
        .menuOrder(.fixed)
    }

    private func filterLabel(_ title: String, _ selected: Bool) -> some View {
        if selected {
            return AnyView(Label(title, systemImage: "checkmark"))
        }
        return AnyView(Text(title))
    }

    @ViewBuilder
    private var catalogContent: some View {
        switch selectedCatalog {
        case .movies:
            if visibleMovies.isEmpty {
                ContentUnavailableView(
                    "No movies match this filter",
                    systemImage: "film",
                    description: Text("Try another list or genre.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                CargoDiscoverSection(title: "Top movies") {
                    if viewMode == .posters {
                        CargoPosterGrid {
                            ForEach(visibleMovies) { movie in
                                movieCard(movie)
                            }
                        }
                    } else {
                        ForEach(visibleMovies) { movie in
                            movieRow(movie)
                        }
                    }
                }
            }
        case .series:
            if visibleSeries.isEmpty {
                ContentUnavailableView(
                    "No series match this filter",
                    systemImage: "tv",
                    description: Text("Try another list.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                CargoDiscoverSection(title: "Top series") {
                    if viewMode == .posters {
                        CargoPosterGrid {
                            ForEach(visibleSeries) { series in
                                seriesCard(series)
                            }
                        }
                    } else {
                        ForEach(visibleSeries) { series in
                            seriesRow(series)
                        }
                    }
                }
            }
        }
    }

    private func movieRow(_ movie: CargoRemoteMovie) -> some View {
        Button {
            selectedDetail = detail(for: movie)
        } label: {
            CargoMediaLine(
                title: movie.displayTitle,
                subtitle: movieSubtitle(movie),
                posterURL: movie.posterURL
            )
        }
        .buttonStyle(.plain)
    }

    private func movieCard(_ movie: CargoRemoteMovie) -> some View {
        Button {
            selectedDetail = detail(for: movie)
        } label: {
            CargoPosterCard(
                title: movie.displayTitle,
                subtitle: movieSubtitle(movie),
                posterURL: movie.posterURL
            )
        }
        .buttonStyle(.plain)
    }

    private func seriesRow(_ series: CargoRemoteSeries) -> some View {
        Button {
            selectedDetail = detail(for: series)
        } label: {
            CargoMediaLine(
                title: series.title,
                subtitle: seriesSubtitle(series),
                posterURL: series.posterURL,
                badge: series.statusLabel.isEmpty ? nil : series.statusLabel
            )
        }
        .buttonStyle(.plain)
    }

    private func seriesCard(_ series: CargoRemoteSeries) -> some View {
        Button {
            selectedDetail = detail(for: series)
        } label: {
            CargoPosterCard(
                title: series.title,
                subtitle: seriesSubtitle(series),
                posterURL: series.posterURL,
                badge: series.statusLabel.isEmpty ? nil : series.statusLabel
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var searchResults: some View {
        if let search = model.searchState {
            VStack(alignment: .leading, spacing: 12) {
                Text(search.status)
                    .font(.title3.weight(.semibold))
                ForEach(search.results) { result in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.title).font(.headline)
                        if let release = result.releaseInfo {
                            Text([release.resolution, release.quality, release.source].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Send to Put.io") {
                            Task {
                                await model.execute(.sendChillRelease(url: result.link, title: result.title))
                            }
                        }
                        .disabled(result.link.isEmpty)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    private func matchesFilter(_ values: [String]) -> Bool {
        activeFilter.isEmpty || values.contains {
            $0.caseInsensitiveCompare(activeFilter) == .orderedSame
        }
    }

    private func movieSubtitle(_ movie: CargoRemoteMovie) -> String {
        [
            movie.year > 0 ? String(movie.year) : nil,
            movie.rating > 0 ? "\(movie.rating.formatted(.number.precision(.fractionLength(1)))) rating" : nil,
            movie.source
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func seriesSubtitle(_ series: CargoRemoteSeries) -> String {
        [
            series.year > 0 ? String(series.year) : nil,
            series.seasonCount > 0 ? "\(series.seasonCount) season\(series.seasonCount == 1 ? "" : "s")" : nil,
            series.rating > 0 ? "\(series.rating.formatted(.number.precision(.fractionLength(1)))) rating" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func detail(for movie: CargoRemoteMovie) -> CargoTitleDetail {
        CargoTitleDetail(
            id: "movie-\(movie.id)",
            title: movie.displayTitle,
            subtitle: "\(movie.year) · \(movie.rating.formatted(.number.precision(.fractionLength(1)))) rating",
            posterURL: movie.posterURL,
            rating: movie.rating,
            overview: movie.overview,
            metadataLine: movie.genres.joined(separator: " · "),
            externalURL: URL(string: movie.externalURL),
            externalLabel: movie.externalURL.isEmpty ? nil : "Open on TMDB",
            action: .sendMovie(id: movie.id)
        )
    }

    private func detail(for series: CargoRemoteSeries) -> CargoTitleDetail {
        CargoTitleDetail(
            id: "series-\(series.id)",
            title: series.title,
            subtitle: "\(series.year) · \(series.seasonCount) seasons",
            posterURL: series.posterURL,
            rating: series.rating,
            overview: series.overview,
            metadataLine: [series.statusLabel, series.networks.joined(separator: " · ")]
                .filter { !$0.isEmpty }
                .joined(separator: " · "),
            externalURL: URL(string: series.externalURL),
            externalLabel: series.externalURL.isEmpty ? nil : "Open on TMDB",
            action: .searchReleases(query: "\(series.title) \(series.year)")
        )
    }
}

private struct CargoDiscoverSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
            LazyVStack(spacing: 0, content: content)
        }
    }
}

private enum CargoWatchlistFilter: String, CaseIterable, Identifiable {
    case all
    case wanted
    case onPutIO
    case inInbox
    case inLibrary

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .wanted: "Wanted"
        case .onPutIO: "On Put.io"
        case .inInbox: "In Inbox"
        case .inLibrary: "In Library"
        }
    }
}

struct CargoWatchlistView: View {
    @Environment(CargoClientModel.self) private var model
    @State private var filter: CargoWatchlistFilter = .all
    @State private var viewMode: CargoMediaViewMode = .posters
    @State private var selectedDetail: CargoTitleDetail?

    private var visibleItems: [(item: CargoRemoteWatchlistItem, status: String)] {
        (model.snapshot?.watchlist ?? []).compactMap { item in
            let status = status(for: item)
            let matches: Bool
            switch filter {
            case .all: matches = true
            case .wanted: matches = status == "Wanted"
            case .onPutIO: matches = ["Available", "Queued"].contains(status)
            case .inInbox: matches = status == "In Inbox"
            case .inLibrary: matches = status == "Organized"
            }
            return matches ? (item, status) : nil
        }
    }

    var body: some View {
        NavigationStack {
            watchlistContent
            .refreshable { await model.refresh() }
            .navigationTitle("Watchlist")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(CargoWatchlistFilter.allCases) { option in
                            Button {
                                filter = option
                            } label: {
                                if filter == option {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        Label(filter.title, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    CargoMediaViewModeMenu(selection: $viewMode)
                    Button {
                        Task { await model.execute(.refreshWatchlist) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(item: $selectedDetail) { detail in
                CargoTitleDetailView(detail: detail) { action in
                    if case .searchReleases(let query) = action {
                        Task { await model.search(query: query) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var watchlistContent: some View {
        if viewMode == .posters {
            ScrollView {
                if visibleItems.isEmpty {
                    watchlistEmptyState
                } else {
                    CargoPosterGrid {
                        ForEach(visibleItems, id: \.item.id) { entry in
                            Button {
                                selectedDetail = detail(for: entry.item, status: entry.status)
                            } label: {
                                CargoPosterCard(
                                    title: entry.item.title,
                                    subtitle: subtitle(for: entry.item),
                                    posterURL: entry.item.metadata?.posterURL,
                                    badge: entry.status
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        } else {
            List {
                if visibleItems.isEmpty {
                    watchlistEmptyState
                } else {
                    ForEach(visibleItems, id: \.item.id) { entry in
                        Button {
                            selectedDetail = detail(for: entry.item, status: entry.status)
                        } label: {
                            CargoMediaLine(
                                title: entry.item.title,
                                subtitle: subtitle(for: entry.item),
                                posterURL: entry.item.metadata?.posterURL,
                                badge: entry.status
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var watchlistEmptyState: some View {
        ContentUnavailableView(
            "No watchlist titles",
            systemImage: "star",
            description: Text(filter == .all ? "The resident watchlist is empty." : "No titles match this filter.")
        )
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private func subtitle(for item: CargoRemoteWatchlistItem) -> String {
        [item.year.map(String.init), item.titleType]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func status(for item: CargoRemoteWatchlistItem) -> String {
        guard let snapshot = model.snapshot else { return "Wanted" }
        if snapshot.library.contains(where: { matches(item, title: $0.title, year: $0.year) }) {
            return "Organized"
        }
        let matchingJobs = snapshot.syncJobs.filter { normalized($0.name).contains(normalized(item.title)) }
        if matchingJobs.contains(where: { $0.status == .needsReview }) { return "In Inbox" }
        if matchingJobs.contains(where: { [.queued, .downloading, .importing].contains($0.status) }) { return "Queued" }
        if snapshot.mediaFiles.contains(where: { normalized($0.name).contains(normalized(item.title)) }) { return "Available" }
        return "Wanted"
    }

    private func matches(_ item: CargoRemoteWatchlistItem, title: String, year: Int?) -> Bool {
        normalized(title).contains(normalized(item.title)) && (item.year == nil || year == nil || item.year == year)
    }

    private func normalized(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func detail(for item: CargoRemoteWatchlistItem, status: String) -> CargoTitleDetail {
        let query = item.year.map { "\(item.title) \($0)" } ?? item.title
        return CargoTitleDetail(
            id: "watchlist-\(item.id)",
            title: item.title,
            subtitle: [item.year.map(String.init), item.titleType, status]
                .compactMap { $0 }
                .joined(separator: " · "),
            posterURL: item.metadata?.posterURL,
            rating: item.metadata?.rating,
            overview: item.metadata?.overview,
            metadataLine: item.metadata?.episodeCounts.isEmpty == false ? "TMDB metadata available" : nil,
            externalURL: URL(string: "https://www.imdb.com/title/\(item.id)/"),
            externalLabel: item.id.hasPrefix("tt") ? "Open on IMDb" : nil,
            action: .searchReleases(query: query)
        )
    }
}

struct CargoInboxView: View {
    @Environment(CargoClientModel.self) private var model

    var body: some View {
        NavigationStack {
            List(model.snapshot?.syncJobs ?? []) { job in
                VStack(alignment: .leading, spacing: 4) {
                    CargoMediaLine(
                        title: job.displayName ?? model.displayTitle(for: job.name),
                        subtitle: nil,
                        posterURL: job.posterURL ?? model.posterURL(for: job.name),
                        badge: job.statusLabel,
                        progress: [.queued, .downloading, .importing].contains(job.status) ? job.progress : nil,
                        error: job.errorMessage
                    )
                    if job.status == .needsReview {
                        Button("Organize") {
                            Task { await model.execute(.organizeLocalJob(id: job.id)) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Inbox")
        }
    }
}

struct CargoSettingsView: View {
    @Environment(CargoClientModel.self) private var model

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    Label(model.connectionState.label, systemImage: "network")
                    LabeledContent("Resident", value: model.residentAddress)
                    if let snapshot = model.snapshot {
                        LabeledContent("Updated", value: snapshot.lastUpdated.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Section("Startup") {
                    Picker(
                        "Start in",
                        selection: Binding(
                            get: { model.startTab },
                            set: { model.setStartTab($0) }
                        )
                    ) {
                        ForEach(CargoStartTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                }
                if let disk = model.snapshot?.disk {
                    Section("Put.io storage") {
                        CargoDiskStatusView(disk: disk)
                    }
                }
                Section {
                    Button("Refresh") { Task { await model.refresh() } }
                    Button("Disconnect", role: .destructive) { Task { await model.disconnect() } }
                }
                if let lastError = model.lastError {
                    Section("Last error") { Text(lastError).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct CargoHistoryView: View {
    @Environment(CargoClientModel.self) private var model

    var body: some View {
        NavigationStack {
            List(model.snapshot?.history ?? []) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.title)
                            .font(.headline)
                        Spacer()
                        Text(entry.date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.vertical, 3)
            }
            .refreshable { await model.refresh() }
            .navigationTitle("History")
        }
    }
}

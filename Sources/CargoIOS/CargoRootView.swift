import CargoRemoteKit
import SwiftUI

struct CargoRootView: View {
    @Environment(CargoClientModel.self) private var model

    var body: some View {
        Group {
            if model.isConnected {
                CargoDashboardView()
            } else {
                CargoConnectView()
            }
        }
        .animation(.default, value: model.isConnected)
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
    @State private var clientName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Connect to the Cargo resident Mac to control transfers and view its library.")
                        .foregroundStyle(.secondary)
                }

                Section("Resident") {
                    TextField("http://mac-name:39817", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Resident token", text: $token)
                    TextField("This device", text: $clientName)
                }

                Section {
                    Button {
                        Task { await model.connect(address: address, token: token, clientName: clientName) }
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

                Section {
                    Label(model.connectionState.label, systemImage: model.isConnected ? "checkmark.circle.fill" : "network")
                        .foregroundStyle(model.isConnected ? .green : .secondary)
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

    var body: some View {
        TabView {
            CargoTransfersView()
                .tabItem { Label("Transfers", systemImage: "arrow.down.circle") }
            CargoFilesView()
                .tabItem { Label("Files", systemImage: "folder") }
            CargoLibraryView()
                .tabItem { Label("Library", systemImage: "film") }
            CargoDiscoverView()
                .tabItem { Label("Discover", systemImage: "sparkles") }
            CargoWatchlistView()
                .tabItem { Label("Watchlist", systemImage: "star") }
            CargoInboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
            CargoHistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            CargoSettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
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
    let transfer: CargoRemoteTransfer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(transfer.name)
                .font(.headline)
                .lineLimit(2)
            HStack {
                Text(transfer.statusLabel)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: transfer.sizeBytes, countStyle: .file))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ProgressView(value: transfer.progress)
        }
        .padding(.vertical, 4)
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

struct CargoLibraryView: View {
    @Environment(CargoClientModel.self) private var model

    var body: some View {
        NavigationStack {
            List(model.snapshot?.library ?? []) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                    Text(detail(for: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.relativePath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.vertical, 3)
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Library")
        }
    }

    private func detail(for item: CargoRemoteLibraryItem) -> String {
        var result = item.kind == .movie ? "Movie" : "TV Show"
        if let year = item.year { result += " · \(year)" }
        if item.kind == .show { result += " · \(item.episodeCount) episodes" }
        return result
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
        HStack {
            Label {
                VStack(alignment: .leading) {
                    Text(file.name).font(.headline).lineLimit(2)
                    Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon).foregroundStyle(.blue)
            }
            Spacer()
            Button("Sync") {
                Task { await model.execute(.enqueueLocalSync(remoteFileID: file.id)) }
            }
            .buttonStyle(.bordered)
            Button(role: .destructive) { fileToDelete = file } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }
}

struct CargoDiscoverView: View {
    @Environment(CargoClientModel.self) private var model
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let catalog = model.snapshot?.chillCatalog
                if let catalog, !catalog.movies.isEmpty {
                    Section("Top movies") {
                        ForEach(catalog.movies.prefix(12)) { movie in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(movie.displayTitle).font(.headline)
                                    Text("\(movie.year) · \(movie.rating, specifier: "%.1f") rating")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Send") {
                                    Task { await model.execute(.sendChillMovie(id: movie.id)) }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                if let search = model.searchState {
                    Section(search.status) {
                        ForEach(search.results) { result in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(result.title)
                                    .font(.headline)
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
                        }
                    }
                }
            }
            .navigationTitle("Discover")
            .searchable(text: $query, prompt: "Search releases")
            .onSubmit(of: .search) {
                Task { await model.search(query: query) }
            }
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.execute(.refreshChillCatalog) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

struct CargoWatchlistView: View {
    @Environment(CargoClientModel.self) private var model

    var body: some View {
        NavigationStack {
            List(model.snapshot?.watchlist ?? []) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.headline)
                    HStack {
                        if let year = item.year { Text(String(year)) }
                        if let titleType = item.titleType { Text(titleType) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Watchlist")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.execute(.refreshWatchlist) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

struct CargoInboxView: View {
    @Environment(CargoClientModel.self) private var model

    var body: some View {
        NavigationStack {
            List(model.snapshot?.syncJobs ?? []) { job in
                VStack(alignment: .leading, spacing: 8) {
                    Text(job.name)
                        .font(.headline)
                    HStack {
                        Text(job.statusLabel)
                        Spacer()
                        if job.hasError { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ProgressView(value: job.progress)
                    if job.status == .needsReview {
                        Button("Organize") {
                            Task { await model.execute(.organizeLocalJob(id: job.id)) }
                        }
                    }
                }
                .padding(.vertical, 4)
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

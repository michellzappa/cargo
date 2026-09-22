import SwiftUI
import UIKit

actor CargoPosterImageCache {
    static let shared = CargoPosterImageCache()

    private let memory = NSCache<NSURL, NSData>()

    func data(for url: URL) async -> Data? {
        let key = url as NSURL
        if let cached = memory.object(forKey: key) {
            return cached as Data
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let response = response as? HTTPURLResponse,
              200..<300 ~= response.statusCode else {
            return nil
        }

        memory.setObject(data as NSData, forKey: key)
        return data
    }
}

struct CargoPosterImage: View {
    let urlString: String?
    var cornerRadius: CGFloat = 12

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.quaternary)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "film.stack")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: urlString) {
            image = nil
            guard let urlString,
                  let url = URL(string: urlString),
                  url.scheme == "https" || url.scheme == "http" else { return }
            guard let data = await CargoPosterImageCache.shared.data(for: url) else { return }
            image = UIImage(data: data)
        }
    }
}

struct CargoPosterCard: View {
    let title: String
    let subtitle: String?
    let posterURL: String?
    let badge: String?

    init(title: String, subtitle: String? = nil, posterURL: String?, badge: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.posterURL = posterURL
        self.badge = badge
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                CargoPosterImage(urlString: posterURL)
                if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.72), in: Capsule())
                        .padding(8)
                }
            }

            Text(title)
                .font(.headline)
                .lineLimit(2)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .contentShape(Rectangle())
    }
}

/// The shared media row used by every media list. Keeping artwork, title,
/// status, progress and errors in one component makes Transfers, Inbox,
/// Put.io files, Library, Watchlist and Discover read as one product.
struct CargoMediaLine: View {
    let title: String
    let subtitle: String?
    let posterURL: String?
    let badge: String?
    let progress: Double?
    let error: String?

    init(
        title: String,
        subtitle: String? = nil,
        posterURL: String? = nil,
        badge: String? = nil,
        progress: Double? = nil,
        error: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.posterURL = posterURL
        self.badge = badge
        self.progress = progress
        self.error = error
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CargoPosterImage(urlString: posterURL, cornerRadius: 8)
                .frame(width: 56, height: 84)
                .clipped()

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(badgeColor)
                        .lineLimit(1)
                }

                if let progress {
                    ProgressView(value: progress)
                        .tint(.accentColor)
                }

                if let error, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var badgeColor: Color {
        let lower = badge?.lowercased() ?? ""
        if lower.contains("fail") || lower.contains("error") { return .red }
        if lower.contains("complete") || lower.contains("organized") { return .green }
        if lower.contains("download") || lower.contains("queued") || lower.contains("inbox") { return .orange }
        return .secondary
    }
}

enum CargoTitleDetailAction: Equatable {
    case sendMovie(id: String)
    case searchReleases(query: String)
}

struct CargoTitleDetail: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let posterURL: String?
    let rating: Double?
    let overview: String?
    let metadataLine: String?
    let externalURL: URL?
    let externalLabel: String?
    let action: CargoTitleDetailAction?
}

struct CargoTitleDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let detail: CargoTitleDetail
    let onAction: (CargoTitleDetailAction) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        CargoPosterImage(urlString: detail.posterURL)
                            .frame(width: 128)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(detail.title)
                                .font(.title2.weight(.bold))
                            Text(detail.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let rating = detail.rating, rating > 0 {
                                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.orange)
                            }
                            if let metadataLine = detail.metadataLine, !metadataLine.isEmpty {
                                Text(metadataLine)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let overview = detail.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 10) {
                        if let action = detail.action {
                            Button(actionLabel(for: action)) {
                                onAction(action)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        }

                        if let externalURL = detail.externalURL,
                           let externalLabel = detail.externalLabel {
                            Link(externalLabel, destination: externalURL)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func actionLabel(for action: CargoTitleDetailAction) -> String {
        switch action {
        case .sendMovie:
            "Send to Put.io"
        case .searchReleases:
            "Search Releases"
        }
    }
}

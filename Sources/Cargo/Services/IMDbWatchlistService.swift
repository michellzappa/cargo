import Foundation

@MainActor
final class IMDbWatchlistService {
    enum ServiceError: LocalizedError {
        case invalidURL
        case requestFailed(String)
        case profileUnavailable
        case watchlistUnavailable
        case noItemsFound

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                "The IMDb Watchlist URL is invalid."
            case .requestFailed(let message):
                "IMDb Watchlist request failed: \(message)"
            case .profileUnavailable:
                "IMDb did not expose this public profile to Cargo."
            case .watchlistUnavailable:
                "IMDb did not expose a public Watchlist for this profile."
            case .noItemsFound:
                "IMDb exposed the Watchlist, but it contains no titles."
            }
        }
    }

    private struct GraphQLError: Decodable {
        let message: String
    }

    private struct GraphQLResponse<Payload: Decodable>: Decodable {
        let data: Payload?
        let errors: [GraphQLError]?
    }

    private struct ProfilePayload: Decodable {
        let userProfile: Profile?
    }

    private struct Profile: Decodable {
        let userId: String?
    }

    private struct WatchlistPayload: Decodable {
        let predefinedList: Watchlist?
    }

    private struct Watchlist: Decodable {
        let id: String?
    }

    private struct ItemsPayload: Decodable {
        let list: IMDbList?
    }

    private struct IMDbList: Decodable {
        let items: Items
    }

    private struct Items: Decodable {
        let edges: [Edge]
        let pageInfo: PageInfo
    }

    private struct Edge: Decodable {
        let node: Node?
    }

    private struct Node: Decodable {
        let listItem: Title?
    }

    private struct Title: Decodable {
        let id: String
        let titleText: TextValue
        let releaseYear: YearValue?
        let titleType: TitleType?
    }

    private struct TextValue: Decodable {
        let text: String
    }

    private struct YearValue: Decodable {
        let year: Int?
    }

    private struct TitleType: Decodable {
        let id: String?
    }

    private struct PageInfo: Decodable {
        let endCursor: String?
        let hasNextPage: Bool
    }

    private static let endpoint = URL(string: "https://api.graphql.imdb.com/")!
    private static let profileQuery = """
    query ResolveProfile($profileID: ID) {
      userProfile(input: { profileId: $profileID }) {
        userId
      }
    }
    """
    private static let watchlistQuery = """
    query ResolveWatchlist($userID: ID!) {
      predefinedList(classType: WATCH_LIST, userId: $userID) {
        id
      }
    }
    """
    private static let itemsQuery = """
    query WatchlistItems($listID: ID!, $first: Int!, $after: ID) {
      list(id: $listID) {
        items(first: $first, after: $after) {
          edges {
            node {
              listItem {
                ... on Title {
                  id
                  titleText { text }
                  releaseYear { year }
                  titleType { id }
                }
              }
            }
          }
          pageInfo {
            endCursor
            hasNextPage
          }
        }
      }
    }
    """

    func fetchItems(from urlString: String) async throws -> [IMDbWatchlistItem] {
        guard let url = URL(string: urlString),
              url.scheme == "https",
              url.host?.lowercased().hasSuffix("imdb.com") == true,
              url.path.lowercased().contains("watchlist"),
              let identifier = Self.userIdentifier(from: url) else {
            throw ServiceError.invalidURL
        }

        let userID: String
        if identifier.hasPrefix("ur") {
            userID = identifier
        } else {
            let profile: ProfilePayload = try await request(
                query: Self.profileQuery,
                variables: ["profileID": identifier]
            )
            guard let resolvedUserID = profile.userProfile?.userId,
                  resolvedUserID.hasPrefix("ur") else {
                throw ServiceError.profileUnavailable
            }
            userID = resolvedUserID
        }

        let watchlist: WatchlistPayload = try await request(
            query: Self.watchlistQuery,
            variables: ["userID": userID]
        )
        guard let listID = watchlist.predefinedList?.id, !listID.isEmpty else {
            throw ServiceError.watchlistUnavailable
        }

        var results: [IMDbWatchlistItem] = []
        var after: String?

        while true {
            var variables: [String: Any] = [
                "listID": listID,
                "first": 250
            ]
            if let after {
                variables["after"] = after
            }

            let page: ItemsPayload = try await request(
                query: Self.itemsQuery,
                variables: variables
            )
            let items = page.list?.items
            results.append(contentsOf: items?.edges.compactMap { edge in
                guard let title = edge.node?.listItem else { return nil }
                return IMDbWatchlistItem(
                    id: title.id,
                    title: title.titleText.text,
                    year: title.releaseYear?.year,
                    titleType: title.titleType?.id
                )
            } ?? [])

            guard let items,
                  items.pageInfo.hasNextPage,
                  let nextCursor = items.pageInfo.endCursor,
                  nextCursor != after else {
                break
            }
            after = nextCursor
        }

        guard !results.isEmpty else {
            throw ServiceError.noItemsFound
        }
        return results
    }

    private func request<Payload: Decodable>(
        query: String,
        variables: [String: Any]
    ) async throws -> Payload {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Cargo/0.3", forHTTPHeaderField: "User-Agent")
        request.setValue("imdb-web-next", forHTTPHeaderField: "x-imdb-client-name")
        request.setValue("https://www.imdb.com/", forHTTPHeaderField: "Origin")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "query": query,
                "variables": variables
            ],
            options: []
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw ServiceError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }

            let decoded = try JSONDecoder().decode(GraphQLResponse<Payload>.self, from: data)
            if let message = decoded.errors?.first?.message {
                throw ServiceError.requestFailed(message)
            }
            guard let payload = decoded.data else {
                throw ServiceError.requestFailed("IMDb returned no data")
            }
            return payload
        } catch let error as ServiceError {
            throw error
        } catch {
            throw ServiceError.requestFailed(error.localizedDescription)
        }
    }

    private static func userIdentifier(from url: URL) -> String? {
        let components = url.pathComponents
        guard let userIndex = components.firstIndex(of: "user"),
              components.index(after: userIndex) < components.endIndex else {
            return nil
        }

        let identifier = components[components.index(after: userIndex)]
        guard identifier.hasPrefix("p.") || identifier.hasPrefix("ur") else {
            return nil
        }
        return identifier
    }
}

import Foundation

enum PutIOOAuth {
    // Cargo uses one registered OAuth application. The user only needs to
    // authorize their Put.io account in the browser.
    static let clientID = "9732"
    static let redirectURI = URL(string: "cargo://oauth/callback")!
    static let authorizationEndpoint = URL(string: "https://api.put.io/v2/oauth2/authenticate")!

    struct Callback: Equatable, Sendable {
        let accessToken: String
        let state: String
    }

    enum OAuthError: LocalizedError, Equatable {
        case invalidCallback
        case provider(String)
        case stateMismatch

        var errorDescription: String? {
            switch self {
            case .invalidCallback:
                "Cargo received an invalid Put.io authorization callback."
            case .provider(let message):
                "Put.io authorization failed: \(message)"
            case .stateMismatch:
                "Put.io authorization could not be verified. Please try again."
            }
        }
    }

    static func authorizationURL(state: String) throws -> URL {
        guard var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw OAuthError.invalidCallback
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components.url else { throw OAuthError.invalidCallback }
        return url
    }

    static func parseCallback(_ url: URL, expectedState: String) throws -> Callback {
        guard url.scheme == redirectURI.scheme,
              url.host == redirectURI.host,
              url.path == redirectURI.path else {
            throw OAuthError.invalidCallback
        }

        let values = fragmentValues(from: url.fragment)
        if let error = values["error"] {
            throw OAuthError.provider(values["error_description"] ?? error)
        }

        guard let accessToken = values["access_token"],
              !accessToken.isEmpty,
              let state = values["state"],
              state == expectedState else {
            if values["state"] != expectedState {
                throw OAuthError.stateMismatch
            }
            throw OAuthError.invalidCallback
        }

        return Callback(accessToken: accessToken, state: state)
    }

    private static func fragmentValues(from fragment: String?) -> [String: String] {
        guard let fragment, !fragment.isEmpty else { return [:] }
        var components = URLComponents()
        components.query = fragment
        return (components.queryItems ?? []).reduce(into: [String: String]()) { values, item in
            if let value = item.value {
                values[item.name] = value
            }
        }
    }
}

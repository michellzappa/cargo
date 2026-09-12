import Foundation
import WebKit

@MainActor
final class IMDbWatchlistService: NSObject, WKNavigationDelegate {
    enum ServiceError: LocalizedError {
        case invalidURL
        case timedOut
        case pageUnavailable
        case noItemsFound

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                "The IMDb Watchlist URL is invalid."
            case .timedOut:
                "IMDb did not finish loading the Watchlist."
            case .pageUnavailable:
                "IMDb did not expose the public Watchlist to Cargo."
            case .noItemsFound:
                "IMDb loaded, but Cargo could not find any Watchlist titles."
            }
        }
    }

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<[IMDbWatchlistItem], Error>?
    private var timeoutTask: Task<Void, Never>?

    func fetchItems(from urlString: String) async throws -> [IMDbWatchlistItem] {
        guard let url = URL(string: urlString),
              url.scheme == "https",
              url.host?.lowercased().hasSuffix("imdb.com") == true else {
            throw ServiceError.invalidURL
        }

        if continuation != nil {
            throw ServiceError.pageUnavailable
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.navigationDelegate = self
        webView = browser

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(ServiceError.timedOut))
            }
            browser.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(Self.extractionScript) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if error != nil {
                    self.finish(.failure(ServiceError.pageUnavailable))
                    return
                }

                guard let json = result as? String,
                      let data = json.data(using: .utf8),
                      let items = try? JSONDecoder().decode([IMDbWatchlistItem].self, from: data),
                      !items.isEmpty else {
                    self.finish(.failure(ServiceError.noItemsFound))
                    return
                }
                self.finish(.success(items))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(ServiceError.pageUnavailable))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(ServiceError.pageUnavailable))
    }

    private func finish(_ result: Result<[IMDbWatchlistItem], Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView = nil
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }

    private static let extractionScript = """
    (() => {
      const nextDataElement = document.getElementById('__NEXT_DATA__');
      if (!nextDataElement) return JSON.stringify([]);
      let data;
      try { data = JSON.parse(nextDataElement.textContent || '{}'); } catch (_) { return JSON.stringify([]); }

      const results = [];
      const seen = new Set();
      const textValue = value => typeof value === 'string' ? value : value?.text;
      const add = value => {
        if (!value || typeof value !== 'object') return;
        const title = value.title && typeof value.title === 'object' ? value.title : value;
        const id = title.id || value.id;
        const name = textValue(title.titleText) || textValue(value.titleText) || title.title;
        if (!/^tt\\d+$/.test(id || '') || !name || seen.has(id)) return;
        const rawYear = title.releaseYear?.year || title.releaseDate?.year || value.releaseYear?.year;
        const year = Number.isFinite(Number(rawYear)) ? Number(rawYear) : null;
        results.push({ id, title: name, year, titleType: title.titleType?.id || null });
        seen.add(id);
      };

      const edges = data?.props?.pageProps?.mainColumnData?.predefinedList?.titleListItemSearch?.edges;
      if (Array.isArray(edges)) edges.forEach(edge => add(edge?.node));

      const walk = value => {
        if (!value || typeof value !== 'object') return;
        add(value);
        if (Array.isArray(value)) value.forEach(walk);
        else Object.values(value).forEach(walk);
      };
      if (!results.length) walk(data);
      return JSON.stringify(results);
    })()
    """
}

import Foundation

/// Terminal and agent access to Cargo: `Cargo --cli <command>`, installed as
/// `cargoctl`. It runs inside the signed app binary, so it reads the Keychain
/// items without a prompt and no token has to live in a file. It never prints
/// a credential.
enum CargoCLI {
    static var isInvocation: Bool {
        CommandLine.arguments.dropFirst().first == "--cli"
    }

    static func runAndExit() -> Never {
        let arguments = Array(CommandLine.arguments.dropFirst(2))
        Task.detached {
            exit(await run(arguments))
        }
        dispatchMain()
    }

    private static let usage = """
    cargoctl: inspect and drive the running Cargo resident. Output is JSON.

      status                   build, Put.io state, disk, counts
      transfers | files | media | jobs | history | library | watchlist | subscriptions | ledger
                               one list from the resident's snapshot
      subscriptions add-series <imdb-id> <tmdb-id> <title> [--year <n>] [--backfill newOnly|currentSeason|all]
                               add a series subscription
      subscriptions add-feed <url> <title> [--keyword <text>] [--unwanted <text>] [--backfill newOnly|currentSeason|all]
                               add a feed subscription
      subscriptions pause | resume | remove <id>
                               pause, resume, or remove a subscription
      ledger set <imdb-id> <season> <episode> <state>
                               set one episode's state in the ledger
      state                    the whole snapshot
      local [key]              Cargo's state file, with local paths and settings
      putio files [parent-id]  Put.io's unfiltered listing, with raw file types
      putio transfers          Put.io's raw transfers, with error messages
      putio events             Put.io's raw activity feed
      putio trash              Put.io's trash, which counts against the quota
      refresh                  re-list Put.io now; the next cycle queues new media
      command '<json>'         any /v1/commands body, such as {"type":"retryTransfer","id":1}
      logs [minutes]           Cargo's unified log, 60 minutes by default

    List options: --grep <text> keeps entries that contain the text;
                  --limit <n> keeps the first n entries.
    """

    private static let snapshotLists = [
        "transfers": "transfers",
        "files": "files",
        "media": "mediaFiles",
        "jobs": "syncJobs",
        "history": "history",
        "library": "library",
        "watchlist": "watchlist",
        "subscriptions": "subscriptions",
        "ledger": "episodeLedger"
    ]

    private struct Failure: Error {
        let message: String
    }

    private struct ListOptions {
        var grep: String?
        var limit: Int?
    }

    private static func run(_ arguments: [String]) async -> Int32 {
        do {
            print(try await output(of: arguments))
            return 0
        } catch {
            printError(message(for: error))
            return 1
        }
    }

    /// The text a command prints. `CargoMCP` calls this too, so the CLI and
    /// the MCP server stay one implementation.
    static func output(of arguments: [String]) async throws -> String {
        var positional: [String] = []
        var options = ListOptions()
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            switch argument {
            case "--grep":
                guard let value = remaining.popFirst() else { throw Failure(message: "--grep needs a value.") }
                options.grep = value
            case "--limit":
                guard let value = remaining.popFirst().flatMap(Int.init), value >= 0 else {
                    throw Failure(message: "--limit needs a number.")
                }
                options.limit = value
            default:
                positional.append(argument)
            }
        }
        switch try await dispatch(positional, options: options) {
        case let text as String:
            return text
        case let value:
            return try json(value)
        }
    }

    static func message(for error: Error) -> String {
        (error as? Failure)?.message ?? error.localizedDescription
    }

    /// A String result is printed as it is; anything else is printed as JSON.
    private static func dispatch(_ arguments: [String], options: ListOptions) async throws -> Any? {
        guard let command = arguments.first else { return usage }
        if command == "subscriptions", arguments.count > 1 {
            let remoteCommand = try parseSubscriptionCommand(Array(arguments.dropFirst()))
            return try await sendCommand(remoteCommand)
        }
        if command == "ledger", arguments.count > 1 {
            let remoteCommand = try parseLedgerCommand(Array(arguments.dropFirst()))
            return try await sendCommand(remoteCommand)
        }
        if let key = snapshotLists[command] {
            let snapshot = try await residentSnapshot()
            return filtered(snapshot[key], options: options)
        }
        switch command {
        case "help", "--help", "-h":
            return usage
        case "status":
            return try await status()
        case "state":
            return try await residentSnapshot()
        case "local":
            return try localState(key: arguments.dropFirst().first, options: options)
        case "putio":
            return try await putIO(Array(arguments.dropFirst()), options: options)
        case "refresh":
            return try await sendCommand(#"{"type":"refresh"}"#)
        case "command":
            guard let body = arguments.dropFirst().first else { throw Failure(message: "command needs a JSON body.") }
            return try await sendCommand(body)
        case "logs":
            return try logs(minutes: arguments.dropFirst().first.flatMap(Int.init) ?? 60)
        default:
            throw Failure(message: "Unknown command \(command).\n\n\(usage)")
        }
    }

    // MARK: - Resident API

    private static func residentData(path: String, method: String = "GET", body: Data? = nil) async throws -> Any {
        guard let token = KeychainStore().readRemoteAPIToken(), !token.isEmpty else {
            throw Failure(message: "Could not read the resident API token from Keychain. Open Cargo once, then retry.")
        }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(CargoHTTPServer.Configuration.defaultPort)\(path)")!)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure(message: "Could not reach the resident API: \(error.localizedDescription) Is Cargo running?")
        }
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(message: "The resident API returned an unexpected response.")
        }
        guard envelope["ok"] as? Bool == true else {
            let error = envelope["error"] as? [String: Any]
            throw Failure(message: error?["message"] as? String ?? "The resident API rejected the request.")
        }
        return envelope["data"] ?? NSNull()
    }

    private static func residentSnapshot() async throws -> [String: Any] {
        guard let snapshot = try await residentData(path: "/v1/state") as? [String: Any] else {
            throw Failure(message: "The resident API returned an unexpected snapshot.")
        }
        return snapshot
    }

    private static func status() async throws -> [String: Any] {
        let health = try await residentData(path: "/v1/health")
        let snapshot = try await residentSnapshot()
        var result: [String: Any] = ["health": health]
        for key in ["generatedAt", "lastUpdated", "putIO", "chill", "disk"] {
            result[key] = snapshot[key]
        }
        let jobs = snapshot["syncJobs"] as? [[String: Any]] ?? []
        let jobCounts: [String: Int] = Dictionary(grouping: jobs) { $0["status"] as? String ?? "unknown" }
            .mapValues(\.count)
        var counts: [String: Any] = ["jobs": jobCounts]
        for (name, key) in [
            ("transfers", "transfers"),
            ("media", "mediaFiles"),
            ("library", "library"),
            ("subscriptions", "subscriptions"),
            ("ledger", "episodeLedger")
        ] {
            counts[name] = (snapshot[key] as? [Any])?.count ?? 0
        }
        result["counts"] = counts
        return result
    }

    private static func sendCommand(_ body: String) async throws -> [String: Any] {
        guard let data = body.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw Failure(message: "The command body is not valid JSON.")
        }
        _ = try await residentData(path: "/v1/commands", method: "POST", body: data)
        return ["ok": true]
    }

    private static func sendCommand(_ command: CargoRemoteCommand) async throws -> [String: Any] {
        let data = try JSONEncoder().encode(command)
        _ = try await residentData(path: "/v1/commands", method: "POST", body: data)
        return ["ok": true]
    }

    // MARK: - Subscriptions and ledger commands

    static func parseSubscriptionCommand(_ arguments: [String]) throws -> CargoRemoteCommand {
        guard let action = arguments.first else {
            throw Failure(message: "subscriptions needs add-series, add-feed, pause, resume, or remove.")
        }
        let rest = Array(arguments.dropFirst())
        switch action {
        case "add-series":
            var positional: [String] = []
            var year: Int?
            var backfill: SubscriptionBackfillPolicy?
            var remaining = rest[...]
            while let token = remaining.popFirst() {
                switch token {
                case "--year":
                    guard let raw = remaining.popFirst(), let parsed = Int(raw) else {
                        throw Failure(message: "--year needs a number.")
                    }
                    year = parsed
                case "--backfill":
                    guard let raw = remaining.popFirst(), let parsed = SubscriptionBackfillPolicy(rawValue: raw) else {
                        throw Failure(message: "--backfill must be newOnly, currentSeason, or all.")
                    }
                    backfill = parsed
                default:
                    positional.append(token)
                }
            }
            guard positional.count >= 3 else {
                throw Failure(message: "add-series needs <imdb-id> <tmdb-id> <title>.")
            }
            guard let tmdbID = Int(positional[1]), tmdbID > 0 else {
                throw Failure(message: "tmdb-id must be a positive integer.")
            }
            let title = positional.dropFirst(2).joined(separator: " ")
            return .addSeriesSubscription(
                imdbID: positional[0],
                tmdbID: tmdbID,
                title: title,
                year: year,
                backfill: backfill
            )
        case "add-feed":
            var positional: [String] = []
            var keywords: [String] = []
            var unwanted: [String] = []
            var backfill: SubscriptionBackfillPolicy?
            var remaining = rest[...]
            while let token = remaining.popFirst() {
                switch token {
                case "--keyword":
                    guard let value = remaining.popFirst() else { throw Failure(message: "--keyword needs a value.") }
                    keywords.append(value)
                case "--unwanted":
                    guard let value = remaining.popFirst() else { throw Failure(message: "--unwanted needs a value.") }
                    unwanted.append(value)
                case "--backfill":
                    guard let raw = remaining.popFirst(), let parsed = SubscriptionBackfillPolicy(rawValue: raw) else {
                        throw Failure(message: "--backfill must be newOnly, currentSeason, or all.")
                    }
                    backfill = parsed
                default:
                    positional.append(token)
                }
            }
            guard positional.count >= 2 else {
                throw Failure(message: "add-feed needs <url> <title>.")
            }
            let title = positional.dropFirst().joined(separator: " ")
            return .addFeedSubscription(
                url: positional[0],
                title: title,
                keywords: keywords,
                unwantedKeywords: unwanted,
                backfill: backfill
            )
        case "pause":
            guard let raw = rest.first, let id = UUID(uuidString: raw) else {
                throw Failure(message: "pause needs a subscription UUID.")
            }
            return .setSubscriptionPaused(id: id, paused: true)
        case "resume":
            guard let raw = rest.first, let id = UUID(uuidString: raw) else {
                throw Failure(message: "resume needs a subscription UUID.")
            }
            return .setSubscriptionPaused(id: id, paused: false)
        case "remove":
            guard let raw = rest.first, let id = UUID(uuidString: raw) else {
                throw Failure(message: "remove needs a subscription UUID.")
            }
            return .removeSubscription(id: id)
        default:
            throw Failure(message: "Unknown subscriptions action \(action). Use add-series, add-feed, pause, resume, or remove.")
        }
    }

    static func parseLedgerCommand(_ arguments: [String]) throws -> CargoRemoteCommand {
        guard let action = arguments.first else {
            throw Failure(message: "ledger needs set <imdb-id> <season> <episode> <state>.")
        }
        guard action == "set" else {
            throw Failure(message: "Unknown ledger action \(action). Use set <imdb-id> <season> <episode> <state>.")
        }
        let rest = Array(arguments.dropFirst())
        guard rest.count == 4 else {
            throw Failure(message: "ledger set needs <imdb-id> <season> <episode> <state>.")
        }
        guard let season = Int(rest[1]), season > 0, let episode = Int(rest[2]), episode > 0 else {
            throw Failure(message: "season and episode must be positive integers.")
        }
        guard let state = EpisodeLedgerState(rawValue: rest[3]) else {
            let valid = EpisodeLedgerState.allCases.map(\.rawValue).joined(separator: ", ")
            throw Failure(message: "Invalid ledger state \(rest[3]). Valid states: \(valid).")
        }
        return .setEpisodeLedgerState(imdbID: rest[0], season: season, episode: episode, state: state)
    }

    // MARK: - Local state

    private static func localState(key: String?, options: ListOptions) throws -> Any {
        // Not `CargoStore()`: its init moves an undecodable state file aside.
        let data = try Data(contentsOf: CargoStore.defaultStateURL)
        guard var state = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(message: "Cargo's state file has an unexpected shape.")
        }
        if let subscriptions = state["subscriptions"] as? [[String: Any]] {
            state["subscriptions"] = subscriptions.map(sanitizedLocalSubscription)
        }
        guard let key else {
            return state.mapValues { value -> Any in
                (value as? [Any]).map { "\($0.count) entries" } ?? value
            }
        }
        guard let value = state[key] else {
            throw Failure(message: "The state file has no key \(key). Keys: \(state.keys.sorted().joined(separator: ", "))")
        }
        return filtered(value, options: options) ?? NSNull()
    }

    private static func sanitizedLocalSubscription(_ entry: [String: Any]) -> [String: Any] {
        var copy = entry
        if var kind = copy["kind"] as? [String: Any],
           kind["type"] as? String == "feed",
           let url = kind["url"] as? String {
            kind["url"] = CargoRemoteLinkSanitizer.sanitizeFeedURL(url)
            copy["kind"] = kind
        }
        return copy
    }

    // MARK: - Put.io

    private static func putIO(_ arguments: [String], options: ListOptions) async throws -> Any {
        guard let token = KeychainStore().readToken(), !token.isEmpty else {
            throw Failure(message: "Could not read the Put.io token from Keychain.")
        }
        let client = PutIOAPIClient(token: token)
        let path: String
        let listKey: String
        var query: [URLQueryItem] = []
        switch arguments.first {
        case "files":
            path = "files/list"
            listKey = "files"
            query = [
                URLQueryItem(name: "parent_id", value: arguments.dropFirst().first ?? "0"),
                URLQueryItem(name: "per_page", value: "1000"),
                URLQueryItem(name: "no_cursor", value: "1")
            ]
        case "transfers":
            path = "transfers/list"
            listKey = "transfers"
            query = [URLQueryItem(name: "per_page", value: "100")]
        case "events":
            path = "events/list"
            listKey = "events"
        case "trash":
            path = "trash/list"
            listKey = "files"
            query = [URLQueryItem(name: "per_page", value: "1000")]
        default:
            throw Failure(message: "putio needs files, transfers, events or trash.")
        }
        let data = try await client.rawGET(path: path, queryItems: query)
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = envelope[listKey] as? [[String: Any]] else {
            throw Failure(message: "Put.io returned an unexpected response.")
        }
        // A transfer's source and callback URL can carry a tracker passkey.
        let safe = list.map { entry in
            entry.filter { $0.key != "source" && $0.key != "callback_url" }
        }
        return filtered(safe, options: options) ?? []
    }

    // MARK: - Logs

    private static func logs(minutes: Int) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show", "--last", "\(max(minutes, 1))m", "--info", "--style", "compact",
            "--predicate", #"subsystem == "app.cargo.Cargo""#
        ]
        process.standardOutput = pipe
        try process.run()
        // Read before the wait: a full pipe blocks `log` and the wait never ends.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Output

    private static func filtered(_ value: Any?, options: ListOptions) -> Any? {
        guard var list = value as? [Any] else { return value }
        if let grep = options.grep {
            list = list.filter { entry in
                guard JSONSerialization.isValidJSONObject(entry),
                      let data = try? JSONSerialization.data(withJSONObject: entry, options: [.withoutEscapingSlashes]),
                      let text = String(data: data, encoding: .utf8) else {
                    return String(describing: entry).localizedCaseInsensitiveContains(grep)
                }
                return text.localizedCaseInsensitiveContains(grep)
            }
        }
        if let limit = options.limit {
            list = Array(list.prefix(limit))
        }
        return list
    }

    private static func json(_ value: Any?) throws -> String {
        let value = value ?? NSNull()
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        )
        return String(decoding: data, as: UTF8.self)
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data("cargoctl: \(message)\n".utf8))
    }
}

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
      transfers | files | media | jobs | history | library | watchlist
                               one list from the resident's snapshot
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
        "watchlist": "watchlist"
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
            try await dispatch(positional, options: options)
            return 0
        } catch let failure as Failure {
            printError(failure.message)
            return 1
        } catch {
            printError(error.localizedDescription)
            return 1
        }
    }

    private static func dispatch(_ arguments: [String], options: ListOptions) async throws {
        guard let command = arguments.first else {
            print(usage)
            return
        }
        if let key = snapshotLists[command] {
            let snapshot = try await residentSnapshot()
            try printJSON(filtered(snapshot[key], options: options))
            return
        }
        switch command {
        case "help", "--help", "-h":
            print(usage)
        case "status":
            try printJSON(try await status())
        case "state":
            try printJSON(try await residentSnapshot())
        case "local":
            try printJSON(try localState(key: arguments.dropFirst().first, options: options))
        case "putio":
            try printJSON(try await putIO(Array(arguments.dropFirst()), options: options))
        case "refresh":
            try await sendCommand(#"{"type":"refresh"}"#)
        case "command":
            guard let body = arguments.dropFirst().first else { throw Failure(message: "command needs a JSON body.") }
            try await sendCommand(body)
        case "logs":
            try showLogs(minutes: arguments.dropFirst().first.flatMap(Int.init) ?? 60)
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
        for (name, key) in [("transfers", "transfers"), ("media", "mediaFiles"), ("library", "library")] {
            counts[name] = (snapshot[key] as? [Any])?.count ?? 0
        }
        result["counts"] = counts
        return result
    }

    private static func sendCommand(_ body: String) async throws {
        guard let data = body.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw Failure(message: "The command body is not valid JSON.")
        }
        _ = try await residentData(path: "/v1/commands", method: "POST", body: data)
        try printJSON(["ok": true])
    }

    // MARK: - Local state

    private static func localState(key: String?, options: ListOptions) throws -> Any {
        // Not `CargoStore()`: its init moves an undecodable state file aside.
        let data = try Data(contentsOf: CargoStore.defaultStateURL)
        guard let state = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(message: "Cargo's state file has an unexpected shape.")
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

    private static func showLogs(minutes: Int) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show", "--last", "\(max(minutes, 1))m", "--info", "--style", "compact",
            "--predicate", #"subsystem == "app.cargo.Cargo""#
        ]
        try process.run()
        process.waitUntilExit()
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

    private static func printJSON(_ value: Any?) throws {
        let value = value ?? NSNull()
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data("cargoctl: \(message)\n".utf8))
    }
}

import Foundation

/// MCP server for local agents: `Cargo --mcp`, installed as `cargo-mcp`. It
/// speaks newline-delimited JSON-RPC on stdin and stdout and maps each tool to
/// a `cargoctl` command, so the CLI stays the one implementation. Like the CLI
/// it runs inside the signed app binary and never returns a credential.
enum CargoMCP {
    static var isInvocation: Bool {
        CommandLine.arguments.dropFirst().first == "--mcp"
    }

    static func runAndExit() -> Never {
        Task.detached {
            await serve()
            exit(0)
        }
        dispatchMain()
    }

    private static let protocolVersion = "2025-06-18"

    private struct Tool {
        let name: String
        let description: String
        let properties: [String: Any]
        let required: [String]
        let arguments: ([String: Any]) throws -> [String]
    }

    private struct InvalidArguments: Error {
        let message: String
    }

    private static var listOptions: [String: Any] {
        [
            "grep": ["type": "string", "description": "Keep only entries whose JSON contains this text, ignoring case."],
            "limit": ["type": "integer", "minimum": 0, "description": "Keep only the first n entries."]
        ]
    }

    private static var tools: [Tool] { [
        Tool(
            name: "cargo_status",
            description: "Cargo's build, Put.io and Chill state, disk space, and counts of transfers, media, library items and jobs.",
            properties: [:],
            required: [],
            arguments: { _ in ["status"] }
        ),
        Tool(
            name: "cargo_list",
            description: "One list from the running resident's snapshot. media is the downloadable video on Put.io; jobs are local downloads; library is the organized local library.",
            properties: listOptions.merging([
                "list": ["type": "string", "enum": ["transfers", "files", "media", "jobs", "history", "library", "watchlist"]]
            ]) { $1 },
            required: ["list"],
            arguments: { input in
                guard let list = input["list"] as? String else { throw InvalidArguments(message: "list is required.") }
                return [list] + options(input)
            }
        ),
        Tool(
            name: "cargo_state",
            description: "The resident's whole snapshot, including the latest Chill search results. Large; prefer cargo_list.",
            properties: [:],
            required: [],
            arguments: { _ in ["state"] }
        ),
        Tool(
            name: "cargo_local",
            description: "Cargo's state file, with local paths and settings. Without key, it lists the keys and the size of each list.",
            properties: listOptions.merging(["key": ["type": "string"]]) { $1 },
            required: [],
            arguments: { input in
                ["local"] + ((input["key"] as? String).map { [$0] } ?? []) + options(input)
            }
        ),
        Tool(
            name: "cargo_putio",
            description: "Put.io's raw, unfiltered data: a files listing, transfers with error messages, the activity feed, or the trash.",
            properties: listOptions.merging([
                "listing": ["type": "string", "enum": ["files", "transfers", "events", "trash"]],
                "parent_id": ["type": "integer", "description": "Folder to list for files. 0 is the root."]
            ]) { $1 },
            required: ["listing"],
            arguments: { input in
                guard let listing = input["listing"] as? String else { throw InvalidArguments(message: "listing is required.") }
                var arguments = ["putio", listing]
                if listing == "files", let parent = input["parent_id"] as? Int { arguments.append(String(parent)) }
                return arguments + options(input)
            }
        ),
        Tool(
            name: "cargo_refresh",
            description: "Re-list Put.io now. The next cycle queues new media for download.",
            properties: [:],
            required: [],
            arguments: { _ in ["refresh"] }
        ),
        Tool(
            name: "cargo_command",
            description: """
            Send one command to the resident. The object has a type and that type's fields:
            refresh, refreshChillCatalog, searchChill {query}, sendChillResult {id}, sendChillMovie {id},
            sendChillRelease {url, title?}, addTransfer {url}, cancelTransfer {id: int}, retryTransfer {id: int},
            cleanFinishedTransfers, requestExtraction {remoteFileID}, deleteRemoteFile {remoteFileID},
            enqueueLocalSync {remoteFileID}, organizeLocalJob {id: uuid}, refreshWatchlist,
            refreshPersonalWatchlist {url?}, clearFailedJobs, clearHistory, playLibraryItem {id},
            playLibraryEpisode {id, season, episode}.
            Read the outcome with cargo_list or cargo_state.
            """,
            properties: ["command": ["type": "object", "properties": ["type": ["type": "string"]], "required": ["type"]]],
            required: ["command"],
            arguments: { input in
                guard let command = input["command"] as? [String: Any], command["type"] is String,
                      let data = try? JSONSerialization.data(withJSONObject: command) else {
                    throw InvalidArguments(message: "command must be an object with a type.")
                }
                return ["command", String(decoding: data, as: UTF8.self)]
            }
        ),
        Tool(
            name: "cargo_logs",
            description: "Cargo's unified log for the last n minutes.",
            properties: ["minutes": ["type": "integer", "minimum": 1, "default": 60]],
            required: [],
            arguments: { input in ["logs", String(input["minutes"] as? Int ?? 60)] }
        )
    ] }

    private static func options(_ input: [String: Any]) -> [String] {
        var arguments: [String] = []
        if let grep = input["grep"] as? String { arguments += ["--grep", grep] }
        if let limit = input["limit"] as? Int { arguments += ["--limit", String(limit)] }
        return arguments
    }

    // MARK: - JSON-RPC

    private static func serve() async {
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                guard let data = line.data(using: .utf8),
                      let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    write(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
                    continue
                }
                // A message without an id is a notification and gets no reply.
                guard let id = message["id"] else { continue }
                write(await reply(id: id, method: message["method"] as? String, params: message["params"] as? [String: Any] ?? [:]))
            }
        } catch {
            FileHandle.standardError.write(Data("cargo-mcp: \(error.localizedDescription)\n".utf8))
        }
    }

    private static func reply(id: Any, method: String?, params: [String: Any]) async -> [String: Any] {
        var response: [String: Any] = ["jsonrpc": "2.0", "id": id]
        switch method {
        case "initialize":
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            response["result"] = [
                "protocolVersion": params["protocolVersion"] as? String ?? protocolVersion,
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "cargo", "version": version],
                "instructions": "Cargo is mz's Put.io and media library resident. Cargo must run for every tool except cargo_local, cargo_putio and cargo_logs."
            ]
        case "ping":
            response["result"] = [:]
        case "tools/list":
            response["result"] = ["tools": tools.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "inputSchema": ["type": "object", "properties": tool.properties, "required": tool.required]
                ]
            }]
        case "tools/call":
            guard let name = params["name"] as? String, let tool = tools.first(where: { $0.name == name }) else {
                response["error"] = ["code": -32602, "message": "Unknown tool."]
                return response
            }
            response["result"] = await call(tool, input: params["arguments"] as? [String: Any] ?? [:])
        default:
            response["error"] = ["code": -32601, "message": "Method not found."]
        }
        return response
    }

    private static func call(_ tool: Tool, input: [String: Any]) async -> [String: Any] {
        do {
            let text = try await CargoCLI.output(of: try tool.arguments(input))
            return ["content": [["type": "text", "text": text]], "isError": false]
        } catch let invalid as InvalidArguments {
            return ["content": [["type": "text", "text": invalid.message]], "isError": true]
        } catch {
            return ["content": [["type": "text", "text": CargoCLI.message(for: error)]], "isError": true]
        }
    }

    private static func write(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }
}

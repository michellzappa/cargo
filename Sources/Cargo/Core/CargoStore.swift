import Foundation

final class CargoStore {
    let stateURL: URL
    private var state: CargoState
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(stateURL: URL? = nil) {
        if let stateURL {
            self.stateURL = stateURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            self.stateURL = applicationSupport
                .appendingPathComponent("Cargo", isDirectory: true)
                .appendingPathComponent("state.json")
        }

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.state = Self.loadState(from: self.stateURL, decoder: self.decoder) ?? .empty
    }

    /// Where the previous good state.json is kept before each overwrite, and
    /// where an undecodable one is moved so it is never silently replaced.
    var backupURL: URL { stateURL.appendingPathExtension("bak") }

    func snapshot() -> CargoState {
        state
    }

    func replace(with newState: CargoState) throws {
        state = newState
        try save()
    }

    func save() throws {
        let directory = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(state)
        if FileManager.default.fileExists(atPath: stateURL.path) {
            _ = try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: stateURL, to: backupURL)
        }
        try data.write(to: stateURL, options: .atomic)
    }

    /// A missing file is a fresh install. A present-but-undecodable file is a
    /// schema break or truncation: keep it as `state.json.corrupt` and start
    /// empty instead of overwriting the only copy on the next save.
    private static func loadState(from url: URL, decoder: JSONDecoder) -> CargoState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(CargoState.self, from: data)
        } catch {
            NSLog("Cargo state.json could not be decoded, preserving it as state.json.corrupt: %@", "\(error)")
            let corruptURL = url.appendingPathExtension("corrupt")
            _ = try? FileManager.default.removeItem(at: corruptURL)
            _ = try? FileManager.default.copyItem(at: url, to: corruptURL)
            return nil
        }
    }
}

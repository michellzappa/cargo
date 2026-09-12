import Foundation

final class CargoStore {
    private let stateURL: URL
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
        self.state = Self.loadState(from: self.stateURL, decoder: self.decoder) ?? .demo
    }

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
        try data.write(to: stateURL, options: .atomic)
    }

    private static func loadState(from url: URL, decoder: JSONDecoder) -> CargoState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CargoState.self, from: data)
    }
}

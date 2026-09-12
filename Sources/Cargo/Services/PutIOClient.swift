import Foundation

protocol PutIOClient: Sendable {
    func fetchTransfers() async throws -> [RemoteTransfer]
}

struct UnconfiguredPutIOClient: PutIOClient {
    enum ClientError: LocalizedError {
        case notConfigured

        var errorDescription: String? {
            "Put.io is not connected yet."
        }
    }

    func fetchTransfers() async throws -> [RemoteTransfer] {
        throw ClientError.notConfigured
    }
}

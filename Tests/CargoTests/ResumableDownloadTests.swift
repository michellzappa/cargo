import XCTest
@testable import Cargo

/// Serves one fixed payload, honours `Range`, and cuts the first request
/// short so the client has to resume.
final class RangeStubProtocol: URLProtocol {
    nonisolated(unsafe) static var payload = Data((0..<(3 * 1024 * 1024 + 123)).map { UInt8($0 % 251) })
    nonisolated(unsafe) static var cutFirstRequestAfter: Int? = 1_500_000
    nonisolated(unsafe) static var requests: [(range: String?, status: Int)] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let payload = Self.payload
        let range = request.value(forHTTPHeaderField: "Range")
        var start = 0
        var status = 200
        var headers = ["Content-Length": String(payload.count)]
        if let range, range.hasPrefix("bytes="), let offset = Int(range.dropFirst(6).dropLast()) {
            if offset >= payload.count {
                status = 416
            } else {
                start = offset
                status = 206
                headers["Content-Range"] = "bytes \(offset)-\(payload.count - 1)/\(payload.count)"
                headers["Content-Length"] = String(payload.count - offset)
            }
        }
        Self.requests.append((range, status))
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        guard status != 416 else { client?.urlProtocolDidFinishLoading(self); return }

        if let cut = Self.cutFirstRequestAfter {
            Self.cutFirstRequestAfter = nil
            // Deliver in chunks with a beat between them, like a real socket,
            // then drop the connection.
            let end = min(start + cut, payload.count)
            var offset = start
            while offset < end {
                let next = min(offset + 256 * 1024, end)
                client?.urlProtocol(self, didLoad: payload[offset..<next])
                offset = next
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [self] in
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            }
            return
        }
        client?.urlProtocol(self, didLoad: payload[start...])
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class ResumableDownloadTests: XCTestCase {
    func testDownloadResumesFromPartialFileAndReportsProgress() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CargoResumeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Movie (2026).mkv")

        RangeStubProtocol.cutFirstRequestAfter = 1_500_000
        RangeStubProtocol.requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RangeStubProtocol.self]
        let client = PutIOAPIClient(token: "t", session: URLSession(configuration: configuration))

        // First attempt: connection drops mid-way, the .part stays behind.
        do {
            try await client.downloadFile(fileID: 1, to: destination, progress: nil)
            XCTFail("expected the first attempt to be interrupted")
        } catch {}
        let partial = PutIOAPIClient.partialURL(for: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let partialSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? Int)
        XCTAssertEqual(partialSize, 1_500_000)

        // Second attempt: resumes with Range, finishes, renames atomically.
        final class Progress: @unchecked Sendable { var last: (Int64, Int64?)? }
        let progress = Progress()
        try await client.downloadFile(fileID: 1, to: destination) { received, total in
            progress.last = (received, total)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertEqual(try Data(contentsOf: destination), RangeStubProtocol.payload)
        XCTAssertEqual(RangeStubProtocol.requests.map(\.status), [200, 206])
        XCTAssertEqual(RangeStubProtocol.requests.last?.range, "bytes=1500000-")
        XCTAssertEqual(progress.last?.0, Int64(RangeStubProtocol.payload.count))
        XCTAssertEqual(progress.last?.1, Int64(RangeStubProtocol.payload.count))
    }

    func testCompletePartialIsPromotedOn416() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CargoResume416-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Done.mkv")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try RangeStubProtocol.payload.write(to: PutIOAPIClient.partialURL(for: destination))

        RangeStubProtocol.cutFirstRequestAfter = nil
        RangeStubProtocol.requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RangeStubProtocol.self]
        let client = PutIOAPIClient(token: "t", session: URLSession(configuration: configuration))
        try await client.downloadFile(fileID: 1, to: destination, progress: nil)
        XCTAssertEqual(RangeStubProtocol.requests.map(\.status), [416])
        XCTAssertEqual(try Data(contentsOf: destination), RangeStubProtocol.payload)
    }
}

import Foundation
import zlib

/// Checks a finished download before Cargo removes the Put.io copy. A size
/// match alone passed a release that was half zero bytes, so the content
/// must match Put.io's CRC32 and start like the container its extension names.
enum DownloadCheck {
    enum Failure: LocalizedError {
        /// The bytes differ from Put.io's copy: the download broke.
        case checksumMismatch(expected: String, actual: String)
        /// The bytes match Put.io's copy, but the copy is not a playable video.
        case invalidContainer(String)

        var errorDescription: String? {
            switch self {
            case .checksumMismatch(let expected, let actual):
                "The download does not match Put.io's copy (CRC32 \(actual), expected \(expected))."
            case .invalidContainer(let fileExtension):
                "Put.io's copy is not a valid .\(fileExtension) video. Re-add the release from another source."
            }
        }
    }

    /// Reads the whole file, so call it off the main actor.
    static func verify(fileURL: URL, expectedCRC32: String?) throws {
        let fileExtension = fileURL.pathExtension.lowercased()
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let header = try handle.read(upToCount: 512) ?? Data()
        guard hasValidHeader(header, fileExtension: fileExtension) else {
            throw Failure.invalidContainer(fileExtension)
        }

        guard let expectedCRC32 else { return }
        try handle.seek(toOffset: 0)
        var checksum = crc32(0, nil, 0)
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            checksum = chunk.withUnsafeBytes { buffer in
                crc32(checksum, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count))
            }
        }
        let actual = String(format: "%08x", checksum)
        guard actual == expectedCRC32.lowercased() else {
            throw Failure.checksumMismatch(expected: expectedCRC32.lowercased(), actual: actual)
        }
    }

    /// Unknown extensions pass: only the containers Cargo downloads are known.
    static func hasValidHeader(_ header: Data, fileExtension: String) -> Bool {
        let bytes = [UInt8](header)
        func matches(_ signature: [UInt8], at offset: Int = 0) -> Bool {
            bytes.count >= offset + signature.count && Array(bytes[offset..<offset + signature.count]) == signature
        }
        switch fileExtension {
        case "mkv", "webm":
            return matches([0x1A, 0x45, 0xDF, 0xA3])
        case "mp4", "m4v", "mov":
            // ISO media starts with a box; QuickTime files can open on moov or mdat.
            let boxes = ["ftyp", "moov", "mdat", "wide", "free", "skip", "pnot"]
            return boxes.contains { matches(Array($0.utf8), at: 4) }
        case "avi":
            return matches(Array("RIFF".utf8)) && matches(Array("AVI ".utf8), at: 8)
        case "wmv":
            return matches([0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11])
        case "ts":
            return matches([0x47]) && (bytes.count < 189 || bytes[188] == 0x47)
        case "mpg", "mpeg":
            return matches([0x00, 0x00, 0x01, 0xBA]) || matches([0x00, 0x00, 0x01, 0xB3])
        default:
            return true
        }
    }
}

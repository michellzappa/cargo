import Foundation

/// Build metadata shared by the macOS resident and iOS companion.
///
/// Marketing versions live in each target's Info.plist. Build numbers and the
/// source commit are injected by the local/release build scripts and CI.
enum CargoAppInfo {
    static var version: String { value(forKey: "CFBundleShortVersionString", fallback: "unknown") }
    static var build: String { value(forKey: "CFBundleVersion", fallback: "unknown") }
    static var commit: String { value(forKey: "CargoCommit", fallback: "unknown") }

    /// The compact form used in the macOS About page and resident health API.
    static var label: String {
        "\(version) (\(build), \(commit))"
    }

    private static func value(forKey key: String, fallback: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.hasPrefix("$(") else {
            return fallback
        }
        return value
    }
}

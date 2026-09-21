import Foundation

enum CargoBuild {
    /// "0.8.0 (96, a1b2c3d)" from the stamped Info.plist keys.
    static var label: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        let commit = info["CargoCommit"] as? String ?? "unknown"
        return "\(version) (\(build), \(commit))"
    }
}

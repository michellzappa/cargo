import Foundation

/// An app-local accent choice. This is deliberately not part of the remote
/// settings or snapshot: each Cargo installation owns its own appearance.
public enum CargoAccentColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case `default`
    case blue
    case green
    case yellow
    case pink
    case orange
    case purple
    case black

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .default: "Default"
        case .blue: "Blue"
        case .green: "Green"
        case .yellow: "Yellow"
        case .pink: "Pink"
        case .orange: "Orange"
        case .purple: "Purple"
        case .black: "Black"
        }
    }
}

/// Local persistence for appearance preferences. UserDefaults is scoped to
/// the current app installation on the current device and is never sent to a
/// Cargo resident or account.
public enum CargoAccentTheme {
    public static let selectionKey = "cargo.appearance.accentColor"
    public static let didChange = Notification.Name("CargoAccentTheme.didChange")

    public static func selection(from defaults: UserDefaults = .standard) -> CargoAccentColor {
        guard let rawValue = defaults.string(forKey: selectionKey),
              let selection = CargoAccentColor(rawValue: rawValue) else {
            return .default
        }
        return selection
    }

    public static func save(_ selection: CargoAccentColor, to defaults: UserDefaults = .standard) {
        defaults.set(selection.rawValue, forKey: selectionKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

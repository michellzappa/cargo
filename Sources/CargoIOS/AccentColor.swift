import CargoRemoteKit
import SwiftUI

enum CargoIOSAccentColor {
    static func tint(for selection: CargoAccentColor) -> Color? {
        switch selection {
        case .default: nil
        case .blue: .blue
        case .green: .green
        case .yellow: .yellow
        case .pink: .pink
        case .orange: .orange
        case .purple: .purple
        case .black: .black
        }
    }

    static func swatchColor(for selection: CargoAccentColor) -> Color {
        tint(for: selection) ?? .blue
    }

}

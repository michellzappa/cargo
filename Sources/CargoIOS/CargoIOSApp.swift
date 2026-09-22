import CargoRemoteKit
import SwiftUI

@main
struct CargoIOSApp: App {
    @State private var model = CargoClientModel()
    @AppStorage(CargoAccentTheme.selectionKey) private var accentRawValue = CargoAccentColor.default.rawValue

    var body: some Scene {
        WindowGroup {
            CargoRootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(CargoIOSAccentColor.tint(for: CargoAccentColor(rawValue: accentRawValue) ?? .default))
                .onOpenURL { url in
                    Task { await model.connect(pairingURL: url) }
                }
        }
    }
}

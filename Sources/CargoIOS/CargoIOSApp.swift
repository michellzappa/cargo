import SwiftUI

@main
struct CargoIOSApp: App {
    @State private var model = CargoClientModel()

    var body: some Scene {
        WindowGroup {
            CargoRootView()
                .environment(model)
                .onOpenURL { url in
                    Task { await model.connect(pairingURL: url) }
                }
        }
    }
}

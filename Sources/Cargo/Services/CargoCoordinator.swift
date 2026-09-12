import Foundation

@MainActor
final class CargoCoordinator {
    private let store: CargoStore
    private(set) var state: CargoState

    init(store: CargoStore = CargoStore()) {
        self.store = store
        self.state = store.snapshot()
    }

    func refresh() {
        state = store.snapshot()
    }

    func persistDemoState() {
        do {
            try store.save()
            refresh()
        } catch {
            // The dashboard remains useful with in-memory state if persistence fails.
        }
    }
}

import AppKit

@main
@MainActor
final class CargoAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var dashboardWindowController: NSWindowController?
    private var dashboardViewController: DashboardViewController!
    private var refreshTask: Task<Void, Never>?
    private let coordinator = CargoCoordinator()

    static func main() {
        let application = NSApplication.shared
        let delegate = CargoAppDelegate()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "shippingbox",
                accessibilityDescription: "Cargo"
            )
            button.image?.isTemplate = true
            button.image?.size = NSSize(width: 16, height: 16)
            button.title = ""
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.setAccessibilityLabel("Cargo menu")
            button.target = self
            button.action = #selector(showDashboard(_:))
            button.toolTip = "Cargo"
        }

        showDashboardWindow()

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await coordinator.refreshFromPutIO()
                dashboardViewController.refreshView()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == PutIOOAuth.redirectURI.scheme {
            Task { @MainActor in
                do {
                    try await coordinator.finishPutIOAuthorization(from: url)
                    dashboardViewController.refreshView()
                } catch {
                    let alert = NSAlert(error: error)
                    alert.runModal()
                }
            }
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            showDashboardWindow()
        }
        return true
    }

    @objc private func showDashboard(_ sender: Any?) {
        showDashboardWindow()
    }

    private func showDashboardWindow() {
        if let dashboardWindowController {
            dashboardWindowController.showWindow(nil)
            dashboardWindowController.window?.orderFrontRegardless()
            dashboardWindowController.window?.makeKeyAndOrderFront(nil)
        } else {
            dashboardViewController = DashboardViewController(coordinator: coordinator)
            let window = NSWindow(contentViewController: dashboardViewController)
            window.title = "Cargo"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 760, height: 820))
            window.minSize = NSSize(width: 680, height: 560)
            window.center()
            window.isReleasedWhenClosed = false
            dashboardWindowController = NSWindowController(window: window)
            dashboardWindowController?.showWindow(nil)
            dashboardWindowController?.window?.orderFrontRegardless()
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

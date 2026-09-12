import AppKit

@main
@MainActor
final class CargoAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindowController: SettingsWindowController?
    private var dashboardViewController: DashboardViewController!
    private var refreshTask: Task<Void, Never>?
    private let coordinator = CargoCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "shippingbox",
                accessibilityDescription: "Cargo"
            )
            button.image?.isTemplate = true
            button.title = "Cargo"
            button.imagePosition = .imageLeft
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "Cargo"
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 370, height: 420)
        dashboardViewController = DashboardViewController(coordinator: coordinator) { [weak self] in
            self?.openSettings()
        }
        popover.contentViewController = dashboardViewController

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

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(coordinator: coordinator)
        }

        popover.performClose(nil)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

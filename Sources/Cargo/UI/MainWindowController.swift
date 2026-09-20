import AppKit

/// The dashboard window: unified toolbar, full-height sidebar, page title + subtitle in the title bar.
@MainActor
final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private enum ToolbarID {
        static let refresh = NSToolbarItem.Identifier("cargo.refresh")
        static let addTransfer = NSToolbarItem.Identifier("cargo.addTransfer")
        static let settings = NSToolbarItem.Identifier("cargo.settings")
    }

    private let coordinator: CargoCoordinator
    let navigation: CargoNavigationViewController
    private let refreshItem = NSToolbarItem(itemIdentifier: ToolbarID.refresh)
    private var refreshing = false
    var openSettings: (() -> Void)?

    init(coordinator: CargoCoordinator) {
        self.coordinator = coordinator
        self.navigation = CargoNavigationViewController(coordinator: coordinator)

        let window = NSWindow(contentViewController: navigation)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = "Cargo"
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.setContentSize(NSSize(width: 1020, height: 680))
        window.minSize = NSSize(width: 820, height: 480)
        window.setFrameAutosaveName("CargoMainWindow")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        let toolbar = NSToolbar(identifier: "CargoMainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        navigation.onSelectionChange = { [weak self] page, subtitle in
            self?.window?.title = page.title
            self?.window?.subtitle = subtitle
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(page: Page? = nil) {
        if let page { navigation.select(page) }
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, ToolbarID.addTransfer, ToolbarID.refresh, ToolbarID.settings]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarID.refresh:
            refreshItem.label = "Refresh"
            refreshItem.toolTip = "Check Put.io and the watchlist now (⌘R)"
            refreshItem.image = Theme.symbol("arrow.clockwise", pointSize: 15, weight: .regular)
            refreshItem.isBordered = true
            refreshItem.target = self
            refreshItem.action = #selector(refreshNow(_:))
            return refreshItem
        case ToolbarID.addTransfer:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Add Transfer"
            item.toolTip = "Add a magnet link or URL to Put.io (⌘N)"
            item.image = Theme.symbol("plus", pointSize: 15, weight: .regular)
            item.isBordered = true
            item.target = self
            item.action = #selector(addTransfer(_:))
            return item
        case ToolbarID.settings:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Settings"
            item.toolTip = "Cargo Settings (⌘,)"
            item.image = Theme.symbol("gearshape", pointSize: 15, weight: .regular)
            item.isBordered = true
            item.target = self
            item.action = #selector(showSettings(_:))
            return item
        default:
            return nil
        }
    }

    // MARK: - Actions (also reachable from the main menu)

    @objc func refreshNow(_ sender: Any?) {
        guard !refreshing else { return }
        refreshing = true
        refreshItem.isEnabled = false
        Task { @MainActor in
            _ = await coordinator.runBackgroundCycle()
            refreshing = false
            refreshItem.isEnabled = true
        }
    }

    @objc func addTransfer(_ sender: Any?) {
        navigation.select(.transfers)
        (navigation.currentPage as? TransfersPageViewController)?.addTransferFromPrompt()
    }

    @objc func pasteTransfer(_ sender: Any?) {
        navigation.select(.transfers)
        (navigation.currentPage as? TransfersPageViewController)?.addTransferFromClipboard()
    }

    @objc func showSettings(_ sender: Any?) {
        openSettings?()
    }

    @objc func selectPage(_ sender: NSMenuItem) {
        guard let page = Page(rawValue: sender.tag) else { return }
        navigation.select(page)
    }
}

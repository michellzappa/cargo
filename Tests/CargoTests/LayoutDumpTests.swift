import AppKit
import XCTest
@testable import Cargo

/// Smoke test: every page lays out inside the window without constraint conflicts
/// and its list fills the content pane. Prints the frame tree for inspection.
@MainActor
final class LayoutDumpTests: XCTestCase {
    func testPagesFillContentPane() throws {
        let coordinator = CargoCoordinator(client: UnconfiguredPutIOClient())
        let windowController = MainWindowController(coordinator: coordinator)
        guard let window = windowController.window else { return XCTFail("no window") }
        window.setContentSize(NSSize(width: 1020, height: 680))
        window.layoutIfNeeded()

        for page in Page.allCases {
            windowController.navigation.select(page)
            window.contentView?.layoutSubtreeIfNeeded()
            guard let pageView = windowController.navigation.currentPage?.view else {
                return XCTFail("no page view for \(page)")
            }
            print("===== \(page)")
            dump(pageView, depth: 0)
            XCTAssertGreaterThan(pageView.frame.width, 500, "\(page) too narrow")
            XCTAssertGreaterThan(pageView.frame.height, 400, "\(page) too short")
            XCTAssertFalse(pageView.hasAmbiguousLayout, "\(page) has ambiguous layout")
        }
    }

    private func dump(_ view: NSView, depth: Int) {
        guard depth < 8, !(view is NSScroller) else { return }
        var desc = "\(String(repeating: "  ", count: depth))\(type(of: view)) \(NSStringFromRect(view.frame))"
        if let tf = view as? NSTextField { desc += " \"\(tf.stringValue.prefix(30))\"" }
        if let b = view as? NSButton { desc += " \"\(b.title)\"" }
        print(desc)
        for sub in view.subviews { dump(sub, depth: depth + 1) }
    }
}

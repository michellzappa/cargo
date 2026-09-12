import AppKit
import XCTest
@testable import Cargo

@MainActor
final class LayoutDumpTests: XCTestCase {
    func testDumpLayout() throws {
        let coordinator = CargoCoordinator(client: UnconfiguredPutIOClient())
        let nav = CargoNavigationViewController(coordinator: coordinator)
        let window = NSWindow(contentViewController: nav)
        window.setContentSize(NSSize(width: 980, height: 650))
        window.layoutIfNeeded()
        for index in [0, 2, 3, 5] {
            nav.dashboardForTesting.selectView(index)
            nav.view.layoutSubtreeIfNeeded()
            print("===== VIEW \(index)")
            dump(nav.view, depth: 0)
        }
    }
    private func dump(_ view: NSView, depth: Int) {
        if view is NSTableView || view is NSScroller || view is NSBox { return }
        if String(describing: type(of: view)).hasPrefix("_") && !(view.subviews.contains { !($0 is NSTableView) }) { return }
        var desc = "\(String(repeating: "  ", count: depth))\(type(of: view)) \(NSStringFromRect(view.frame))"
        if let tf = view as? NSTextField { desc += " \"\(tf.stringValue.prefix(30))\"" }
        if let b = view as? NSButton { desc += " \"\(b.title)\"" }
        print(desc)
        for sub in view.subviews { dump(sub, depth: depth + 1) }
    }
}

import Foundation

/// The app's main destinations, shared by the macOS sidebar and the iOS tab bar.
///
/// The platform shells deliberately present these differently: macOS can show
/// every destination in its sidebar, while compact iOS has a fixed primary set
/// and a More surface. Keeping those policies here prevents a new destination
/// from silently changing the meaning of either shell's ordering.
enum CargoNavigationDestination: String, CaseIterable, Hashable, Identifiable, Sendable {
    case transfers
    case library
    case discover
    case watchlist
    case subscriptions
    case files
    case inbox
    case history
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .transfers: "Transfers"
        case .library: "Library"
        case .discover: "Discover"
        case .watchlist: "Watchlist"
        case .subscriptions: "Subscriptions"
        case .files: "Files"
        case .inbox: "Inbox"
        case .history: "History"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .transfers: "arrow.down.circle"
        case .library: "film.stack"
        case .discover: "sparkles"
        case .watchlist: "star"
        case .subscriptions: "dot.radiowaves.up.forward"
        case .files: "folder"
        case .inbox: "tray"
        case .history: "clock"
        case .settings: "gearshape"
        }
    }

    /// Destinations that remain directly reachable on a compact iPhone tab bar.
    static let compactPrimary: [Self] = [.transfers, .library, .discover, .watchlist]

    /// Destinations exposed from iOS More, in stable product order.
    static let compactMore: [Self] = [.subscriptions, .files, .inbox, .history, .settings]

    static var compactTabOrder: [Self] { compactPrimary + compactMore }

    /// macOS shows all main destinations in the same order as the iOS model.
    static let macSidebarOrder: [Self] = compactPrimary + [.subscriptions, .files, .inbox, .history]
}

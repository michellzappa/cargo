import AppKit

/// Shared label styles, badge view and formatters so pages don't hand-roll fonts and colors.
enum Theme {
    enum LabelStyle {
        case pageTitle
        case sectionHeader
        case rowTitle
        case body
        case detail
        case caption

        var font: NSFont {
            switch self {
            case .pageTitle: .systemFont(ofSize: 22, weight: .semibold)
            case .sectionHeader: .systemFont(ofSize: 13, weight: .semibold)
            case .rowTitle: .systemFont(ofSize: 13, weight: .medium)
            case .body: .systemFont(ofSize: 13)
            case .detail: .systemFont(ofSize: 11)
            case .caption: .systemFont(ofSize: 11)
            }
        }

        var color: NSColor {
            switch self {
            case .pageTitle, .sectionHeader, .rowTitle, .body: .labelColor
            case .detail: .secondaryLabelColor
            case .caption: .tertiaryLabelColor
            }
        }
    }

    @MainActor
    static func label(
        _ text: String = "",
        style: LabelStyle,
        color: NSColor? = nil,
        lineBreak: NSLineBreakMode = .byTruncatingTail,
        wraps: Bool = false
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = style.font
        label.textColor = color ?? style.color
        label.lineBreakMode = wraps ? .byWordWrapping : lineBreak
        label.maximumNumberOfLines = wraps ? 0 : 1
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    @MainActor
    static func symbol(_ name: String, pointSize: CGFloat = 13, weight: NSFont.Weight = .medium) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
    }
}

enum Formatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func percent(_ progress: Double) -> String {
        "\(Int((progress * 100).rounded()))%"
    }

    static func bytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Tinted capsule used for row status ("Wanted", "Seeding", "Organized").
struct StatusBadge: Equatable {
    let text: String
    let color: NSColor

    static func neutral(_ text: String) -> StatusBadge { .init(text: text, color: .secondaryLabelColor) }
    static func info(_ text: String) -> StatusBadge { .init(text: text, color: .systemBlue) }
    static func success(_ text: String) -> StatusBadge { .init(text: text, color: .systemGreen) }
    static func warning(_ text: String) -> StatusBadge { .init(text: text, color: .systemOrange) }
    static func failure(_ text: String) -> StatusBadge { .init(text: text, color: .systemRed) }
    static func highlight(_ text: String) -> StatusBadge { .init(text: text, color: .systemPurple) }
}

final class StatusBadgeView: NSView {
    private let label = Theme.label(style: .caption)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var badge: StatusBadge? {
        didSet {
            guard let badge else {
                isHidden = true
                return
            }
            isHidden = false
            label.stringValue = badge.text.uppercased()
            label.textColor = badge.color
            layer?.backgroundColor = badge.color.withAlphaComponent(0.14).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let current = badge
        badge = current
    }
}

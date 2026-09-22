import AppKit
import CargoRemoteKit

enum CargoMacAccentColor {
    static var selection: CargoAccentColor {
        CargoAccentTheme.selection()
    }

    static var color: NSColor {
        color(for: selection)
    }

    static func color(for selection: CargoAccentColor) -> NSColor {
        switch selection {
        case .default: return NSColor.controlAccentColor
        case .blue: return NSColor.systemBlue
        case .green: return NSColor.systemGreen
        case .yellow: return NSColor.systemYellow
        case .pink: return NSColor.systemPink
        case .orange: return NSColor.systemOrange
        case .purple: return NSColor.systemPurple
        case .black: return NSColor.black
        }
    }

    @MainActor
    static func swatch(for color: NSColor, size: CGFloat = 14) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let rect = NSRect(x: 1, y: 1, width: size - 2, height: size - 2)
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        let border = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
        image.unlockFocus()
        return image
    }
}

/// Compact AppKit control used from the General settings page.
@MainActor
final class CargoMacAccentColorControl: NSStackView {
    private let currentSwatch = NSImageView()
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .horizontal
        alignment = .centerY
        spacing = 8

        currentSwatch.imageScaling = .scaleProportionallyDown
        currentSwatch.widthAnchor.constraint(equalToConstant: 16).isActive = true
        currentSwatch.heightAnchor.constraint(equalToConstant: 16).isActive = true

        popup.controlSize = .small
        popup.widthAnchor.constraint(equalToConstant: 150).isActive = true
        popup.target = self
        popup.action = #selector(selectionChanged)
        for selection in CargoAccentColor.allCases {
            popup.addItem(withTitle: selection.displayName)
            let item = popup.lastItem
            item?.representedObject = selection.rawValue
            item?.image = CargoMacAccentColor.swatch(for: CargoMacAccentColor.color(for: selection))
        }

        addArrangedSubview(currentSwatch)
        addArrangedSubview(popup)
        refresh()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accentDidChange),
            name: CargoAccentTheme.didChange,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func accentDidChange() {
        refresh()
    }

    private func refresh() {
        let selection = CargoMacAccentColor.selection
        currentSwatch.image = CargoMacAccentColor.swatch(for: CargoMacAccentColor.color)
        if let index = popup.itemArray.firstIndex(where: { ($0.representedObject as? String) == selection.rawValue }) {
            popup.selectItem(at: index)
        }
    }

    @objc private func selectionChanged() {
        guard let rawValue = popup.selectedItem?.representedObject as? String,
              let selection = CargoAccentColor(rawValue: rawValue) else { return }
        CargoAccentTheme.save(selection)
    }
}

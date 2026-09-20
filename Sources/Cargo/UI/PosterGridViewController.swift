import AppKit

/// Poster-card presentation for catalog rows. The list remains the canonical
/// presentation; this controller is only used by pages that opt into cards.
@MainActor
final class PosterGridViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private static let itemIdentifier = NSUserInterfaceItemIdentifier("PosterGridItem")

    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let emptyLabel = Theme.label(style: .body, color: .secondaryLabelColor, wraps: true)
    private var rows: [ListRow] = []

    var emptyState = EmptyState(symbol: "film.stack", title: "Nothing here") {
        didSet { updateEmptyState() }
    }

    override func loadView() {
        view = NSView()

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 156, height: 272)
        layout.minimumInteritemSpacing = 18
        layout.minimumLineSpacing = 22
        layout.sectionInset = NSEdgeInsets(top: 18, left: 18, bottom: 24, right: 18)

        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PosterGridItem.self, forItemWithIdentifier: Self.itemIdentifier)

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        emptyLabel.alignment = .center
        emptyLabel.preferredMaxLayoutWidth = 360
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
        updateEmptyState()
    }

    func apply(_ rows: [ListRow]) {
        self.rows = rows
        collectionView.reloadData()
        updateEmptyState()
    }

    private func updateEmptyState() {
        guard isViewLoaded else { return }
        let hasRows = !rows.isEmpty
        scrollView.isHidden = !hasRows
        emptyLabel.isHidden = hasRows
        emptyLabel.stringValue = [emptyState.title, emptyState.detail]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        rows.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: Self.itemIdentifier, for: indexPath)
        guard let posterItem = item as? PosterGridItem, rows.indices.contains(indexPath.item) else { return item }
        posterItem.configure(with: rows[indexPath.item])
        return posterItem
    }
}

@MainActor
private final class PosterGridItem: NSCollectionViewItem {
    private let posterView = NSImageView()
    private let titleLabel = Theme.label(style: .rowTitle, wraps: true)
    private let detailLabel = Theme.label(style: .detail, wraps: false)
    private var posterURL: URL?
    private var action: RowAction?
    private var menuActions: [RowAction] = []

    override func loadView() {
        let card = PosterCardView()
        card.onActivate = { [weak self] in self?.action?.handler() }
        view = card

        posterView.imageScaling = .scaleProportionallyUpOrDown
        posterView.image = Theme.symbol("film", pointSize: 28, weight: .light)
        posterView.contentTintColor = .tertiaryLabelColor
        posterView.wantsLayer = true
        posterView.layer?.cornerRadius = 6
        posterView.layer?.masksToBounds = true
        posterView.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        posterView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        detailLabel.alignment = .center

        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .centerX
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(posterView)
        view.addSubview(labels)
        NSLayoutConstraint.activate([
            posterView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            posterView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            posterView.topAnchor.constraint(equalTo: view.topAnchor),
            posterView.heightAnchor.constraint(equalToConstant: 224),
            labels.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            labels.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            labels.topAnchor.constraint(equalTo: posterView.bottomAnchor, constant: 8),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
        ])
    }

    func configure(with row: ListRow) {
        posterURL = row.thumbnail
        action = row.primaryAction
        menuActions = row.menuActions
        titleLabel.stringValue = row.title
        detailLabel.stringValue = row.details.first ?? ""
        detailLabel.isHidden = row.details.first == nil
        view.toolTip = row.title
        installMenu()

        posterView.image = Theme.symbol("film", pointSize: 28, weight: .light)
        guard let url = row.thumbnail else { return }
        Task { @MainActor [weak self] in
            let image = await PosterCache.shared.image(for: url)
            guard let self, self.posterURL == url else { return }
            self.posterView.image = image ?? Theme.symbol("film", pointSize: 28, weight: .light)
        }
    }

    private func installMenu() {
        let menu = NSMenu()
        for (index, action) in menuActions.enumerated() {
            if action.isSeparatorBefore { menu.addItem(.separator()) }
            let item = NSMenuItem(title: action.title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.isEnabled = action.isEnabled
            if action.isDestructive {
                item.attributedTitle = NSAttributedString(string: action.title, attributes: [.foregroundColor: NSColor.systemRed])
            }
            menu.addItem(item)
        }
        view.menu = menu
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard menuActions.indices.contains(sender.tag) else { return }
        let action = menuActions[sender.tag]
        guard action.isEnabled else { return }
        if let confirmation = action.confirmation {
            let alert = NSAlert()
            alert.messageText = confirmation.message
            alert.informativeText = confirmation.detail
            alert.addButton(withTitle: confirmation.button)
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        action.handler()
    }
}

private final class PosterCardView: NSView {
    var onActivate: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard event.clickCount == 1 else { return }
        onActivate?()
    }
}

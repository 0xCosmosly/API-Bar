import AppKit

func providerAccentNSColor(_ id: String) -> NSColor {
    switch id {
    case "vertex":
        return NSColor(srgbRed: 26/255.0, green: 115/255.0, blue: 232/255.0, alpha: 1.0) // Google Blue #1A73E8
    case "fireworks":
        return NSColor(srgbRed: 101/255.0, green: 29/255.0, blue: 255/255.0, alpha: 1.0) // Fireworks Violet #651DFF
    case "crowbot":
        return NSColor(srgbRed: 0/255.0, green: 220/255.0, blue: 130/255.0, alpha: 1.0)  // Crowbot Green #00DC82
    case "aistudio":
        return NSColor(srgbRed: 14/255.0, green: 165/255.0, blue: 233/255.0, alpha: 1.0) // Gemini Cyan #0EA5E9
    case "cerebras":
        return NSColor(srgbRed: 240/255.0, green: 91/255.0, blue: 41/255.0, alpha: 1.0)  // Cerebras Orange #F05B29
    case "refuseless":
        return NSColor(srgbRed: 200/255.0, green: 16/255.0, blue: 46/255.0, alpha: 1.0)  // Crimson Red #C8102E
    case "venice":
        return NSColor(srgbRed: 138/255.0, green: 43/255.0, blue: 226/255.0, alpha: 1.0) // Venice Purple #8A2BE2
    default:
        return NSColor.systemBlue
    }
}

struct ProviderTabItem {
    let id: String
    let name: String
    let accentColor: NSColor?
}

@MainActor final class ProviderTabButton: NSButton {
    let tabItem: ProviderTabItem
    override var isFlipped: Bool { true }

    init(tab: ProviderTabItem, index: Int, target: AnyObject?, action: Selector) {
        self.tabItem = tab
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.tag = index
        self.isBordered = false
        self.title = tab.name
        self.setAccessibilityLabel("Show " + tab.name)
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let isSelected = state == .on

        // 1. Blue pill background for active tab (matches CodexBar)
        if isSelected {
            let pillRect = bounds.insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(roundedRect: pillRect, xRadius: 7, yRadius: 7)
            NSColor(srgbRed: 0/255, green: 122/255, blue: 255/255, alpha: 1).setFill()
            path.fill()
        }

        // 2. Icon (centered horizontally, white if selected, labelColor if unselected)
        let iconSize = NSSize(width: 16, height: 16)
        let iconRect = NSRect(
            x: round((bounds.width - iconSize.width) / 2),
            y: 5,
            width: iconSize.width,
            height: iconSize.height
        )
        if let baseImage = ProviderIcon.image(tabItem.id).copy() as? NSImage {
            baseImage.isTemplate = false
            baseImage.lockFocus()
            (isSelected ? NSColor.white : NSColor.labelColor).set()
            NSRect(origin: .zero, size: baseImage.size).fill(using: .sourceAtop)
            baseImage.unlockFocus()
            baseImage.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        }

        // 3. Label text (auto-fit font so full name is always shown without truncation)
        let textColor = isSelected ? NSColor.white : NSColor.labelColor
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail

        var fontSize: CGFloat = 10.0
        var font = NSFont.systemFont(ofSize: fontSize, weight: isSelected ? .semibold : .medium)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: style
        ]
        var titleString = NSAttributedString(string: title, attributes: attrs)
        while titleString.size().width > bounds.width - 4 && fontSize > 7.5 {
            fontSize -= 0.5
            font = NSFont.systemFont(ofSize: fontSize, weight: isSelected ? .semibold : .medium)
            attrs[.font] = font
            titleString = NSAttributedString(string: title, attributes: attrs)
        }

        let textSize = titleString.size()
        let textRect = NSRect(
            x: 1,
            y: 24,
            width: bounds.width - 2,
            height: textSize.height
        )
        titleString.draw(in: textRect)

        // 4. Colored brand indicator bar underneath the label (if accentColor is set)
        if let accentColor = tabItem.accentColor {
            let barWidth: CGFloat = round(min(textSize.width, bounds.width - 12))
            let barHeight: CGFloat = 2.0
            let barRect = NSRect(
                x: round((bounds.width - barWidth) / 2),
                y: round(textRect.origin.y + textSize.height + 2),
                width: barWidth,
                height: barHeight
            )
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: 1.0, yRadius: 1.0)
            accentColor.setFill()
            barPath.fill()
        }
    }
}

/// NSMenu runs its own tracking loop. Handle press/release in the persistent
/// parent, rather than nesting SwiftUI/NSButton tracking loops inside it.
/// This follows CodexBar's MIT-licensed ProviderSwitcherView click handling.
@MainActor final class ProviderTabsView: NSView {
    private(set) var items: [ProviderTabItem]
    let onSelect: (String) -> Void
    private(set) var buttons: [NSButton] = []
    private var pressedIndex: Int?
    var selectedID: String { didSet { updateSelection() } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private let columns = 4
    private let rowHeight: CGFloat = 46.0

    static func defaultItems(balances: [Balance]) -> [ProviderTabItem] {
        var result = [ProviderTabItem(id: "overview", name: "Overview", accentColor: nil)]
        for b in balances {
            result.append(ProviderTabItem(id: b.id, name: b.name, accentColor: providerAccentNSColor(b.id)))
        }
        return result
    }

    convenience init(providers: [Balance], selectedID: String, onSelect: @escaping (String) -> Void) {
        self.init(items: Self.defaultItems(balances: providers), selectedID: selectedID, onSelect: onSelect)
    }

    init(items: [ProviderTabItem], selectedID: String, onSelect: @escaping (String) -> Void) {
        self.items = items; self.selectedID = selectedID; self.onSelect = onSelect
        let rowCount = (items.count + 4 - 1) / 4
        let initialHeight = CGFloat(rowCount) * 46.0 + 8
        super.init(frame: NSRect(x: 0, y: 0, width: 330, height: initialHeight))
        buildButtons()
        layoutTabs()
        updateSelection()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildButtons() {
        for button in buttons { button.removeFromSuperview() }
        buttons.removeAll()
        for (index, item) in items.enumerated() {
            let button = ProviderTabButton(tab: item, index: index, target: self, action: #selector(activate(_:)))
            addSubview(button)
            buttons.append(button)
        }
    }

    func updateItems(_ newItems: [ProviderTabItem]) {
        guard newItems.map(\.id) != items.map(\.id) else {
            updateSelection()
            return
        }
        items = newItems
        buildButtons()
        layoutTabs()
        updateSelection()
    }

    private func layoutTabs() {
        let count = max(1, items.count)
        let rowCount = (count + columns - 1) / columns
        let sideMargin: CGFloat = 8
        let totalWidth = bounds.width - sideMargin * 2
        let colWidth = totalWidth / CGFloat(columns)

        for (index, button) in buttons.enumerated() {
            let row = index / columns
            let col = index % columns
            button.frame = NSRect(
                x: sideMargin + CGFloat(col) * colWidth + 1,
                y: 4 + CGFloat(row) * rowHeight,
                width: colWidth - 2,
                height: rowHeight - 2
            )
        }
        let neededHeight = CGFloat(rowCount) * rowHeight + 8
        if frame.height != neededHeight {
            frame.size.height = neededHeight
        }
    }

    override func layout() { super.layout(); layoutTabs() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Subtle divider line spanning full width underneath all tabs
        let lineRect = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        NSColor.separatorColor.setFill()
        lineRect.fill()
    }

    private func updateSelection() {
        for (index, button) in buttons.enumerated() {
            let selected = items[index].id == selectedID
            button.state = selected ? .on : .off
            button.needsDisplay = true
        }
        needsDisplay = true
    }

    @objc private func activate(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        onSelect(items[sender.tag].id)
    }

    func index(at point: NSPoint) -> Int? { buttons.firstIndex(where: { $0.frame.contains(point) }) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit === self ? hit : self
    }

    private func location(_ event: NSEvent) -> NSPoint {
        guard let eventWindow = event.window, let window, eventWindow !== window else { return convert(event.locationInWindow, from: nil) }
        return convert(window.convertPoint(fromScreen: eventWindow.convertPoint(toScreen: event.locationInWindow)), from: nil)
    }

    // Pure point handlers also allow canceled drags and tab-edge clicks to be
    // regression-tested without generating input into a user's open apps.
    func press(at point: NSPoint) { pressedIndex = index(at: point) }
    func release(at point: NSPoint) {
        defer { pressedIndex = nil }
        guard let pressedIndex, index(at: point) == pressedIndex else { return }
        onSelect(items[pressedIndex].id)
    }

    override func mouseDown(with event: NSEvent) { press(at: location(event)) }
    override func mouseUp(with event: NSEvent) { release(at: location(event)) }
    override func keyDown(with event: NSEvent) {
        let current = items.firstIndex(where: { $0.id == selectedID }) ?? 0
        switch event.keyCode {
        case 123: // Left arrow
            onSelect(items[(current + items.count - 1) % items.count].id)
        case 124: // Right arrow
            onSelect(items[(current + 1) % items.count].id)
        case 125: // Down arrow
            let next = current + columns
            if next < items.count { onSelect(items[next].id) }
            else { onSelect(items[(current + 1) % items.count].id) }
        case 126: // Up arrow
            let prev = current - columns
            if prev >= 0 { onSelect(items[prev].id) }
            else { onSelect(items[(current + items.count - 1) % items.count].id) }
        default: super.keyDown(with: event)
        }
    }
}

@MainActor final class MergedMenuView: NSView {
    unowned let app: APIBarApp
    var tabs: ProviderTabsView
    private var detail: NSView?

    init(app: APIBarApp) {
        self.app = app
        let items = ProviderTabsView.defaultItems(balances: app.balances)
        tabs = ProviderTabsView(items: items, selectedID: app.mergedProvider) { [weak app] id in
            app?.selectMergedProvider(id)
        }
        super.init(frame: NSRect(x: 0, y: 0, width: 330, height: 280))
        addSubview(tabs)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateProviders(_ balances: [Balance]) {
        let items = ProviderTabsView.defaultItems(balances: balances)
        tabs.updateItems(items)
        refresh()
    }

    func refresh() {
        tabs.selectedID = app.mergedProvider
        tabs.updateItems(ProviderTabsView.defaultItems(balances: app.balances))
        detail?.removeFromSuperview()
        let card: NSView
        if app.mergedProvider == "overview" {
            card = OverviewCard(app: app)
        } else {
            let b = app.balances.first(where: { $0.id == app.mergedProvider }) ?? app.selectedMergedBalance
            card = BalanceCard(b, status: app.providerStatus[b.id])
        }
        let detailHeight = card.frame.height
        frame.size.height = tabs.frame.height + detailHeight
        tabs.frame.origin = NSPoint(x: 0, y: detailHeight)
        card.frame.origin = NSPoint(x: round((bounds.width - card.frame.width) / 2), y: detailHeight - card.frame.height)
        addSubview(card, positioned: .below, relativeTo: tabs)
        detail = card
        layoutSubtreeIfNeeded()
        needsDisplay = true
    }
}

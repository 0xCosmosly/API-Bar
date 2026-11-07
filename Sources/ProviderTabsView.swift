import AppKit

let percentageYellowNSColor = NSColor(name: nil, dynamicProvider: { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor.systemYellow
        : NSColor(srgbRed: 180/255.0, green: 120/255.0, blue: 0/255.0, alpha: 1.0)
})

func providerAccentNSColor(_ id: String) -> NSColor {
    switch id {
    case "vertex", "aistudio":
        return NSColor(srgbRed: 26/255.0, green: 115/255.0, blue: 232/255.0, alpha: 1.0) // Google Blue #1A73E8
    case "fireworks":
        return NSColor(srgbRed: 212/255.0, green: 100/255.0, blue: 0/255.0, alpha: 1.0)   // Deep Orange #D46400
    case "crowbot":
        return NSColor(srgbRed: 13/255.0, green: 115/255.0, blue: 60/255.0, alpha: 1.0)  // Deep Emerald #0D733C
    case "cerebras":
        return NSColor(srgbRed: 220/255.0, green: 50/255.0, blue: 30/255.0, alpha: 1.0)  // Cerebras Red-Orange #DC321E
    case "refuseless":
        return NSColor(srgbRed: 200/255.0, green: 16/255.0, blue: 46/255.0, alpha: 1.0)  // Crimson Red #C8102E
    case "venice":
        return NSColor(srgbRed: 123/255.0, green: 31/255.0, blue: 162/255.0, alpha: 1.0) // Venice Purple #7B1FA2
    case "lutheos":
        return NSColor(srgbRed: 173/255.0, green: 79/255.0, blue: 44/255.0, alpha: 1.0)   // Lutheos Terracotta #AD4F2C
    case "unaligned":
        return NSColor(srgbRed: 229/255.0, green: 50/255.0, blue: 45/255.0, alpha: 1.0) // Unaligned Signal Red #E5322D
    case "yeta":
        return NSColor(srgbRed: 202/255.0, green: 138/255.0, blue: 4/255.0, alpha: 1.0) // Yeta Amber #CA8A04
    case "heimdallm":
        return NSColor(srgbRed: 183/255.0, green: 23/255.0, blue: 31/255.0, alpha: 1.0) // Heimdall Crimson #B7171F
    default:
        return NSColor.systemBlue
    }
}

struct ProviderTabItem: Equatable {
    let id: String
    let name: String
    let accentColor: NSColor?
    var percent: Double = 100.0
    var isLive: Bool = false
}

@MainActor final class ProviderTabButton: NSButton {
    var tabItem: ProviderTabItem {
        didSet {
            title = tabItem.name
            setAccessibilityLabel("Show " + tabItem.name)
            needsDisplay = true
        }
    }
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

        var fontSize: CGFloat = 11.5
        var font = NSFont.systemFont(ofSize: fontSize, weight: isSelected ? .bold : .semibold)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: style
        ]
        var titleString = NSAttributedString(string: title, attributes: attrs)
        while titleString.size().width > bounds.width - 4 && fontSize > 9.0 {
            fontSize -= 0.5
            font = NSFont.systemFont(ofSize: fontSize, weight: isSelected ? .bold : .semibold)
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

        // 4. Indicator bar underneath the label matching provider view gauge
        if let accentColor = tabItem.accentColor {
            let totalBarWidth: CGFloat = round(min(max(textSize.width, 24), bounds.width - 12))
            let barHeight: CGFloat = 2.5
            let barY: CGFloat = round(textRect.origin.y + textSize.height + 2)
            let trackRect = NSRect(
                x: round((bounds.width - totalBarWidth) / 2),
                y: barY,
                width: totalBarWidth,
                height: barHeight
            )
            let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
            let trackColor = isSelected ? NSColor.white.withAlphaComponent(0.25) : NSColor.labelColor.withAlphaComponent(0.12)
            trackColor.setFill()
            trackPath.fill()

            let fillFraction = max(0.0, min(1.0, tabItem.percent / 100.0))
            var fillWidth = round(totalBarWidth * CGFloat(fillFraction))
            if fillFraction > 0 && fillWidth < barHeight {
                fillWidth = barHeight
            }
            if fillWidth > 0 {
                let fillRect = NSRect(
                    x: trackRect.origin.x,
                    y: barY,
                    width: fillWidth,
                    height: barHeight
                )
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
                accentColor.setFill()
                fillPath.fill()
            }
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
    private let rowHeight: CGFloat = 48.0

    static func defaultItems(balances: [Balance]) -> [ProviderTabItem] {
        let totalRemaining = balances.reduce(0.0) { $0 + $1.remaining }
        let totalBaseline = balances.reduce(0.0) { $0 + $1.baseline }
        let totalPercent = totalBaseline > 0 ? max(0, totalRemaining / totalBaseline * 100) : 0
        let anyLive = balances.contains { $0.live }
        var result = [ProviderTabItem(id: "overview", name: "Overview", accentColor: nil, percent: totalPercent, isLive: anyLive)]
        for b in balances {
            result.append(ProviderTabItem(id: b.id, name: b.name, accentColor: providerAccentNSColor(b.id), percent: b.percent, isLive: b.live))
        }
        return result
    }

    convenience init(providers: [Balance], selectedID: String, onSelect: @escaping (String) -> Void) {
        self.init(items: Self.defaultItems(balances: providers), selectedID: selectedID, onSelect: onSelect)
    }

    init(items: [ProviderTabItem], selectedID: String, onSelect: @escaping (String) -> Void) {
        self.items = items; self.selectedID = selectedID; self.onSelect = onSelect
        let rowCount = (items.count + 4 - 1) / 4
        let initialHeight = CGFloat(rowCount) * 48.0 + 8
        super.init(frame: NSRect(x: 0, y: 0, width: 365, height: initialHeight))
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
        if newItems.map(\.id) == items.map(\.id) {
            items = newItems
            for (index, item) in newItems.enumerated() where index < buttons.count {
                if let tabBtn = buttons[index] as? ProviderTabButton {
                    tabBtn.tabItem = item
                }
            }
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
        super.init(frame: NSRect(x: 0, y: 0, width: 365, height: 280))
        addSubview(tabs)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateProviders(_ balances: [Balance]) {
        // Paused providers are hidden here, matching refresh(). Passing the full
        // list made the tab ids flip between calls, which rebuilt the buttons and
        // left callers holding stale references.
        let items = ProviderTabsView.defaultItems(balances: balances.filter(\.isEnabled))
        tabs.updateItems(items)
        refresh()
    }

    func refresh() {
        tabs.selectedID = app.mergedProvider
        tabs.updateItems(ProviderTabsView.defaultItems(balances: app.activeBalances))
        detail?.removeFromSuperview()
        let card: NSView
        if app.mergedProvider == "overview" {
            card = OverviewCard(app: app)
        } else {
            let b = app.activeBalances.first(where: { $0.id == app.mergedProvider }) ?? app.selectedMergedBalance
            card = BalanceCard(b, status: app.providerStatus[b.id])
        }
        let detailHeight = card.frame.height
        frame.size.height = tabs.frame.height + detailHeight
        tabs.frame = NSRect(x: 0, y: detailHeight, width: bounds.width, height: tabs.frame.height)
        card.frame = NSRect(x: 0, y: 0, width: bounds.width, height: detailHeight)
        addSubview(card, positioned: .below, relativeTo: tabs)
        detail = card
        layoutSubtreeIfNeeded()
        needsDisplay = true
    }
}

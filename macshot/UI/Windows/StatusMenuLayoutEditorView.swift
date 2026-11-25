import Cocoa

/// Settings editor for the menu bar menu: three stacked sections ("In the
/// Menu", "Under More", "Hidden"). Rows are dragged to reorder them or to move
/// them between sections; locked items (Settings, Quit, More) can only move
/// inside the menu. Right-click a row for the same moves without dragging.
final class StatusMenuLayoutEditorView: NSView {

    typealias Zone = StatusMenuLayout.Zone

    /// Called after every change the user makes, with the new layout.
    var onChange: ((StatusMenuLayout) -> Void)?

    var layout: StatusMenuLayout {
        get { currentLayout() }
        set {
            cancelDrag()
            rebuildRows(newValue.normalized())
        }
    }

    // MARK: Metrics

    static let rowHeight: CGFloat = 26
    private static let headerHeight: CGFloat = 26
    private static let boxPadding: CGFloat = 4
    private static let emptyHeight: CGFloat = 32
    private static let sectionGap: CGFloat = 10
    private static let dragThreshold: CGFloat = 3

    // MARK: State

    private var rows: [Zone: [RowView]] = [.menu: [], .more: [], .hidden: []]

    private struct Drag {
        let row: RowView
        let origin: (zone: Zone, index: Int)
        let grabOffsetY: CGFloat
        var target: (zone: Zone, index: Int)?
        /// The section the pointer is over, when the row can't go there.
        var rejectedZone: Zone?
    }
    private var pressedRow: (row: RowView, point: NSPoint)?
    private var drag: Drag?

    override var isFlipped: Bool { true }

    init(layout: StatusMenuLayout) {
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
        translatesAutoresizingMaskIntoConstraints = false
        rebuildRows(layout.normalized())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Model <-> rows

    private func rebuildRows(_ layout: StatusMenuLayout) {
        rows.values.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        for zone in Zone.allCases {
            rows[zone] = layout[zone].map { entry in
                let row = RowView(entry: entry)
                addSubview(row)
                return row
            }
        }
        refreshRowStates()
        layoutRows(animated: false)
    }

    private func currentLayout() -> StatusMenuLayout {
        var layout = StatusMenuLayout(menu: [], more: [], hidden: [])
        for zone in Zone.allCases { layout[zone] = (rows[zone] ?? []).map(\.entry) }
        if let drag {
            let index = min(drag.origin.index, layout[drag.origin.zone].count)
            layout[drag.origin.zone].insert(drag.row.entry, at: index)
        }
        return layout
    }

    private func refreshRowStates() {
        for zone in Zone.allCases {
            for row in rows[zone] ?? [] { row.zone = zone }
        }
    }

    // MARK: Geometry

    private struct SectionFrame {
        var header: NSRect
        var box: NSRect
        var rowsStartY: CGFloat
    }

    /// Rows shown in each zone, with the drag gap where the dragged row would land.
    private func slotCount(in zone: Zone) -> Int {
        var count = rows[zone]?.count ?? 0
        if let target = drag?.target, target.zone == zone { count += 1 }
        return count
    }

    private func sectionFrames() -> [Zone: SectionFrame] {
        var result: [Zone: SectionFrame] = [:]
        var y: CGFloat = 0
        let width = bounds.width
        for zone in Zone.allCases {
            let header = NSRect(x: 0, y: y, width: width, height: Self.headerHeight)
            y += Self.headerHeight
            let slots = slotCount(in: zone)
            let contentHeight = slots == 0 ? Self.emptyHeight : CGFloat(slots) * Self.rowHeight + Self.boxPadding * 2
            let box = NSRect(x: 0, y: y, width: width, height: contentHeight)
            result[zone] = SectionFrame(header: header, box: box, rowsStartY: y + Self.boxPadding)
            y += contentHeight + Self.sectionGap
        }
        return result
    }

    private var contentHeight: CGFloat {
        (sectionFrames()[.hidden].map { $0.box.maxY }) ?? 0
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: contentHeight)
    }

    override func layout() {
        super.layout()
        layoutRows(animated: false)
    }

    private func layoutRows(animated: Bool) {
        let frames = sectionFrames()
        let apply = {
            for zone in Zone.allCases {
                guard let section = frames[zone] else { continue }
                var slot = 0
                for row in self.rows[zone] ?? [] {
                    if let target = self.drag?.target, target.zone == zone, target.index == slot { slot += 1 }
                    let frame = NSRect(x: Self.boxPadding, y: section.rowsStartY + CGFloat(slot) * Self.rowHeight,
                                       width: section.box.width - Self.boxPadding * 2, height: Self.rowHeight)
                    if animated { row.animator().frame = frame } else { row.frame = frame }
                    slot += 1
                }
            }
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.allowsImplicitAnimation = true
                apply()
            }
        } else {
            apply()
        }
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let frames = sectionFrames()
        for zone in Zone.allCases {
            guard let section = frames[zone] else { continue }
            drawHeader(for: zone, in: section.header)

            let boxPath = NSBezierPath(roundedRect: section.box.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
            NSColor.controlBackgroundColor.withAlphaComponent(0.55).setFill()
            boxPath.fill()
            let isTarget = drag?.target?.zone == zone && drag?.origin.zone != zone
            let isRejected = drag?.rejectedZone == zone
            if isRejected {
                NSColor.systemRed.setStroke()
                boxPath.lineWidth = 2
            } else if isTarget {
                NSColor.controlAccentColor.setStroke()
                boxPath.lineWidth = 2
            } else {
                NSColor.separatorColor.setStroke()
                boxPath.lineWidth = 1
            }
            boxPath.stroke()

            if slotCount(in: zone) == 0 {
                let hint = zone == .more ? L("Drop items here to keep them under More.")
                    : zone == .hidden ? L("Drop items here to hide them.") : ""
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
                let size = hint.size(withAttributes: attributes)
                hint.draw(at: NSPoint(x: section.box.minX + 12, y: section.box.midY - size.height / 2),
                          withAttributes: attributes)
            }
        }
    }

    private func drawHeader(for zone: Zone, in rect: NSRect) {
        let title: String
        switch zone {
        case .menu: title = L("In the Menu")
        case .more: title = L("Under More")
        case .hidden: title = L("Hidden")
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 0.4,
        ]
        let text = title.uppercased() as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: 2, y: rect.maxY - size.height - 6), withAttributes: attributes)

        let right: String
        let color: NSColor
        if drag?.rejectedZone == zone {
            right = L("Settings and Quit always stay in the menu.")
            color = .systemRed
        } else {
            let count = (rows[zone] ?? []).filter { $0.entry != .separator }.count
            right = count == 0 ? "" : "\(count)"
            color = .tertiaryLabelColor
        }
        let rightAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: color,
        ]
        let rightSize = right.size(withAttributes: rightAttributes)
        right.draw(at: NSPoint(x: rect.maxX - rightSize.width - 4, y: rect.maxY - rightSize.height - 6),
                   withAttributes: rightAttributes)
    }

    // MARK: Mouse

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func row(at point: NSPoint) -> RowView? {
        for zone in Zone.allCases {
            if let row = rows[zone]?.first(where: { $0.frame.contains(point) }) { return row }
        }
        return nil
    }

    private func position(of row: RowView) -> (zone: Zone, index: Int)? {
        for zone in Zone.allCases {
            if let index = rows[zone]?.firstIndex(where: { $0 === row }) { return (zone, index) }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressedRow = row(at: point).map { ($0, point) }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if drag == nil {
            guard let pressed = pressedRow,
                  hypot(point.x - pressed.point.x, point.y - pressed.point.y) >= Self.dragThreshold,
                  let origin = position(of: pressed.row) else { return }
            beginDrag(row: pressed.row, origin: origin, at: pressed.point)
        }
        updateDrag(at: point)
        autoscroll(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        pressedRow = nil
        guard drag != nil else { return }
        endDrag()
    }

    // MARK: Dragging

    private func beginDrag(row: RowView, origin: (zone: Zone, index: Int), at point: NSPoint) {
        rows[origin.zone]?.remove(at: origin.index)
        drag = Drag(row: row, origin: origin, grabOffsetY: point.y - row.frame.minY,
                    target: origin, rejectedZone: nil)
        row.isLifted = true
        // Keep the dragged row above its neighbours.
        addSubview(row, positioned: .above, relativeTo: nil)
        NSCursor.closedHand.push()
    }

    /// The section under `y`, or the nearest one.
    private func zone(atY y: CGFloat) -> Zone {
        let frames = sectionFrames()
        var best: (zone: Zone, distance: CGFloat) = (.menu, .greatestFiniteMagnitude)
        for zone in Zone.allCases {
            guard let section = frames[zone] else { continue }
            let area = NSRect(x: 0, y: section.header.minY, width: bounds.width,
                              height: section.box.maxY - section.header.minY)
            let distance = y < area.minY ? area.minY - y : (y > area.maxY ? y - area.maxY : 0)
            if distance < best.distance { best = (zone, distance) }
        }
        return best.zone
    }

    private func updateDrag(at point: NSPoint) {
        guard var current = drag else { return }
        current.row.frame.origin.y = point.y - current.grabOffsetY

        let rowCenter = current.row.frame.midY
        let zone = zone(atY: rowCenter)
        if StatusMenuLayout.canPlace(current.row.entry, in: zone) {
            // Rows above the dragged row's center, by their slots without the
            // gap: stable while the gap moves, so the target doesn't flicker.
            let start = sectionFrames()[zone]?.rowsStartY ?? 0
            let slots = rows[zone]?.count ?? 0
            var index = 0
            while index < slots, start + (CGFloat(index) + 0.5) * Self.rowHeight < rowCenter { index += 1 }
            current.target = (zone, index)
            current.rejectedZone = nil
        } else {
            current.target = nil
            current.rejectedZone = zone
        }
        let changed = current.target?.zone != drag?.target?.zone || current.target?.index != drag?.target?.index
            || current.rejectedZone != drag?.rejectedZone
        drag = current
        if changed { layoutRowsKeepingDragged(animated: true) }
    }

    private func layoutRowsKeepingDragged(animated: Bool) {
        let frame = drag?.row.frame
        layoutRows(animated: animated)
        if let frame { drag?.row.frame = frame }
    }

    private func endDrag() {
        guard let current = drag else { return }
        NSCursor.pop()
        let destination = current.target ?? current.origin
        drag = nil
        current.row.isLifted = false

        if current.row.entry == .separator && destination.zone == .hidden {
            // A hidden separator means nothing: dropping one in Hidden removes it.
            current.row.removeFromSuperview()
        } else {
            let index = min(destination.index, rows[destination.zone]?.count ?? 0)
            rows[destination.zone]?.insert(current.row, at: index)
        }
        refreshRowStates()
        layoutRows(animated: true)
        let moved = destination.zone != current.origin.zone || destination.index != current.origin.index
        if current.target != nil && moved { onChange?(currentLayout()) }
    }

    private func cancelDrag() {
        guard let current = drag else { return }
        NSCursor.pop()
        drag = nil
        current.row.isLifted = false
        rows[current.origin.zone]?.insert(current.row, at: min(current.origin.index, rows[current.origin.zone]?.count ?? 0))
    }

    // MARK: Programmatic moves (context menu, tests)

    /// Moves the entry at `source` into `zone` (at its end, or above the
    /// Settings block for the menu). Returns false when the move isn't allowed.
    @discardableResult
    func move(from source: (zone: Zone, index: Int), to zone: Zone) -> Bool {
        var layout = currentLayout()
        let destinationIndex: Int
        if zone == .menu, source.zone != .menu {
            destinationIndex = layout.menu.firstIndex(of: .item(.more)) ?? layout.menu.firstIndex(of: .item(.settings)) ?? layout.menu.count
        } else {
            destinationIndex = layout[zone].count
        }
        guard layout.move(from: source, to: (zone, destinationIndex)) else { return false }
        applyAnimated(layout)
        return true
    }

    /// Replaces the layout, reusing row views so unchanged rows glide into place.
    private func applyAnimated(_ layout: StatusMenuLayout) {
        var pool = rows
        var used = Set<ObjectIdentifier>()
        func take(_ entry: StatusMenuEntry) -> RowView {
            for zone in Zone.allCases {
                if let index = pool[zone]?.firstIndex(where: { $0.entry == entry && !used.contains(ObjectIdentifier($0)) }) {
                    let row = pool[zone]!.remove(at: index)
                    used.insert(ObjectIdentifier(row))
                    return row
                }
            }
            let row = RowView(entry: entry)
            row.frame = NSRect(x: Self.boxPadding, y: 0, width: bounds.width - Self.boxPadding * 2, height: Self.rowHeight)
            addSubview(row)
            return row
        }
        var next: [Zone: [RowView]] = [:]
        for zone in Zone.allCases { next[zone] = layout[zone].map(take) }
        pool.values.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        rows = next
        refreshRowStates()
        layoutRows(animated: true)
        onChange?(currentLayout())
    }

    func addSeparator() {
        var layout = currentLayout()
        layout.addSeparator()
        applyAnimated(layout)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let row = row(at: point), let source = position(of: row) else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, zone: Zone) {
            let item = NSMenuItem(title: title, action: #selector(contextMove(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ContextMove(source: source, zone: zone)
            item.isEnabled = source.zone != zone && StatusMenuLayout.canPlace(row.entry, in: zone)
            menu.addItem(item)
        }
        if row.entry == .separator {
            add(L("Remove Separator"), zone: .hidden)
        } else {
            add(L("Show in Menu"), zone: .menu)
            add(L("Move to More"), zone: .more)
            add(L("Hide"), zone: .hidden)
        }
        return menu
    }

    private final class ContextMove {
        let source: (zone: Zone, index: Int)
        let zone: Zone
        init(source: (zone: Zone, index: Int), zone: Zone) { self.source = source; self.zone = zone }
    }

    @objc private func contextMove(_ sender: NSMenuItem) {
        guard let move = sender.representedObject as? ContextMove else { return }
        self.move(from: move.source, to: move.zone)
    }

    // MARK: Test hooks

    /// Simulates a drag of the row at `source` to `point` (view coordinates)
    /// and back up, exactly like the mouse path, for tests and visual probes.
    func simulateDrag(from source: (zone: Zone, index: Int), toY y: CGFloat, release: Bool = true) {
        guard let row = rows[source.zone]?[source.index] else { return }
        let start = NSPoint(x: row.frame.midX, y: row.frame.midY)
        beginDrag(row: row, origin: source, at: start)
        updateDrag(at: NSPoint(x: start.x, y: y))
        updateDrag(at: NSPoint(x: start.x, y: y))
        if release { endDrag() } else { layoutRowsKeepingDragged(animated: false) }
    }

    func rowFrame(zone: Zone, index: Int) -> NSRect? { rows[zone]?[index].frame }

    func sectionBoxFrame(_ zone: Zone) -> NSRect? { sectionFrames()[zone]?.box }
}

// MARK: - Row

private final class RowView: NSView {
    let entry: StatusMenuEntry
    var zone: StatusMenuLayout.Zone = .menu { didSet { needsDisplay = true } }
    var isLifted = false {
        didSet {
            wantsLayer = true
            layer?.shadowOpacity = isLifted ? 0.25 : 0
            layer?.shadowRadius = 6
            layer?.shadowOffset = NSSize(width: 0, height: -2)
            needsDisplay = true
        }
    }

    init(entry: StatusMenuEntry) {
        self.entry = entry
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        setAccessibilityLabel(entry.itemID?.title ?? L("Separator"))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight))
    }

    private static func draw(_ image: NSImage?, tint: NSColor, centeredIn rect: NSRect) {
        guard let image else { return }
        let size = image.size
        let target = NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                            width: size.width, height: size.height)
        let tinted = NSImage(size: size, flipped: false) { bounds in
            image.draw(in: bounds)
            tint.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let content = bounds.insetBy(dx: 0, dy: 1)
        if isLifted {
            NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: content, xRadius: 5, yRadius: 5).fill()
            NSColor.controlBackgroundColor.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: content, xRadius: 5, yRadius: 5).fill()
            NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
            NSBezierPath(roundedRect: content.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5).stroke()
        }

        var x: CGFloat = 6
        Self.draw(Self.symbol("line.3.horizontal", size: 10), tint: .tertiaryLabelColor,
                  centeredIn: NSRect(x: x, y: 0, width: 14, height: bounds.height))
        x += 20

        guard let id = entry.itemID else {
            let label = L("Separator")
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.5),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            let size = label.size(withAttributes: attributes)
            let midX = (x + bounds.width - 8) / 2
            label.draw(at: NSPoint(x: midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
            NSColor.separatorColor.setFill()
            NSRect(x: x, y: bounds.midY, width: midX - size.width / 2 - 8 - x, height: 1).fill()
            NSRect(x: midX + size.width / 2 + 8, y: bounds.midY, width: bounds.width - 8 - (midX + size.width / 2 + 8), height: 1).fill()
            return
        }

        let dimmed = zone == .hidden
        Self.draw(Self.symbol(id.symbolName, size: 13), tint: dimmed ? .tertiaryLabelColor : .secondaryLabelColor,
                  centeredIn: NSRect(x: x, y: 0, width: 18, height: bounds.height))
        x += 26

        var right = bounds.width - 8
        if id.isLocked {
            let lock = Self.symbol("lock.fill", size: 10, weight: .semibold)
            Self.draw(lock, tint: .systemOrange, centeredIn: NSRect(x: right - 12, y: 0, width: 12, height: bounds.height))
            right -= 20
        }
        if id.hasSubmenu {
            Self.draw(Self.symbol("chevron.right", size: 9, weight: .semibold), tint: .tertiaryLabelColor,
                      centeredIn: NSRect(x: right - 10, y: 0, width: 10, height: bounds.height))
            right -= 18
        } else if let shortcut = Self.shortcutText(for: id) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11.5),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let size = shortcut.size(withAttributes: attributes)
            shortcut.draw(at: NSPoint(x: right - size.width, y: bounds.midY - size.height / 2), withAttributes: attributes)
            right -= size.width + 10
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: dimmed ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let title = id.title as NSString
        let height = title.size(withAttributes: titleAttributes).height
        title.draw(in: NSRect(x: x, y: bounds.midY - height / 2, width: max(0, right - x), height: height),
                   withAttributes: titleAttributes)
    }

    static func shortcutText(for id: StatusMenuItemID) -> String? {
        if let fixed = id.fixedShortcut { return fixed }
        guard let slot = id.hotkeySlot else { return nil }
        let (keyCode, modifiers) = HotkeyManager.readHotkey(for: slot)
        if keyCode == 0 && modifiers == 0 { return nil }
        return HotkeyManager.displayString(for: slot)
    }
}

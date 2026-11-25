import Cocoa

/// Real NSView top bar for the editor window. Pinned to top of container.
/// Contains: pixel dimensions, crop/flip/add-capture buttons, drag-out handle, zoom dropdown.
class EditorTopBarView: NSView {

    weak var overlayView: OverlayView?
    /// Drags the current image into other apps; the editor controller supplies the image.
    let dragHandle = EditorDragHandleView()
    private var sizeLabel: NSTextField!
    private var zoomButton: NSButton!
    private var doneButton: NSButton?
    private var toolButtons: [NSButton] = []
    private let bottomBorder = NSView()
    var onDone: (() -> Void)?
    var onSaveProject: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.width, .minYMargin]  // pin to top, stretch width
        layer?.backgroundColor = ToolbarLayout.bgColor.cgColor

        sizeLabel = makeLabel("")
        sizeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.45)

        let cropBtn = makeButton("crop", tooltip: L("Crop"), action: #selector(cropClicked))
        let flipHBtn = makeButton("arrow.left.and.right.righttriangle.left.righttriangle.right", tooltip: L("Flip Horizontal"), action: #selector(flipHClicked))
        let flipVBtn = makeButton("arrow.up.and.down.righttriangle.up.righttriangle.down", tooltip: L("Flip Vertical"), action: #selector(flipVClicked))
        let addCaptureBtn = makeButton("rectangle.badge.plus", tooltip: L("Add Capture"), action: #selector(addCaptureClicked))
        let saveProjectBtn = makeButton("square.and.arrow.down.on.square",
            tooltip: L("Save as Editable Project (⇧⌘S)"), action: #selector(saveProjectClicked))
        toolButtons = [cropBtn, flipHBtn, flipVBtn, addCaptureBtn, saveProjectBtn]

        // Zoom dropdown button
        let zoom = TopBarHoverButton()
        zoom.quickTooltip = L("Zoom")
        zoomButton = zoom
        zoomButton.bezelStyle = .recessed
        zoomButton.isBordered = false
        zoomButton.title = "100% ▾"
        zoomButton.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        zoomButton.contentTintColor = ToolbarLayout.iconColor.withAlphaComponent(0.45)
        zoomButton.target = self
        zoomButton.action = #selector(zoomButtonClicked)

        // Bottom border
        let border = bottomBorder
        border.wantsLayer = true
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)

        // Layout with constraints
        for v: NSView in [sizeLabel, cropBtn, flipHBtn, flipVBtn, addCaptureBtn, saveProjectBtn, dragHandle, zoomButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),

            sizeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            sizeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            cropBtn.leadingAnchor.constraint(equalTo: sizeLabel.trailingAnchor, constant: 16),
            cropBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            cropBtn.widthAnchor.constraint(equalToConstant: 24),
            cropBtn.heightAnchor.constraint(equalToConstant: 22),

            flipHBtn.leadingAnchor.constraint(equalTo: cropBtn.trailingAnchor, constant: 4),
            flipHBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            flipHBtn.widthAnchor.constraint(equalToConstant: 24),
            flipHBtn.heightAnchor.constraint(equalToConstant: 22),

            flipVBtn.leadingAnchor.constraint(equalTo: flipHBtn.trailingAnchor, constant: 4),
            flipVBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            flipVBtn.widthAnchor.constraint(equalToConstant: 24),
            flipVBtn.heightAnchor.constraint(equalToConstant: 22),

            addCaptureBtn.leadingAnchor.constraint(equalTo: flipVBtn.trailingAnchor, constant: 12),
            addCaptureBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            addCaptureBtn.widthAnchor.constraint(equalToConstant: 24),
            addCaptureBtn.heightAnchor.constraint(equalToConstant: 22),

            saveProjectBtn.leadingAnchor.constraint(equalTo: addCaptureBtn.trailingAnchor, constant: 12),
            saveProjectBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            saveProjectBtn.widthAnchor.constraint(equalToConstant: 24),
            saveProjectBtn.heightAnchor.constraint(equalToConstant: 22),

            zoomButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            zoomButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            dragHandle.trailingAnchor.constraint(equalTo: zoomButton.leadingAnchor, constant: -10),
            dragHandle.centerYAnchor.constraint(equalTo: centerYAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: 40),
            dragHandle.heightAnchor.constraint(equalToConstant: 22),

            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        applyHUDColors()
        NotificationCenter.default.addObserver(
            self, selector: #selector(hudColorsChanged),
            name: .toolbarColorsDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func hudColorsChanged() {
        applyHUDColors()
    }

    private func applyHUDColors() {
        layer?.backgroundColor = ToolbarLayout.bgColor.cgColor
        bottomBorder.layer?.backgroundColor = (ToolbarLayout.usesLightPalette
            ? NSColor(white: 0.82, alpha: 1.0) : NSColor(white: 0.25, alpha: 1.0)).cgColor
        sizeLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.45)
        zoomButton.contentTintColor = ToolbarLayout.iconColor.withAlphaComponent(0.45)
        for button in toolButtons {
            button.contentTintColor = ToolbarLayout.iconColor.withAlphaComponent(0.85)
        }
        doneButton?.contentTintColor = ToolbarLayout.accentColor
        dragHandle.needsDisplay = true
    }

    required init?(coder: NSCoder) { fatalError() }

    private func makeButton(_ symbol: String, tooltip: String, action: Selector) -> NSButton {
        let btn = TopBarHoverButton()
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        btn.contentTintColor = ToolbarLayout.iconColor.withAlphaComponent(0.85)
        btn.quickTooltip = tooltip
        btn.setAccessibilityHelp(tooltip)
        btn.target = self
        btn.action = action
        return btn
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }

    func updateSizeLabel(width: Int, height: Int) {
        sizeLabel.stringValue = "\(width) × \(height)"
    }

    func updateZoom(_ magnification: CGFloat) {
        zoomButton.title = "\(Int(magnification * 100))% ▾"
    }

    // MARK: - Zoom dropdown

    @objc private func zoomButtonClicked() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let zoomIn = NSMenuItem(title: L("Zoom In"), action: #selector(zoomInAction), keyEquivalent: "+")
        zoomIn.keyEquivalentModifierMask = .command
        zoomIn.target = self
        menu.addItem(zoomIn)

        let zoomOut = NSMenuItem(title: L("Zoom Out"), action: #selector(zoomOutAction), keyEquivalent: "-")
        zoomOut.keyEquivalentModifierMask = .command
        zoomOut.target = self
        menu.addItem(zoomOut)

        menu.addItem(.separator())

        let fitCanvas = NSMenuItem(title: L("Fit Canvas"), action: #selector(fitCanvasAction), keyEquivalent: "1")
        fitCanvas.keyEquivalentModifierMask = .command
        fitCanvas.target = self
        menu.addItem(fitCanvas)

        menu.addItem(.separator())

        let presets: [(String, CGFloat, String)] = [
            ("50%", 0.5, ""),
            ("100%", 1.0, "0"),
            ("200%", 2.0, ""),
        ]
        let currentMag = overlayView?.enclosingScrollView?.magnification ?? 1.0
        for (title, mag, key) in presets {
            let item = NSMenuItem(title: title, action: #selector(zoomPresetAction(_:)), keyEquivalent: key)
            if !key.isEmpty { item.keyEquivalentModifierMask = .command }
            item.target = self
            item.tag = Int(mag * 100)
            if abs(currentMag - mag) < 0.01 { item.state = .on }
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: zoomButton.bounds.height + 2), in: zoomButton)
    }

    @objc func zoomInAction() {
        guard let sv = overlayView?.enclosingScrollView, let doc = sv.documentView else { return }
        let newMag = min(sv.maxMagnification, sv.magnification * 1.25)
        sv.setMagnification(newMag, centeredAt: NSPoint(x: doc.bounds.midX, y: doc.bounds.midY))
        updateZoom(newMag)
    }

    @objc func zoomOutAction() {
        guard let sv = overlayView?.enclosingScrollView, let doc = sv.documentView else { return }
        let newMag = max(sv.minMagnification, sv.magnification / 1.25)
        sv.setMagnification(newMag, centeredAt: NSPoint(x: doc.bounds.midX, y: doc.bounds.midY))
        updateZoom(newMag)
    }

    @objc func fitCanvasAction() {
        guard let sv = overlayView?.enclosingScrollView, let doc = sv.documentView else { return }
        let docUnscaledW = doc.frame.width / sv.magnification
        let docUnscaledH = doc.frame.height / sv.magnification
        guard docUnscaledW > 0, docUnscaledH > 0 else { return }
        let clipSize = sv.contentView.bounds.size
        let fitMag = min(clipSize.width / docUnscaledW, clipSize.height / docUnscaledH)
        let clamped = max(sv.minMagnification, min(sv.maxMagnification, fitMag))
        sv.magnification = clamped
        updateZoom(clamped)
    }

    /// Garabatapp: View › Actual Size.
    func zoomToActualSize() {
        guard let sv = overlayView?.enclosingScrollView else { return }
        sv.magnification = 1
        updateZoom(1)
    }

    @objc private func zoomPresetAction(_ sender: NSMenuItem) {
        let mag = CGFloat(sender.tag) / 100.0
        guard let sv = overlayView?.enclosingScrollView else { return }
        sv.magnification = mag
        updateZoom(mag)
    }

    // MARK: - Top bar actions

    /// Show a "Done" button for committing edits back to history.
    func showDoneButton() {
        guard doneButton == nil else { return }
        let btn = NSButton()
        btn.bezelStyle = .recessed
        btn.isBordered = true
        btn.title = L("Done")
        btn.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        btn.contentTintColor = ToolbarLayout.accentColor
        btn.target = self
        btn.action = #selector(doneClicked)
        btn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(btn)
        NSLayoutConstraint.activate([
            btn.trailingAnchor.constraint(equalTo: dragHandle.leadingAnchor, constant: -12),
            btn.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        doneButton = btn
    }

    /// Remove the Done button (used until the user makes an edit).
    func hideDoneButton() {
        doneButton?.removeFromSuperview()
        doneButton = nil
    }

    @objc private func doneClicked() { onDone?() }

    @objc private func cropClicked() {
        guard let ov = overlayView else { return }
        ov.currentTool = ov.currentTool == .crop ? .arrow : .crop
        ov.rebuildToolbarLayout()
        ov.needsDisplay = true
    }

    @objc private func flipHClicked() {
        guard let ov = overlayView else { return }
        EditorFlipAnimator.flip(ov, axis: .horizontal) { ov.flipImageHorizontally() }
    }
    @objc private func flipVClicked() {
        guard let ov = overlayView else { return }
        EditorFlipAnimator.flip(ov, axis: .vertical) { ov.flipImageVertically() }
    }
    @objc private func saveProjectClicked() {
        overlayView?.commitTextFieldIfNeeded()
        onSaveProject?()
    }

    @objc private func addCaptureClicked() { overlayView?.overlayDelegate?.overlayViewDidRequestAddCapture() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

/// Top bar icon button with the same hover highlight as the tool strips and a
/// custom tooltip that appears almost immediately (the system one waits ~1 s).
final class TopBarHoverButton: NSButton {
    var quickTooltip: String?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    private var showWork: DispatchWorkItem?
    private static let showDelay: TimeInterval = 0.1

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        scheduleTooltip()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        hideTooltip()
    }

    override func mouseDown(with event: NSEvent) {
        hideTooltip()
        super.mouseDown(with: event)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            hideTooltip()
            isHovered = false
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            ToolbarLayout.iconColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
        super.draw(dirtyRect)
    }

    private func scheduleTooltip() {
        showWork?.cancel()
        guard let text = quickTooltip, !text.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isHovered else { return }
            TopBarTooltipView.show(text, below: self)
        }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: work)
    }

    private func hideTooltip() {
        showWork?.cancel()
        showWork = nil
        TopBarTooltipView.hide(owner: self)
    }
}

/// Small floating label drawn in the window's content view, under the hovered button.
final class TopBarTooltipView: NSView {
    private static weak var current: TopBarTooltipView?
    private weak var owner: NSView?
    private var tooltip: ShortcutTooltip?

    static func show(_ text: String, below button: NSView) {
        guard let content = button.window?.contentView else { return }
        current?.removeFromSuperview()
        let tooltip = ShortcutTooltip(parsing: text)
        let w = tooltip.size.width
        let h = tooltip.size.height
        let btnRect = button.convert(button.bounds, to: content)
        var x = btnRect.midX - w / 2
        x = max(content.bounds.minX + 4, min(x, content.bounds.maxX - w - 4))
        // Below the button (AppKit is bottom-left origin).
        var y = btnRect.minY - h - 6
        if content.isFlipped { y = btnRect.maxY + 6 }
        let tip = TopBarTooltipView(frame: NSRect(x: x, y: y, width: w, height: h))
        tip.tooltip = tooltip
        tip.owner = button
        content.addSubview(tip, positioned: .above, relativeTo: nil)
        current = tip
    }

    static func hide(owner: NSView) {
        guard let tip = current, tip.owner === owner else { return }
        tip.removeFromSuperview()
        current = nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        tooltip?.draw(in: bounds, background: ToolbarLayout.bgColor, foreground: ToolbarLayout.iconColor)
    }
}

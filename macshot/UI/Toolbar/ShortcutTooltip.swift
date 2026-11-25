import Cocoa

/// Garabatapp: tooltip label with the shortcut drawn as keyboard keys
/// ("Rectangle  [R]") instead of "Rectangle (r)". Pure drawing, no app state,
/// so every custom tooltip (toolbar strips, editor top bar) looks the same.
struct ShortcutTooltip {
    let title: String
    /// One entry per key cap, already uppercased ("R", "⌘Z", "Space").
    let keys: [String]

    static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let keyFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    static let pad: CGFloat = 6
    private static let titleKeyGap: CGFloat = 7
    private static let keyGap: CGFloat = 4
    private static let keyPadX: CGFloat = 4

    init(title: String, shortcut: String?) {
        self.title = title
        self.keys = Self.keyCaps(from: shortcut)
    }

    /// Splits a localized "Title (⇧⌘S)" into its title and shortcut.
    init(parsing text: String) {
        if text.hasSuffix(")"), let open = text.range(of: " (", options: .backwards) {
            let inner = String(text[open.upperBound..<text.index(before: text.endIndex)])
            self.init(title: String(text[..<open.lowerBound]), shortcut: inner)
        } else {
            self.init(title: text, shortcut: nil)
        }
    }

    /// "r" → ["R"]; "⌘Z / ⇧⌘Z" → ["⌘Z", "⇧⌘Z"]; " " → ["Space"].
    static func keyCaps(from shortcut: String?) -> [String] {
        guard let shortcut, !shortcut.isEmpty else { return [] }
        if shortcut == " " { return [L("Space")] }
        return shortcut.components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.count <= 3 ? $0.uppercased() : $0 }
    }

    private var titleAttrs: [NSAttributedString.Key: Any] { [.font: Self.font] }
    private var keyAttrs: [NSAttributedString.Key: Any] { [.font: Self.keyFont] }

    private var titleSize: NSSize { (title as NSString).size(withAttributes: titleAttrs) }

    private func keyWidth(_ key: String) -> CGFloat {
        let w = ceil((key as NSString).size(withAttributes: keyAttrs).width) + Self.keyPadX * 2
        return max(w, keyHeight)
    }

    private var keyHeight: CGFloat { ceil(Self.keyFont.ascender - Self.keyFont.descender) + 3 }

    /// Size of the whole tooltip, background padding included.
    var size: NSSize {
        let t = titleSize
        var w = ceil(t.width)
        if !keys.isEmpty {
            w += Self.titleKeyGap
            w += keys.map(keyWidth).reduce(0, +) + Self.keyGap * CGFloat(keys.count - 1)
        }
        let h = max(ceil(t.height), keyHeight + 2)
        return NSSize(width: w + Self.pad * 2, height: h + Self.pad)
    }

    /// Draws background, title and key caps filling `rect`.
    func draw(in rect: NSRect, background: NSColor, foreground: NSColor) {
        background.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()

        let t = titleSize
        var attrs = titleAttrs
        attrs[.foregroundColor] = foreground
        (title as NSString).draw(
            at: NSPoint(x: rect.minX + Self.pad, y: rect.midY - t.height / 2),
            withAttributes: attrs)

        guard !keys.isEmpty else { return }
        var x = rect.minX + Self.pad + ceil(t.width) + Self.titleKeyGap
        let h = keyHeight
        let y = (rect.midY - h / 2).rounded()
        var kAttrs = keyAttrs
        kAttrs[.foregroundColor] = foreground
        for key in keys {
            let w = keyWidth(key)
            let cap = NSRect(x: x, y: y, width: w, height: h)
            // Darker lip at the bottom, then the key face: reads as a physical key.
            foreground.withAlphaComponent(0.28).setFill()
            NSBezierPath(roundedRect: cap, xRadius: 3, yRadius: 3).fill()
            let face = NSRect(x: cap.minX, y: cap.minY + 1.5, width: cap.width, height: cap.height - 1.5)
            let facePath = NSBezierPath(roundedRect: face, xRadius: 3, yRadius: 3)
            background.setFill()
            facePath.fill()
            foreground.withAlphaComponent(0.16).setFill()
            facePath.fill()
            foreground.withAlphaComponent(0.30).setStroke()
            facePath.lineWidth = 0.5
            facePath.stroke()
            let ks = (key as NSString).size(withAttributes: kAttrs)
            (key as NSString).draw(
                at: NSPoint(x: face.midX - ks.width / 2, y: face.midY - ks.height / 2),
                withAttributes: kAttrs)
            x += w + Self.keyGap
        }
    }
}

#!/bin/bash
# Renders ShortcutTooltip samples (dark + light toolbar colors) to a PNG so the
# key-cap look can be checked without driving the app. Usage:
#   scripts/render-shortcut-tooltips.sh [output.png]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/garabatapp-shortcut-tooltips.png}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/main.swift" <<'SWIFT'
import Cocoa
func L(_ key: String) -> String { key }
let samples: [ShortcutTooltip] = [
    ShortcutTooltip(title: "Rectangle", shortcut: "r"),
    ShortcutTooltip(title: "Undo", shortcut: "⌘Z"),
    ShortcutTooltip(title: "Redo", shortcut: "⇧⌘Z / ⌘Y"),
    ShortcutTooltip(title: "Move", shortcut: " "),
    ShortcutTooltip(parsing: "Save as Editable Project (⇧⌘S)"),
    ShortcutTooltip(title: "Flip Horizontal", shortcut: nil),
]
let themes: [(NSColor, NSColor)] = [
    (NSColor(white: 0.13, alpha: 1), .white),
    (NSColor(white: 0.96, alpha: 1), NSColor(white: 0.12, alpha: 1)),
]
let scale: CGFloat = 2
let colW: CGFloat = 300, rowH: CGFloat = 34
let size = NSSize(width: colW * CGFloat(themes.count), height: rowH * CGFloat(samples.count) + 12)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
    pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
for (c, (bg, fg)) in themes.enumerated() {
    let page = NSRect(x: CGFloat(c) * colW, y: 0, width: colW, height: size.height)
    (c == 0 ? NSColor(white: 0.3, alpha: 1) : NSColor(white: 0.8, alpha: 1)).setFill()
    page.fill()
    for (i, t) in samples.enumerated() {
        let s = t.size
        let r = NSRect(x: page.minX + 12, y: size.height - 12 - rowH * CGFloat(i + 1) + (rowH - s.height) / 2,
                       width: s.width, height: s.height)
        t.draw(in: r, background: bg, foreground: fg)
    }
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT
swiftc -O -o "$WORK/render" macshot/UI/Toolbar/ShortcutTooltip.swift "$WORK/main.swift"
"$WORK/render" "$OUT"
echo "$OUT"

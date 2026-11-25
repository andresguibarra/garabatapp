import Cocoa

/// A two-headed resize cursor pointing along any angle, like the system's
/// column/row resize cursors but turned to match what is being dragged: a
/// line's or arrow's end, or a handle of a rotated shape.
enum ResizeCursor {

    /// Angles are bucketed so hovering doesn't build a new cursor per pixel.
    private static let step: CGFloat = .pi / 90  // 2°
    @MainActor private static var cache: [Int: NSCursor] = [:]

    /// The cursor for a drag along `angle` (radians, counter-clockwise from +x,
    /// AppKit's bottom-left coordinates). A two-headed arrow is the same both
    /// ways, so angles are taken modulo π.
    @MainActor static func cursor(angle: CGFloat) -> NSCursor {
        let bucket = bucketIndex(for: angle)
        if let cached = cache[bucket] { return cached }
        let cursor = make(angle: CGFloat(bucket) * step)
        cache[bucket] = cursor
        return cursor
    }

    static func bucketIndex(for angle: CGFloat) -> Int {
        guard angle.isFinite else { return 0 }
        var a = angle.truncatingRemainder(dividingBy: .pi)
        if a < 0 { a += .pi }
        let count = Int((.pi / step).rounded())
        return Int((a / step).rounded()) % count
    }

    /// Direction of a line-like annotation's end: from the neighbouring point
    /// (next anchor, bend, or the other end) out to that end.
    static func endpointAngle(of annotation: Annotation, atStart: Bool) -> CGFloat? {
        let pts = annotation.waypoints
        guard pts.count >= 2 else { return nil }
        let end = atStart ? pts[0] : pts[pts.count - 1]
        let neighbour: NSPoint
        if pts.count > 2 {
            neighbour = atStart ? pts[1] : pts[pts.count - 2]
        } else {
            neighbour = annotation.controlPoint ?? (atStart ? pts[1] : pts[0])
        }
        let dx = end.x - neighbour.x, dy = end.y - neighbour.y
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return nil }
        return atan2(dy, dx)
    }

    @MainActor private static func make(angle: CGFloat) -> NSCursor {
        let size: CGFloat = 26
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: size / 2, y: size / 2)
            ctx.rotate(by: angle)
            // Shaft plus two heads, drawn as one outline so it reads on any background.
            let half: CGFloat = 10, head: CGFloat = 5.5, wing: CGFloat = 4.5, shaft: CGFloat = 1.2
            let arrow = CGMutablePath()
            arrow.move(to: CGPoint(x: -half, y: 0))
            arrow.addLine(to: CGPoint(x: -half + head, y: wing))
            arrow.addLine(to: CGPoint(x: -half + head, y: shaft))
            arrow.addLine(to: CGPoint(x: half - head, y: shaft))
            arrow.addLine(to: CGPoint(x: half - head, y: wing))
            arrow.addLine(to: CGPoint(x: half, y: 0))
            arrow.addLine(to: CGPoint(x: half - head, y: -wing))
            arrow.addLine(to: CGPoint(x: half - head, y: -shaft))
            arrow.addLine(to: CGPoint(x: -half + head, y: -shaft))
            arrow.addLine(to: CGPoint(x: -half + head, y: -wing))
            arrow.closeSubpath()
            ctx.setLineJoin(.round)
            ctx.addPath(arrow)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(2.5)
            ctx.strokePath()
            ctx.addPath(arrow)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }
}

import Cocoa

/// Arrows attached to shapes, like connectors in a whiteboard app.
///
/// An arrow end can be attached to a text box, rectangle, ellipse or number
/// (`Annotation.connectedStartID` / `connectedEndID` name the shape's
/// `connectorID`). Attached ends are derived, not stored: `resolve` recomputes
/// them from the shapes' current geometry, so moving, resizing, rotating,
/// undoing or reloading a shape carries its arrows along without any extra
/// undo bookkeeping. Each attached end sits on the shape's outline, on the line
/// toward whatever the arrow points at (the other shape's center, the bend
/// point, or the free end), where the arrow's cap or tip just touches the
/// shape's painted edge: the same path the shape draws, plus half its stroke
/// (`Silhouette`), so every shape type, corner radius and outline is handled alike.
///
/// Pure geometry: no view state, so it is unit tested directly.
enum ArrowConnectors {

    /// Extra space between an attached arrow end and the shape's painted edge.
    /// 0: the arrow's cap or tip just touches the outside of the shape's paint.
    static let gap: CGFloat = 0

    /// One round dab of the arrow's paint near an end, in the end's own frame:
    /// `back` along the arrow away from its tip, `side` across it, `radius` of paint.
    struct Dab { let back: CGFloat; let side: CGFloat; let radius: CGFloat }

    /// The paint an arrow puts down around one end, as dabs: the tip, the head's
    /// two edges back to its wings, a tail circle or round cap. Mirrors
    /// `Annotation.drawArrow`, `drawThickArrow` and `drawSketchyArrow`, so a
    /// head that meets a long edge at a shallow angle keeps its wings off it too.
    /// `length` is the arrow's length, which sizes its head.
    static func endPaint(of arrow: Annotation, atStart: Bool, length: CGFloat) -> [Dab] {
        let sw = arrow.strokeWidth
        let ring: CGFloat = arrow.outlineColor != nil ? 3 : 0
        // The drawn path runs end → start when reversed: the head is on its last point.
        let isHeadEnd = atStart == arrow.arrowReversed
        func head(length headLen: CGFloat, halfWidth: CGFloat, radius: CGFloat, nose: CGFloat = 0) -> [Dab] {
            var dabs: [Dab] = []
            for k in 0...12 {
                let f = CGFloat(k) / 12
                let back = -nose + (headLen + nose) * f
                dabs.append(Dab(back: back, side: halfWidth * f, radius: radius))
                dabs.append(Dab(back: back, side: -halfWidth * f, radius: radius))
            }
            return dabs
        }
        let arrowLen = min(max(14, sw * 5), max(4, length * 0.45))
        let wingBack = arrowLen * cos(CGFloat.pi / 6), wingSide = arrowLen * sin(CGFloat.pi / 6)
        switch arrow.arrowStyle {
        case .single, .tail, .double:
            if isHeadEnd || arrow.arrowStyle == .double {
                return head(length: wingBack, halfWidth: wingSide, radius: ring)
            }
            let reach = arrow.arrowStyle == .tail ? max(4, sw * 2) : sw / 2
            return [Dab(back: 0, side: 0, radius: reach + ring)]
        case .open:
            if isHeadEnd { return head(length: wingBack, halfWidth: wingSide, radius: sw / 2 + ring) }
            return [Dab(back: 0, side: 0, radius: sw / 2 + ring)]
        case .thick:
            let shaftHalf = max(4, sw * 1.5)
            let fit = min(1, length / max(1, shaftHalf * 2 * 2 * 1.5))
            if isHeadEnd {
                let headHalf = shaftHalf * 2 * fit
                return head(length: min(length * 0.35, headHalf * 1.8), halfWidth: headHalf, radius: ring)
            }
            let tailHalf = max(2, sw * 0.5) * fit
            return (0...4).flatMap { k -> [Dab] in
                let side = tailHalf * CGFloat(k) / 4
                return [Dab(back: 0, side: side, radius: ring), Dab(back: 0, side: -side, radius: ring)]
            }
        case .sketchy:
            let width = max(1.2, sw)
            if isHeadEnd {
                let headLen = min(max(width * 4.3, 13), length * 0.27)
                // Uneven legs: up to 1.18x long, 1.25x spread, nose up to 0.14x ahead.
                return head(length: headLen * 1.18, halfWidth: max(width * 2.6, 8) * 1.25,
                            radius: width / 2 + ring, nose: headLen * 0.14)
            }
            return [Dab(back: 0, side: 0, radius: width / 2 + ring)]
        }
    }

    /// Where an arrow end attached to `shape` goes: on the ray from the shape's
    /// center toward `aim` (what the arrow points at), as close as it can be
    /// while none of the arrow's paint there touches the shape's paint.
    static func attachPoint(of arrow: Annotation, atStart: Bool, on shape: Annotation,
                            toward aim: NSPoint) -> NSPoint? {
        guard let silhouette = silhouette(of: shape) else { return nil }
        let c = silhouette.center
        var ux = aim.x - c.x, uy = aim.y - c.y
        let distance = hypot(ux, uy)
        if distance < 0.0001 { ux = 1; uy = 0 } else { ux /= distance; uy /= distance }
        let dabs = endPaint(of: arrow, atStart: atStart, length: max(distance, 1))
        // The arrow runs from its tip out toward the aim: `back` is +u, `side` is the normal.
        var regions: [CGFloat: (CGPoint) -> Bool] = [:]
        for d in dabs where regions[d.radius + gap] == nil {
            regions[d.radius + gap] = silhouette.region(clearance: d.radius + gap)
        }
        func clear(_ t: CGFloat) -> Bool {
            for d in dabs {
                let p = CGPoint(x: c.x + ux * (t + d.back) - uy * d.side,
                                y: c.y + uy * (t + d.back) + ux * d.side)
                if regions[d.radius + gap]!(p) { return false }
            }
            return true
        }
        let box = silhouette.path.boundingBoxOfPath
        let maxDab = dabs.map { abs($0.back) + abs($0.side) + $0.radius }.max() ?? 0
        var hi = hypot(box.width, box.height) + silhouette.stroke * 2 + maxDab * 2 + 2
        while !clear(hi) { hi *= 2 }
        var lo: CGFloat = 0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if clear(mid) { hi = mid } else { lo = mid }
        }
        return NSPoint(x: c.x + ux * hi, y: c.y + uy * hi)
    }

    /// Shapes an arrow end can attach to.
    static func isConnectable(_ annotation: Annotation) -> Bool {
        switch annotation.tool {
        case .rectangle, .filledRectangle, .ellipse, .number:
            return true
        case .text:
            return annotation.textDrawRect.width > 0 && annotation.textDrawRect.height > 0
        default:
            return false
        }
    }

    /// What a shape actually paints, for every shape the same way: the path its
    /// drawing code fills or strokes (rotation applied) and the width of the
    /// stroke centered on that path (0 when it is only filled). The painted area
    /// is the inside of `path` plus `stroke / 2` on each side of it. Mirrors
    /// `Annotation.drawRectangle`, `drawEllipse`, `drawNumber` and `drawText`.
    struct Silhouette {
        let path: CGPath
        let stroke: CGFloat
        let center: NSPoint
        var join: CGLineJoin = .miter

        /// The painted area's own boundary: the stroke's outer contour (with the
        /// shape's real join, so sharp miter corners count), or the filled path.
        private var paintedEdge: CGPath {
            stroke > 0
                ? path.copy(strokingWithWidth: stroke, lineCap: .butt, lineJoin: join, miterLimit: 10)
                : path
        }

        /// Membership test for the painted area grown by `clearance`.
        func region(clearance: CGFloat) -> (CGPoint) -> Bool {
            let edge = paintedEdge
            let fill = path
            let grown = clearance > 0
                ? edge.copy(strokingWithWidth: 2 * clearance, lineCap: .round, lineJoin: .round, miterLimit: 10)
                : nil
            let hasStroke = stroke > 0
            return { p in
                fill.contains(p) || (hasStroke && edge.contains(p, using: .winding)) || (grown?.contains(p) ?? false)
            }
        }

        /// The painted area grown by `clearance` on every side.
        func contains(_ point: NSPoint, clearance: CGFloat) -> Bool {
            region(clearance: clearance)(point)
        }

        /// Where the ray from the center toward `target` leaves the painted area
        /// grown by `clearance`: the spot an arrow end of that reach just touches.
        func exitPoint(toward target: NSPoint, clearance: CGFloat) -> NSPoint {
            var dx = target.x - center.x, dy = target.y - center.y
            let len = hypot(dx, dy)
            if len < 0.0001 { dx = 1; dy = 0 } else { dx /= len; dy /= len }
            let inside = region(clearance: clearance)
            func at(_ t: CGFloat) -> CGPoint { CGPoint(x: center.x + dx * t, y: center.y + dy * t) }
            let box = path.boundingBoxOfPath
            var hi = hypot(box.width, box.height) + stroke * 2 + 2 * clearance + 2
            while inside(at(hi)) { hi *= 2 }
            // Painted areas here are convex, so there is one crossing.
            var lo: CGFloat = 0
            for _ in 0..<40 {
                let mid = (lo + hi) / 2
                if inside(at(mid)) { lo = mid } else { hi = mid }
            }
            return at(hi)
        }
    }

    static func silhouette(of a: Annotation) -> Silhouette? {
        guard isConnectable(a) else { return nil }
        let ring: CGFloat = a.outlineColor != nil ? 6 : 0  // outline strokes are strokeWidth + 6 wide
        var path: CGPath
        var stroke: CGFloat
        var center: NSPoint
        var join: CGLineJoin = .miter
        switch a.tool {
        case .number:
            let radius = 8 + a.strokeWidth * 3 + (a.outlineColor != nil ? 3 : 0)
            center = a.startPoint
            path = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                            width: radius * 2, height: radius * 2), transform: nil)
            stroke = 0
        case .text:
            let boxed = a.textBgColor != nil || a.textOutlineColor != nil
            let rect = boxed ? a.textDrawRect.insetBy(dx: -4, dy: -4) : a.textDrawRect
            path = roundedRect(rect, radius: boxed ? 4 : 0)
            stroke = a.textOutlineColor != nil ? 2 : 0
            center = NSPoint(x: rect.midX, y: rect.midY)
        case .ellipse:
            let rect = a.boundingRect
            path = CGPath(ellipseIn: rect, transform: nil)
            stroke = a.rectFillStyle == .fill ? (ring > 0 ? a.strokeWidth + ring : 0) : a.strokeWidth + ring
            center = NSPoint(x: rect.midX, y: rect.midY)
        default:  // rectangle, filledRectangle
            let rect = a.boundingRect
            let radius = a.rectCornerRadius > 0 ? a.rectCornerRadius
                : (a.isRounded ? min(rect.width, rect.height) * 0.2 : 0)
            path = roundedRect(rect, radius: radius)
            join = radius > 0 ? .round : .miter
            let filledOnly = a.tool == .filledRectangle || a.rectFillStyle == .fill
            stroke = filledOnly ? (ring > 0 ? a.strokeWidth + ring : 0) : a.strokeWidth + ring
            center = NSPoint(x: rect.midX, y: rect.midY)
        }
        if a.rotation != 0 && a.supportsRotation {
            // Same pivot as Annotation.draw(in:).
            let pivot = NSPoint(x: a.boundingRect.midX, y: a.boundingRect.midY)
            var t = CGAffineTransform(translationX: pivot.x, y: pivot.y)
                .rotated(by: a.rotation)
                .translatedBy(x: -pivot.x, y: -pivot.y)
            path = path.copy(using: &t) ?? path
            center = center.applying(t)
        }
        return Silhouette(path: path, stroke: stroke, center: center, join: join)
    }

    private static func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let r = max(0, min(radius, rect.width / 2, rect.height / 2))
        guard rect.width > 0, rect.height > 0 else { return CGPath(rect: rect, transform: nil) }
        return r > 0 ? CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
                     : CGPath(rect: rect, transform: nil)
    }

    static func center(of annotation: Annotation) -> NSPoint? {
        silhouette(of: annotation)?.center
    }

    /// Where the ray from the shape's center toward `target` leaves its painted
    /// area grown by `gap`.
    static func borderPoint(of annotation: Annotation, toward target: NSPoint, gap: CGFloat = gap) -> NSPoint? {
        silhouette(of: annotation)?.exitPoint(toward: target, clearance: gap)
    }

    /// The painted edge in the pointer's direction and how far the pointer is from it.
    static func nearestBorder(of annotation: Annotation, to point: NSPoint) -> (point: NSPoint, distance: CGFloat)? {
        guard let p = borderPoint(of: annotation, toward: point, gap: 0) else { return nil }
        return (p, hypot(p.x - point.x, p.y - point.y))
    }

    /// Whether `point` is on the shape's painted area (grown by `margin`).
    static func contains(_ annotation: Annotation, point: NSPoint, margin: CGFloat = 0) -> Bool {
        silhouette(of: annotation)?.contains(point, clearance: margin) ?? false
    }

    /// Topmost connectable shape whose border is within `threshold` of `point`.
    static func hoverTarget(in annotations: [Annotation], at point: NSPoint, threshold: CGFloat,
                            excluding: Annotation? = nil) -> (shape: Annotation, point: NSPoint)? {
        for shape in annotations.reversed() where shape !== excluding {
            guard let hit = nearestBorder(of: shape, to: point), hit.distance <= threshold else { continue }
            return (shape, hit.point)
        }
        return nil
    }

    /// Topmost connectable shape containing `point`, for dropping an arrow end on it.
    static func dropTarget(in annotations: [Annotation], at point: NSPoint, margin: CGFloat,
                           excluding: Set<UUID> = []) -> Annotation? {
        annotations.reversed().first {
            !excluding.contains($0.connectorID) && contains($0, point: point, margin: margin)
        }
    }

    /// Recompute every attached arrow end from its shape. Returns whether anything moved.
    @discardableResult
    static func resolve(_ annotations: [Annotation]) -> Bool {
        guard annotations.contains(where: { $0.tool == .arrow && $0.hasConnector }) else { return false }
        var shapes: [UUID: Annotation] = [:]
        for a in annotations where isConnectable(a) && shapes[a.connectorID] == nil {
            shapes[a.connectorID] = a
        }
        var changed = false
        for arrow in annotations where arrow.tool == .arrow && arrow.hasConnector {
            let from = arrow.connectedStartID.flatMap { shapes[$0] }
            let to = arrow.connectedEndID.flatMap { shapes[$0] }
            if from == nil && to == nil { continue }  // shapes deleted: keep the last position
            if update(arrow, from: from, to: to) { changed = true }
        }
        return changed
    }

    /// Place the attached ends of one arrow. Returns whether it moved.
    @discardableResult
    static func update(_ arrow: Annotation, from: Annotation?, to: Annotation?) -> Bool {
        let anchors = arrow.anchorPoints ?? []
        let multi = anchors.count >= 3
        // What each end points at: the other shape, else the nearest bend, else the other end.
        let startAim = to.flatMap { center(of: $0) }
            ?? (multi ? anchors[1] : arrow.controlPoint ?? arrow.endPoint)
        let endAim = from.flatMap { center(of: $0) }
            ?? (multi ? anchors[anchors.count - 2] : arrow.controlPoint ?? arrow.startPoint)
        let newStart = from.flatMap {
            attachPoint(of: arrow, atStart: true, on: $0, toward: startAim)
        } ?? arrow.startPoint
        let newEnd = to.flatMap {
            attachPoint(of: arrow, atStart: false, on: $0, toward: endAim)
        } ?? arrow.endPoint

        func moved(_ a: NSPoint, _ b: NSPoint) -> Bool { abs(a.x - b.x) > 0.01 || abs(a.y - b.y) > 0.01 }
        guard moved(newStart, arrow.startPoint) || moved(newEnd, arrow.endPoint) else { return false }

        // Bend points travel with the average of the two ends so a curve keeps its shape.
        let shift = NSPoint(
            x: ((newStart.x - arrow.startPoint.x) + (newEnd.x - arrow.endPoint.x)) / 2,
            y: ((newStart.y - arrow.startPoint.y) + (newEnd.y - arrow.endPoint.y)) / 2)
        if let cp = arrow.controlPoint {
            arrow.controlPoint = NSPoint(x: cp.x + shift.x, y: cp.y + shift.y)
        }
        if anchors.count >= 2 {
            var next = anchors
            for i in 1..<(next.count - 1) {
                next[i] = NSPoint(x: next[i].x + shift.x, y: next[i].y + shift.y)
            }
            next[0] = newStart
            next[next.count - 1] = newEnd
            arrow.anchorPoints = next
        }
        arrow.startPoint = newStart
        arrow.endPoint = newEnd
        return true
    }

    /// Give copied annotations fresh identities. Attachments between copies follow
    /// the copies; attachments to shapes outside the copied set are dropped so a
    /// pasted or duplicated arrow stays where it was put instead of snapping back
    /// onto the original shape.
    static func reassignIdentities(_ copies: [Annotation]) {
        var map: [UUID: UUID] = [:]
        for c in copies {
            let fresh = UUID()
            map[c.connectorID] = fresh
            c.connectorID = fresh
        }
        for c in copies {
            c.connectedStartID = c.connectedStartID.flatMap { map[$0] }
            c.connectedEndID = c.connectedEndID.flatMap { map[$0] }
        }
    }
}

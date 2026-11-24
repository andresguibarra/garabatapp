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
/// point, or the free end), far enough out that the arrow's cap or head and the
/// shape's stroke don't overlap (`clearance`).
///
/// Pure geometry: no view state, so it is unit tested directly.
enum ArrowConnectors {

    /// Visible space between an attached arrow end and the shape's drawn edge.
    static let gap: CGFloat = 3

    /// How far a shape's paint reaches outside its geometric outline: half its
    /// stroke (strokes are centered on the outline), its outline ring, the text
    /// background pill.
    static func edgeExtent(of shape: Annotation) -> CGFloat {
        let ring: CGFloat = shape.outlineColor != nil ? 3 : 0
        switch shape.tool {
        case .rectangle, .ellipse:
            let stroke = shape.rectFillStyle == .fill ? 0 : shape.strokeWidth / 2
            return stroke + ring
        case .filledRectangle, .number:
            return ring
        case .text:
            return shape.textBgColor != nil ? 4 : 0
        default:
            return 0
        }
    }

    /// How far the arrow's paint reaches past its start or end point: the round
    /// cap or stroked head tip, the tail circle, the outline ring.
    static func endExtent(of arrow: Annotation, atStart: Bool) -> CGFloat {
        let ring: CGFloat = arrow.outlineColor != nil ? 3 : 0
        // The tail circle sits on the drawn first point (the end when reversed).
        let isTail = arrow.arrowStyle == .tail && atStart != arrow.arrowReversed
        let reach = isTail ? max(4, arrow.strokeWidth * 2) : arrow.strokeWidth / 2
        return reach + ring
    }

    /// Distance from a shape's outline to where an attached arrow end goes, so the
    /// two drawings meet with a small clean gap instead of overlapping.
    static func clearance(arrow: Annotation, atStart: Bool, shape: Annotation) -> CGFloat {
        edgeExtent(of: shape) + endExtent(of: arrow, atStart: atStart) + gap
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

    /// The outline an attached end follows.
    enum Outline: Equatable {
        case rect(NSRect, rotation: CGFloat)
        case ellipse(NSRect, rotation: CGFloat)
        case circle(center: NSPoint, radius: CGFloat)

        var center: NSPoint {
            switch self {
            case .rect(let r, _), .ellipse(let r, _): return NSPoint(x: r.midX, y: r.midY)
            case .circle(let c, _): return c
            }
        }
    }

    static func outline(of annotation: Annotation) -> Outline? {
        guard isConnectable(annotation) else { return nil }
        switch annotation.tool {
        case .number:
            return .circle(center: annotation.startPoint, radius: 8 + annotation.strokeWidth * 3)
        case .ellipse:
            return .ellipse(annotation.boundingRect, rotation: annotation.rotation)
        case .text:
            return .rect(annotation.textDrawRect, rotation: annotation.rotation)
        default:
            return .rect(annotation.boundingRect, rotation: annotation.rotation)
        }
    }

    static func center(of annotation: Annotation) -> NSPoint? {
        outline(of: annotation)?.center
    }

    /// Where the ray from the center toward `target` crosses the outline grown by `gap`.
    static func borderPoint(of outline: Outline, toward target: NSPoint, gap: CGFloat = gap) -> NSPoint {
        let c = outline.center
        var dx = target.x - c.x
        var dy = target.y - c.y
        let len = hypot(dx, dy)
        if len < 0.0001 { dx = 1; dy = 0 } else { dx /= len; dy /= len }

        switch outline {
        case .circle(_, let radius):
            let t = radius + gap
            return NSPoint(x: c.x + dx * t, y: c.y + dy * t)
        case .rect(let r, let rotation), .ellipse(let r, let rotation):
            // Work in the shape's unrotated frame.
            let cosR = cos(-rotation), sinR = sin(-rotation)
            let ux = dx * cosR - dy * sinR
            let uy = dx * sinR + dy * cosR
            // Grow the shape by `gap` and meet its edge, so the gap is measured
            // across the border (perpendicular), not along a slanted arrow,
            // which would leave too little room at an angle.
            let hw = max(r.width / 2 + gap, 0.0001), hh = max(r.height / 2 + gap, 0.0001)
            let t: CGFloat
            if case .ellipse = outline {
                t = 1 / ((ux * ux) / (hw * hw) + (uy * uy) / (hh * hh)).squareRoot()
            } else {
                let tx = abs(ux) > 0.0001 ? hw / abs(ux) : .greatestFiniteMagnitude
                let ty = abs(uy) > 0.0001 ? hh / abs(uy) : .greatestFiniteMagnitude
                t = min(tx, ty)
            }
            return NSPoint(x: c.x + dx * t, y: c.y + dy * t)
        }
    }

    static func borderPoint(of annotation: Annotation, toward target: NSPoint, gap: CGFloat = gap) -> NSPoint? {
        outline(of: annotation).map { borderPoint(of: $0, toward: target, gap: gap) }
    }

    /// The outline point under the pointer's direction and how far the pointer is from it.
    static func nearestBorder(of annotation: Annotation, to point: NSPoint) -> (point: NSPoint, distance: CGFloat)? {
        guard let o = outline(of: annotation) else { return nil }
        let p = borderPoint(of: o, toward: point, gap: 0)
        return (p, hypot(p.x - point.x, p.y - point.y))
    }

    /// Whether `point` is inside the shape (grown by `margin`).
    static func contains(_ annotation: Annotation, point: NSPoint, margin: CGFloat = 0) -> Bool {
        guard let o = outline(of: annotation) else { return false }
        let c = o.center
        let d = hypot(point.x - c.x, point.y - c.y)
        if d < 0.0001 { return true }
        let edge = borderPoint(of: o, toward: point, gap: margin)
        return d <= hypot(edge.x - c.x, edge.y - c.y)
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
            borderPoint(of: $0, toward: startAim, gap: clearance(arrow: arrow, atStart: true, shape: $0))
        } ?? arrow.startPoint
        let newEnd = to.flatMap {
            borderPoint(of: $0, toward: endAim, gap: clearance(arrow: arrow, atStart: false, shape: $0))
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

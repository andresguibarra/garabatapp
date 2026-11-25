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

    /// Where an arrow end attached to `shape` goes, given `aim`, the point the
    /// arrow comes from (the other end, its bend, or the other shape's tip).
    static func attachPoint(of arrow: Annotation, atStart: Bool, on shape: Annotation,
                            toward aim: NSPoint) -> NSPoint? {
        attach(arrow, atStart: atStart, on: shape, toward: aim)?.point
    }

    /// `onCenterLine`: the end sits on the line from the shape's center to the aim.
    static func attach(_ arrow: Annotation, atStart: Bool, on shape: Annotation,
                       toward aim: NSPoint) -> (point: NSPoint, onCenterLine: Bool)? {
        guard let silhouette = silhouette(of: shape) else { return nil }
        let c = silhouette.center
        var ux = aim.x - c.x, uy = aim.y - c.y
        let distance = hypot(ux, uy)
        if distance < 0.0001 { ux = 1; uy = 0 } else { ux /= distance; uy /= distance }
        let dabs = endPaint(of: arrow, atStart: atStart, length: max(distance, 1))
        // Along the center line the arrow runs from its tip out toward the aim:
        // `back` is +u, `side` is the normal.
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
        let tipReach = dabs.filter { $0.side == 0 }.map { $0.radius - $0.back }.max() ?? 0

        // 1. Pointing at the center, with the tip (cap, tail) just touching the
        //    shape's paint, when nothing else of the arrow touches it there.
        let onLine = silhouette.exitPoint(toward: aim, clearance: tipReach + gap)
        let t0 = hypot(onLine.x - c.x, onLine.y - c.y)
        if distance > t0, clear(t0) {
            return (onLine, true)
        }
        // 1b. Almost: something beside the tip (a thick arrow's flat tail, a wing)
        //     grazes the edge. Back off along the center line if a point is enough.
        //     A flat end (a thick arrow's tail) has nothing behind its tip, so
        //     walking out until one of its corners touches never leaves it floating.
        let flatEnd = dabs.allSatisfy { $0.back <= 0 }
        if distance > t0 {
            var lo = t0, hi = t0 + 1
            if flatEnd { while !clear(hi) && hi < distance { hi += 1 } }
            if clear(hi) {
                for _ in 0..<30 {
                    let mid = (lo + hi) / 2
                    if clear(mid) { hi = mid } else { lo = mid }
                }
                return (NSPoint(x: c.x + ux * hi, y: c.y + uy * hi), true)
            }
        }
        // 2. Too shallow for that (a wing would land on the edge first and the
        //    tip would float): the spot of the paint nearest to the aim. The tip
        //    touches there and, the shape being convex, the wings never do.
        if let p = silhouette.nearestPoint(to: aim, clearance: tipReach + gap) {
            return (p, false)
        }
        // 3. The aim is on or inside the shape (a bend dragged over it): walk out
        //    along the center line until none of the arrow's paint touches.
        let box = silhouette.path.boundingBoxOfPath
        let maxDab = dabs.map { abs($0.back) + abs($0.side) + $0.radius }.max() ?? 0
        var hi = hypot(box.width, box.height) + silhouette.stroke * 2 + maxDab * 2 + 2
        while !clear(hi) { hi *= 2 }
        var lo: CGFloat = 0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if clear(mid) { hi = mid } else { lo = mid }
        }
        return (NSPoint(x: c.x + ux * hi, y: c.y + uy * hi), true)
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

        /// The same painted area described exactly, for nearest-point queries:
        /// a convex base shape (unrotated) plus `offset` of paint around it.
        enum Base { case roundedRect(CGRect, CGFloat), ellipse(CGRect) }
        var base: Base = .roundedRect(.zero, 0)
        var offset: CGFloat = 0
        var rotation: CGFloat = 0
        var pivot: NSPoint = .zero

        private func toLocal(_ p: NSPoint) -> NSPoint {
            guard rotation != 0 else { return p }
            let dx = p.x - pivot.x, dy = p.y - pivot.y
            let c = cos(-rotation), s = sin(-rotation)
            return NSPoint(x: pivot.x + dx * c - dy * s, y: pivot.y + dx * s + dy * c)
        }

        private func toWorld(_ p: NSPoint) -> NSPoint {
            guard rotation != 0 else { return p }
            let dx = p.x - pivot.x, dy = p.y - pivot.y
            let c = cos(rotation), s = sin(rotation)
            return NSPoint(x: pivot.x + dx * c - dy * s, y: pivot.y + dx * s + dy * c)
        }

        /// The point of the base shape closest to `q` (local coordinates), or nil
        /// when `q` is inside it.
        private func nearestOnBase(_ q: NSPoint) -> NSPoint? {
            switch base {
            case .roundedRect(let rect, let radius):
                let r = max(0, min(radius, rect.width / 2, rect.height / 2))
                let inner = rect.insetBy(dx: r, dy: r)
                let k = NSPoint(x: min(max(q.x, inner.minX), inner.maxX),
                                y: min(max(q.y, inner.minY), inner.maxY))
                let d = hypot(q.x - k.x, q.y - k.y)
                guard d > r + 1e-9 else { return nil }
                return NSPoint(x: k.x + (q.x - k.x) / d * r, y: k.y + (q.y - k.y) / d * r)
            case .ellipse(let rect):
                let a = rect.width / 2, b = rect.height / 2
                guard a > 0, b > 0 else { return NSPoint(x: rect.midX, y: rect.midY) }
                let x = abs(q.x - rect.midX), y = abs(q.y - rect.midY)
                guard (x / a) * (x / a) + (y / b) * (y / b) > 1 else { return nil }
                // Distance to an outside point is unimodal over a quadrant of the ellipse.
                func f(_ t: CGFloat) -> CGFloat {
                    let ex = a * cos(t) - x, ey = b * sin(t) - y
                    return ex * ex + ey * ey
                }
                var lo: CGFloat = 0, hi: CGFloat = .pi / 2
                let g: CGFloat = (sqrt(5) - 1) / 2
                for _ in 0..<60 {
                    let m1 = hi - (hi - lo) * g, m2 = lo + (hi - lo) * g
                    if f(m1) < f(m2) { hi = m2 } else { lo = m1 }
                }
                let t = (lo + hi) / 2
                let px = a * cos(t) * (q.x < rect.midX ? -1 : 1)
                let py = b * sin(t) * (q.y < rect.midY ? -1 : 1)
                return NSPoint(x: rect.midX + px, y: rect.midY + py)
            }
        }

        /// The point of the painted area grown by `clearance` that is closest to
        /// `q`, or nil when `q` is inside that area. An arrow tip placed there and
        /// pointing from `q` touches the paint, and because the area is convex the
        /// rest of the arrow (head wings, shaft) stays on the far side of it.
        func nearestPoint(to q: NSPoint, clearance: CGFloat) -> NSPoint? {
            let local = toLocal(q)
            guard let p = nearestOnBase(local) else { return nil }
            let d = hypot(local.x - p.x, local.y - p.y)
            let reach = offset + clearance
            guard d > reach + 0.01 else { return nil }
            return toWorld(NSPoint(x: p.x + (local.x - p.x) / d * reach, y: p.y + (local.y - p.y) / d * reach))
        }

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
        var base: Silhouette.Base
        var offset: CGFloat
        switch a.tool {
        case .number:
            let radius = 8 + a.strokeWidth * 3 + (a.outlineColor != nil ? 3 : 0)
            center = a.startPoint
            path = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                            width: radius * 2, height: radius * 2), transform: nil)
            stroke = 0
            base = .ellipse(CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            offset = 0
        case .text:
            let boxed = a.textBgColor != nil || a.textOutlineColor != nil
            let rect = boxed ? a.textDrawRect.insetBy(dx: -4, dy: -4) : a.textDrawRect
            path = roundedRect(rect, radius: boxed ? 4 : 0)
            stroke = a.textOutlineColor != nil ? 2 : 0
            center = NSPoint(x: rect.midX, y: rect.midY)
            base = .roundedRect(rect, boxed ? 4 : 0)
            offset = stroke / 2
        case .ellipse:
            let rect = a.boundingRect
            path = CGPath(ellipseIn: rect, transform: nil)
            stroke = a.rectFillStyle == .fill ? (ring > 0 ? a.strokeWidth + ring : 0) : a.strokeWidth + ring
            center = NSPoint(x: rect.midX, y: rect.midY)
            base = .ellipse(rect)
            offset = stroke / 2
        default:  // rectangle, filledRectangle
            let rect = a.boundingRect
            let radius = a.rectCornerRadius > 0 ? a.rectCornerRadius
                : (a.isRounded ? min(rect.width, rect.height) * 0.2 : 0)
            path = roundedRect(rect, radius: radius)
            join = radius > 0 ? .round : .miter
            let filledOnly = a.tool == .filledRectangle || a.rectFillStyle == .fill
            stroke = filledOnly ? (ring > 0 ? a.strokeWidth + ring : 0) : a.strokeWidth + ring
            center = NSPoint(x: rect.midX, y: rect.midY)
            if radius > 0 {
                base = .roundedRect(rect, radius)  // round join: the paint is the shape grown evenly
                offset = stroke / 2
            } else {
                // Miter join: the paint keeps sharp corners, half a stroke out.
                base = .roundedRect(rect.insetBy(dx: -stroke / 2, dy: -stroke / 2), 0)
                offset = 0
            }
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
        var result = Silhouette(path: path, stroke: stroke, center: center, join: join)
        result.base = base
        result.offset = offset
        if a.rotation != 0 && a.supportsRotation {
            result.rotation = a.rotation
            result.pivot = NSPoint(x: a.boundingRect.midX, y: a.boundingRect.midY)
        }
        return result
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

    /// The closest spot of the painted edge and how far the pointer is from it
    /// (from inside the shape: the edge in the pointer's direction).
    static func nearestBorder(of annotation: Annotation, to point: NSPoint) -> (point: NSPoint, distance: CGFloat)? {
        guard let silhouette = silhouette(of: annotation) else { return nil }
        let p = silhouette.nearestPoint(to: point, clearance: 0)
            ?? silhouette.exitPoint(toward: point, clearance: 0)
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
        let startFit = from.flatMap { attach(arrow, atStart: true, on: $0, toward: startAim) }
        let endFit = to.flatMap { attach(arrow, atStart: false, on: $0, toward: endAim) }
        var newStart = startFit?.point ?? arrow.startPoint
        var newEnd = endFit?.point ?? arrow.endPoint
        if let from, let to, !multi, arrow.controlPoint == nil,
           startFit?.onCenterLine == false || endFit?.onCenterLine == false {
            // Center to center was too shallow for one end: each tip aims at the
            // other tip instead, so the head points along the real line. A few
            // rounds settle it.
            for _ in 0..<4 {
                newEnd = attachPoint(of: arrow, atStart: false, on: to, toward: newStart) ?? newEnd
                newStart = attachPoint(of: arrow, atStart: true, on: from, toward: newEnd) ?? newStart
            }
            newEnd = attachPoint(of: arrow, atStart: false, on: to, toward: newStart) ?? newEnd
        }

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

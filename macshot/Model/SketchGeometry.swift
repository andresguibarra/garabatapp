import CoreGraphics
import Foundation

/// Hand-drawn ("a mano") geometry for the `.sketch` line style, ported from the
/// previous app's tuned marker look: an ellipse is one open stroke that goes a
/// little more than once around (starts inside, ends past the start, outside), a
/// rectangle is two passes of slightly bowed sides that overshoot the corners,
/// and a line/arrow is a filled, variable-width body with an open hand-drawn head.
///
/// Everything is pure and deterministic for a given seed, so a shape looks the
/// same while it is moved, re-rendered, exported or reopened.
enum SketchGeometry {

    // MARK: - Randoms

    /// 100 values in [0, 1] from xorshift64* (same generator as the original).
    static func randoms(seed: UInt32) -> [CGFloat] {
        var s = UInt64(seed) | (UInt64(seed) << 32) | 1
        var out: [CGFloat] = []
        out.reserveCapacity(100)
        for _ in 0..<100 {
            s ^= s >> 12
            s ^= s << 25
            s ^= s >> 27
            s = s &* 0x2545F4914F6CDD1D
            out.append(CGFloat(s & 0xFFFF_FFFF) / 4294967295.0)
        }
        return out
    }

    // MARK: - Ellipse

    /// Stroke width for a sketched shape: thin shapes cap it at a tenth of the short side.
    static func shapeLineWidth(_ width: CGFloat, rect: CGRect) -> CGFloat {
        let minSide = min(abs(rect.width), abs(rect.height))
        if minSide <= 40, width > minSide / 10 { return max(minSide / 10, 1) }
        return width
    }

    /// Open stroke (round caps) that spirals a little more than one turn.
    static func ellipsePath(in rect: CGRect, randoms r: [CGFloat]) -> CGPath {
        let path = CGMutablePath()
        let rect = rect.standardized
        let cx = rect.midX, cy = rect.midY, rx = rect.width / 2, ry = rect.height / 2
        guard rx > 0, ry > 0 else { return path }
        func rnd(_ i: Int) -> CGFloat { r.isEmpty ? 0.5 : r[i % r.count] }
        let startAngle = CGFloat.pi * (0.22 + 0.06 * rnd(1))
        let sweep = CGFloat.pi * 2 * (1.05 + 0.03 * rnd(2))
        let rInner: CGFloat = 0.89 + 0.02 * rnd(3)
        let rOuter: CGFloat = 1.05 + 0.02 * rnd(4)
        let wobble = 0.01 * (rnd(5) + 0.5)
        func smooth(_ x: CGFloat) -> CGFloat { let v = min(max(x, 0), 1); return v * v * (3 - 2 * v) }
        let steps = 120
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let a = startAngle + sweep * t
            var k: CGFloat = 1
            k += (rInner - 1) * (1 - smooth(t / 0.30))
            k += (rOuter - 1) * smooth((t - 0.70) / 0.30)
            k += wobble * sin(t * .pi * 3 + rnd(6) * 6)
            let p = CGPoint(x: cx + cos(a) * rx * k, y: cy + sin(a) * ry * k)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    // MARK: - Rectangle

    /// Two passes of four slightly bowed sides with jittered ends (stroke, butt caps).
    static func rectPath(in rect: CGRect, lineWidth: CGFloat, randoms r: [CGFloat]) -> CGPath {
        let path = CGMutablePath()
        let rect = rect.standardized
        guard rect.width > 0, rect.height > 0 else { return path }
        func rnd(_ i: Int) -> CGFloat { r.isEmpty ? 0.5 : r[i % r.count] }
        // The original's jitter was 2× a thin pixel width; past ~5 pt that pulls thick
        // passes apart into slivers, so it grows more slowly for thick strokes.
        let rough = lineWidth == 0 ? 12 : min(lineWidth * 2, 6 + lineWidth * 0.8)
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        for pass in 0..<2 {
            let k = pass * 20
            for i in 0..<4 {
                let a = corners[i], b = corners[(i + 1) % 4]
                let ja = CGPoint(x: a.x + (rnd(k + i * 4) - 0.5) * rough,
                                 y: a.y + (rnd(k + i * 4 + 1) - 0.5) * rough)
                let jb = CGPoint(x: b.x + (rnd(k + i * 4 + 2) - 0.5) * rough,
                                 y: b.y + (rnd(k + i * 4 + 3) - 0.5) * rough)
                let mid = CGPoint(x: (ja.x + jb.x) / 2 + (rnd(k + i + 60) - 0.5) * rough,
                                  y: (ja.y + jb.y) / 2 + (rnd(k + i + 70) - 0.5) * rough)
                path.move(to: ja)
                path.addQuadCurve(to: jb, control: mid)
            }
        }
        return path
    }

    // MARK: - Line / arrow

    /// Filled outline of a hand-drawn line along `centerline` (start → end), with
    /// a hand-drawn head at the end when `endHead`, and at the start when `startHead`.
    /// `strokeWidth` is the annotation's width in points.
    static func strokePath(centerline: [CGPoint], strokeWidth: CGFloat, randoms r: [CGFloat],
                           endHead: Bool, startHead: Bool = false) -> CGPath {
        // The original worked in Retina pixels; build at 2x and scale back so its
        // tuned thresholds (head size, short-arrow scaling) keep their meaning.
        let k: CGFloat = 2
        let pts = centerline.map { CGPoint(x: $0.x * k, y: $0.y * k) }
        guard pts.count >= 2, let start = pts.first, let end = pts.last else { return CGMutablePath() }
        let rnd: (Int) -> CGFloat = { i in i >= 0 && i < r.count ? r[i] : 0.5 }

        let diag = hypot(end.x - start.x, end.y - start.y)
        let arcLen = polylineLength(pts)
        guard arcLen > 1 else { return CGMutablePath() }
        var width = (strokeWidth * 0.7 + 1.3) * k
        width = min(width, max(arcLen, diag) / 15)
        width = max(width, 1)
        let scale: CGFloat = arcLen < 200 ? arcLen / 200 : 1
        let headSize = scale * width.squareRoot() * 20
        let minW = width * 0.8
        let closedHead = rnd(62) < 0.25

        var out = CGMutablePath()
        var bodyPts = pts
        if startHead {
            // Leave room for the start head the same way the end leaves room.
            bodyPts = trimStart(bodyPts, by: min(headSize * 0.3, arcLen * 0.2))
        }

        let isStraight = pts.count == 2 || maxDeviation(pts) < 0.5
        var anchors: [StrokePoint]
        let bodyEndShorten: CGFloat
        if endHead {
            // Straight: as the original. Bent: the original's curved shaft stopped at
            // 0.7·width, and a full 2·width gap there reads as a detached head.
            var s = isStraight ? minW : width * 0.7
            if closedHead { s += headSize * 0.89 - width * 0.5 }
            if rnd(10) < 0.25 { s += isStraight ? width * 2 : width * 0.6 }
            bodyEndShorten = s
        } else {
            bodyEndShorten = 0
        }

        if isStraight {
            let s0 = bodyPts.first!, e0 = end
            let angle = atan2(e0.y - s0.y, e0.x - s0.x)
            let bodyLen = max(hypot(e0.x - s0.x, e0.y - s0.y) - bodyEndShorten, 1)
            let bodyEnd = CGPoint(x: s0.x + cos(angle) * bodyLen, y: s0.y + sin(angle) * bodyLen)
            if rnd(11) >= 0.25 {
                anchors = straightCurve(from: s0, to: bodyEnd)
                anchors[0].b = offsetPoint(s0, toward: bodyEnd, scale: 0.33, rotatedBy: (rnd(11) * 0.06 - 0.03) * .pi)
                anchors[1].a = offsetPoint(bodyEnd, toward: s0, scale: 0.33, rotatedBy: (rnd(12) * 0.02 - 0.01) * .pi)
            } else {
                let span = hypot(bodyEnd.x - s0.x, bodyEnd.y - s0.y)
                let jitter = span * 0.03 * 0.125
                anchors = []
                for i in 0...8 {
                    let dist = span * CGFloat(i) / 8
                    var jx = 2 * jitter * rnd((87 + 2 * i) % 100) - jitter
                    var jy = 2 * jitter * rnd((88 + 2 * i) % 100) - jitter
                    if i == 0 || i == 8 { jx = 0; jy = 0 } else if i == 1 || i == 7 { jx *= 0.3; jy *= 0.3 }
                    anchors.append(StrokePoint(CGPoint(x: s0.x + cos(angle) * dist + jx,
                                                       y: s0.y + sin(angle) * dist + jy)))
                }
                anchors = computeControlPoints(anchors)
            }
        } else {
            let even = resampleEvenly(bodyPts, count: 51)
            let trimmed = trimEnd(even, by: bodyEndShorten)
            anchors = computeControlPoints(trimmed.map { StrokePoint($0) })
            let n = anchors.count
            if n >= 2 {
                anchors[0].b = CGPoint(x: anchors[0].x + (anchors[1].x - anchors[0].x) / 3,
                                       y: anchors[0].y + (anchors[1].y - anchors[0].y) / 3)
                anchors[n - 1].a = CGPoint(x: anchors[n - 1].x - (anchors[n - 1].x - anchors[n - 2].x) / 3,
                                           y: anchors[n - 1].y - (anchors[n - 1].y - anchors[n - 2].y) / 3)
            }
        }

        if anchors.count >= 2 {
            let sampled = resample(anchors, step: 4)
            let kind = [2, 4, 5][min(Int(rnd(18) * 2.99), 2)]
            let widths = applyWidths(sampled, kind: kind, minWidth: minW, maxWidth: width * 1.2)
            out.addPath(outlinePath(width: width, points: widths, cap: kind == 5 ? 6 : 0))
        }

        if endHead {
            let back = backPoint(pts, tip: end, headSize: headSize, straight: isStraight)
            out.addPath(head(tip: end, back: back, width: width, closed: closedHead, rnd: rnd))
        }
        if startHead {
            let rev = Array(pts.reversed())
            let back = backPoint(rev, tip: start, headSize: headSize, straight: isStraight)
            // A different slice of randoms so the two heads don't mirror each other.
            let shifted: (Int) -> CGFloat = { i in rnd((i + 37) % 100) }
            out.addPath(head(tip: start, back: back, width: width, closed: closedHead, rnd: shifted))
        }

        var t = CGAffineTransform(scaleX: 1 / k, y: 1 / k)
        return out.copy(using: &t) ?? out
    }

    /// Point `headSize` behind the tip along the line, where the head opens.
    private static func backPoint(_ pts: [CGPoint], tip: CGPoint, headSize: CGFloat, straight: Bool) -> CGPoint {
        let dir: CGFloat
        if straight {
            let s = pts.first!
            dir = atan2(s.y - tip.y, s.x - tip.x)
        } else {
            // Tangent half a head length back from the tip.
            var acc: CGFloat = 0
            var ref = pts[pts.count - 2]
            var i = pts.count - 1
            while i > 0 {
                acc += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
                ref = pts[i - 1]
                if acc >= headSize * 0.5 { break }
                i -= 1
            }
            dir = atan2(ref.y - tip.y, ref.x - tip.x)
        }
        return CGPoint(x: tip.x + headSize * cos(dir), y: tip.y + headSize * sin(dir))
    }

    /// Two wings from the tip (open) or a nearly closed triangle.
    private static func head(tip: CGPoint, back: CGPoint, width: CGFloat, closed: Bool,
                             rnd: (Int) -> CGFloat) -> CGPath {
        let v = CGVector(dx: back.x - tip.x, dy: back.y - tip.y)
        let length = (v.dx * v.dx + v.dy * v.dy).squareRoot()
        let kk = max(0, width.squareRoot() - 2)
        let spread1 = ((kk + 9 + rnd(13) * 2) * .pi) / 180
        var spread2 = ((kk + 9 + rnd(14) * 2) * .pi) / 180
        var a1 = spread1
        var s1 = rnd(15) * 0.4 + 0.8
        var s2 = rnd(16) * 0.4 + 0.8
        if closed {
            a1 = spread1 * 0.66
            spread2 = a1
            s1 = 1; s2 = 1
        }
        func wing(_ angle: CGFloat, _ s: CGFloat) -> CGPoint {
            let rv = rotate(v, by: angle * .pi)
            let a = atan2(rv.dy, rv.dx)
            return CGPoint(x: tip.x + length * s * cos(a), y: tip.y + length * s * sin(a))
        }
        let wing1 = wing(a1, s1)
        let wing2 = wing(-spread2, s2)

        var anchors = straightCurve(from: wing1, to: tip)
        anchors.append(contentsOf: straightCurve(from: tip, to: wing2).dropFirst())
        anchors[0].b = offsetPoint(wing1, toward: tip, scale: 0.5, rotatedBy: (rnd(19) * 0.1 - 0.08) * .pi)
        anchors[1].a = offsetPoint(tip, toward: wing1, scale: 0.1, rotatedBy: .pi / 5)
        anchors[1].b = offsetPoint(tip, toward: wing2, scale: 0.1, rotatedBy: -.pi / 5)
        anchors[2].a = offsetPoint(wing2, toward: tip, scale: 0.5, rotatedBy: (rnd(20) * 0.1 - 0.02) * .pi)
        if closed {
            var closeTo = wing1
            if rnd(88) < 0.25 { closeTo = offsetPoint(wing2, toward: wing1, scale: 0.66, rotatedBy: 0) }
            anchors.append(contentsOf: straightCurve(from: wing2, to: closeTo).dropFirst())
            let tilt = asin(0.3894183423086505)
            anchors[2].b = offsetPoint(wing2, toward: closeTo, scale: 0.3, rotatedBy: tilt)
            anchors[3].a = offsetPoint(closeTo, toward: wing2, scale: 0.3, rotatedBy: -tilt)
        }
        let sampled = removeClosePoints(resample(anchors, step: 4), minDistance: 2)
        let kind = [0, 4, 5][min(Int(rnd(18) * 2.99), 2)]
        let pts = applyWidths(sampled, kind: kind, minWidth: width * 0.8, maxWidth: width * 1.2)
        return outlinePath(width: width, points: pts, cap: kind == 5 ? 6 : 0)
    }

    // MARK: - Stroke machinery (ported from the original FreehandHelper)

    struct StrokePoint {
        var x: CGFloat
        var y: CGFloat
        var weight: CGFloat = 0.5
        var width: CGFloat = 0
        var a: CGPoint = CGPoint(x: unset, y: unset)  // control in
        var b: CGPoint = CGPoint(x: unset, y: unset)  // control out
        static let unset: CGFloat = -999
        init(_ p: CGPoint) { x = p.x; y = p.y }
        var point: CGPoint { CGPoint(x: x, y: y) }
    }

    private static func dist(_ p: StrokePoint, _ q: StrokePoint) -> CGFloat { hypot(p.x - q.x, p.y - q.y) }

    private static func rotate(_ v: CGVector, by angle: CGFloat) -> CGVector {
        let c = cos(angle), s = sin(angle)
        return CGVector(dx: v.dx * c - v.dy * s, dy: v.dy * c + v.dx * s)
    }

    private static func offsetPoint(_ o: CGPoint, toward t: CGPoint, scale: CGFloat, rotatedBy angle: CGFloat) -> CGPoint {
        let dx = t.x - o.x, dy = t.y - o.y
        let len = (dx * dx + dy * dy).squareRoot() * scale
        let a = atan2(dy, dx)
        let v = rotate(CGVector(dx: cos(a) * len, dy: sin(a) * len), by: angle)
        return CGPoint(x: o.x + v.dx, y: o.y + v.dy)
    }

    private static func straightCurve(from s: CGPoint, to e: CGPoint) -> [StrokePoint] {
        let length = hypot(e.x - s.x, e.y - s.y)
        let angle = atan2(e.y - s.y, e.x - s.x)
        let c = cos(angle), sn = sin(angle)
        var p0 = StrokePoint(s), p1 = StrokePoint(e)
        p0.a = s
        p0.b = CGPoint(x: s.x + length * 0.33 * c, y: s.y + length * 0.33 * sn)
        p1.a = CGPoint(x: s.x + length * 0.66 * c, y: s.y + length * 0.66 * sn)
        p1.b = e
        return [p0, p1]
    }

    static func computeControlPoints(_ input: [StrokePoint]) -> [StrokePoint] {
        guard input.count >= 2 else { return input }
        var pts = input
        if pts.count > 2 {
            for i in 1..<(pts.count - 1) {
                let p0 = pts[i - 1], p = pts[i], p1 = pts[i + 1]
                let ax = p0.x - p.x, ay = p0.y - p.y
                let bx = p1.x - p.x, by = p1.y - p.y
                let la = (ax * ax + ay * ay).squareRoot(), lb = (bx * bx + by * by).squareRoot()
                guard la > 0, lb > 0 else { continue }
                var tension: CGFloat = 0.1
                if (ax * bx + ay * by) / la / lb <= -0.1 { tension = (1 - p.weight) * 0.04 + 0.3 }
                let dx = p1.x - p0.x, dy = p1.y - p0.y
                let d = max((dx * dx + dy * dy).squareRoot(), 0.0001)
                pts[i].b = CGPoint(x: p.x + dx * lb * tension / d, y: p.y + dy * lb * tension / d)
                pts[i].a = CGPoint(x: p.x - dx * la * tension / d, y: p.y - dy * la * tension / d)
            }
        }
        let last = pts.count - 1
        pts[0].a = pts[0].point
        pts[last].b = pts[last].point
        if pts.count < 3 {
            pts[0].b = CGPoint(x: (pts[0].x + pts[1].x) * 0.5, y: (pts[0].y + pts[1].y) * 0.5)
            pts[last].a = CGPoint(x: (pts[last - 1].x + pts[last].x) * 0.5, y: (pts[last - 1].y + pts[last].y) * 0.5)
        } else {
            pts[0].b = CGPoint(x: pts[0].x * 0.8 + pts[1].a.x * 0.2, y: pts[0].y * 0.8 + pts[1].a.y * 0.2)
            pts[last].a = CGPoint(x: pts[last].x * 0.8 + pts[last - 1].b.x * 0.2,
                                  y: pts[last].y * 0.8 + pts[last - 1].b.y * 0.2)
        }
        return pts
    }

    private static func sampleSegment(_ p1: StrokePoint, _ p2: StrokePoint, step: CGFloat) -> [StrokePoint] {
        let length = dist(p1, p2) * 1.2
        if length == 0 { return [p1] }
        if length < step { return [p1, p2] }
        let n = min(max(Int(length / step), 1), 4000)
        var out = [p1]
        var lx = p1.x, ly = p1.y
        let c1 = p1.b, c2 = p2.a
        for k in 0..<n {
            let t = CGFloat(k) / CGFloat(n), u = 1 - t
            let x = p2.x * t * t * t + c2.x * (t * t * u * 3) + p1.x * u * u * u + c1.x * (t * u * u * 3)
            let y = p2.y * t * t * t + c2.y * (t * t * u * 3) + p1.y * u * u * u + c1.y * (t * u * u * 3)
            if step * step <= (x - lx) * (x - lx) + (y - ly) * (y - ly) {
                var q = StrokePoint(CGPoint(x: x, y: y))
                q.weight = p2.weight * t + p1.weight * u
                out.append(q)
                lx = x; ly = y
            }
        }
        out.append(p2)
        return out
    }

    private static func resample(_ input: [StrokePoint], step: CGFloat) -> [StrokePoint] {
        guard input.count >= 2 else { return input }
        var out: [StrokePoint] = []
        for i in 0..<(input.count - 1) {
            var seg = sampleSegment(input[i], input[i + 1], step: step)
            if i < input.count - 2 { seg.removeLast() }
            out.append(contentsOf: seg)
        }
        return out
    }

    private static func removeClosePoints(_ input: [StrokePoint], minDistance: CGFloat) -> [StrokePoint] {
        guard input.count >= 3 else { return input }
        let limit = (minDistance * 0.33) * (minDistance * 0.33)
        var out = [input[0]]
        var lx = input[0].x, ly = input[0].y
        for p in input.dropFirst().dropLast() where (lx - p.x) * (lx - p.x) + (ly - p.y) * (ly - p.y) > limit {
            out.append(p)
            lx = p.x; ly = p.y
        }
        let last = input[input.count - 1]
        if out.count >= 2, (lx - last.x) * (lx - last.x) + (ly - last.y) * (ly - last.y) < limit {
            out[out.count - 1] = last
        } else {
            out.append(last)
        }
        return out
    }

    private static func easing(_ t: CGFloat, kind: Int) -> CGFloat {
        switch kind {
        case 1: return cos(t * 2 * .pi) * 0.5 + 0.5
        case 2: return 2 * t - t * t
        case 3: return t * t - 2 * t + 1
        case 4: return (t * t - t) * -4
        case 5: let u = 2 * t - 1; return abs(max(0, 1 - u * u).squareRoot())
        case 6: return t * t * (3 - 2 * t)
        case 7: return t * t * t * (t * (t * 6 - 15) + 10)
        default: return t
        }
    }

    private static func applyWidths(_ points: [StrokePoint], kind: Int, minWidth: CGFloat, maxWidth: CGFloat) -> [StrokePoint] {
        guard points.count >= 2 else { return points }
        var pts = points
        var cum: [CGFloat] = [0]
        for i in 1..<pts.count { cum.append(cum[i - 1] + dist(pts[i], pts[i - 1])) }
        let total = cum[cum.count - 1]
        for i in pts.indices {
            let t = total > 0 ? cum[i] / total : 0
            pts[i].width = minWidth + (maxWidth - minWidth) * easing(t, kind: kind)
        }
        return pts
    }

    private static func sharpenCorners(_ input: [StrokePoint]) -> [StrokePoint] {
        guard input.count >= 3 else { return input }
        var pts = input
        for i in 1..<(pts.count - 1) {
            let p0 = pts[i - 1], p = pts[i], p1 = pts[i + 1]
            let a1 = atan2(p.y - p0.y, p.x - p0.x) * 180 / .pi
            let a2 = atan2(p1.y - p.y, p1.x - p.x) * 180 / .pi
            var turn = abs(a2 - a1)
            if turn > 180 { turn = 360 - turn }
            let m = min(dist(p0, p), dist(p, p1))
            let threshold: CGFloat = m > 80 ? 49 : (m > 30 ? 66 : 84)
            if turn >= threshold && turn <= 180 - threshold {
                pts[i].a = p.point
                pts[i].b = p.point
            }
        }
        return pts
    }

    private static func finalizeControls(_ input: [StrokePoint]) -> [StrokePoint] {
        guard input.count >= 2 else { return input }
        var pts = input
        let u = StrokePoint.unset
        for i in pts.indices {
            let prev = pts[max(i - 1, 0)], next = pts[min(i + 1, pts.count - 1)]
            let dx = next.x - prev.x, dy = next.y - prev.y
            if pts[i].a.x == pts[i].x { pts[i].a.x = u }
            if pts[i].a.y == pts[i].y { pts[i].a.y = u }
            if pts[i].b.x == pts[i].x { pts[i].b.x = u }
            if pts[i].b.y == pts[i].y { pts[i].b.y = u }
            if pts[i].a.x == u { pts[i].a.x = pts[i].x - dx / 3 }
            if pts[i].a.y == u { pts[i].a.y = pts[i].y - dy / 3 }
            if pts[i].b.x == u { pts[i].b.x = pts[i].x + dx / 3 }
            if pts[i].b.y == u { pts[i].b.y = pts[i].y + dy / 3 }
        }
        let size = max(pts.map(\.width).max() ?? 1, 1)
        pts = removeClosePoints(pts, minDistance: size * 0.5)
        pts = computeControlPoints(pts)
        return sharpenCorners(pts)
    }

    /// Closed variable-width outline: left side, end cap, right side reversed, start cap.
    private static func strokeOutline(_ pts: [StrokePoint], size: CGFloat, cap: Int) -> [StrokePoint] {
        guard let first = pts.first else { return [] }
        func hw(_ p: StrokePoint) -> CGFloat { max((p.width > 0 ? p.width : size) * 0.5, 0.25) }
        if pts.count == 1 {
            let r = hw(first)
            return computeControlPoints((0..<12).map { k in
                let t = CGFloat(k) / 12 * 2 * .pi
                return StrokePoint(CGPoint(x: first.x + cos(t) * r, y: first.y + sin(t) * r))
            })
        }
        var left: [StrokePoint] = [], right: [StrokePoint] = [], normals: [CGVector] = []
        for i in pts.indices {
            let prev = pts[max(i - 1, 0)], next = pts[min(i + 1, pts.count - 1)]
            var dx = next.x - prev.x, dy = next.y - prev.y
            let len = (dx * dx + dy * dy).squareRoot()
            if len == 0 { dx = 1; dy = 0 } else { dx /= len; dy /= len }
            normals.append(CGVector(dx: -dy, dy: dx))
            let h = hw(pts[i])
            left.append(StrokePoint(CGPoint(x: pts[i].x - dy * h, y: pts[i].y + dx * h)))
            right.append(StrokePoint(CGPoint(x: pts[i].x + dy * h, y: pts[i].y - dx * h)))
        }
        func roundCap(_ p: StrokePoint, _ n: CGVector) -> [StrokePoint] {
            guard cap == 0 else { return [] }
            let r = hw(p), base = atan2(n.dy, n.dx)
            return (1..<6).map { k in
                let t = base - CGFloat(k) / 6 * .pi
                return StrokePoint(CGPoint(x: p.x + cos(t) * r, y: p.y + sin(t) * r))
            }
        }
        var outline = left
        outline += roundCap(pts[pts.count - 1], normals[normals.count - 1])
        outline += right.reversed()
        outline += roundCap(first, CGVector(dx: -normals[0].dx, dy: -normals[0].dy))
        return computeControlPoints(outline)
    }

    private static func outlinePath(width: CGFloat, points: [StrokePoint], cap: Int) -> CGPath {
        let outline = strokeOutline(finalizeControls(points), size: width, cap: cap)
        let path = CGMutablePath()
        guard outline.count >= 2 else { return path }
        path.move(to: outline[0].point)
        for i in 1..<outline.count {
            path.addCurve(to: outline[i].point, control1: outline[i - 1].b, control2: outline[i].a)
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Polyline helpers

    static func polylineLength(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count >= 2 else { return 0 }
        var l: CGFloat = 0
        for i in 1..<pts.count { l += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y) }
        return l
    }

    /// Largest distance of any point from the chord, to tell straight lines from bent ones.
    private static func maxDeviation(_ pts: [CGPoint]) -> CGFloat {
        guard let s = pts.first, let e = pts.last else { return 0 }
        let dx = e.x - s.x, dy = e.y - s.y
        let len = max(hypot(dx, dy), 0.0001)
        return pts.map { abs(($0.x - s.x) * dy - ($0.y - s.y) * dx) / len }.max() ?? 0
    }

    static func resampleEvenly(_ pts: [CGPoint], count: Int) -> [CGPoint] {
        guard pts.count >= 2, count >= 2 else { return pts }
        let total = polylineLength(pts)
        guard total > 0 else { return [pts[0], pts[pts.count - 1]] }
        var out: [CGPoint] = [pts[0]]
        var seg = 0
        var segStart: CGFloat = 0
        for k in 1..<(count - 1) {
            let target = total * CGFloat(k) / CGFloat(count - 1)
            while seg < pts.count - 2 {
                let l = hypot(pts[seg + 1].x - pts[seg].x, pts[seg + 1].y - pts[seg].y)
                if segStart + l >= target { break }
                segStart += l
                seg += 1
            }
            let a = pts[seg], b = pts[seg + 1]
            let l = max(hypot(b.x - a.x, b.y - a.y), 0.0001)
            let t = min(max((target - segStart) / l, 0), 1)
            out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        out.append(pts[pts.count - 1])
        return out
    }

    /// Cuts `amount` of arc length off the end of a polyline.
    static func trimEnd(_ pts: [CGPoint], by amount: CGFloat) -> [CGPoint] {
        guard amount > 0, pts.count >= 2 else { return pts }
        let total = polylineLength(pts)
        let keep = max(total - amount, min(total, 1))
        var out: [CGPoint] = [pts[0]]
        var acc: CGFloat = 0
        for i in 1..<pts.count {
            let l = hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
            if acc + l >= keep {
                let t = l > 0 ? (keep - acc) / l : 0
                out.append(CGPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t,
                                   y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t))
                return out
            }
            acc += l
            out.append(pts[i])
        }
        return out
    }

    static func trimStart(_ pts: [CGPoint], by amount: CGFloat) -> [CGPoint] {
        Array(trimEnd(Array(pts.reversed()), by: amount).reversed())
    }
}

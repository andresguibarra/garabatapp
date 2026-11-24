import Cocoa
import XCTest

/// Draws real shapes and real attached arrows with their own drawing code and
/// checks the pixels: the arrow's paint must not land on the shape's paint, and
/// must come right up to it (no visible gap). Covers every connectable shape,
/// outlines, corner radii, rotation, arrow styles, stroke widths and directions.
///
/// Set `MACSHOT_CONNECTOR_RENDERS` to a folder to also get one PNG per case
/// (shape red, arrow blue, overlap yellow) to look at.
final class ArrowConnectorsRenderTests: XCTestCase {

    private let scale: CGFloat = 3
    private let canvas: CGFloat = 340
    private let center = NSPoint(x: 170, y: 170)

    private struct Masks { let shape: [UInt8]; let arrow: [UInt8]; let size: Int }

    private func render(_ a: Annotation) -> [UInt8] {
        let size = Int(canvas * scale)
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        pixels.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.scaleBy(x: scale, y: scale)
            let previous = NSGraphicsContext.current
            let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.current = ns
            a.draw(in: ns)
            NSGraphicsContext.current = previous
        }
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }

    /// Shape factory: centered on `center`.
    private func shapes() -> [(String, () -> Annotation)] {
        func rect(_ w: CGFloat, _ h: CGFloat, sw: CGFloat, tool: AnnotationTool = .rectangle,
                  configure: (Annotation) -> Void = { _ in }) -> Annotation {
            let a = Annotation(tool: tool, startPoint: NSPoint(x: center.x - w / 2, y: center.y - h / 2),
                               endPoint: NSPoint(x: center.x + w / 2, y: center.y + h / 2),
                               color: .red, strokeWidth: sw)
            configure(a)
            return a
        }
        func text(_ w: CGFloat, _ h: CGFloat, outline: Bool, background: Bool) -> Annotation {
            let r = NSRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
            let t = Annotation(tool: .text, startPoint: r.origin, endPoint: NSPoint(x: r.maxX, y: r.maxY),
                               color: .red, strokeWidth: 2)
            t.textDrawRect = r
            t.textImage = ImageProbe.solidImage(width: Int(w), height: Int(h))
            if outline { t.textOutlineColor = .systemGreen }
            if background { t.textBgColor = .systemYellow }
            return t
        }
        return [
            ("rect-2", { rect(120, 70, sw: 2) }),
            ("rect-12", { rect(120, 70, sw: 12) }),
            ("rect-outline", { rect(120, 70, sw: 4) { $0.outlineColor = .black } }),
            ("rect-round", { rect(120, 70, sw: 6) { $0.rectCornerRadius = 24 } }),
            ("rect-fill", { rect(120, 70, sw: 6) { $0.rectFillStyle = .fill } }),
            ("rect-rotated", { rect(120, 50, sw: 4) { $0.rotation = 0.5 } }),
            ("filled-rect", { rect(100, 60, sw: 4, tool: .filledRectangle) }),
            ("wide-rect", { rect(260, 30, sw: 3) }),
            ("ellipse", { rect(140, 70, sw: 5, tool: .ellipse) }),
            ("ellipse-outline", { rect(140, 70, sw: 3, tool: .ellipse) { $0.outlineColor = .black } }),
            ("number", { Annotation(tool: .number, startPoint: self.center, endPoint: self.center, color: .red, strokeWidth: 3) }),
            ("number-outline", {
                let n = Annotation(tool: .number, startPoint: self.center, endPoint: self.center, color: .red, strokeWidth: 3)
                n.outlineColor = .black
                return n
            }),
            ("text-plain", { text(150, 28, outline: false, background: false) }),
            ("text-outline", { text(150, 28, outline: true, background: false) }),
            ("text-box", { text(150, 28, outline: true, background: true) }),
        ]
    }

    private func arrows() -> [(String, (Annotation) -> Void)] {
        [
            ("single-2", { $0.arrowStyle = .single; $0.strokeWidth = 2 }),
            ("single-10", { $0.arrowStyle = .single; $0.strokeWidth = 10 }),
            ("open-6", { $0.arrowStyle = .open; $0.strokeWidth = 6 }),
            ("double-4", { $0.arrowStyle = .double; $0.strokeWidth = 4 }),
            ("tail-5", { $0.arrowStyle = .tail; $0.strokeWidth = 5 }),
            ("thick-4", { $0.arrowStyle = .thick; $0.strokeWidth = 4 }),
            ("outline-4", { $0.arrowStyle = .single; $0.strokeWidth = 4; $0.outlineColor = .black }),
            ("sketchy-3", { $0.arrowStyle = .sketchy; $0.strokeWidth = 3 }),
        ]
    }

    func testAttachedArrowsTouchButNeverCoverTheShape() throws {
        let angles: [CGFloat] = [0, 33, 45, 90, 160, 200, 251, 337]
        let outDir = ProcessInfo.processInfo.environment["MACSHOT_CONNECTOR_RENDERS"].map { URL(fileURLWithPath: $0) }
        if let outDir { try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) }
        var worst: [String] = []
        for (shapeName, makeShape) in shapes() {
            for (arrowName, style) in arrows() {
                for (i, degrees) in angles.enumerated() {
                    // Alternate which end is attached so both the head and the tail end get covered.
                    let attachStart = i % 2 == 1
                    let shape = makeShape()
                    let rad = degrees * .pi / 180
                    let free = NSPoint(x: center.x + cos(rad) * 165, y: center.y + sin(rad) * 165)
                    let link = Annotation(tool: .arrow, startPoint: attachStart ? center : free,
                                          endPoint: attachStart ? free : center, color: .blue, strokeWidth: 2)
                    style(link)
                    if attachStart { link.connectedStartID = shape.connectorID } else { link.connectedEndID = shape.connectorID }
                    ArrowConnectors.resolve([shape, link])

                    let s = render(shape), a = render(link)
                    let size = Int(canvas * scale)
                    let attached = attachStart ? link.startPoint : link.endPoint
                    let result = measure(shape: s, arrow: a, size: size, near: attached)
                    let label = "\(shapeName) / \(arrowName) / \(Int(degrees))° / \(attachStart ? "start" : "end")"
                    if let outDir {
                        writePNG(shape: s, arrow: a, size: size,
                                 to: outDir.appendingPathComponent("\(shapeName)_\(arrowName)_\(Int(degrees)).png"))
                    }
                    // Antialiased edges share a pixel or two; anything more is visible overlap.
                    XCTAssertLessThanOrEqual(result.overlap, 2, "\(label): arrow covers the shape (\(result.overlap) px)")
                    XCTAssertLessThanOrEqual(result.gap, 1.6, "\(label): gap of \(result.gap) pt between arrow and shape")
                    if result.gap > 1 || result.overlap > 0 {
                        worst.append("\(label): overlap \(result.overlap) px, gap \(String(format: "%.2f", result.gap)) pt")
                    }
                }
            }
        }
        if !worst.isEmpty { print("Connector render cases with antialias contact:\n" + worst.joined(separator: "\n")) }
    }

    /// Pixels both paints cover (each more than 5/8, which two shapes that only
    /// touch can't both reach), and the smallest distance (pt, up to `reach`)
    /// from the arrow's paint to the shape's paint near the attached end.
    private func measure(shape: [UInt8], arrow: [UInt8], size: Int, near p: NSPoint) -> (overlap: Int, gap: CGFloat) {
        var overlap = 0
        for i in 0..<shape.count where shape[i] > 160 && arrow[i] > 160 { overlap += 1 }
        let solid: UInt8 = 128
        let reach = Int(3 * scale)  // look 3 pt around each arrow pixel
        let window = Int(45 * scale)
        let cx = Int(p.x * scale), cy = size - Int(p.y * scale)  // bitmap rows go top-down
        var best = Int.max
        scan: for y in max(0, cy - window)..<min(size, cy + window) {
            for x in max(0, cx - window)..<min(size, cx + window) where arrow[y * size + x] >= solid {
                if best <= 1 { break scan }  // already touching
                for ny in max(0, y - reach)...min(size - 1, y + reach) {
                    for nx in max(0, x - reach)...min(size - 1, x + reach) where shape[ny * size + nx] >= solid {
                        let d = (nx - x) * (nx - x) + (ny - y) * (ny - y)
                        if d < best { best = d }
                    }
                }
            }
        }
        let gap = best == Int.max ? CGFloat(reach) / scale : max(0, (sqrt(CGFloat(best)) - 1) / scale)
        return (overlap, gap)
    }

    private func writePNG(shape: [UInt8], arrow: [UInt8], size: Int, to url: URL) {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32),
              let data = rep.bitmapData else { return }
        for i in 0..<(size * size) {
            let s = shape[i], a = arrow[i]
            let both = s >= 128 && a >= 128
            data[i * 4 + 0] = both ? 255 : max(255 - a, 0)
            data[i * 4 + 1] = both ? 230 : 255 - max(s, a)
            data[i * 4 + 2] = both ? 0 : 255 - s
            data[i * 4 + 3] = 255
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

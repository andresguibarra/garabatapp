import Cocoa
import XCTest

/// The hand-drawn ("a mano") line style: deterministic per seed, never empty or
/// runaway, and it stays near the shape the user drew.
final class SketchGeometryTests: XCTestCase {

    func testRandomsAreDeterministicAndInRange() {
        let a = SketchGeometry.randoms(seed: 42), b = SketchGeometry.randoms(seed: 42)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 100)
        XCTAssertTrue(a.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertNotEqual(a, SketchGeometry.randoms(seed: 43))
    }

    func testEllipseHugsItsRect() {
        let rect = CGRect(x: 10, y: 20, width: 200, height: 100)
        for seed in [1, 7, 99, 12345] as [UInt32] {
            let box = SketchGeometry.ellipsePath(in: rect, randoms: SketchGeometry.randoms(seed: seed)).boundingBoxOfPath
            // Starts ~10% inside and ends ~7% outside, never far off.
            XCTAssertTrue(rect.insetBy(dx: -rect.width * 0.1, dy: -rect.height * 0.1).contains(box))
            XCTAssertGreaterThan(box.width, rect.width * 0.9)
        }
    }

    func testRectHugsItsRect() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 120)
        let box = SketchGeometry.rectPath(in: rect, lineWidth: 5, randoms: SketchGeometry.randoms(seed: 3)).boundingBoxOfPath
        XCTAssertTrue(rect.insetBy(dx: -6, dy: -6).contains(box))
        XCTAssertGreaterThan(box.width, rect.width - 10)
    }

    func testArrowsOfEveryShapeStayBounded() {
        let lines: [[CGPoint]] = [
            [CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 120)],
            [CGPoint(x: 0, y: 0), CGPoint(x: 6, y: 2)],
            [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0)],
            (0...40).map { i in CGPoint(x: CGFloat(i) * 5, y: sin(CGFloat(i) / 6) * 60) },
        ]
        for line in lines {
            for seed in 1...60 as ClosedRange<UInt32> {
                for width in [1, 4, 12] as [CGFloat] {
                    for heads in [(true, false), (true, true), (false, false)] {
                        let path = SketchGeometry.strokePath(centerline: line, strokeWidth: width,
                                                             randoms: SketchGeometry.randoms(seed: seed),
                                                             endHead: heads.0, startHead: heads.1)
                        guard !path.isEmpty else { continue }
                        let box = path.boundingBoxOfPath
                        let lineBox = line.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
                        XCTAssertTrue(lineBox.insetBy(dx: -80, dy: -80).contains(box), "\(seed) \(width)")
                    }
                }
            }
        }
    }

    /// Writes sample renders when SKETCH_RENDER_DIR is set (visual check only).
    func testRenderSamples() throws {
        guard let dir = ProcessInfo.processInfo.environment["SKETCH_RENDER_DIR"] else { return }
        let size = NSSize(width: 900, height: 520)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let red = NSColor(calibratedRed: 0.9, green: 0.28, blue: 0.3, alpha: 1)
        var anns: [Annotation] = []
        for (i, w) in ([3, 5, 8] as [CGFloat]).enumerated() {
            let x = 30 + CGFloat(i) * 290
            let e = Annotation(tool: .ellipse, startPoint: NSPoint(x: x, y: 400), endPoint: NSPoint(x: x + 220, y: 490), color: red, strokeWidth: w)
            let r = Annotation(tool: .rectangle, startPoint: NSPoint(x: x, y: 260), endPoint: NSPoint(x: x + 220, y: 360), color: red, strokeWidth: w)
            let a = Annotation(tool: .arrow, startPoint: NSPoint(x: x, y: 30), endPoint: NSPoint(x: x + 200, y: 200), color: red, strokeWidth: w)
            let b = Annotation(tool: .arrow, startPoint: NSPoint(x: x + 40, y: 40), endPoint: NSPoint(x: x + 240, y: 120), color: .systemBlue, strokeWidth: w)
            b.controlPoint = NSPoint(x: x + 60, y: 180)
            for ann in [e, r, a, b] { ann.lineStyle = .sketch; anns.append(ann) }
        }
        for ann in anns { ann.draw(in: ctx) }
        NSGraphicsContext.restoreGraphicsState()
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("sketch-samples.png"))
    }
}

import Cocoa
import XCTest

final class ResizeCursorTests: XCTestCase {

    private func line(_ a: NSPoint, _ b: NSPoint) -> Annotation {
        Annotation(tool: .arrow, startPoint: a, endPoint: b, color: .red, strokeWidth: 2)
    }

    func testEndsPointAlongTheLine() {
        let diagonal = line(NSPoint(x: 0, y: 0), NSPoint(x: 100, y: 100))
        XCTAssertEqual(ResizeCursor.endpointAngle(of: diagonal, atStart: false)!, .pi / 4, accuracy: 1e-9)
        XCTAssertEqual(ResizeCursor.endpointAngle(of: diagonal, atStart: true)!, -3 * .pi / 4, accuracy: 1e-9)
        // Same two-headed cursor at both ends of a straight line.
        XCTAssertEqual(ResizeCursor.bucketIndex(for: ResizeCursor.endpointAngle(of: diagonal, atStart: true)!),
                       ResizeCursor.bucketIndex(for: ResizeCursor.endpointAngle(of: diagonal, atStart: false)!))
    }

    func testBentLineUsesTheDirectionAtEachEnd() {
        let bent = line(NSPoint(x: 0, y: 0), NSPoint(x: 100, y: 0))
        bent.controlPoint = NSPoint(x: 50, y: 50)
        XCTAssertEqual(ResizeCursor.endpointAngle(of: bent, atStart: true)!, -3 * .pi / 4, accuracy: 1e-9)
        XCTAssertEqual(ResizeCursor.endpointAngle(of: bent, atStart: false)!, -.pi / 4, accuracy: 1e-9)

        let anchored = line(.zero, NSPoint(x: 100, y: 0))
        anchored.anchorPoints = [.zero, NSPoint(x: 0, y: 60), NSPoint(x: 100, y: 0)]
        XCTAssertEqual(ResizeCursor.endpointAngle(of: anchored, atStart: true)!, -.pi / 2, accuracy: 1e-9)
    }

    func testBucketsWrapHalfTurns() {
        XCTAssertEqual(ResizeCursor.bucketIndex(for: 0), ResizeCursor.bucketIndex(for: .pi))
        XCTAssertEqual(ResizeCursor.bucketIndex(for: -.pi / 2), ResizeCursor.bucketIndex(for: .pi / 2))
        XCTAssertEqual(ResizeCursor.bucketIndex(for: .nan), 0)
    }

    /// Renders the cursor at a few angles; with `MACSHOT_CONNECTOR_RENDERS` set,
    /// writes them as one PNG strip to look at.
    @MainActor
    func testCursorImagesTurnWithTheAngle() throws {
        let angles: [CGFloat] = [0, 20, 45, 60, 90, 120, 135, 160]
        let cursors = angles.map { ResizeCursor.cursor(angle: $0 * .pi / 180) }
        XCTAssertTrue(cursors[0] === ResizeCursor.cursor(angle: .pi), "cached per direction")
        for c in cursors { XCTAssertEqual(c.hotSpot, NSPoint(x: 13, y: 13)) }
        guard let dir = ProcessInfo.processInfo.environment["MACSHOT_CONNECTOR_RENDERS"] else { return }
        let cell = 52, size = NSSize(width: cell * cursors.count, height: cell)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.55, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        for (i, c) in cursors.enumerated() {
            c.image.draw(in: NSRect(x: i * cell, y: 0, width: cell, height: cell))
        }
        NSGraphicsContext.restoreGraphicsState()
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("resize-cursors.png"))
    }
}

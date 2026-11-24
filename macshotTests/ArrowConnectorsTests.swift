import Cocoa
import XCTest

final class ArrowConnectorsTests: XCTestCase {

    private func rect(_ r: NSRect) -> Annotation {
        Annotation(tool: .rectangle, startPoint: r.origin, endPoint: NSPoint(x: r.maxX, y: r.maxY),
                   color: .red, strokeWidth: 2)
    }

    private func arrow(_ a: NSPoint, _ b: NSPoint) -> Annotation {
        Annotation(tool: .arrow, startPoint: a, endPoint: b, color: .red, strokeWidth: 2)
    }

    private func assertPoint(_ p: NSPoint, _ x: CGFloat, _ y: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.x, x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(p.y, y, accuracy: 0.001, file: file, line: line)
    }

    func testBorderPointOfRectangleSitsGapOutsideTheEdge() {
        let box = rect(NSRect(x: 0, y: 0, width: 100, height: 50))
        let right = ArrowConnectors.borderPoint(of: box, toward: NSPoint(x: 500, y: 25))!
        assertPoint(right, 100 + ArrowConnectors.gap, 25)
        let top = ArrowConnectors.borderPoint(of: box, toward: NSPoint(x: 50, y: 400), gap: 0)!
        assertPoint(top, 50, 50)
    }

    func testBorderPointOfEllipseAndNumber() {
        let oval = Annotation(tool: .ellipse, startPoint: .zero, endPoint: NSPoint(x: 200, y: 100),
                              color: .red, strokeWidth: 2)
        assertPoint(ArrowConnectors.borderPoint(of: oval, toward: NSPoint(x: 100, y: 999), gap: 0)!, 100, 100)
        assertPoint(ArrowConnectors.borderPoint(of: oval, toward: NSPoint(x: -999, y: 50), gap: 0)!, 0, 50)

        let number = Annotation(tool: .number, startPoint: NSPoint(x: 10, y: 10), endPoint: NSPoint(x: 10, y: 10),
                                color: .red, strokeWidth: 2)
        let radius: CGFloat = 8 + 2 * 3
        assertPoint(ArrowConnectors.borderPoint(of: number, toward: NSPoint(x: 10, y: 100), gap: 0)!, 10, 10 + radius)
    }

    func testRotatedRectangleUsesItsOwnFrame() {
        let box = rect(NSRect(x: -50, y: -10, width: 100, height: 20))
        box.rotation = .pi / 2  // now 20 wide, 100 tall
        let up = ArrowConnectors.borderPoint(of: box, toward: NSPoint(x: 0, y: 500), gap: 0)!
        assertPoint(up, 0, 50)
    }

    func testOnlyShapesAreConnectable() {
        XCTAssertTrue(ArrowConnectors.isConnectable(rect(NSRect(x: 0, y: 0, width: 10, height: 10))))
        XCTAssertFalse(ArrowConnectors.isConnectable(arrow(.zero, NSPoint(x: 5, y: 5))))
        let emptyText = Annotation(tool: .text, startPoint: .zero, endPoint: .zero, color: .red, strokeWidth: 2)
        XCTAssertFalse(ArrowConnectors.isConnectable(emptyText), "text without a box has no outline")
    }

    func testHoverAndDropTargets() {
        let box = rect(NSRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertNotNil(ArrowConnectors.hoverTarget(in: [box], at: NSPoint(x: 104, y: 50), threshold: 6))
        XCTAssertNil(ArrowConnectors.hoverTarget(in: [box], at: NSPoint(x: 50, y: 50), threshold: 6),
                     "the middle of a shape is its body, not its border")
        XCTAssertNil(ArrowConnectors.hoverTarget(in: [box], at: NSPoint(x: 104, y: 50), threshold: 6, excluding: box))
        XCTAssertTrue(ArrowConnectors.dropTarget(in: [box], at: NSPoint(x: 50, y: 50), margin: 0) === box)
        XCTAssertNil(ArrowConnectors.dropTarget(in: [box], at: NSPoint(x: 50, y: 50), margin: 0,
                                                excluding: [box.connectorID]))
    }

    func testArrowBetweenTwoShapesFollowsThemWhenMoved() {
        let a = rect(NSRect(x: 0, y: 0, width: 100, height: 100))
        let b = rect(NSRect(x: 300, y: 0, width: 100, height: 100))
        let link = arrow(NSPoint(x: 1, y: 1), NSPoint(x: 2, y: 2))
        link.connectedStartID = a.connectorID
        link.connectedEndID = b.connectorID

        let startGap = ArrowConnectors.clearance(arrow: link, atStart: true, shape: a)
        let endGap = ArrowConnectors.clearance(arrow: link, atStart: false, shape: b)
        XCTAssertTrue(ArrowConnectors.resolve([a, b, link]))
        assertPoint(link.startPoint, 100 + startGap, 50)
        assertPoint(link.endPoint, 300 - endGap, 50)
        XCTAssertFalse(ArrowConnectors.resolve([a, b, link]), "resolving again changes nothing")

        b.move(dx: 0, dy: 200)
        XCTAssertTrue(ArrowConnectors.resolve([a, b, link]))
        // From a's center (50,50) toward b's center (350,250): exits through a's right edge.
        XCTAssertEqual(link.startPoint.x, 100 + startGap * 300 / hypot(300, 200), accuracy: 0.01)
        XCTAssertGreaterThan(link.endPoint.y, link.startPoint.y)
    }

    func testOneEndedArrowAimsAtItsFreeEnd() {
        let a = rect(NSRect(x: 0, y: 0, width: 100, height: 100))
        let link = arrow(NSPoint(x: 100, y: 50), NSPoint(x: 50, y: 400))
        link.connectedStartID = a.connectorID
        ArrowConnectors.resolve([a, link])
        assertPoint(link.startPoint, 50, 100 + ArrowConnectors.clearance(arrow: link, atStart: true, shape: a))
        assertPoint(link.endPoint, 50, 400)
    }

    func testDeletedShapeLeavesArrowWhereItWas() {
        let link = arrow(NSPoint(x: 10, y: 10), NSPoint(x: 90, y: 90))
        link.connectedStartID = UUID()
        XCTAssertFalse(ArrowConnectors.resolve([link]))
        assertPoint(link.startPoint, 10, 10)
    }

    func testBendTravelsWithTheEnds() {
        let a = rect(NSRect(x: 0, y: 0, width: 100, height: 100))
        let link = arrow(NSPoint(x: 104, y: 50), NSPoint(x: 400, y: 50))
        link.controlPoint = NSPoint(x: 250, y: 120)
        link.connectedStartID = a.connectorID
        ArrowConnectors.resolve([a, link])
        a.move(dx: 0, dy: 40)
        let before = link.controlPoint!
        let startBefore = link.startPoint
        ArrowConnectors.resolve([a, link])
        let startShift = link.startPoint.y - startBefore.y
        XCTAssertEqual(link.controlPoint!.y - before.y, startShift / 2, accuracy: 0.01)
    }

    func testCopiesGetFreshIdentitiesAndKeepInternalLinksOnly() {
        let a = rect(NSRect(x: 0, y: 0, width: 10, height: 10))
        let outside = rect(NSRect(x: 50, y: 0, width: 10, height: 10))
        let link = arrow(.zero, NSPoint(x: 50, y: 5))
        link.connectedStartID = a.connectorID
        link.connectedEndID = outside.connectorID

        let copies = [a.clone(), link.clone()]
        ArrowConnectors.reassignIdentities(copies)
        XCTAssertNotEqual(copies[0].connectorID, a.connectorID)
        XCTAssertEqual(copies[1].connectedStartID, copies[0].connectorID)
        XCTAssertNil(copies[1].connectedEndID, "a copy must not snap onto the original's shape")
    }

    func testConnectionsSurviveSerialization() throws {
        let a = rect(NSRect(x: 0, y: 0, width: 10, height: 10))
        let link = arrow(.zero, NSPoint(x: 50, y: 5))
        link.connectedStartID = a.connectorID
        let data = try XCTUnwrap(AnnotationSerializer.encode([a, link]))
        let decoded = try XCTUnwrap(AnnotationSerializer.decode(data))
        XCTAssertEqual(decoded[1].connectedStartID, decoded[0].connectorID)
    }

    func testClearanceKeepsThickStrokesFromOverlapping() {
        let box = rect(NSRect(x: 0, y: 0, width: 100, height: 100))
        box.strokeWidth = 10
        let link = arrow(.zero, NSPoint(x: 300, y: 50))
        link.strokeWidth = 12
        // Rect paint reaches 5 past its edge, the arrow's round cap 6 past its point.
        XCTAssertEqual(ArrowConnectors.clearance(arrow: link, atStart: true, shape: box), 5 + 6 + ArrowConnectors.gap)

        link.arrowStyle = .tail
        XCTAssertEqual(ArrowConnectors.endExtent(of: link, atStart: true), 24, "tail circle radius")
        XCTAssertEqual(ArrowConnectors.endExtent(of: link, atStart: false), 6)
        link.arrowReversed = true
        XCTAssertEqual(ArrowConnectors.endExtent(of: link, atStart: false), 24, "reversed: the tail is at the end")

        box.rectFillStyle = .fill
        XCTAssertEqual(ArrowConnectors.edgeExtent(of: box), 0, "a fill-only shape has no stroke outside its edge")
    }
}

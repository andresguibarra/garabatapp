import Cocoa
import XCTest

final class ArrowConnectorsTests: XCTestCase {

    private func rect(_ r: NSRect) -> Annotation {
        Annotation(tool: .rectangle, startPoint: r.origin, endPoint: NSPoint(x: r.maxX, y: r.maxY),
                   color: .red, strokeWidth: 2)
    }

    private func arrow(_ a: NSPoint, _ b: NSPoint) -> Annotation {
        let link = Annotation(tool: .arrow, startPoint: a, endPoint: b, color: .red, strokeWidth: 2)
        link.arrowStyle = .single
        return link
    }

    private func assertPoint(_ p: NSPoint, _ x: CGFloat, _ y: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.x, x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(p.y, y, accuracy: 0.001, file: file, line: line)
    }

    func testBorderPointIsTheOutsideOfThePaint() {
        // A 2 pt stroke is centered on the edge: its paint ends 1 pt outside.
        let box = rect(NSRect(x: 0, y: 0, width: 100, height: 50))
        assertPoint(ArrowConnectors.borderPoint(of: box, toward: NSPoint(x: 500, y: 25), gap: 0)!, 101, 25)
        assertPoint(ArrowConnectors.borderPoint(of: box, toward: NSPoint(x: 50, y: 400), gap: 0)!, 50, 51)
    }

    func testSlantedRayKeepsTheFullGapAcrossTheEdge() {
        // Measured perpendicular to the edge, not along the ray.
        let box = rect(NSRect(x: 0, y: 0, width: 100, height: 100))
        let slanted = ArrowConnectors.borderPoint(of: box, toward: NSPoint(x: 1050, y: 550), gap: 14)!
        XCTAssertEqual(slanted.x, 115, accuracy: 0.001, "1 pt of stroke + 14 pt out")
    }

    func testTextBoxUsesItsPillAndOutline() {
        // The pill is 4 pt bigger than the text on every side and its outline
        // stroke (2 pt) reaches 1 pt further: the case that used to pierce it.
        let text = textBox(NSRect(x: 0, y: 0, width: 100, height: 20), outline: true)
        assertPoint(ArrowConnectors.borderPoint(of: text, toward: NSPoint(x: 900, y: 10), gap: 0)!, 105, 10)
        let plain = textBox(NSRect(x: 0, y: 0, width: 100, height: 20), outline: false)
        assertPoint(ArrowConnectors.borderPoint(of: plain, toward: NSPoint(x: 900, y: 10), gap: 0)!, 100, 10)
    }

    func testRoundedCornerFollowsTheCurve() {
        let box = rect(NSRect(x: 0, y: 0, width: 100, height: 100))
        box.rectCornerRadius = 30
        box.rectFillStyle = .fill  // no stroke: the paint is the path itself
        let corner = ArrowConnectors.borderPoint(of: box, toward: NSPoint(x: 1000, y: 1000), gap: 0)!
        // Arc center (70,70), radius 30: the 45° point is 30/√2 past it.
        XCTAssertEqual(corner.x, 70 + 30 / sqrt(2), accuracy: 0.01)
    }

    func testBorderPointOfEllipseAndNumber() {
        let oval = Annotation(tool: .ellipse, startPoint: .zero, endPoint: NSPoint(x: 200, y: 100),
                              color: .red, strokeWidth: 2)
        assertPoint(ArrowConnectors.borderPoint(of: oval, toward: NSPoint(x: 100, y: 999), gap: 0)!, 100, 101)
        assertPoint(ArrowConnectors.borderPoint(of: oval, toward: NSPoint(x: -999, y: 50), gap: 0)!, -1, 50)

        let number = Annotation(tool: .number, startPoint: NSPoint(x: 10, y: 10), endPoint: NSPoint(x: 10, y: 10),
                                color: .red, strokeWidth: 2)
        let radius: CGFloat = 8 + 2 * 3
        assertPoint(ArrowConnectors.borderPoint(of: number, toward: NSPoint(x: 10, y: 100), gap: 0)!, 10, 10 + radius)
    }

    func testRotatedRectangleUsesItsOwnFrame() {
        let box = rect(NSRect(x: -50, y: -10, width: 100, height: 20))
        box.rotation = .pi / 2  // now 20 wide, 100 tall
        let up = ArrowConnectors.borderPoint(of: box, toward: NSPoint(x: 0, y: 500), gap: 0)!
        assertPoint(up, 0, 51)
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

        // 1 pt of rectangle stroke, then the start's 1 pt round cap; the head's tip touches.
        let startGap: CGFloat = 1 + 1
        let endGap: CGFloat = 1
        XCTAssertTrue(ArrowConnectors.resolve([a, b, link]))
        assertPoint(link.startPoint, 100 + startGap, 50)
        assertPoint(link.endPoint, 300 - endGap, 50)
        XCTAssertFalse(ArrowConnectors.resolve([a, b, link]), "resolving again changes nothing")

        b.move(dx: 0, dy: 200)
        XCTAssertTrue(ArrowConnectors.resolve([a, b, link]))
        // Diagonal neighbours: the connector runs corner to corner, each end
        // touching its shape's paint (1 pt stroke) with its own reach.
        XCTAssertGreaterThan(link.endPoint.y, link.startPoint.y)
        XCTAssertFalse(ArrowConnectors.contains(a, point: link.startPoint, margin: 0.99))
        XCTAssertTrue(ArrowConnectors.contains(a, point: link.startPoint, margin: 1.01))
        XCTAssertTrue(ArrowConnectors.contains(b, point: link.endPoint, margin: 0.01))
    }

    func testFacingShapesGetAStraightConnector() {
        // Boxes side by side, one a bit higher: the arrow runs straight across
        // their shared height instead of slanting between the centers.
        let a = rect(NSRect(x: 0, y: 0, width: 100, height: 100))
        let b = rect(NSRect(x: 300, y: 40, width: 100, height: 100))
        let link = arrow(.zero, .zero)
        link.connectedStartID = a.connectorID
        link.connectedEndID = b.connectorID
        ArrowConnectors.resolve([a, b, link])
        XCTAssertEqual(link.startPoint.y, link.endPoint.y, accuracy: 0.05)
        XCTAssertEqual(link.startPoint.x, 102, accuracy: 0.01)
        XCTAssertEqual(link.endPoint.x, 299, accuracy: 0.01)
    }

    func testOneEndedArrowAimsAtItsFreeEnd() {
        let a = rect(NSRect(x: 0, y: 0, width: 100, height: 100))
        let link = arrow(NSPoint(x: 100, y: 50), NSPoint(x: 50, y: 400))
        link.connectedStartID = a.connectorID
        ArrowConnectors.resolve([a, link])
        assertPoint(link.startPoint, 50, 101 + 1)
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

    func testEndPaintFollowsWhatEachStyleDraws() {
        let link = arrow(.zero, NSPoint(x: 300, y: 50))
        link.strokeWidth = 12
        func reach(_ atStart: Bool) -> CGFloat {
            ArrowConnectors.endPaint(of: link, atStart: atStart, length: 300)
                .filter { $0.side == 0 }.map { $0.radius - $0.back }.max()!
        }
        XCTAssertEqual(reach(true), 6, "round cap")
        XCTAssertEqual(reach(false), 0, "filled head ends on its point")
        link.arrowStyle = .tail
        XCTAssertEqual(reach(true), 24, "tail circle radius")
        link.arrowReversed = true
        XCTAssertEqual(reach(false), 24, "reversed: the tail is at the end")
        link.arrowStyle = .open
        XCTAssertEqual(reach(true), 6, "stroked chevron tip")
        link.outlineColor = .black
        XCTAssertEqual(reach(true), 9)
    }

    func testHeadWingsStayOffAShallowEdge() {
        // A wide box hit far from its middle: the ray meets the top edge at a
        // shallow angle, so the head's wing, not its tip, is what touches.
        let wide = rect(NSRect(x: 0, y: 0, width: 400, height: 30))
        let link = arrow(NSPoint(x: 600, y: 120), .zero)
        link.connectedEndID = wide.connectorID
        ArrowConnectors.resolve([wide, link])
        let ux = link.startPoint.x - link.endPoint.x, uy = link.startPoint.y - link.endPoint.y
        let len = hypot(ux, uy)
        let dabs = ArrowConnectors.endPaint(of: link, atStart: false, length: len)
        var closest = -CGFloat.greatestFiniteMagnitude  // signed distance below the top edge
        for dab in dabs {
            let p = NSPoint(x: link.endPoint.x + ux / len * dab.back - uy / len * dab.side,
                            y: link.endPoint.y + uy / len * dab.back + ux / len * dab.side)
            XCTAssertFalse(ArrowConnectors.contains(wide, point: p, margin: dab.radius - 0.01))
            closest = max(closest, wide.boundingRect.maxY + 1 - p.y)
        }
        XCTAssertEqual(closest, 0, accuracy: 0.05, "a wing touches the top edge, nothing crosses it")
    }

    private func textBox(_ r: NSRect, outline: Bool, background: Bool = false) -> Annotation {
        let t = Annotation(tool: .text, startPoint: r.origin, endPoint: NSPoint(x: r.maxX, y: r.maxY),
                           color: .black, strokeWidth: 2)
        t.textDrawRect = r
        t.textImage = ImageProbe.solidImage(width: max(1, Int(r.width)), height: max(1, Int(r.height)), color: CGColor(gray: 0, alpha: 1))
        if outline { t.textOutlineColor = .systemGreen }
        if background { t.textBgColor = .systemYellow }
        return t
    }
}

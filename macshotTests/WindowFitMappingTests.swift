import CoreGraphics
import XCTest

final class WindowFitMappingTests: XCTestCase {
    private let mapping = WindowFitMapping(outputSize: CGSize(width: 800, height: 600))

    func testUnchangedWindowMapsLikeAFixedRegion() {
        let frame = CGRect(x: 100, y: 50, width: 800, height: 600)
        let point = mapping.normalized(CGPoint(x: 500, y: 200), windowFrame: frame)
        XCTAssertEqual(point.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(point.y, 0.25, accuracy: 1e-9)
    }

    func testMovedWindowKeepsRelativePosition() {
        let frame = CGRect(x: 1400, y: 700, width: 800, height: 600)
        let point = mapping.normalized(CGPoint(x: 1400, y: 1300), windowFrame: frame)
        XCTAssertEqual(point.x, 0, accuracy: 1e-9)
        XCTAssertEqual(point.y, 1, accuracy: 1e-9)
    }

    func testWiderWindowIsLetterboxedTopAndBottom() {
        // 1600x600 fits 800x300 inside 800x600: bars of 150 above and below.
        let content = mapping.contentRect(forWindowSize: CGSize(width: 1600, height: 600))
        XCTAssertEqual(content.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(content.width, 1, accuracy: 1e-9)
        XCTAssertEqual(content.minY, 0.25, accuracy: 1e-9)
        XCTAssertEqual(content.height, 0.5, accuracy: 1e-9)
        let frame = CGRect(x: 0, y: 0, width: 1600, height: 600)
        let topLeft = mapping.normalized(.zero, windowFrame: frame)
        XCTAssertEqual(topLeft.y, 0.25, accuracy: 1e-9)
    }

    func testTallerWindowIsPillarboxed() {
        let content = mapping.contentRect(forWindowSize: CGSize(width: 400, height: 600))
        XCTAssertEqual(content.minX, 0.25, accuracy: 1e-9)
        XCTAssertEqual(content.width, 0.5, accuracy: 1e-9)
        XCTAssertEqual(content.height, 1, accuracy: 1e-9)
    }

    func testSmallerWindowWithSameShapeFillsTheVideo() {
        let content = mapping.contentRect(forWindowSize: CGSize(width: 400, height: 300))
        XCTAssertEqual(content, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testDestinationRectCentersInWholePixels() {
        let rect = mapping.destinationRect(forWindowSize: CGSize(width: 1600, height: 600),
                                           pixelSize: CGSize(width: 1600, height: 1200))
        XCTAssertEqual(rect, CGRect(x: 0, y: 300, width: 1600, height: 600))
        let tall = mapping.destinationRect(forWindowSize: CGSize(width: 400, height: 600),
                                           pixelSize: CGSize(width: 1600, height: 1200))
        XCTAssertEqual(tall, CGRect(x: 400, y: 0, width: 800, height: 1200))
    }
}

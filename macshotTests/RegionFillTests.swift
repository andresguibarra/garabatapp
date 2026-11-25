import XCTest

final class RegionFillTests: XCTestCase {
    /// 40×30 white image with a grey panel (x 5..24, rows 4..19) holding a
    /// black "text" block, and a soft horizontal gradient strip at the bottom.
    private func fixture() -> RegionFill {
        let w = 40, h = 30
        var px = [UInt8](repeating: 255, count: w * h * 4)
        func set(_ x: Int, _ y: Int, _ v: UInt8) {
            let i = (y * w + x) * 4
            px[i] = v; px[i + 1] = v; px[i + 2] = v; px[i + 3] = 255
        }
        for y in 4...19 { for x in 5...24 { set(x, y, 200) } }
        for y in 10...12 { for x in 9...15 { set(x, y, 0) } }
        for y in 24...28 { for x in 0..<w { set(x, y, UInt8(100 + x)) } }
        return RegionFill(pixels: px, width: w, height: h)
    }

    func testClickOnPanelSelectsPanelBounds() {
        XCTAssertEqual(fixture().bounds(x: 20, row: 6), CGRect(x: 5, y: 4, width: 20, height: 16))
    }

    func testClickOnTextSelectsOnlyTheText() {
        XCTAssertEqual(fixture().bounds(x: 10, row: 11), CGRect(x: 9, y: 10, width: 7, height: 3))
    }

    func testGradientGrowsAcrossSoftSteps() {
        XCTAssertEqual(fixture().bounds(x: 2, row: 26), CGRect(x: 0, y: 24, width: 40, height: 5))
    }

    func testOutsideImageIsNil() {
        XCTAssertNil(fixture().bounds(x: -1, row: 0))
        XCTAssertNil(fixture().bounds(x: 40, row: 0))
    }
}

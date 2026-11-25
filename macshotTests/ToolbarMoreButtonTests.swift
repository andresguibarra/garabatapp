import XCTest

final class ToolbarMoreButtonTests: XCTestCase {
    private func hidden(_ symbol: String, selected: Bool) -> ToolbarButton {
        var b = ToolbarButton(action: .tool(.highlight), sfSymbol: symbol, tooltip: symbol)
        b.isSelected = selected
        b.isOverflow = true
        return b
    }

    func testMoreShowsEllipsisWhenNoHiddenItemIsActive() {
        let more = ToolbarLayout.moreButton(action: .moreBottom, hidden: [hidden("sun.max", selected: false)])
        XCTAssertEqual(more.sfSymbol, "ellipsis")
        XCTAssertFalse(more.isSelected)
        XCTAssertFalse(more.showsMenuChevron)
    }

    func testMoreTakesTheActiveHiddenToolIcon() {
        let more = ToolbarLayout.moreButton(
            action: .moreBottom,
            hidden: [hidden("face.smiling", selected: false), hidden("sun.max", selected: true)])
        XCTAssertEqual(more.sfSymbol, "sun.max")
        XCTAssertTrue(more.isSelected)
        XCTAssertTrue(more.showsMenuChevron)
    }

    func testBottomStripMoreFollowsSelectedHiddenTool() {
        let buttons = ToolbarLayout.withMoreButton(
            [hidden("sun.max", selected: true)], action: .moreBottom)
        XCTAssertEqual(buttons.last?.sfSymbol, "sun.max")
    }
}

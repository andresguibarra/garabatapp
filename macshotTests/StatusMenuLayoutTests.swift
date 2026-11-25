import AppKit
import XCTest

final class StatusMenuLayoutTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "StatusMenuLayoutTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testDefaultHasEveryItemOnceAndAllInTheMenu() {
        let layout = StatusMenuLayout.default
        XCTAssertEqual(Set(layout.allItems), Set(StatusMenuItemID.allCases))
        XCTAssertEqual(layout.allItems.count, StatusMenuItemID.allCases.count)
        XCTAssertTrue(layout.more.isEmpty)
        XCTAssertTrue(layout.hidden.isEmpty)
        XCTAssertEqual(layout, layout.normalized())
    }

    func testNothingSavedLoadsTheDefault() {
        XCTAssertEqual(StatusMenuLayout.load(defaults: defaults), .default)
    }

    func testSaveAndLoadRoundTrip() {
        var layout = StatusMenuLayout.default
        let pin = layout.menu.firstIndex(of: .item(.pinFromClipboard))!
        XCTAssertTrue(layout.move(from: (.menu, pin), to: (.more, 0)))
        let video = layout.menu.firstIndex(of: .item(.openVideo))!
        XCTAssertTrue(layout.move(from: (.menu, video), to: (.hidden, 0)))
        layout.save(defaults: defaults)
        XCTAssertEqual(StatusMenuLayout.load(defaults: defaults), layout)
    }

    func testLockedItemsCantLeaveTheMenu() {
        var layout = StatusMenuLayout.default
        for id in [StatusMenuItemID.settings, .quit, .more] {
            let index = layout.menu.firstIndex(of: .item(id))!
            XCTAssertFalse(layout.move(from: (.menu, index), to: (.hidden, 0)))
            XCTAssertFalse(layout.move(from: (.menu, index), to: (.more, 0)))
        }
        XCTAssertEqual(layout, .default)
        // …but they can move inside the menu.
        let quit = layout.menu.firstIndex(of: .item(.quit))!
        XCTAssertTrue(layout.move(from: (.menu, quit), to: (.menu, 0)))
        XCTAssertEqual(layout.menu.first, .item(.quit))
    }

    func testDroppingASeparatorInHiddenRemovesIt() {
        var layout = StatusMenuLayout.default
        let separators = layout.menu.filter { $0 == .separator }.count
        let index = layout.menu.firstIndex(of: .separator)!
        XCTAssertTrue(layout.move(from: (.menu, index), to: (.hidden, 0)))
        XCTAssertEqual(layout.menu.filter { $0 == .separator }.count, separators - 1)
        XCTAssertTrue(layout.hidden.isEmpty)
    }

    func testCorruptStoredLayoutIsRepaired() {
        defaults.set([
            "menu": ["captureScreen", "bogus", "captureScreen", "-"],
            "more": ["quit", "openVideo", "-"],
            "hidden": ["settings", "-", "recordGIF", 42],
        ], forKey: StatusMenuLayout.userDefaultsKey)
        let layout = StatusMenuLayout.load(defaults: defaults)

        XCTAssertEqual(layout.allItems.count, StatusMenuItemID.allCases.count, "every item exactly once")
        XCTAssertEqual(Set(layout.allItems), Set(StatusMenuItemID.allCases))
        XCTAssertEqual(layout.zone(of: .quit), .menu)
        XCTAssertEqual(layout.zone(of: .settings), .menu)
        XCTAssertEqual(layout.zone(of: .openVideo), .more)
        XCTAssertEqual(layout.zone(of: .recordGIF), .hidden)
        XCTAssertFalse(layout.hidden.contains(.separator))
        XCTAssertEqual(layout.menu.first, .item(.captureScreen))
    }

    func testItemsMissingFromAnOlderLayoutJoinTheMenuNextToTheirDefaultNeighbour() {
        defaults.set([
            "menu": ["captureArea", "recordArea", "settings", "quit"],
            "more": [], "hidden": [],
        ], forKey: StatusMenuLayout.userDefaultsKey)
        let layout = StatusMenuLayout.load(defaults: defaults)
        XCTAssertEqual(Array(layout.menu.prefix(2)), [.item(.captureArea), .item(.captureScreen)])
        XCTAssertEqual(layout.zone(of: .pinFromClipboard), .menu)
    }

    func testLegacyCaptureOrderIsKept() {
        defaults.set(["scrollCapture", "captureArea"], forKey: CaptureMenuItemID.userDefaultsKey)
        let layout = StatusMenuLayout.load(defaults: defaults)
        XCTAssertEqual(Array(layout.menu.prefix(2)), [.item(.scrollCapture), .item(.captureArea)])
        XCTAssertEqual(CaptureMenuItemID.orderedItems(defaults: defaults).first, .scrollCapture)
    }

    func testResetForgetsLegacyOrderToo() {
        defaults.set(["scrollCapture"], forKey: CaptureMenuItemID.userDefaultsKey)
        StatusMenuLayout.default.save(defaults: defaults)
        StatusMenuLayout.reset(defaults: defaults)
        XCTAssertEqual(StatusMenuLayout.load(defaults: defaults), .default)
    }

    func testDisplayEntriesCollapseSeparatorsAndDropEmptyMore() {
        let entries: [StatusMenuEntry] = [.separator, .item(.captureArea), .separator, .separator,
                                          .item(.more), .separator, .item(.quit), .separator]
        XCTAssertEqual(StatusMenuLayout.displayEntries(entries, moreIsEmpty: true),
                       [.item(.captureArea), .separator, .item(.quit)])
        XCTAssertEqual(StatusMenuLayout.displayEntries(entries, moreIsEmpty: false),
                       [.item(.captureArea), .separator, .item(.more), .separator, .item(.quit)])
    }

    func testAddSeparatorGoesAboveMore() {
        var layout = StatusMenuLayout.default
        layout.addSeparator()
        let more = layout.menu.firstIndex(of: .item(.more))!
        XCTAssertEqual(layout.menu[more - 1], .separator)
        XCTAssertEqual(layout.menu[more - 2], .separator)
    }
}

@MainActor
final class StatusMenuLayoutEditorTests: XCTestCase {

    private func makeEditor() -> StatusMenuLayoutEditorView {
        let editor = StatusMenuLayoutEditorView(layout: .default)
        editor.frame = NSRect(x: 0, y: 0, width: 420, height: editor.intrinsicContentSize.height)
        editor.layoutSubtreeIfNeeded()
        return editor
    }

    func testDraggingARowIntoMoreMovesIt() {
        let editor = makeEditor()
        var reported: StatusMenuLayout?
        editor.onChange = { reported = $0 }
        let pin = StatusMenuLayout.default.menu.firstIndex(of: .item(.pinFromClipboard))!
        let moreBox = editor.sectionBoxFrame(.more)!
        editor.simulateDrag(from: (.menu, pin), toY: moreBox.midY)
        XCTAssertEqual(editor.layout.more, [.item(.pinFromClipboard)])
        XCTAssertEqual(reported?.more, [.item(.pinFromClipboard)])
        XCTAssertNil(editor.layout.menu.firstIndex(of: .item(.pinFromClipboard)))
    }

    func testDraggingQuitToHiddenIsRefused() {
        let editor = makeEditor()
        var changes = 0
        editor.onChange = { _ in changes += 1 }
        let quit = StatusMenuLayout.default.menu.firstIndex(of: .item(.quit))!
        editor.simulateDrag(from: (.menu, quit), toY: editor.sectionBoxFrame(.hidden)!.midY)
        XCTAssertEqual(editor.layout, .default)
        XCTAssertEqual(changes, 0)
    }

    func testReorderingInsideTheMenu() {
        let editor = makeEditor()
        let scroll = StatusMenuLayout.default.menu.firstIndex(of: .item(.scrollCapture))!
        let top = editor.rowFrame(zone: .menu, index: 0)!
        editor.simulateDrag(from: (.menu, scroll), toY: top.minY + 2)
        XCTAssertEqual(editor.layout.menu.first, .item(.scrollCapture))
        XCTAssertEqual(Set(editor.layout.allItems), Set(StatusMenuItemID.allCases))
    }

    func testContextMenuMoves() {
        let editor = makeEditor()
        let video = StatusMenuLayout.default.menu.firstIndex(of: .item(.openVideo))!
        XCTAssertTrue(editor.move(from: (.menu, video), to: .hidden))
        XCTAssertEqual(editor.layout.hidden, [.item(.openVideo)])
        XCTAssertTrue(editor.move(from: (.hidden, 0), to: .menu))
        XCTAssertEqual(editor.layout.zone(of: .openVideo), .menu)
        let settings = editor.layout.menu.firstIndex(of: .item(.settings))!
        XCTAssertFalse(editor.move(from: (.menu, settings), to: .more))
    }
}

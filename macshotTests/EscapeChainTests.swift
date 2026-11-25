import Cocoa
import XCTest

/// Escape after drawing: one press deselects AND puts the drawing tool down
/// (back to Select & Move), so the next press closes.
@MainActor
final class EscapeChainTests: XCTestCase {
    private let selection = NSRect(x: 80, y: 60, width: 200, height: 150)
    private let settings: [String: Any?] = [
        "startCapturesInMoveMode": false,
        "rememberLastTool": false,
        "boundarySnapEnabled": false,
        "doubleClickToCopy": false,
        "openEditorAfterSelection": false,
        "beautifyEnabled": false,
    ]

    private func mouse(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private var escape: NSEvent {
        TestKeyEvent.keyDown(characters: "\u{1b}", keyCode: TestKeyEvent.Code.escape)
    }

    func testOneEscapeAfterDrawingDeselectsAndReturnsToSelect() {
        withDefaults(settings) {
            let view = OverlayView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
            view.screenshotImage = ImageProbe.quadrantImage(width: 500, height: 400)
            view.applySelection(selection)
            for tool: AnnotationTool in [.rectangle, .arrow, .ellipse, .pencil] {
                view.handleToolbarAction(.tool(tool))
                view.mouseDown(with: mouse(.leftMouseDown, at: NSPoint(x: 120, y: 100)))
                view.mouseDragged(with: mouse(.leftMouseDragged, at: NSPoint(x: 160, y: 140)))
                view.mouseDragged(with: mouse(.leftMouseDragged, at: NSPoint(x: 200, y: 170)))
                view.mouseUp(with: mouse(.leftMouseUp, at: NSPoint(x: 200, y: 170)))
                XCTAssertEqual(view.currentTool, tool)
                // Selected or not after drawing, a single Escape lands on Select & Move.
                view.keyDown(with: escape)
                XCTAssertEqual(view.currentTool, .select, "\(tool)")
            }
        }
    }
}

import Cocoa
import XCTest

/// Cropping keeps only what the user framed: annotations left entirely outside
/// the crop are removed (undo brings them back), and ones the crop cuts through
/// stay clipped to it instead of growing the canvas back on the next edit.
@MainActor
final class CropAnnotationsTests: XCTestCase {

    private func makeEditor(width: CGFloat = 400, height: CGFloat = 300) -> EditorView {
        let view = EditorView()
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.layoutEditorDocument(forImageSize: NSSize(width: width, height: height))
        view.screenshotImage = ImageProbe.quadrantImage(width: Int(width), height: Int(height))
        view.applySelection(NSRect(x: 0, y: 0, width: width, height: height))
        return view
    }

    private func crop(_ editor: EditorView, to rect: NSRect) {
        editor.areaRect = rect
        editor.cropToArea()
    }

    func testAnnotationsOutsideTheCropAreRemovedAndComeBackOnUndo() {
        let editor = makeEditor()
        let inside = Annotation(tool: .rectangle, startPoint: NSPoint(x: 220, y: 20),
                                endPoint: NSPoint(x: 300, y: 80), color: .red, strokeWidth: 3)
        let outside = Annotation(tool: .arrow, startPoint: NSPoint(x: 20, y: 200),
                                 endPoint: NSPoint(x: 120, y: 280), color: .red, strokeWidth: 3)
        let text = Annotation(tool: .text, startPoint: NSPoint(x: 30, y: 250),
                              endPoint: NSPoint(x: 130, y: 280), color: .red, strokeWidth: 3)
        text.text = "Whaaat?"
        editor.annotations = [outside, inside, text]

        crop(editor, to: NSRect(x: 200, y: 0, width: 200, height: 150))
        XCTAssertEqual(editor.selectionRect.size, NSSize(width: 200, height: 150))
        XCTAssertTrue(editor.annotations.count == 1 && editor.annotations[0] === inside)

        // A later edit must not grow the canvas back.
        editor.expandCanvasToFitAnnotations()
        XCTAssertEqual(editor.selectionRect.size, NSSize(width: 200, height: 150))

        editor.undo()
        XCTAssertEqual(editor.selectionRect.size, NSSize(width: 400, height: 300))
        XCTAssertTrue(editor.annotations.count == 3 && editor.annotations[0] === outside
                      && editor.annotations[2] === text, "same objects, same order")
        XCTAssertEqual(outside.startPoint, NSPoint(x: 20, y: 200))

        editor.redo()
        XCTAssertEqual(editor.selectionRect.size, NSSize(width: 200, height: 150))
        XCTAssertTrue(editor.annotations.count == 1 && editor.annotations[0] === inside)
        editor.undo()
        XCTAssertEqual(editor.annotations.count, 3)
    }

    func testAnAnnotationTheCropCutsStaysClippedUntilMoved() {
        let editor = makeEditor()
        let rect = Annotation(tool: .rectangle, startPoint: NSPoint(x: 150, y: 20),
                              endPoint: NSPoint(x: 260, y: 80), color: .red, strokeWidth: 3)
        editor.annotations = [rect]

        crop(editor, to: NSRect(x: 200, y: 0, width: 200, height: 150))
        XCTAssertEqual(editor.annotations.count, 1, "partly inside: kept")
        editor.expandCanvasToFitAnnotations()
        XCTAssertEqual(editor.selectionRect.size, NSSize(width: 200, height: 150),
                       "the crop is the edge; the cut part does not come back")

        // Once the user moves it, it is an ordinary annotation past the edge again.
        rect.move(dx: -10, dy: 0)
        editor.expandCanvasToFitAnnotations()
        XCTAssertGreaterThan(editor.selectionRect.width, 200)
    }

    func testDrawingPastTheEdgeAfterACropStillGrowsTheCanvas() {
        let editor = makeEditor()
        crop(editor, to: NSRect(x: 0, y: 0, width: 200, height: 150))
        let text = Annotation(tool: .rectangle, startPoint: NSPoint(x: 150, y: 20),
                              endPoint: NSPoint(x: 260, y: 80), color: .red, strokeWidth: 3)
        editor.annotations.append(text)
        editor.expandCanvasToFitAnnotations()
        XCTAssertGreaterThan(editor.selectionRect.width, 200)
    }
}

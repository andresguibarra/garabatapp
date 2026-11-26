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

/// The area the canvas grows into takes the capture's border color; only a
/// mostly transparent border (a window shadow) leaves it transparent.
@MainActor
final class CanvasFillColorTests: XCTestCase {

    private func image(width: Int = 60, height: Int = 40, draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx)
        return ctx.makeImage()!
    }

    func testRoundedTransparentCornersStillGiveTheBorderColor() throws {
        let cg = image { ctx in
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
            // Transparent corners, like a rounded or anti-aliased edge.
            for (x, y) in [(0, 0), (1, 0), (0, 1), (59, 39), (58, 39), (59, 38), (0, 39), (59, 0)] {
                ctx.clear(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let color = try XCTUnwrap(OverlayView.borderFillColor(of: cg)?.usingColorSpace(.sRGB))
        XCTAssertEqual(color.redComponent, 1, accuracy: 0.02)
        XCTAssertEqual(color.greenComponent, 1, accuracy: 0.02)
        XCTAssertEqual(color.blueComponent, 1, accuracy: 0.02)
    }

    func testATransparentBorderStaysTransparent() {
        let cg = image { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
            ctx.fill(CGRect(x: 6, y: 6, width: 48, height: 28))
        }
        XCTAssertNil(OverlayView.borderFillColor(of: cg))
    }
}

import Cocoa

/// An `NSTextView` whose editing history is scoped to the lifetime of the view.
///
/// A regular text view obtains its undo manager from the responder chain, which
/// can leave a longer-lived window undo manager holding operations for a text
/// view that has already been removed. Keeping the manager here also prevents
/// temporary text edits from polluting the owning window's undo history.
class ScopedUndoTextView: NSTextView {
    private let scopedUndoManager = UndoManager()

    override var undoManager: UndoManager? { scopedUndoManager }

    /// Lets the owner keep its own cursor (e.g. a resize handle that overlaps the
    /// text view's edge): return true for a window-space point and the text view
    /// won't reset it to the I-beam.
    var ownerHandlesCursor: ((NSPoint) -> Bool)?

    override func mouseMoved(with event: NSEvent) {
        if ownerHandlesCursor?(event.locationInWindow) == true { return }
        super.mouseMoved(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        if ownerHandlesCursor?(event.locationInWindow) == true { return }
        super.cursorUpdate(with: event)
    }

    /// Clears both undo and redo operations before an editing session is torn down.
    func discardUndoHistory() {
        scopedUndoManager.removeAllActions()
    }
}

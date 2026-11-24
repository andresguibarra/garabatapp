import Cocoa

/// Handles arrow tool interaction.
/// Same as line but also applies arrow style.
final class ArrowToolHandler: AnnotationToolHandler {

    let tool: AnnotationTool = .arrow

    func start(at point: NSPoint, canvas: AnnotationCanvas) -> Annotation? {
        let annotation = Annotation(
            tool: .arrow,
            startPoint: point,
            endPoint: point,
            color: canvas.opacityAppliedColor(for: .arrow),
            strokeWidth: canvas.currentStrokeWidth
        )
        annotation.lineStyle = canvas.currentLineStyle
        annotation.arrowStyle = canvas.currentArrowStyle
        annotation.arrowReversed = canvas.arrowReversed
        return annotation
    }

    func update(to point: NSPoint, shiftHeld: Bool, canvas: AnnotationCanvas) {
        guard let annotation = canvas.activeAnnotation else { return }
        var clampedPoint = point

        if shiftHeld {
            clampedPoint = snap45(point, from: annotation.startPoint)
            canvas.snapGuideX = nil
            canvas.snapGuideY = nil
        } else {
            clampedPoint = canvas.snapPoint(point, excluding: annotation)
        }

        annotation.endPoint = clampedPoint

        // Started on a shape's border: dropping the tip on another shape attaches it there.
        if let startID = annotation.connectedStartID {
            let source = canvas.annotations.first { $0.connectorID == startID }
            let target = ArrowConnectors.dropTarget(
                in: canvas.annotations, at: point, margin: 6, excluding: [startID])
            canvas.connectorDropTarget = target
            if let target, let snapped = ArrowConnectors.borderPoint(
                of: target, toward: source.flatMap { ArrowConnectors.center(of: $0) } ?? annotation.startPoint) {
                annotation.endPoint = snapped
                canvas.snapGuideX = nil
                canvas.snapGuideY = nil
            }
            if let source {
                ArrowConnectors.update(annotation, from: source, to: target)
            }
        }
    }

    func finish(canvas: AnnotationCanvas) {
        let dropTarget = canvas.connectorDropTarget
        canvas.connectorDropTarget = nil
        guard let annotation = canvas.activeAnnotation else { return }
        if annotation.connectedStartID != nil, let target = dropTarget {
            annotation.connectedEndID = target.connectorID
        }
        let dx = abs(annotation.endPoint.x - annotation.startPoint.x)
        let dy = abs(annotation.endPoint.y - annotation.startPoint.y)
        guard dx > 2 || dy > 2 else {
            canvas.activeAnnotation = nil
            canvas.setNeedsDisplay()
            return
        }
        commitAnnotation(annotation, canvas: canvas)
    }
}

import Cocoa
import QuartzCore

/// Garabatapp: "card" flip animation for the editor's Flip Horizontal / Flip
/// Vertical buttons. The flip itself happens instantly (same undo entry, same
/// pixels); this only plays a 3D turn over a snapshot of the visible canvas:
/// the old picture turns away to 90°, the flipped one turns in from -90°.
@MainActor
enum EditorFlipAnimator {
    enum Axis { case horizontal, vertical }

    private static let halfDuration: CFTimeInterval = 0.175
    private static weak var currentHost: NSView?

    static func flip(_ view: OverlayView, axis: Axis, perform: () -> Void) {
        currentHost?.removeFromSuperview()
        currentHost = nil

        guard view.isEditorMode,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let content = view.window?.contentView
        else { perform(); return }

        let visible = view.captureDrawRect.intersection(view.visibleRect).integral
        guard visible.width >= 2, visible.height >= 2,
              let before = snapshot(view, visible) else { perform(); return }

        perform()
        view.displayIfNeeded()
        guard let after = snapshot(view, visible) else { return }

        let host = PassthroughLayerView(frame: view.convert(visible, to: content))
        host.wantsLayer = true
        guard let hostLayer = host.layer else { return }
        hostLayer.backgroundColor = (view.enclosingScrollView?.backgroundColor
            ?? NSColor(white: 0.15, alpha: 1)).cgColor
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 900.0
        hostLayer.sublayerTransform = perspective

        let card = CALayer()
        card.frame = hostLayer.bounds
        card.contents = before
        card.contentsGravity = .resize
        card.isDoubleSided = false
        hostLayer.addSublayer(card)

        content.addSubview(host, positioned: .above, relativeTo: nil)
        currentHost = host

        let (x, y): (CGFloat, CGFloat) = axis == .horizontal ? (0, 1) : (1, 0)
        let edgeOn = CATransform3DMakeRotation(.pi / 2, x, y, 0)
        let edgeOnIn = CATransform3DMakeRotation(-.pi / 2, x, y, 0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        card.transform = edgeOn
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak host, weak card] in
            guard let host, let card, host.superview != nil else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            card.contents = after
            card.transform = CATransform3DIdentity
            CATransaction.commit()

            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak host] in
                host?.removeFromSuperview()
            }
            let turnIn = CABasicAnimation(keyPath: "transform")
            turnIn.fromValue = NSValue(caTransform3D: edgeOnIn)
            turnIn.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            turnIn.duration = halfDuration
            turnIn.timingFunction = CAMediaTimingFunction(name: .easeOut)
            card.add(turnIn, forKey: "turnIn")
            CATransaction.commit()
        }
        let turnAway = CABasicAnimation(keyPath: "transform")
        turnAway.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        turnAway.toValue = NSValue(caTransform3D: edgeOn)
        turnAway.duration = halfDuration
        turnAway.timingFunction = CAMediaTimingFunction(name: .easeIn)
        card.add(turnAway, forKey: "turnAway")
        CATransaction.commit()
    }

    private static func snapshot(_ view: NSView, _ rect: NSRect) -> CGImage? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: rep)
        return rep.cgImage
    }
}

/// Layer host that never takes clicks, so the canvas stays usable mid-animation.
private final class PassthroughLayerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

import Cocoa

@MainActor
final class CanvasOutsideProbe: NSObject, NSApplicationDelegate {
    private let output: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("canvas-outside-probe", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    private var failures = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "beautifyEnabled")
        UserDefaults.standard.set(0, forKey: "historySize")
        log("OUTPUT \(output.path)")
        Task { @MainActor in
            await run()
            log("DONE failures=\(failures)")
            NSApp.terminate(nil)
        }
    }

    private func run() async {
        // A narrow capture (like one just cropped) in a wide window.
        DetachedEditorWindowController.open(image: makeImage(width: 420, height: 640))
        await pause(0.8)
        guard let (window, editor) = findEditor() else { return fail("editor did not open") }
        window.setFrame(NSRect(x: 60, y: 60, width: 1500, height: 950), display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        await pause(0.5)
        snap(window, "01-narrow-canvas")
        let image = editor.selectionRect
        log("canvas \(image) docFrame \(editor.frame)")

        // Text far to the left of the capture, well past the old 40 pt margin.
        editor.handleToolbarAction(.tool(.text))
        await pause(0.2)
        let textPoint = NSPoint(x: -380, y: image.midY)
        let clickWindow = editor.convert(textPoint, to: nil)
        let content = window.contentView!
        let hit = content.hitTest(content.convert(clickWindow, from: nil))
        check(hit is EditorView, "click left of the capture reaches the editor (\(hit.map { String(describing: type(of: $0)) } ?? "nil"))")
        let imageOriginBefore = editor.convert(NSPoint.zero, to: nil)
        await mouse(.leftMouseDown, editor, textPoint)
        await mouse(.leftMouseUp, editor, textPoint)
        await pause(0.3)
        guard let tv = editor.textEditView, let box = tv.enclosingScrollView else { return fail("no text box opened") }
        let boxTopLeftWindow = editor.convert(NSPoint(x: box.frame.minX, y: box.frame.maxY), to: nil)
        check(abs(boxTopLeftWindow.x - clickWindow.x) < 2 && abs(boxTopLeftWindow.y - clickWindow.y) < 2,
              "text box opened right where clicked (click \(clickWindow), box \(boxTopLeftWindow))")
        let imageOriginAfter = editor.convert(NSPoint.zero, to: nil)
        check(abs(imageOriginAfter.x - imageOriginBefore.x) < 1 && abs(imageOriginAfter.y - imageOriginBefore.y) < 1,
              "capture did not move on screen when the box opened (\(imageOriginBefore) -> \(imageOriginAfter))")
        let visibleInDoc = editor.visibleRect.contains(box.frame.insetBy(dx: 1, dy: 1))
        check(visibleInDoc, "text box is inside the document, not cut off (box \(box.frame), visible \(editor.visibleRect))")
        tv.insertText("Texto afuera", replacementRange: NSRange(location: NSNotFound, length: 0))
        await pause(0.3)
        snap(window, "02-typing-outside")
        editor.commitTextFieldIfNeeded()
        await pause(0.5)
        check(editor.annotations.contains { $0.tool == .text }, "text annotation committed")
        check(editor.selectionRect.width > image.width + 300, "canvas grew left to the text (\(editor.selectionRect))")
        snap(window, "03-text-committed-canvas-grown")

        // Rectangle drawn in the empty area right of the capture.
        editor.handleToolbarAction(.tool(.rectangle))
        await pause(0.2)
        let canvasNow = editor.selectionRect
        let count = editor.annotations.count
        let from = NSPoint(x: canvasNow.maxX + 120, y: canvasNow.midY + 120)
        let to = NSPoint(x: canvasNow.maxX + 260, y: canvasNow.midY - 40)
        await drag(editor, from: from, to: to, steps: 8, release: false)
        snap(window, "04-rectangle-dragging-outside")
        await mouse(.leftMouseUp, editor, to)
        await pause(0.5)
        check(editor.annotations.count == count + 1, "rectangle drawn outside the capture")
        check(editor.selectionRect.width > canvasNow.width + 200, "canvas grew right to the rectangle (\(editor.selectionRect))")
        snap(window, "05-rectangle-committed")

        // Arrow from inside the capture to far below-left of it is unaffected; just check undo restores.
        editor.undo(); await pause(0.1)
        editor.undo(); await pause(0.1)
        editor.undo(); await pause(0.1)
        editor.undo(); await pause(0.3)
        check(editor.selectionRect.size == image.size, "undo brings back the original canvas (\(editor.selectionRect))")
        snap(window, "06-after-undo")

        // Typing a long text past the edge: the view zooms out so all of it stays visible.
        editor.handleToolbarAction(.tool(.text))
        await pause(0.2)
        let longPoint = NSPoint(x: -300, y: image.maxY - 20)
        await mouse(.leftMouseDown, editor, longPoint)
        await mouse(.leftMouseUp, editor, longPoint)
        await pause(0.3)
        guard let tv2 = editor.textEditView, let box2 = tv2.enclosingScrollView, let sv = editor.enclosingScrollView
        else { return fail("no second text box") }
        for i in 1...40 {
            tv2.insertText(i == 1 ? "Linea 1" : "\nLinea \(i)", replacementRange: NSRange(location: NSNotFound, length: 0))
            editor.textDidChange(Notification(name: NSText.didChangeNotification))
            await pause(0.02)
        }
        await pause(0.3)
        let visible = sv.contentView.documentVisibleRect
        log("long text box \(box2.frame) magnification \(sv.magnification) visible \(visible)")
        check(sv.magnification < 0.999, "zoomed out while the text outgrew the window (\(sv.magnification))")
        check(visible.contains(box2.frame.insetBy(dx: 1, dy: 1)), "whole text box visible while typing")
        let zoomLabel = find(NSButton.self, in: window.contentView!, where: { $0.title.hasSuffix("% ▾") })?.title ?? "none"
        check(zoomLabel == "\(Int(sv.magnification * 100))% ▾", "zoom label follows the fit (\(zoomLabel))")
        snap(window, "07-long-text-zoomed-out")
        editor.commitTextFieldIfNeeded()
        await pause(0.5)
        check(editor.selectionRect.height > image.height + 300, "canvas grew down to the long text (\(editor.selectionRect))")
        let visibleAfter = sv.contentView.documentVisibleRect
        check(visibleAfter.contains(editor.selectionRect), "whole canvas visible after commit (\(visibleAfter))")
        snap(window, "08-long-text-committed")
    }

    private func findEditor() -> (NSWindow, EditorView)? {
        for window in NSApp.windows.reversed() where window.isVisible {
            if let view = find(EditorView.self, in: window.contentView ?? NSView(), where: { _ in true }) {
                return (window, view)
            }
        }
        return nil
    }

    private func find<T: NSView>(_ type: T.Type, in root: NSView, where predicate: (T) -> Bool) -> T? {
        if let match = root as? T, predicate(match) { return match }
        for sub in root.subviews {
            if let found = find(type, in: sub, where: predicate) { return found }
        }
        return nil
    }

    private var popoverWindows: [NSWindow] {
        NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
    }

    private func popoverView<T: NSView>(_ type: T.Type, where predicate: (T) -> Bool) -> T? {
        for window in popoverWindows {
            if let root = window.contentView, let found = find(type, in: root, where: predicate) { return found }
        }
        return nil
    }

    private func popoverButton(titled title: String) -> NSButton? {
        popoverView(NSButton.self, where: { $0.title == title })
    }

    private func mouse(_ type: NSEvent.EventType, _ view: NSView, _ canvasPoint: NSPoint) async {
        guard let window = view.window else { return }
        let point = view.convert(canvasPoint, to: nil)
        guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil,
                                             eventNumber: 0, clickCount: 1, pressure: 1) else { return }
        NSApp.sendEvent(event)
        await pause(0.03)
    }

    private func drag(_ view: NSView, from: NSPoint, to: NSPoint, steps: Int, release: Bool = true) async {
        await mouse(.leftMouseDown, view, from)
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            await mouse(.leftMouseDragged, view, NSPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
        }
        if release { await mouse(.leftMouseUp, view, to) }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func write(_ view: NSView, _ name: String) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = output.appendingPathComponent(name + ".png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        log("SNAP \(url.path)")
    }

    private func snap(_ window: NSWindow, _ name: String) {
        window.displayIfNeeded()
        if let content = window.contentView { write(content, name) }
    }

    private func snapPopover(_ name: String) {
        guard let window = popoverWindows.last, let content = window.contentView else { return log("no popover for \(name)") }
        write(content.superview ?? content, name)
    }

    private func snapSheet(_ window: NSWindow, _ name: String) {
        guard let sheet = window.attachedSheet, let content = sheet.contentView else { return log("no sheet for \(name)") }
        write(content.superview ?? content, name)
    }

    private func check(_ condition: Bool, _ message: String) {
        if condition { log("PASS \(message)") } else { fail(message) }
    }

    private func fail(_ message: String) {
        failures += 1
        log("FAIL \(message)")
    }

    private func log(_ message: String) {
        print(message)
        fflush(stdout)
    }

    private func makeImage(width: Int = 900, height: Int = 560, hue: CGFloat = 0.58) -> NSImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let base = NSColor(hue: hue, saturation: 0.45, brightness: 0.35, alpha: 1)
        context.setFillColor(base.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor(hue: hue, saturation: 0.3, brightness: 0.8, alpha: 1).cgColor)
        for i in 0..<6 {
            context.fill(CGRect(x: 30 + i * width / 7, y: height / 3, width: width / 9, height: height / 3))
        }
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: width, height: height))
    }
}

let probeApplication = NSApplication.shared
let probeDelegate = MainActor.assumeIsolated { CanvasOutsideProbe() }
probeApplication.delegate = probeDelegate
probeApplication.setActivationPolicy(.regular)
probeApplication.run()
withExtendedLifetime(probeDelegate) {}

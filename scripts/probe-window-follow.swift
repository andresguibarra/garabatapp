// Real ScreenCaptureKit probe for window-follow recording (same config as RecordingEngine).
// Build from the repo root: swiftc -O -default-isolation MainActor -parse-as-library macshot/Capture/WindowFollowTracker.swift scripts/probe-window-follow.swift -o /tmp/wf-probe
// Run: /tmp/wf-probe <output-dir>   (needs Screen Recording permission; shows a red test window for ~5 s)
import Cocoa
import ScreenCaptureKit
import CoreMedia

final class FrameSink: NSObject, SCStreamOutput, @unchecked Sendable {
    let lock = NSLock()
    var latest: CVPixelBuffer?
    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pb = sb.imageBuffer else { return }
        // Only complete frames carry pixels.
        if let att = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
           let raw = att[.status] as? Int, raw != SCFrameStatus.complete.rawValue { return }
        lock.lock(); latest = pb; lock.unlock()
    }
}

final class PatternView: NSView {
    override func draw(_ r: NSRect) {
        NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1).setFill(); bounds.fill()
        // blue dot at 25% x, 25% from the top
        NSColor.blue.setFill()
        let p = NSPoint(x: bounds.width * 0.25, y: bounds.height * 0.75)
        NSBezierPath(ovalIn: NSRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)).fill()
    }
}

@main
struct Probe {
    static func main() async {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let win = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = PatternView(); win.level = .floating; win.hasShadow = true
        win.orderFrontRegardless()
        try? await Task.sleep(nanoseconds: 500_000_000)
        let wid = CGWindowID(win.windowNumber)
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let scw = content.windows.first(where: { $0.windowID == wid }) else { print("FAIL no window / permission"); exit(1) }
        let start = WindowFollowTracker.bounds(of: wid)!
        let scale = win.backingScaleFactor
        let cfg = SCStreamConfiguration()
        cfg.width = Int(start.width * scale); cfg.height = Int(start.height * scale)
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.scalesToFit = true
        cfg.backgroundColor = CGColor.black
        if #available(macOS 14.0, *) { cfg.ignoreShadowsSingleWindow = true; cfg.preservesAspectRatio = true }
        let sink = FrameSink()
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: scw), configuration: cfg, delegate: nil)
        try! stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: DispatchQueue(label: "f"))
        try! await stream.startCapture()
        let mapping = WindowFitMapping(outputSize: start.size)
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp"
        var failures = 0
        let steps: [(String, NSRect)] = [
            ("start", NSRect(x: 200, y: 200, width: 600, height: 400)),
            ("moved", NSRect(x: 700, y: 350, width: 600, height: 400)),
            ("wider", NSRect(x: 300, y: 250, width: 900, height: 400)),
            ("taller", NSRect(x: 300, y: 150, width: 400, height: 600)),
            ("smaller", NSRect(x: 400, y: 300, width: 300, height: 200)),
        ]
        for (name, rect) in steps {
            win.setFrame(rect, display: true); win.contentView?.needsDisplay = true
            // Same re-centering RecordingEngine.followedWindowDidResize does.
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let size = WindowFollowTracker.bounds(of: wid)?.size {
                cfg.destinationRect = mapping.destinationRect(forWindowSize: size,
                    pixelSize: CGSize(width: cfg.width, height: cfg.height))
                try? await stream.updateConfiguration(cfg)
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            sink.lock.lock(); let pb = sink.latest; sink.lock.unlock()
            guard let pb else { print("FAIL \(name): no frame"); failures += 1; continue }
            let ci = CIImage(cvPixelBuffer: pb)
            let rep = NSBitmapImageRep(ciImage: ci)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/wf-\(name).png"))
            let w = rep.pixelsWide, h = rep.pixelsHigh
            // red content bbox
            var minX = w, minY = h, maxX = -1, maxY = -1, bx = 0.0, by = 0.0, bn = 0.0
            for y in stride(from: 0, to: h, by: 1) { for x in stride(from: 0, to: w, by: 1) {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                if c.redComponent > 0.6 && c.greenComponent < 0.45 && c.blueComponent < 0.45 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
                if c.blueComponent > 0.6 && c.redComponent < 0.4 { bx += Double(x); by += Double(y); bn += 1 }
            }}
            let frame = WindowFollowTracker.bounds(of: wid)!
            let expected = mapping.contentRect(forWindowSize: frame.size)
            let got = CGRect(x: Double(minX) / Double(w), y: Double(minY) / Double(h),
                             width: Double(maxX - minX + 1) / Double(w), height: Double(maxY - minY + 1) / Double(h))
            let dot = mapping.normalized(CGPoint(x: frame.minX + frame.width * 0.25, y: frame.minY + frame.height * 0.25), windowFrame: frame)
            let gotDot = bn > 0 ? CGPoint(x: bx / bn / Double(w), y: by / bn / Double(h)) : .zero
            let tol = 0.02
            let ok = abs(got.minX - expected.minX) < tol && abs(got.minY - expected.minY) < tol
                && abs(got.width - expected.width) < tol && abs(got.height - expected.height) < tol
                && abs(gotDot.x - dot.x) < tol && abs(gotDot.y - dot.y) < tol
            if !ok { failures += 1 }
            print("\(ok ? "PASS" : "FAIL") \(name) video=\(w)x\(h) window=\(frame) content=\(got) expected=\(expected) dot=\(gotDot) expectedDot=\(dot)")
        }
        try? await stream.stopCapture()
        print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}

import Cocoa

/// Where a followed window's content lands in a window recording.
///
/// The video keeps the size the window had when the take started. When the
/// window is resized, ScreenCaptureKit scales its content to fit that size
/// (keeping the aspect ratio) and centers it, leaving bars on the sides or
/// top and bottom. This maps a global point to the same normalized video
/// position, so recorded pointer data lines up with the pixels.
nonisolated struct WindowFitMapping: Sendable {
    /// Window size at the start of the take: the video's aspect ratio.
    let outputSize: CGSize

    /// Normalized rect (0...1, top-left origin) that a window of `windowSize`
    /// occupies in the video.
    func contentRect(forWindowSize windowSize: CGSize) -> CGRect {
        guard outputSize.width > 0, outputSize.height > 0,
              windowSize.width > 0, windowSize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let scale = min(outputSize.width / windowSize.width, outputSize.height / windowSize.height)
        let width = windowSize.width * scale / outputSize.width
        let height = windowSize.height * scale / outputSize.height
        return CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }

    /// Where the window's content is drawn in a video of `pixelSize`, in
    /// pixels (top-left origin), rounded to whole pixels. ScreenCaptureKit
    /// pins scaled content to the top-left corner on its own, so the stream's
    /// `destinationRect` is set to this to center it.
    func destinationRect(forWindowSize windowSize: CGSize, pixelSize: CGSize) -> CGRect {
        let content = contentRect(forWindowSize: windowSize)
        let width = (content.width * pixelSize.width).rounded()
        let height = (content.height * pixelSize.height).rounded()
        return CGRect(x: ((pixelSize.width - width) / 2).rounded(.down),
                      y: ((pixelSize.height - height) / 2).rounded(.down),
                      width: width, height: height)
    }

    /// Normalized video position of a global point (Core Graphics coordinates)
    /// while the window covers `windowFrame` (Core Graphics coordinates).
    func normalized(_ point: CGPoint, windowFrame: CGRect) -> CGPoint {
        guard windowFrame.width > 0, windowFrame.height > 0 else { return .zero }
        let content = contentRect(forWindowSize: windowFrame.size)
        return CGPoint(x: content.minX + (point.x - windowFrame.minX) / windowFrame.width * content.width,
                       y: content.minY + (point.y - windowFrame.minY) / windowFrame.height * content.height)
    }
}

/// Latest frame of a followed window, readable from any thread.
nonisolated final class TrackedWindowFrame: @unchecked Sendable {
    private let lock = NSLock()
    private var frame: CGRect

    init(_ frame: CGRect) { self.frame = frame }

    /// Window bounds in global Core Graphics coordinates (top-left origin).
    var current: CGRect {
        lock.lock(); defer { lock.unlock() }
        return frame
    }

    func update(_ newFrame: CGRect) {
        lock.lock(); frame = newFrame; lock.unlock()
    }
}

/// Polls a window's on-screen frame while it is being recorded so the
/// recording chrome (border, keystrokes, HUD) and pointer data follow it.
@MainActor
final class WindowFollowTracker {
    let windowID: CGWindowID
    let frame: TrackedWindowFrame
    /// Called with the window's new frame in AppKit screen coordinates.
    var onChange: ((NSRect) -> Void)?
    private var timer: Timer?

    init?(windowID: CGWindowID) {
        guard let bounds = Self.bounds(of: windowID) else { return nil }
        self.windowID = windowID
        frame = TrackedWindowFrame(bounds)
    }

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onChange = nil
    }

    private func poll() {
        guard let bounds = Self.bounds(of: windowID), bounds != frame.current else { return }
        frame.update(bounds)
        onChange?(Self.appKitRect(forGlobal: bounds))
    }

    /// Window bounds in global Core Graphics coordinates, without its shadow.
    static func bounds(of windowID: CGWindowID) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let dict = info.first?[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dict),
              rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    static func appKitRect(forGlobal rect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

import CoreGraphics
import Foundation

/// Garabatapp: "⌘-click to snap" in the editor. Finds the region of
/// continuous colour under a point and returns its bounding box, so a click
/// on a panel, button, card or image background selects exactly that box.
///
/// Neighbouring pixels join the region when they differ by less than
/// `tolerance` (sum of |ΔR|+|ΔG|+|ΔB|), so soft gradients and shadows grow
/// with it while hard edges (borders, text, other elements) stop it.
struct RegionFill {
    /// Tightly packed 8-bit RGBA, row 0 at the top.
    let pixels: [UInt8]
    let width: Int
    let height: Int

    static let defaultTolerance = 24

    init(pixels: [UInt8], width: Int, height: Int) {
        self.pixels = pixels
        self.width = width
        self.height = height
    }

    /// Renders `image` into an RGBA buffer. nil for empty images.
    init?(image: CGImage) {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        self.init(pixels: buffer, width: w, height: h)
    }

    /// Bounding box (pixels, top-left origin) of the region containing
    /// (`x`, `row`). nil when the point is outside the image.
    func bounds(x: Int, row: Int, tolerance: Int = RegionFill.defaultTolerance) -> CGRect? {
        guard x >= 0, row >= 0, x < width, row < height else { return nil }
        let w = width, h = height
        var visited = [Bool](repeating: false, count: w * h)
        var stack: [Int] = [row * w + x]
        visited[row * w + x] = true
        var minX = x, maxX = x, minY = row, maxY = row

        pixels.withUnsafeBufferPointer { p in
            @inline(__always) func close(_ a: Int, _ b: Int) -> Bool {
                let i = a * 4, j = b * 4
                let d = abs(Int(p[i]) - Int(p[j])) + abs(Int(p[i + 1]) - Int(p[j + 1]))
                    + abs(Int(p[i + 2]) - Int(p[j + 2]))
                return d < tolerance
            }
            @inline(__always) func visit(_ from: Int, _ to: Int) {
                if !visited[to] && close(from, to) {
                    visited[to] = true
                    stack.append(to)
                }
            }
            while let idx = stack.popLast() {
                let cx = idx % w, cy = idx / w
                if cx < minX { minX = cx } else if cx > maxX { maxX = cx }
                if cy < minY { minY = cy } else if cy > maxY { maxY = cy }
                if cx > 0 { visit(idx, idx - 1) }
                if cx < w - 1 { visit(idx, idx + 1) }
                if cy > 0 { visit(idx, idx - w) }
                if cy < h - 1 { visit(idx, idx + w) }
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

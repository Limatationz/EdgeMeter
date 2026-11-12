import Testing
import Foundation
import EdgeMeterCore

/// Coarse sanity checks against the targets in FEATURES.md §17 (hover snap < 1 ms).
/// Bounds are generous because tests run in debug builds; they catch accidental
/// O(n²) regressions, not micro-optimisation drift.
@Suite("Performance", .serialized)
struct PerformanceTests {
    static func fiveK() -> PixelBuffer {
        var img = SyntheticImage(width: 5120, height: 2880, background: RGBA(gray: 200))
        img.fill(PixelRect(x: 1000, y: 800, width: 3000, height: 1200), .white)
        return img.buffer(format: .bgra8)
    }

    @Test("hover snap on a 5K buffer")
    func snap5K() {
        let buf = Self.fiveK()
        let d = EdgeDetector(tolerance: 0.1)
        let start = Date()
        let iterations = 100
        for _ in 0..<iterations {
            _ = d.snap(at: PixelPoint(2500, 1400), in: buf)
        }
        let perSnap = Date().timeIntervalSince(start) / Double(iterations)
        #expect(perSnap < 0.010, "hover snap took \(perSnap * 1000) ms")
    }

    @Test("object detection of a 3000×1200 element on a 5K buffer")
    func object5K() {
        let buf = Self.fiveK()
        let d = ObjectDetector(tolerance: 0.1)
        let start = Date()
        let o = d.objectBounds(at: PixelPoint(2500, 1400), in: buf)
        let elapsed = Date().timeIntervalSince(start)
        #expect(o.rect == PixelRect(x: 1000, y: 800, width: 3000, height: 1200))
        #expect(elapsed < 3.0, "object detection took \(elapsed * 1000) ms")
    }
}

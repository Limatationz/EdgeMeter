import Testing
import KaliberCore

@Suite("Ray scan")
struct ScanTests {
    let detector = EdgeDetector(tolerance: 0.1)

    @Test("stops at the first differing pixel in each direction")
    func fourDirections() {
        let buf = buttonFixture().buffer()
        let p = PixelPoint(105, 140) // inside the button, below the label

        let left = detector.scan(from: p, direction: .left, in: buf)
        #expect(left == EdgeHit(position: 99, kind: .colorChange, direction: .left, color: .white))
        #expect(left.boundary == 100)

        let right = detector.scan(from: p, direction: .right, in: buf)
        #expect(right.position == 200)
        #expect(right.boundary == 200)
        #expect(right.kind == .colorChange)

        let up = detector.scan(from: p, direction: .up, in: buf)
        #expect(up.position == 99)
        #expect(up.boundary == 100)

        let down = detector.scan(from: p, direction: .down, in: buf)
        #expect(down.position == 150)
        #expect(down.boundary == 150)
    }

    @Test("reports the buffer edge when no change is found")
    func hitsBounds() {
        let buf = buttonFixture().buffer()
        let p = PixelPoint(10, 10) // top-left background corner

        let left = detector.scan(from: p, direction: .left, in: buf)
        #expect(left == EdgeHit(position: -1, kind: .bounds, direction: .left, color: nil))
        #expect(left.boundary == 0)

        let up = detector.scan(from: p, direction: .up, in: buf)
        #expect(up.position == -1)
        #expect(up.kind == .bounds)

        // Row 10 is pure background all the way to the right edge.
        let right = detector.scan(from: p, direction: .right, in: buf)
        #expect(right == EdgeHit(position: 400, kind: .bounds, direction: .right))
        #expect(right.boundary == 400)
    }

    @Test("respects a clip rect")
    func clip() {
        let buf = buttonFixture().buffer()
        var clipped = detector
        clipped.clip = PixelRect(x: 50, y: 50, width: 100, height: 100) // ends at x=149, y=149
        let p = PixelPoint(105, 140)
        let right = clipped.scan(from: p, direction: .right, in: buf)
        #expect(right == EdgeHit(position: 150, kind: .bounds, direction: .right))
        let left = clipped.scan(from: p, direction: .left, in: buf)
        #expect(left.position == 99) // real edge inside the clip wins
    }

    @Test("reads BGRA and padded rows identically to RGBA")
    func formats() {
        let img = buttonFixture()
        let a = img.buffer(format: .rgba8)
        let b = img.buffer(format: .bgra8, rowPadding: 64)
        let p = PixelPoint(105, 140)
        #expect(b.color(at: p) == RGBA.blue)
        for d in ScanDirection.allCases {
            #expect(detector.scan(from: p, direction: d, in: a) == detector.scan(from: p, direction: d, in: b))
        }
    }

    @Test("tolerance zero treats every change as an edge, tolerance one none")
    func toleranceExtremes() {
        var img = SyntheticImage(width: 50, height: 1, background: RGBA(gray: 100))
        img[25, 0] = RGBA(gray: 101)
        let buf = img.buffer()
        let strict = EdgeDetector(tolerance: 0)
        #expect(strict.scan(from: PixelPoint(0, 0), direction: .right, in: buf).position == 25)
        let lax = EdgeDetector(tolerance: 1)
        #expect(lax.scan(from: PixelPoint(0, 0), direction: .right, in: buf).kind == .bounds)
    }
}

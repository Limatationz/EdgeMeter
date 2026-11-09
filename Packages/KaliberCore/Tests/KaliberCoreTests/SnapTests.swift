import Testing
import KaliberCore

@Suite("Hover snap")
struct SnapTests {
    let detector = EdgeDetector(tolerance: 0.1)

    @Test("measures a solid box from inside")
    func insideBox() {
        let buf = buttonFixture().buffer()
        let r = detector.snap(at: PixelPoint(105, 140), in: buf)
        #expect(r.horizontal == PixelSpan(start: 100, end: 199))
        #expect(r.vertical == PixelSpan(start: 100, end: 149))
        #expect(r.insideSize == (100, 50))
        #expect(r.outsideSize == (102, 52))
        #expect(r.insideRect == PixelRect(x: 100, y: 100, width: 100, height: 50))
    }

    @Test("measures the gap between an object and the screen edge from outside")
    func outsideBox() {
        let buf = buttonFixture().buffer()
        // Left of the box, on its middle row: run from x=0 to x=99.
        let r = detector.snap(at: PixelPoint(50, 125), in: buf)
        #expect(r.horizontal == PixelSpan(start: 0, end: 99))
        #expect(r.left.kind == .bounds)
        #expect(r.right.kind == .colorChange)
        #expect(r.right.color == RGBA.blue)
        #expect(r.insideSize.width == 100)
        // Only the right side has a real edge pixel to include.
        #expect(r.outsideSize.width == 101)
        // Vertically the background runs the full height.
        #expect(r.vertical == PixelSpan(start: 0, end: 299))
    }

    @Test("snaps to a glyph inside the button when hovering the label")
    func label() {
        let buf = buttonFixture().buffer()
        let r = detector.snap(at: PixelPoint(123, 125), in: buf)
        #expect(r.insideRect == PixelRect(x: 120, y: 118, width: 8, height: 14))
    }

    @Test("hovering the button background between glyphs measures the gap")
    func gapBetweenGlyphs() {
        let buf = buttonFixture().buffer()
        let r = detector.snap(at: PixelPoint(130, 125), in: buf)
        #expect(r.horizontal == PixelSpan(start: 128, end: 131))
        #expect(r.insideSize.width == 4)
        #expect(r.vertical == PixelSpan(start: 100, end: 149)) // column 130 has no glyph
    }

    @Test("low tolerance stops at the anti-aliased fringe, higher tolerance crosses it")
    func antialiasing() {
        var img = SyntheticImage(width: 200, height: 100)
        // Black 60×20 box with a 50 % grey fringe.
        img.antialiasedRect(PixelRect(x: 50, y: 40, width: 60, height: 20), .black, coverage: 0.5)
        let buf = img.buffer()
        #expect(buf.color(x: 49, y: 50) == RGBA(gray: 128))

        let strict = EdgeDetector(tolerance: 0.1)
        let s = strict.snap(at: PixelPoint(80, 50), in: buf)
        #expect(s.horizontal == PixelSpan(start: 50, end: 109))

        // 0.6 > 128/255 ≈ 0.5, so the fringe counts as "black"; white (1.0) still ends the run.
        let lax = EdgeDetector(tolerance: 0.6)
        let l = lax.snap(at: PixelPoint(80, 50), in: buf)
        #expect(l.horizontal == PixelSpan(start: 49, end: 110))
        #expect(l.vertical == PixelSpan(start: 39, end: 60))
    }

    @Test("compares against the start pixel, so gradients produce a finite run")
    func gradient() {
        var img = SyntheticImage(width: 256, height: 10)
        img.horizontalGradient(PixelRect(x: 0, y: 0, width: 256, height: 10), from: .black, to: .white)
        let buf = img.buffer()
        #expect(buf.color(x: 128, y: 5) == RGBA(gray: 128))

        let d = EdgeDetector(tolerance: 0.1, metric: .maxChannel) // 0.1 * 255 = 25.5
        let r = d.snap(at: PixelPoint(128, 5), in: buf)
        // |v − 128| > 25.5 first at v = 102 (x = 102) and v = 154 (x = 154).
        #expect(r.left.position == 102)
        #expect(r.right.position == 154)
        #expect(r.horizontal == PixelSpan(start: 103, end: 153))
        // Vertically the gradient column is uniform.
        #expect(r.vertical == PixelSpan(start: 0, end: 9))
    }

    @Test("single-pixel buffer")
    func singlePixel() {
        let buf = PixelBuffer(width: 1, height: 1, fill: .red)
        let r = detector.snap(at: PixelPoint(0, 0), in: buf)
        #expect(r.insideSize == (1, 1))
        #expect(r.outsideSize == (1, 1))
    }
}

@Suite("Nearest boundary")
struct NearestBoundaryTests {
    let detector = EdgeDetector(tolerance: 0.1)

    @Test("snaps a boundary just outside the box onto its edge")
    func outsideToEdge() {
        let buf = buttonFixture().buffer()
        #expect(detector.nearestBoundary(to: 97, along: 125, axis: .horizontal, radius: 8, in: buf) == 100)
        #expect(detector.nearestBoundary(to: 203, along: 125, axis: .horizontal, radius: 8, in: buf) == 200)
        #expect(detector.nearestBoundary(to: 98, along: 150, axis: .vertical, radius: 8, in: buf) == 100)
        #expect(detector.nearestBoundary(to: 153, along: 150, axis: .vertical, radius: 8, in: buf) == 150)
    }

    @Test("snaps a boundary just inside the box onto its edge")
    func insideToEdge() {
        let buf = buttonFixture().buffer()
        #expect(detector.nearestBoundary(to: 103, along: 140, axis: .horizontal, radius: 8, in: buf) == 100)
        #expect(detector.nearestBoundary(to: 196, along: 140, axis: .horizontal, radius: 8, in: buf) == 200)
    }

    @Test("exact hit stays put and far-away boundaries are ignored")
    func exactAndOutOfRange() {
        let buf = buttonFixture().buffer()
        #expect(detector.nearestBoundary(to: 100, along: 140, axis: .horizontal, radius: 8, in: buf) == 100)
        #expect(detector.nearestBoundary(to: 200, along: 140, axis: .horizontal, radius: 8, in: buf) == 200)
        #expect(detector.nearestBoundary(to: 50, along: 140, axis: .horizontal, radius: 8, in: buf) == nil)
    }

    @Test("screen edges are valid snap targets")
    func screenEdge() {
        let buf = buttonFixture().buffer()
        #expect(detector.nearestBoundary(to: 3, along: 10, axis: .horizontal, radius: 8, in: buf) == 0)
        #expect(detector.nearestBoundary(to: 397, along: 10, axis: .horizontal, radius: 8, in: buf) == 400)
        #expect(detector.nearestBoundary(to: 400, along: 10, axis: .horizontal, radius: 8, in: buf) == 400)
    }
}

import Testing
import EdgeMeterCore

@Suite("Object mode")
struct ObjectTests {
    let detector = ObjectDetector(tolerance: 0.1)

    @Test("clicking a button background returns the whole button despite the label")
    func buttonWithLabel() {
        let buf = buttonFixture().buffer()
        let o = detector.objectBounds(at: PixelPoint(105, 105), in: buf)
        #expect(o.rect == PixelRect(x: 100, y: 100, width: 100, height: 50))
        #expect(o.reference == RGBA.blue)
        #expect(o.truncated == false)
        #expect(o.pixelCount == 100 * 50 - 8 * 14 - 8 * 14 - 8 * 10)
    }

    @Test("clicking a glyph returns only that glyph")
    func glyph() {
        let buf = buttonFixture().buffer()
        let o = detector.objectBounds(at: PixelPoint(135, 120), in: buf)
        #expect(o.rect == PixelRect(x: 132, y: 118, width: 8, height: 14))
        #expect(o.pixelCount == 8 * 14)
    }

    @Test("clicking the background returns the full canvas")
    func background() {
        let buf = buttonFixture().buffer()
        let o = detector.objectBounds(at: PixelPoint(5, 5), in: buf)
        #expect(o.rect == buf.bounds)
        #expect(o.pixelCount == 400 * 300 - 100 * 50)
    }

    @Test("follows an L-shape around a corner")
    func lShape() {
        var img = SyntheticImage(width: 100, height: 100)
        img.fill(PixelRect(x: 10, y: 10, width: 10, height: 60), .red) // vertical bar
        img.fill(PixelRect(x: 10, y: 60, width: 60, height: 10), .red) // horizontal bar
        let buf = img.buffer()
        let o = detector.objectBounds(at: PixelPoint(12, 12), in: buf)
        #expect(o.rect == PixelRect(x: 10, y: 10, width: 60, height: 60))
        #expect(o.pixelCount == 10 * 60 + 60 * 10 - 10 * 10)
    }

    @Test("does not leak through a diagonal gap (4-connectivity)")
    func diagonalGap() {
        var img = SyntheticImage(width: 20, height: 20)
        img.fill(PixelRect(x: 0, y: 0, width: 10, height: 10), .red)
        img.fill(PixelRect(x: 10, y: 10, width: 10, height: 10), .red) // touches only at a corner
        let buf = img.buffer()
        let o = detector.objectBounds(at: PixelPoint(2, 2), in: buf)
        #expect(o.rect == PixelRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test("separate same-colored boxes are not merged")
    func twoBoxes() {
        var img = SyntheticImage(width: 100, height: 40)
        img.fill(PixelRect(x: 10, y: 10, width: 20, height: 20), .red)
        img.fill(PixelRect(x: 50, y: 10, width: 20, height: 20), .red)
        let buf = img.buffer()
        #expect(detector.objectBounds(at: PixelPoint(15, 15), in: buf).rect == PixelRect(x: 10, y: 10, width: 20, height: 20))
        #expect(detector.objectBounds(at: PixelPoint(55, 15), in: buf).rect == PixelRect(x: 50, y: 10, width: 20, height: 20))
    }

    @Test("nested boxes: clicking the ring returns the outer box")
    func nested() {
        var img = SyntheticImage(width: 100, height: 100)
        img.fill(PixelRect(x: 10, y: 10, width: 80, height: 80), .blue)
        img.fill(PixelRect(x: 30, y: 30, width: 40, height: 40), .red)
        let buf = img.buffer()
        #expect(detector.objectBounds(at: PixelPoint(15, 50), in: buf).rect == PixelRect(x: 10, y: 10, width: 80, height: 80))
        #expect(detector.objectBounds(at: PixelPoint(50, 50), in: buf).rect == PixelRect(x: 30, y: 30, width: 40, height: 40))
    }

    @Test("respects the clip rect")
    func clipped() {
        let buf = buttonFixture().buffer()
        var d = detector
        d.clip = PixelRect(x: 0, y: 0, width: 150, height: 300)
        let o = d.objectBounds(at: PixelPoint(105, 105), in: buf)
        #expect(o.rect == PixelRect(x: 100, y: 100, width: 50, height: 50))
    }

    @Test("stops at maxPixels and reports truncation")
    func truncation() {
        let buf = buttonFixture().buffer()
        var d = detector
        d.maxPixels = 1000
        let o = d.objectBounds(at: PixelPoint(5, 5), in: buf)
        #expect(o.truncated)
        #expect(o.pixelCount >= 1000)
        #expect(o.pixelCount < 400 * 300 - 100 * 50)
    }

    @Test("anti-aliased fringe is excluded at low tolerance and included at high tolerance")
    func antialiased() {
        var img = SyntheticImage(width: 100, height: 100)
        img.antialiasedRect(PixelRect(x: 20, y: 20, width: 30, height: 30), .black, coverage: 0.5)
        let buf = img.buffer()
        #expect(ObjectDetector(tolerance: 0.1).objectBounds(at: PixelPoint(30, 30), in: buf).rect == PixelRect(x: 20, y: 20, width: 30, height: 30))
        #expect(ObjectDetector(tolerance: 0.6).objectBounds(at: PixelPoint(30, 30), in: buf).rect == PixelRect(x: 19, y: 19, width: 32, height: 32))
    }
}

@Suite("Area snapping")
struct AreaSnapTests {
    let snapper = AreaSnapper(detector: EdgeDetector(tolerance: 0.1), radius: 8)

    @Test("a sloppy drag around a box snaps onto the box")
    func sloppyDrag() {
        let buf = buttonFixture().buffer()
        let dragged = PixelRect(x: 96, y: 97, width: 110, height: 58) // 96...205 × 97...154
        #expect(snapper.snap(dragged, in: buf) == PixelRect(x: 100, y: 100, width: 100, height: 50))
    }

    @Test("a drag slightly inside the box snaps outwards onto the box")
    func insideDrag() {
        let buf = buttonFixture().buffer()
        let dragged = PixelRect(x: 103, y: 102, width: 93, height: 45) // 103...195 × 102...146
        #expect(snapper.snap(dragged, in: buf) == PixelRect(x: 100, y: 100, width: 100, height: 50))
    }

    @Test("sides without a nearby edge are left alone")
    func partialSnap() {
        let buf = buttonFixture().buffer()
        // Right side ends at x=170, in the middle of the box: no edge within 8 px.
        let dragged = PixelRect(x: 96, y: 97, width: 75, height: 58)
        let snapped = snapper.snap(dragged, in: buf)
        #expect(snapped.minX == 100)
        #expect(snapped.maxX == 170)
        #expect(snapped.minY == 100)
        #expect(snapped.maxY == 149)
    }

    @Test("empty rects pass through")
    func empty() {
        let buf = buttonFixture().buffer()
        let r = PixelRect(x: 5, y: 5, width: 0, height: 0)
        #expect(snapper.snap(r, in: buf) == r)
    }
}

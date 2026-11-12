import Testing
import EdgeMeterCore

@Suite("Measurements and units")
struct MeasurementTests {
    @Test("length formatting divides by the scale and trims zeros", arguments: [
        (240, 2.0, 1, "120"),
        (15, 2.0, 1, "7.5"),
        (10, 3.0, 1, "3.3"),
        (10, 3.0, 2, "3.33"),
        (10, 3.0, 0, "3"),
        (0, 2.0, 1, "0"),
        (300, 1.5, 1, "200"),
        (7, 1.0, 2, "7"),
    ])
    func formatting(pixels: Int, scale: Double, decimals: Int, expected: String) {
        #expect(LengthFormat(maxDecimals: decimals).string(pixels: pixels, scale: scale) == expected)
    }

    @Test("invalid scales fall back to 1")
    func invalidScale() {
        #expect(LengthFormat().string(pixels: 12, scale: 0) == "12")
        #expect(ScaleMode.fixed(0).factor(displayScale: 2) == 1)
        #expect(ScaleMode.auto.factor(displayScale: 0) == 1)
    }

    @Test("scale mode cycles Auto → 1× → 2× → 3× → Auto")
    func scaleCycle() {
        var m = ScaleMode.auto
        var seen: [ScaleMode] = []
        for _ in 0..<4 { m = m.next; seen.append(m) }
        #expect(seen == [.fixed(1), .fixed(2), .fixed(3), .auto])
        #expect(ScaleMode.fixed(1.5).next == .auto)
    }

    @Test("scale labels")
    func scaleLabels() {
        #expect(ScaleMode.auto.label(displayScale: 2) == "Auto (2×)")
        #expect(ScaleMode.fixed(1.5).label(displayScale: 2) == "1.5×")
    }

    @Test("cross from a snap uses inside or outside spans")
    func crossFromSnap() {
        let buf = buttonFixture().buffer()
        let snap = EdgeDetector(tolerance: 0.1).snap(at: PixelPoint(105, 140), in: buf)
        let inside = ScreenMeasurement(snap: snap)
        #expect(inside == .cross(origin: PixelPoint(105, 140), horizontal: PixelSpan(start: 100, end: 199), vertical: PixelSpan(start: 100, end: 149)))
        #expect(inside.text(format: LengthFormat(), scale: 2) == "50 × 25")

        let outside = ScreenMeasurement(snap: snap, outside: true)
        #expect(outside == .cross(origin: PixelPoint(105, 140), horizontal: PixelSpan(start: 99, end: 200), vertical: PixelSpan(start: 99, end: 150)))
        let sizes = snap.outsideSize
        #expect(outside.text(format: LengthFormat(), scale: 1) == "\(sizes.width) × \(sizes.height)")
    }

    @Test("outside spans don't grow past the screen edge")
    func outsideAtBounds() {
        let buf = buttonFixture().buffer()
        let snap = EdgeDetector(tolerance: 0.1).snap(at: PixelPoint(50, 125), in: buf)
        let spans = snap.spans(outside: true)
        #expect(spans.horizontal == PixelSpan(start: 0, end: 100))
        #expect(spans.vertical == PixelSpan(start: 0, end: 299))
    }

    @Test("line and box text")
    func lineAndBox() {
        let line = ScreenMeasurement.line(LineMeasurement(axis: .horizontal, line: 10, from: 200, to: 100))
        #expect(line.text(format: LengthFormat(), scale: 2) == "50")
        let box = ScreenMeasurement.box(PixelRect(x: 0, y: 0, width: 101, height: 40))
        #expect(box.text(format: LengthFormat(), scale: 2) == "50.5 × 20")
        let l = LineMeasurement(axis: .vertical, line: 3, from: 9, to: 2)
        #expect((l.lower, l.upper, l.length) == (2, 9, 7))
    }

    @Test("labels show pt and px when scaled, px only at 1×")
    func labels() {
        let f = LengthFormat()
        #expect(f.label(pixels: 200, scale: 2) == "100 pt · 200 px")
        #expect(f.label(pixels: 15, scale: 2) == "7.5 pt · 15 px")
        #expect(f.label(pixels: 200, scale: 3) == "66.7 pt · 200 px")
        #expect(f.label(pixels: 200, scale: 1) == "200 px")
        #expect(f.label(pixels: 200, scale: 0) == "200 px")
        #expect(f.label(width: 200, height: 80, scale: 2) == "100 × 40 pt · 200 × 80 px")
        #expect(f.label(width: 200, height: 80, scale: 1) == "200 × 80 px")
    }

    @Test("measurement labels carry units, clipboard text stays numeric")
    func measurementLabels() {
        let f = LengthFormat()
        let line = ScreenMeasurement.line(LineMeasurement(axis: .horizontal, line: 0, from: 0, to: 32))
        #expect(line.label(format: f, scale: 2) == "16 pt · 32 px")
        #expect(line.text(format: f, scale: 2) == "16")
        let box = ScreenMeasurement.box(PixelRect(x: 0, y: 0, width: 280, height: 80))
        #expect(box.label(format: f, scale: 2) == "140 × 40 pt · 280 × 80 px")
        #expect(box.label(format: f, scale: 1) == "280 × 80 px")
        #expect(box.text(format: f, scale: 2) == "140 × 40")
    }
}

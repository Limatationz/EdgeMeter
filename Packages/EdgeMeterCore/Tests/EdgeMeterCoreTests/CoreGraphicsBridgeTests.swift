#if canImport(CoreGraphics)
import Testing
import CoreGraphics
import EdgeMeterCore

@Suite("CoreGraphics bridge")
struct CoreGraphicsBridgeTests {
    /// Draws the button fixture with Core Graphics (what ScreenCaptureKit hands us is a CGImage).
    func makeImage() -> CGImage {
        let width = 400, height = 300
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        ctx.setShouldAntialias(false)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // CG origin is bottom-left; the box at image-space y=100...149 is CG y = 300-150 = 150.
        ctx.setFillColor(CGColor(srgbRed: 40 / 255, green: 80 / 255, blue: 220 / 255, alpha: 1))
        ctx.fill(CGRect(x: 100, y: 150, width: 100, height: 50))
        return ctx.makeImage()!
    }

    @Test("converts a CGImage into a BGRA buffer with the expected pixels")
    func conversion() throws {
        let buf = try #require(PixelBuffer(cgImage: makeImage()))
        #expect(buf.width == 400 && buf.height == 300)
        #expect(buf.format == .bgra8)
        #expect(buf.color(x: 5, y: 5) == RGBA.white)
        #expect(buf.color(x: 150, y: 125) == RGBA.blue)
        #expect(buf.color(x: 99, y: 125) == RGBA.white)
    }

    @Test("round-trips through makeCGImage", arguments: [PixelFormat.bgra8, .rgba8])
    func roundTrip(format: PixelFormat) throws {
        let original = buttonFixture().buffer(format: format, rowPadding: 16)
        let image = try #require(original.makeCGImage())
        let back = try #require(PixelBuffer(cgImage: image))
        for p in [PixelPoint(5, 5), PixelPoint(150, 140), PixelPoint(123, 125), PixelPoint(399, 299)] {
            #expect(back.color(at: p) == original.color(at: p))
        }
    }

    @Test("detectors work on the converted image")
    func detection() throws {
        let buf = try #require(PixelBuffer(cgImage: makeImage()))
        let snap = EdgeDetector(tolerance: 0.1).snap(at: PixelPoint(150, 125), in: buf)
        #expect(snap.insideRect == PixelRect(x: 100, y: 100, width: 100, height: 50))
        let obj = ObjectDetector(tolerance: 0.1).objectBounds(at: PixelPoint(150, 125), in: buf)
        #expect(obj.rect == PixelRect(x: 100, y: 100, width: 100, height: 50))
    }
}
#endif

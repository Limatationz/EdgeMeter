#if canImport(CoreGraphics)
import CoreGraphics

extension PixelBuffer {
    /// Copies a `CGImage` into a BGRA8 buffer by drawing it into a bitmap context.
    ///
    /// Redrawing (instead of reading the image's own data provider) normalises any
    /// source format – 16-bit, non-premultiplied, odd row strides – to the one layout
    /// the detectors understand, at the cost of one blit. For a 5K display that is a
    /// few milliseconds and happens once per snapshot.
    public init?(cgImage: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        self.init(width: width, height: height, bytesPerRow: bytesPerRow, format: .bgra8, data: data)
    }
}
#endif

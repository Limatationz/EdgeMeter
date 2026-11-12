#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

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

    /// Wraps the pixels in a `CGImage`, e.g. to freeze the latest live frame.
    /// - Parameter colorSpace: the space the pixels are in (a live stream delivers the
    ///   display's own space; `init(cgImage:)` produces sRGB).
    public func makeCGImage(colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) -> CGImage? {
        let info: UInt32 = switch format {
        case .bgra8: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        case .rgba8: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        }
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
#endif

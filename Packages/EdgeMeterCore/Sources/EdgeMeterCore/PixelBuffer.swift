/// Byte order of one 8-bit-per-channel pixel.
public enum PixelFormat: Sendable {
    /// Blue, green, red, alpha – what `CGImage`s from ScreenCaptureKit use
    /// (`kCGBitmapByteOrder32Little` + premultiplied first alpha).
    case bgra8
    /// Red, green, blue, alpha – what most synthetic/test data and PNG decoders produce.
    case rgba8

    public var bytesPerPixel: Int { 4 }

    @usableFromInline
    var offsets: (r: Int, g: Int, b: Int, a: Int) {
        switch self {
        case .bgra8: (2, 1, 0, 3)
        case .rgba8: (0, 1, 2, 3)
        }
    }
}

/// A frozen, CPU-side copy of a display's framebuffer that the detectors read from.
///
/// The buffer is immutable once created; all detectors are pure functions over it,
/// so a single snapshot can be shared across threads.
public struct PixelBuffer: Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let format: PixelFormat
    public let data: [UInt8]

    public init(width: Int, height: Int, bytesPerRow: Int? = nil, format: PixelFormat, data: [UInt8]) {
        precondition(width > 0 && height > 0, "PixelBuffer must not be empty")
        let bpr = bytesPerRow ?? width * format.bytesPerPixel
        precondition(bpr >= width * format.bytesPerPixel, "bytesPerRow too small for width")
        precondition(data.count >= bpr * (height - 1) + width * format.bytesPerPixel, "data too short")
        self.width = width
        self.height = height
        self.bytesPerRow = bpr
        self.format = format
        self.data = data
    }

    /// Copies pixels out of foreign memory, e.g. a locked `CVPixelBuffer` from a live
    /// ScreenCaptureKit stream. One `memcpy`; row padding is kept as is.
    public init(copying bytes: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int, format: PixelFormat) {
        let count = bytesPerRow * height
        precondition(bytes.count >= count, "source buffer too small")
        let data = [UInt8](unsafeUninitializedCapacity: count) { dst, initialized in
            dst.baseAddress!.initialize(from: bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), count: count)
            initialized = count
        }
        self.init(width: width, height: height, bytesPerRow: bytesPerRow, format: format, data: data)
    }

    /// Creates a buffer filled with a single color.
    public init(width: Int, height: Int, format: PixelFormat = .rgba8, fill: RGBA) {
        var data = [UInt8](repeating: 0, count: width * height * format.bytesPerPixel)
        let o = format.offsets
        var i = 0
        while i < data.count {
            data[i + o.r] = fill.r
            data[i + o.g] = fill.g
            data[i + o.b] = fill.b
            data[i + o.a] = fill.a
            i += 4
        }
        self.init(width: width, height: height, format: format, data: data)
    }

    public var bounds: PixelRect { PixelRect(x: 0, y: 0, width: width, height: height) }

    @inlinable
    public func contains(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    @inlinable
    public func contains(_ p: PixelPoint) -> Bool { contains(x: p.x, y: p.y) }

    /// Color at (x, y). The caller must ensure the point is inside `bounds`.
    @inlinable
    public func color(x: Int, y: Int) -> RGBA {
        let o = format.offsets
        let base = y * bytesPerRow + x * 4
        return RGBA(r: data[base + o.r], g: data[base + o.g], b: data[base + o.b], a: data[base + o.a])
    }

    @inlinable
    public func color(at p: PixelPoint) -> RGBA { color(x: p.x, y: p.y) }

    /// Color at (x, y), or `nil` when outside the buffer.
    @inlinable
    public func colorIfInside(x: Int, y: Int) -> RGBA? {
        contains(x: x, y: y) ? color(x: x, y: y) : nil
    }
}

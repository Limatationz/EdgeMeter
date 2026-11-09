/// An 8-bit RGBA color as read from a `PixelBuffer`.
///
/// Alpha is carried along but ignored by all color metrics: screen captures are
/// opaque, and a semi-transparent pixel on top of something is still "a different
/// color" for measurement purposes.
public struct RGBA: Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init(gray: UInt8, a: UInt8 = 255) {
        self.init(r: gray, g: gray, b: gray, a: a)
    }

    public static let black = RGBA(gray: 0)
    public static let white = RGBA(gray: 255)
    public static let clear = RGBA(gray: 0, a: 0)
}

/// How the difference between two colors is measured. Every metric returns a
/// value in `0...1`, where 0 means identical and 1 means black vs. white.
public enum ColorMetric: Sendable, CaseIterable {
    /// Largest per-channel difference. Cheapest; good default for flat UI colors.
    case maxChannel
    /// Euclidean distance in RGB space, normalised to 0...1.
    case euclidean
    /// Weighted Euclidean distance ("redmean" approximation, compuphase.com).
    /// Closer to perceived difference than plain RGB; useful on gradients and shadows.
    case perceptual

    @inlinable
    public func distance(_ a: RGBA, _ b: RGBA) -> Double {
        let dr = Double(Int(a.r) - Int(b.r))
        let dg = Double(Int(a.g) - Int(b.g))
        let db = Double(Int(a.b) - Int(b.b))
        switch self {
        case .maxChannel:
            return max(abs(dr), abs(dg), abs(db)) / 255
        case .euclidean:
            // Max possible distance is sqrt(3 * 255²).
            return min((dr * dr + dg * dg + db * db).squareRoot() / (255 * 1.7320508075688772), 1)
        case .perceptual:
            let rMean = Double(Int(a.r) + Int(b.r)) / 2
            let wr = 2 + rMean / 256
            let wg = 4.0
            let wb = 2 + (255 - rMean) / 256
            let d = (wr * dr * dr + wg * dg * dg + wb * db * db).squareRoot()
            // Normalise by the distance between black and white under this metric.
            // At rMean = 127.5: wr = wb = 2.498..., wg = 4 → sqrt(255² * (wr + wg + wb)).
            let maxDistance = 255 * (2 + 127.5 / 256 + 4 + 2 + 127.5 / 256).squareRoot()
            return min(d / maxDistance, 1)
        }
    }
}

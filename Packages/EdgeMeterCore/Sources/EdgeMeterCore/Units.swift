import Foundation

/// Divisor applied to device pixels before display (feature 7.3).
public enum ScaleMode: Hashable, Sendable {
    /// Use the backing scale factor of the display being measured (2 on Retina → points).
    case auto
    /// Fixed divisor, e.g. 1 for raw pixels or 1.5 for a browser at 150 % zoom.
    case fixed(Double)

    public func factor(displayScale: Double) -> Double {
        switch self {
        case .auto: displayScale > 0 ? displayScale : 1
        case let .fixed(f): f > 0 ? f : 1
        }
    }

    /// Cycle order for the S key: Auto → 1× → 2× → 3× → Auto. Custom values return to Auto.
    public var next: ScaleMode {
        switch self {
        case .auto: .fixed(1)
        case .fixed(1): .fixed(2)
        case .fixed(2): .fixed(3)
        default: .auto
        }
    }

    /// Short label for the HUD, e.g. `Auto (2×)`, `1×`, `1.5×`.
    public func label(displayScale: Double) -> String {
        switch self {
        case .auto: "Auto (\(LengthFormat.trimmed(displayScale, maxDecimals: 2))×)"
        case let .fixed(f): "\(LengthFormat.trimmed(f, maxDecimals: 2))×"
        }
    }
}

/// Formats pixel lengths after scaling, without trailing zeros: 240 px at 2× → `120`,
/// 15 px at 2× → `7.5`. Locale-independent so clipboard output is stable.
public struct LengthFormat: Hashable, Sendable {
    public var maxDecimals: Int

    public init(maxDecimals: Int = 1) {
        self.maxDecimals = max(0, maxDecimals)
    }

    public func value(pixels: Int, scale: Double) -> Double {
        Double(pixels) / (scale > 0 ? scale : 1)
    }

    public func string(pixels: Int, scale: Double) -> String {
        Self.trimmed(value(pixels: pixels, scale: scale), maxDecimals: maxDecimals)
    }

    /// On-screen label with units. When the scale divides the pixels (Retina, or a fixed
    /// 2×/3×) both values are shown, `100 pt · 200 px`; at 1× only `200 px`.
    public func label(pixels: Int, scale: Double) -> String {
        Self.showsPoints(scale)
            ? "\(string(pixels: pixels, scale: scale)) pt · \(pixels) px"
            : "\(pixels) px"
    }

    /// Size label, e.g. `100 × 40 pt · 200 × 80 px` or `200 × 80 px`.
    public func label(width: Int, height: Int, scale: Double) -> String {
        let px = "\(width) × \(height) px"
        guard Self.showsPoints(scale) else { return px }
        return "\(string(pixels: width, scale: scale)) × \(string(pixels: height, scale: scale)) pt · \(px)"
    }

    static func showsPoints(_ scale: Double) -> Bool {
        scale > 0 && abs(scale - 1) > 1e-9
    }

    static func trimmed(_ value: Double, maxDecimals: Int) -> String {
        let m = pow(10, Double(maxDecimals))
        let rounded = (value * m).rounded() / m
        if rounded == rounded.rounded(), abs(rounded) < 1e15 {
            return String(Int(rounded))
        }
        var s = String(format: "%.\(maxDecimals)f", rounded)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

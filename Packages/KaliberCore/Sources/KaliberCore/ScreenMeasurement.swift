/// An axis-locked distance between two boundaries (two-point mode, feature 5.1).
public struct LineMeasurement: Hashable, Sendable {
    public var axis: Axis
    /// Pixel row (horizontal lines) or column (vertical lines) the line runs along.
    public var line: Int
    /// Start boundary. Boundary `b` lies between pixel `b - 1` and pixel `b`.
    public var from: Int
    /// End boundary.
    public var to: Int

    public init(axis: Axis, line: Int, from: Int, to: Int) {
        self.axis = axis
        self.line = line
        self.from = from
        self.to = to
    }

    /// Length in device pixels.
    public var length: Int { abs(to - from) }
    public var lower: Int { min(from, to) }
    public var upper: Int { max(from, to) }
}

/// Anything that can be pinned on the overlay.
public enum ScreenMeasurement: Hashable, Sendable {
    /// Hover-snap result: horizontal and vertical run through `origin` (inclusive pixel spans).
    case cross(origin: PixelPoint, horizontal: PixelSpan, vertical: PixelSpan)
    /// Two-point distance.
    case line(LineMeasurement)
    /// Object or area box (inclusive pixel rect).
    case box(PixelRect)

    /// Creates a cross from a snap, using inside or outside edge handling (feature 4.6).
    public init(snap: SnapResult, outside: Bool = false) {
        let spans = snap.spans(outside: outside)
        self = .cross(origin: snap.origin, horizontal: spans.horizontal, vertical: spans.vertical)
    }

    /// Text for the clipboard and labels, e.g. `120 × 28` or `64`.
    public func text(format: LengthFormat, scale: Double) -> String {
        switch self {
        case let .cross(_, h, v):
            "\(format.string(pixels: h.length, scale: scale)) × \(format.string(pixels: v.length, scale: scale))"
        case let .line(l):
            format.string(pixels: l.length, scale: scale)
        case let .box(r):
            "\(format.string(pixels: r.width, scale: scale)) × \(format.string(pixels: r.height, scale: scale))"
        }
    }
}

extension SnapResult {
    /// The horizontal and vertical runs, optionally widened by the edge pixel on each side
    /// that stopped at a color change ("outside" measuring). Lengths match `outsideSize`.
    public func spans(outside: Bool) -> (horizontal: PixelSpan, vertical: PixelSpan) {
        guard outside else { return (horizontal, vertical) }
        let h = PixelSpan(
            start: horizontal.start - (left.kind == .colorChange ? 1 : 0),
            end: horizontal.end + (right.kind == .colorChange ? 1 : 0)
        )
        let v = PixelSpan(
            start: vertical.start - (top.kind == .colorChange ? 1 : 0),
            end: vertical.end + (bottom.kind == .colorChange ? 1 : 0)
        )
        return (h, v)
    }
}

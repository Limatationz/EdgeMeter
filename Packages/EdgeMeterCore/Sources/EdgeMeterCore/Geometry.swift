/// Integer pixel coordinate in a `PixelBuffer`. Origin is top-left, y grows downwards.
public struct PixelPoint: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }
}

/// Integer pixel rectangle. `width`/`height` count pixels, so a rect covering
/// columns 10...19 has `x = 10, width = 10`.
public struct PixelRect: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Int { x }
    public var minY: Int { y }
    /// Last column that is inside the rect.
    public var maxX: Int { x + width - 1 }
    /// Last row that is inside the rect.
    public var maxY: Int { y + height - 1 }

    public func contains(_ p: PixelPoint) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }
}

/// The four scan directions used by the edge detector.
public enum ScanDirection: CaseIterable, Sendable {
    case left, right, up, down

    var step: (dx: Int, dy: Int) {
        switch self {
        case .left: (-1, 0)
        case .right: (1, 0)
        case .up: (0, -1)
        case .down: (0, 1)
        }
    }
}

/// An inclusive run of pixels along one axis, e.g. all pixels of a button's
/// background between its left and right border.
public struct PixelSpan: Hashable, Sendable {
    /// First pixel coordinate that belongs to the run.
    public var start: Int
    /// Last pixel coordinate that belongs to the run.
    public var end: Int

    public init(start: Int, end: Int) {
        precondition(end >= start, "PixelSpan end must not precede start")
        self.start = start
        self.end = end
    }

    /// Number of pixels in the run (the "inside" measurement).
    public var length: Int { end - start + 1 }
}

/// Why a scan stopped.
public enum EdgeKind: Sendable, Hashable {
    /// A pixel whose color differs from the start pixel by more than the tolerance.
    case colorChange
    /// The scan ran off the buffer (or the configured clip rect) without finding a change.
    case bounds
}

/// Result of scanning one ray from a start pixel.
public struct EdgeHit: Sendable, Hashable {
    /// Coordinate (x for horizontal scans, y for vertical) of the first pixel that is
    /// *not* part of the start pixel's run. For `.bounds` this is one past the clip
    /// rect, i.e. `-1` or `width`/`height`.
    public var position: Int
    public var kind: EdgeKind
    public var direction: ScanDirection
    /// Color of the edge pixel, `nil` when the scan hit the bounds.
    public var color: RGBA?

    public init(position: Int, kind: EdgeKind, direction: ScanDirection, color: RGBA? = nil) {
        self.position = position
        self.kind = kind
        self.direction = direction
        self.color = color
    }

    /// The edge as a *boundary* coordinate: boundary `b` lies between pixel `b - 1`
    /// and pixel `b`. A box occupying columns 100...199 has boundaries 100 and 200,
    /// and 200 − 100 is its width. This is the coordinate two-point measurements and
    /// area snapping work in; `position` is the pixel coordinate hover-snap works in.
    public var boundary: Int {
        switch direction {
        case .left, .up: position + 1
        case .right, .down: position
        }
    }
}

/// The hover-snap result: the run of "same" pixels through the cursor on both axes.
public struct SnapResult: Sendable, Hashable {
    public var origin: PixelPoint
    /// Run of similar pixels along the cursor's row.
    public var horizontal: PixelSpan
    /// Run of similar pixels along the cursor's column.
    public var vertical: PixelSpan
    public var left: EdgeHit
    public var right: EdgeHit
    public var top: EdgeHit
    public var bottom: EdgeHit

    /// Width/height when measuring *between* the edges (PixelSnap "inside").
    public var insideSize: (width: Int, height: Int) {
        (horizontal.length, vertical.length)
    }

    /// Width/height when the one edge pixel on each side is included (PixelSnap "outside").
    /// Edges at the buffer bounds contribute no extra pixel because there is none.
    public var outsideSize: (width: Int, height: Int) {
        let w = horizontal.length
            + (left.kind == .colorChange ? 1 : 0)
            + (right.kind == .colorChange ? 1 : 0)
        let h = vertical.length
            + (top.kind == .colorChange ? 1 : 0)
            + (bottom.kind == .colorChange ? 1 : 0)
        return (w, h)
    }

    /// The uniform region around the cursor as a rect (inside edges).
    public var insideRect: PixelRect {
        PixelRect(x: horizontal.start, y: vertical.start, width: horizontal.length, height: vertical.length)
    }
}

/// Finds edges in a `PixelBuffer` by comparing pixels against a *start* pixel.
///
/// Comparing against the start pixel (and not the previous one) is what makes the
/// detector stop on gradients and soft shadows instead of drifting through them.
public struct EdgeDetector: Sendable {
    /// Color difference (0...1) above which a pixel counts as an edge. 0 means any
    /// difference is an edge; 1 means nothing ever is.
    public var tolerance: Double
    public var metric: ColorMetric
    /// Optional rect the scans are confined to (e.g. the active window's frame).
    /// Must lie inside the buffer; `nil` means the whole buffer.
    public var clip: PixelRect?

    public init(tolerance: Double = 0.1, metric: ColorMetric = .maxChannel, clip: PixelRect? = nil) {
        self.tolerance = tolerance
        self.metric = metric
        self.clip = clip
    }

    @inlinable
    func effectiveClip(in buffer: PixelBuffer) -> PixelRect {
        guard let clip else { return buffer.bounds }
        let x0 = max(0, clip.minX), y0 = max(0, clip.minY)
        let x1 = min(buffer.width - 1, clip.maxX), y1 = min(buffer.height - 1, clip.maxY)
        return PixelRect(x: x0, y: y0, width: max(0, x1 - x0 + 1), height: max(0, y1 - y0 + 1))
    }

    @inlinable
    func isSimilar(_ a: RGBA, _ b: RGBA) -> Bool {
        metric.distance(a, b) <= tolerance
    }

    /// Scans from `start` (exclusive) in `direction` until a pixel differs from the
    /// color at `start`, or the clip rect ends. The start pixel must be inside the clip rect.
    public func scan(from start: PixelPoint, direction: ScanDirection, in buffer: PixelBuffer) -> EdgeHit {
        scan(from: start, reference: buffer.color(at: start), direction: direction, in: buffer)
    }

    /// Like `scan(from:direction:in:)` but compares against an explicit reference color.
    public func scan(from start: PixelPoint, reference: RGBA, direction: ScanDirection, in buffer: PixelBuffer) -> EdgeHit {
        let clip = effectiveClip(in: buffer)
        precondition(clip.contains(start), "scan start must be inside the clip rect")
        let step = direction.step
        var x = start.x + step.dx
        var y = start.y + step.dy
        while clip.contains(PixelPoint(x: x, y: y)) {
            let c = buffer.color(x: x, y: y)
            if !isSimilar(c, reference) {
                return EdgeHit(position: step.dx != 0 ? x : y, kind: .colorChange, direction: direction, color: c)
            }
            x += step.dx
            y += step.dy
        }
        return EdgeHit(position: step.dx != 0 ? x : y, kind: .bounds, direction: direction)
    }

    /// The hover-snap measurement: scans all four directions from `point`.
    public func snap(at point: PixelPoint, in buffer: PixelBuffer) -> SnapResult {
        let reference = buffer.color(at: point)
        let left = scan(from: point, reference: reference, direction: .left, in: buffer)
        let right = scan(from: point, reference: reference, direction: .right, in: buffer)
        let top = scan(from: point, reference: reference, direction: .up, in: buffer)
        let bottom = scan(from: point, reference: reference, direction: .down, in: buffer)
        return SnapResult(
            origin: point,
            horizontal: PixelSpan(start: left.position + 1, end: right.position - 1),
            vertical: PixelSpan(start: top.position + 1, end: bottom.position - 1),
            left: left, right: right, top: top, bottom: bottom
        )
    }

    /// Snaps a boundary coordinate to the nearest edge boundary within `radius`,
    /// for two-point measurements (5.2) and area snapping (5.6).
    ///
    /// - Parameters:
    ///   - boundary: the coordinate to snap (x for `.horizontal`, y for `.vertical`),
    ///     in boundary space: `b` lies between pixel `b - 1` and pixel `b`.
    ///   - line: the row (for `.horizontal`) or column (for `.vertical`) to scan along.
    /// - Returns: the nearest boundary (color change or clip edge) within `radius`,
    ///   or `nil`. Ties prefer the lower coordinate.
    public func nearestBoundary(to boundary: Int, along line: Int, axis: Axis, radius: Int, in buffer: PixelBuffer) -> Int? {
        let clip = effectiveClip(in: buffer)
        let (lo, hi) = axis == .horizontal ? (clip.minX, clip.maxX) : (clip.minY, clip.maxY)
        let (backward, forward): (ScanDirection, ScanDirection) = axis == .horizontal ? (.left, .right) : (.up, .down)
        // Scan from the pixel just after the boundary; its backward scan finds boundaries
        // ≤ boundary, its forward scan boundaries > boundary.
        let pixel = min(max(boundary, lo), hi)
        let point = axis == .horizontal ? PixelPoint(x: pixel, y: line) : PixelPoint(x: line, y: pixel)
        guard clip.contains(point) else { return nil }
        let b = scan(from: point, direction: backward, in: buffer).boundary
        let f = scan(from: point, direction: forward, in: buffer).boundary
        let db = abs(boundary - b), df = abs(f - boundary)
        let best = db <= df ? (db, b) : (df, f)
        return best.0 <= radius ? best.1 : nil
    }
}

public enum Axis: Sendable, Hashable {
    case horizontal, vertical
}

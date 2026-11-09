/// Result of an object-mode click (feature 5.5).
public struct ObjectBounds: Sendable, Hashable {
    /// Bounding box of all pixels connected to the clicked pixel with a similar color.
    public var rect: PixelRect
    /// Number of pixels in the connected region.
    public var pixelCount: Int
    /// `true` when the flood fill stopped because `maxPixels` was reached; the rect is
    /// then a lower bound of the real object.
    public var truncated: Bool
    /// Color of the clicked pixel, i.e. what the region was compared against.
    public var reference: RGBA
}

/// Finds the connected region of similar color around a point and returns its
/// bounding box. Uses a scanline flood fill with a visited bitmap, so a solid
/// 1000×1000 element costs about one byte per pixel and no recursion.
///
/// Clicking the background of a button returns the button's frame even when the
/// button has a text label: the label is a hole in the region, and holes don't
/// change the bounding box.
public struct ObjectDetector: Sendable {
    public var tolerance: Double
    public var metric: ColorMetric
    public var clip: PixelRect?
    /// Safety valve so a click on a 5K desktop background can't run away.
    public var maxPixels: Int

    public init(tolerance: Double = 0.1, metric: ColorMetric = .maxChannel, clip: PixelRect? = nil, maxPixels: Int = 20_000_000) {
        self.tolerance = tolerance
        self.metric = metric
        self.clip = clip
        self.maxPixels = maxPixels
    }

    public init(from edgeDetector: EdgeDetector, maxPixels: Int = 20_000_000) {
        self.init(tolerance: edgeDetector.tolerance, metric: edgeDetector.metric, clip: edgeDetector.clip, maxPixels: maxPixels)
    }

    public func objectBounds(at point: PixelPoint, in buffer: PixelBuffer) -> ObjectBounds {
        let clip = EdgeDetector(tolerance: tolerance, metric: metric, clip: self.clip).effectiveClip(in: buffer)
        precondition(clip.contains(point), "object detection start must be inside the clip rect")
        let reference = buffer.color(at: point)
        let similar = { (x: Int, y: Int) -> Bool in
            metric.distance(buffer.color(x: x, y: y), reference) <= tolerance
        }

        // Visited bitmap covers the clip rect only.
        let cw = clip.width, ch = clip.height
        var visited = [Bool](repeating: false, count: cw * ch)
        @inline(__always) func index(_ x: Int, _ y: Int) -> Int { (y - clip.minY) * cw + (x - clip.minX) }

        var minX = point.x, maxX = point.x, minY = point.y, maxY = point.y
        var count = 0
        var truncated = false

        // Each stack entry is a horizontal segment [x0, x1] on row y that is known
        // to be similar and not yet expanded to the rows above and below.
        var stack: [(x0: Int, x1: Int, y: Int)] = []

        // Seed: expand the start row.
        do {
            var x0 = point.x, x1 = point.x
            while x0 - 1 >= clip.minX, similar(x0 - 1, point.y) { x0 -= 1 }
            while x1 + 1 <= clip.maxX, similar(x1 + 1, point.y) { x1 += 1 }
            for x in x0...x1 { visited[index(x, point.y)] = true }
            count += x1 - x0 + 1
            minX = x0; maxX = x1
            stack.append((x0, x1, point.y))
        }

        outer: while let seg = stack.popLast() {
            for ny in [seg.y - 1, seg.y + 1] where ny >= clip.minY && ny <= clip.maxY {
                var x = seg.x0
                while x <= seg.x1 {
                    // Skip pixels that are visited or dissimilar.
                    if visited[index(x, ny)] || !similar(x, ny) {
                        x += 1
                        continue
                    }
                    // Found the start of a new run; extend left past seg.x0 if possible.
                    var x0 = x
                    while x0 - 1 >= clip.minX, !visited[index(x0 - 1, ny)], similar(x0 - 1, ny) { x0 -= 1 }
                    var x1 = x
                    while x1 + 1 <= clip.maxX, !visited[index(x1 + 1, ny)], similar(x1 + 1, ny) { x1 += 1 }
                    for vx in x0...x1 { visited[index(vx, ny)] = true }
                    count += x1 - x0 + 1
                    if x0 < minX { minX = x0 }
                    if x1 > maxX { maxX = x1 }
                    if ny < minY { minY = ny }
                    if ny > maxY { maxY = ny }
                    stack.append((x0, x1, ny))
                    if count >= maxPixels {
                        truncated = true
                        break outer
                    }
                    x = x1 + 1
                }
            }
        }

        return ObjectBounds(
            rect: PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1),
            pixelCount: count,
            truncated: truncated,
            reference: reference
        )
    }
}

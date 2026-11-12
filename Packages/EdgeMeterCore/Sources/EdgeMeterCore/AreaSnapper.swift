/// Snaps the four sides of a dragged rectangle to the nearest edges (feature 5.6).
///
/// Each side is snapped independently along the line through the rect's center:
/// the left and right sides scan the middle row, top and bottom the middle column.
/// Sides without an edge within `radius` stay where the user put them.
public struct AreaSnapper: Sendable {
    public var detector: EdgeDetector
    public var radius: Int

    public init(detector: EdgeDetector = EdgeDetector(), radius: Int = 8) {
        self.detector = detector
        self.radius = radius
    }

    public func snap(_ rect: PixelRect, in buffer: PixelBuffer) -> PixelRect {
        guard rect.width > 0, rect.height > 0 else { return rect }
        let clip = detector.effectiveClip(in: buffer)
        guard clip.width > 0, clip.height > 0 else { return rect }
        let midX = min(max(rect.x + rect.width / 2, clip.minX), clip.maxX)
        let midY = min(max(rect.y + rect.height / 2, clip.minY), clip.maxY)

        // A rect covering pixels minX...maxX spans boundaries minX and maxX + 1.
        let left = detector.nearestBoundary(to: rect.minX, along: midY, axis: .horizontal, radius: radius, in: buffer) ?? rect.minX
        let right = detector.nearestBoundary(to: rect.maxX + 1, along: midY, axis: .horizontal, radius: radius, in: buffer) ?? rect.maxX + 1
        let top = detector.nearestBoundary(to: rect.minY, along: midX, axis: .vertical, radius: radius, in: buffer) ?? rect.minY
        let bottom = detector.nearestBoundary(to: rect.maxY + 1, along: midX, axis: .vertical, radius: radius, in: buffer) ?? rect.maxY + 1

        guard right > left, bottom > top else { return rect }
        return PixelRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

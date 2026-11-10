import AppKit
import KaliberCore

/// Transparent layer above the snapshot: handles input for all four modes and draws
/// measurements in device-pixel space, so 1-px lines land exactly on pixels.
final class MeasureView: NSView {
    private weak var session: MeasureSession?
    let snapshot: DisplaySnapshot

    private(set) var pinned: [ScreenMeasurement] = []
    private var redoStack: [ScreenMeasurement] = []

    /// Pixel under the cursor, `nil` when the mouse is on another display.
    private var hoverPixel: PixelPoint?
    private var hoverSnap: SnapResult?
    private var drag: (start: CGPoint, current: CGPoint)? // in fractional device pixels
    private var flashText: String?
    private var flashTask: Task<Void, Never>?

    /// Forces the HUD on regardless of mouse position (used by the debug renderer).
    var forceActive = false

    init(snapshot: DisplaySnapshot, session: MeasureSession) {
        self.snapshot = snapshot
        self.session = session
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Coordinates

    private var buffer: PixelBuffer { snapshot.buffer }

    /// Device pixels per view point (normally the backing scale).
    private var pxPerPt: CGFloat {
        bounds.width > 0 ? CGFloat(buffer.width) / bounds.width : CGFloat(snapshot.displayScale)
    }

    private var displayScaleFactor: Double {
        session?.scaleMode.factor(displayScale: snapshot.displayScale) ?? snapshot.displayScale
    }

    private func devicePoint(_ p: NSPoint) -> CGPoint {
        CGPoint(x: p.x * pxPerPt, y: p.y * pxPerPt)
    }

    private func pixel(_ device: CGPoint) -> PixelPoint {
        PixelPoint(
            x: min(max(Int(device.x.rounded(.down)), 0), buffer.width - 1),
            y: min(max(Int(device.y.rounded(.down)), 0), buffer.height - 1)
        )
    }

    /// View coordinate of boundary `b` (between pixel b-1 and b).
    private func v(_ b: Int) -> CGFloat { CGFloat(b) / pxPerPt }
    /// View coordinate of the center of pixel `p`.
    private func c(_ p: Int) -> CGFloat { (CGFloat(p) + 0.5) / pxPerPt }

    private var snapRadiusPixels: Int {
        Int(((session?.snapRadiusPoints ?? 6) * Double(pxPerPt)).rounded())
    }

    private var modifiers: NSEvent.ModifierFlags {
        NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }

    // MARK: Hover

    func refreshHover() {
        if let p = hoverPixel, let session {
            hoverSnap = session.detector.snap(at: p, in: buffer)
        } else {
            hoverSnap = nil
        }
        needsDisplay = true
    }

    private func setHover(_ point: NSPoint?) {
        hoverPixel = point.map { pixel(devicePoint($0)) }
        refreshHover()
    }

    /// Debug renderer hook: hover a device pixel directly.
    func simulateHover(at p: PixelPoint) {
        hoverPixel = p
        refreshHover()
    }

    /// Debug renderer hook: pin a measurement directly.
    func simulatePin(_ m: ScreenMeasurement) {
        pin(m)
    }

    private var hoverMeasurement: ScreenMeasurement? {
        guard let session, let snap = hoverSnap else { return nil }
        switch session.mode {
        case .hover: return ScreenMeasurement(snap: snap, outside: modifiers.contains(.option))
        case .object: return .box(snap.insideRect)
        case .twoPoint, .area: return nil
        }
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self
        ))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        setHover(convert(event.locationInWindow, from: nil))
        session?.redrawAll() // HUD moves to this display
    }

    override func mouseExited(with event: NSEvent) {
        setHover(nil)
        session?.redrawAll()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        setHover(convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        guard let session else { return }
        let point = convert(event.locationInWindow, from: nil)
        setHover(point)
        switch session.mode {
        case .hover:
            if let m = hoverMeasurement { pin(m) }
        case .object:
            guard let p = hoverPixel else { return }
            let detector = ObjectDetector(from: session.detector)
            let result = detector.objectBounds(at: p, in: buffer)
            pin(.box(result.rect))
            if result.truncated { flash("Object too large – showing partial bounds") }
        case .twoPoint, .area:
            let d = devicePoint(point)
            drag = (d, d)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard drag != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        drag?.current = devicePoint(point)
        hoverPixel = pixel(devicePoint(point))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = nil; needsDisplay = true }
        guard let m = dragMeasurement else { return }
        switch m {
        case let .line(l) where l.length == 0: return
        default: pin(m)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.option) else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.002 : event.scrollingDeltaY * 0.01
        session?.adjustTolerance(by: delta)
    }

    override func keyDown(with event: NSEvent) {
        if session?.handleKey(event) != true { super.keyDown(with: event) }
    }

    /// The measurement currently being dragged out, with snapping unless ⌘ is held.
    private var dragMeasurement: ScreenMeasurement? {
        guard let session, let drag else { return nil }
        let snapping = !modifiers.contains(.command)
        let detector = session.detector
        switch session.mode {
        case .twoPoint:
            let dx = drag.current.x - drag.start.x
            let dy = drag.current.y - drag.start.y
            let startPixel = pixel(drag.start)
            if abs(dx) >= abs(dy) {
                var from = Int(drag.start.x.rounded())
                var to = Int(drag.current.x.rounded())
                if snapping {
                    from = detector.nearestBoundary(to: from, along: startPixel.y, axis: .horizontal, radius: snapRadiusPixels, in: buffer) ?? from
                    to = detector.nearestBoundary(to: to, along: startPixel.y, axis: .horizontal, radius: snapRadiusPixels, in: buffer) ?? to
                }
                return .line(LineMeasurement(axis: .horizontal, line: startPixel.y, from: from, to: to))
            } else {
                var from = Int(drag.start.y.rounded())
                var to = Int(drag.current.y.rounded())
                if snapping {
                    from = detector.nearestBoundary(to: from, along: startPixel.x, axis: .vertical, radius: snapRadiusPixels, in: buffer) ?? from
                    to = detector.nearestBoundary(to: to, along: startPixel.x, axis: .vertical, radius: snapRadiusPixels, in: buffer) ?? to
                }
                return .line(LineMeasurement(axis: .vertical, line: startPixel.x, from: from, to: to))
            }
        case .area:
            let a = pixel(drag.start), b = pixel(drag.current)
            let rect = PixelRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x) + 1, height: abs(a.y - b.y) + 1)
            guard snapping else { return .box(rect) }
            return .box(AreaSnapper(detector: detector, radius: snapRadiusPixels).snap(rect, in: buffer))
        case .hover, .object:
            return nil
        }
    }

    // MARK: Pinned measurements

    private func pin(_ m: ScreenMeasurement) {
        pinned.append(m)
        redoStack.removeAll()
        needsDisplay = true
    }

    func undo() {
        guard let m = pinned.popLast() else { NSSound.beep(); return }
        redoStack.append(m)
        needsDisplay = true
    }

    func redo() {
        guard let m = redoStack.popLast() else { NSSound.beep(); return }
        pinned.append(m)
        needsDisplay = true
    }

    func deleteLast() { undo() }

    func clearAll() {
        guard !pinned.isEmpty else { return }
        redoStack.append(contentsOf: pinned.reversed())
        pinned.removeAll()
        needsDisplay = true
    }

    private func text(_ m: ScreenMeasurement) -> String {
        m.text(format: session?.lengthFormat ?? LengthFormat(), scale: displayScaleFactor)
    }

    /// The hovered measurement, or the last pinned one.
    func currentMeasurementText() -> String? {
        (hoverMeasurement ?? pinned.last).map(text)
    }

    func allMeasurementsText() -> String? {
        pinned.isEmpty ? nil : pinned.map(text).joined(separator: "\n")
    }

    func flash(_ text: String) {
        flashText = text
        needsDisplay = true
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.flashText = nil
            self?.needsDisplay = true
        }
    }

    // MARK: Drawing

    private enum Style { case pinned, live }

    private let accent = NSColor.systemPink

    /// Rect labels must avoid (the HUD), set for the duration of one `draw` pass.
    private var reservedRect: CGRect?

    override func draw(_ dirtyRect: NSRect) {
        let hud = hudLayout
        reservedRect = hud?.rect.insetBy(dx: -4, dy: -4)
        defer { reservedRect = nil }
        for m in pinned { draw(m, style: .pinned) }
        if let m = dragMeasurement {
            draw(m, style: .live)
        } else if let m = hoverMeasurement {
            draw(m, style: .live)
        }
        if let hud { drawHUD(hud) }
        let active = forceActive || (session?.isActive(self) ?? false)
        if active, let flashText { drawFlash(flashText) }
    }

    private var hairline: CGFloat { 1 / pxPerPt }

    private func draw(_ m: ScreenMeasurement, style: Style) {
        let color = style == .live ? accent : accent.withAlphaComponent(0.85)
        let label = m.label(format: session?.lengthFormat ?? LengthFormat(), scale: displayScaleFactor)
        switch m {
        case let .cross(origin, h, vs):
            let y = c(origin.y), x = c(origin.x)
            if h.length > 0 {
                strokeLine(from: CGPoint(x: v(h.start), y: y), to: CGPoint(x: v(h.end + 1), y: y), color: color)
                tick(at: CGPoint(x: c(h.start), y: y), vertical: true, color: color)
                tick(at: CGPoint(x: c(h.end), y: y), vertical: true, color: color)
            }
            if vs.length > 0 {
                strokeLine(from: CGPoint(x: x, y: v(vs.start)), to: CGPoint(x: x, y: v(vs.end + 1)), color: color)
                tick(at: CGPoint(x: x, y: c(vs.start)), vertical: false, color: color)
                tick(at: CGPoint(x: x, y: c(vs.end)), vertical: false, color: color)
            }
            let fmt = session?.lengthFormat ?? LengthFormat()
            let w = fmt.label(pixels: h.length, scale: displayScaleFactor)
            let hgt = fmt.label(pixels: vs.length, scale: displayScaleFactor)
            drawLabel(w, at: CGPoint(x: (v(h.start) + v(h.end + 1)) / 2, y: y - 14), color: color)
            drawLabel(hgt, at: CGPoint(x: x + 8, y: (v(vs.start) + v(vs.end + 1)) / 2), color: color, anchorLeft: true)

        case let .line(l):
            if l.axis == .horizontal {
                let y = c(l.line)
                strokeLine(from: CGPoint(x: v(l.lower), y: y), to: CGPoint(x: v(l.upper), y: y), color: color)
                tick(at: CGPoint(x: v(l.lower), y: y), vertical: true, color: color)
                tick(at: CGPoint(x: v(l.upper), y: y), vertical: true, color: color)
                drawLabel(label, at: CGPoint(x: (v(l.lower) + v(l.upper)) / 2, y: y - 14), color: color)
            } else {
                let x = c(l.line)
                strokeLine(from: CGPoint(x: x, y: v(l.lower)), to: CGPoint(x: x, y: v(l.upper)), color: color)
                tick(at: CGPoint(x: x, y: v(l.lower)), vertical: false, color: color)
                tick(at: CGPoint(x: x, y: v(l.upper)), vertical: false, color: color)
                drawLabel(label, at: CGPoint(x: x + 8, y: (v(l.lower) + v(l.upper)) / 2), color: color, anchorLeft: true)
            }

        case let .box(r):
            // Outline on the pixel ring just outside the box, so the content stays visible.
            let outline = CGRect(x: c(r.minX - 1), y: c(r.minY - 1), width: v(r.width + 1), height: v(r.height + 1))
            color.withAlphaComponent(0.12).setFill()
            CGRect(x: v(r.minX), y: v(r.minY), width: v(r.width), height: v(r.height)).fill()
            let path = NSBezierPath(rect: outline)
            path.lineWidth = hairline
            color.setStroke()
            path.stroke()
            let below = CGPoint(x: outline.midX, y: outline.maxY + 12)
            let fitsBelow = below.y + 10 < bounds.height && !(reservedRect?.insetBy(dx: -40, dy: -10).contains(below) ?? false)
            drawLabel(label, at: fitsBelow ? below : CGPoint(x: outline.midX, y: outline.minY - 12), color: color)
        }
    }

    private func strokeLine(from a: CGPoint, to b: CGPoint, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: a)
        path.line(to: b)
        path.lineWidth = hairline
        color.setStroke()
        path.stroke()
    }

    /// Short perpendicular end mark, centered on `p`.
    private func tick(at p: CGPoint, vertical: Bool, color: NSColor) {
        let half: CGFloat = 4
        if vertical {
            strokeLine(from: CGPoint(x: p.x, y: p.y - half), to: CGPoint(x: p.x, y: p.y + half), color: color)
        } else {
            strokeLine(from: CGPoint(x: p.x - half, y: p.y), to: CGPoint(x: p.x + half, y: p.y), color: color)
        }
    }

    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: NSColor.white,
    ]

    private func drawLabel(_ text: String, at p: CGPoint, color: NSColor, anchorLeft: Bool = false) {
        let size = (text as NSString).size(withAttributes: Self.labelAttributes)
        let w = size.width + 10, h = size.height + 4
        var rect = CGRect(x: anchorLeft ? p.x : p.x - w / 2, y: p.y - h / 2, width: w, height: h)
        rect.origin.x = min(max(rect.minX, 2), bounds.width - w - 2)
        rect.origin.y = min(max(rect.minY, 2), bounds.height - h - 2)
        if let reserved = reservedRect, rect.intersects(reserved) {
            rect.origin.y = reserved.minY - h - 2
        }
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: rect.minX + 5, y: rect.minY + 2), withAttributes: Self.labelAttributes)
    }

    private struct HUDLayout {
        var rect: CGRect
        var status: String
        var hints: String
        var statusSize: CGSize
        var hintSize: CGSize
    }

    private static let hudStatusAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
        .foregroundColor: NSColor.white,
    ]
    private static let hudHintAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10.5),
        .foregroundColor: NSColor.white.withAlphaComponent(0.7),
    ]

    /// Where the HUD goes on this display, or `nil` if it isn't shown here.
    private var hudLayout: HUDLayout? {
        guard let session, session.showHUD, forceActive || session.isActive(self) else { return nil }
        var status = "\(session.mode.title)   \(session.scaleMode.label(displayScale: snapshot.displayScale))   Tolerance \(Int((session.tolerance * 100).rounded()))%"
        if let p = hoverPixel {
            let fmt = session.lengthFormat
            status += "   x \(fmt.string(pixels: p.x, scale: displayScaleFactor))  y \(fmt.string(pixels: p.y, scale: displayScaleFactor))"
        }
        let hints = "1–4 mode · S scale · [ ] or ⌥-scroll tolerance · ⌥ outside · ⌘ no snap · ⌘C copy · ⌘Z undo · X clear · H hide · Esc exit"
        let s1 = (status as NSString).size(withAttributes: Self.hudStatusAttributes)
        let s2 = (hints as NSString).size(withAttributes: Self.hudHintAttributes)
        let w = max(s1.width, s2.width) + 24
        let h = s1.height + s2.height + 16
        let rect = CGRect(x: (bounds.width - w) / 2, y: bounds.height - h - 24, width: w, height: h)
        return HUDLayout(rect: rect, status: status, hints: hints, statusSize: s1, hintSize: s2)
    }

    private func drawHUD(_ hud: HUDLayout) {
        let rect = hud.rect
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        (hud.status as NSString).draw(at: CGPoint(x: rect.midX - hud.statusSize.width / 2, y: rect.minY + 6), withAttributes: Self.hudStatusAttributes)
        (hud.hints as NSString).draw(at: CGPoint(x: rect.midX - hud.hintSize.width / 2, y: rect.minY + 8 + hud.statusSize.height), withAttributes: Self.hudHintAttributes)
    }

    private func drawFlash(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = CGRect(x: (bounds.width - size.width - 24) / 2, y: 40, width: size.width + 24, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        (text as NSString).draw(at: CGPoint(x: rect.minX + 12, y: rect.minY + 6), withAttributes: attrs)
    }
}

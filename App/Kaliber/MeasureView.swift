import AppKit
import KaliberCore

/// Transparent layer above the snapshot (frozen) or the live screen: handles input for all
/// four modes and draws measurements in device-pixel space, so 1-px lines land exactly on pixels.
final class MeasureView: NSView {
    private weak var session: MeasureSession?
    /// Backing scale of the display (device pixels per point).
    let displayScale: Double
    /// Pixels the detectors read: the snapshot, or the newest live frame. `nil` until the
    /// first live frame arrives.
    private(set) var buffer: PixelBuffer?
    var isLive = false { didSet { liveFrameTimes.removeAll(); lastCopyMilliseconds = nil; needsDisplay = true } }
    private var liveFrameTimes: [TimeInterval] = []
    private var lastCopyMilliseconds: Double?

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

    init(screen: NSScreen, session: MeasureSession) {
        displayScale = Double(screen.backingScaleFactor)
        self.session = session
        super.init(frame: .zero)
    }

    /// New pixels (snapshot or live frame): re-run hover detection on them.
    func setBuffer(_ buffer: PixelBuffer, copyMilliseconds: Double? = nil) {
        self.buffer = buffer
        if isLive {
            let now = ProcessInfo.processInfo.systemUptime
            liveFrameTimes.append(now)
            liveFrameTimes.removeAll { now - $0 > 1 }
            lastCopyMilliseconds = copyMilliseconds
        }
        refreshHover()
    }

    /// Frames received during the last second.
    private var liveFPS: Int {
        let now = ProcessInfo.processInfo.systemUptime
        return liveFrameTimes.filter { now - $0 <= 1 }.count
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Coordinates

    /// Device pixels per view point (normally the backing scale).
    private var pxPerPt: CGFloat {
        if let buffer, bounds.width > 0 { return CGFloat(buffer.width) / bounds.width }
        return CGFloat(displayScale)
    }

    private var displayScaleFactor: Double {
        session?.scaleMode.factor(displayScale: displayScale) ?? displayScale
    }

    private func devicePoint(_ p: NSPoint) -> CGPoint {
        CGPoint(x: p.x * pxPerPt, y: p.y * pxPerPt)
    }

    private func pixel(_ device: CGPoint) -> PixelPoint {
        let w = buffer?.width ?? Int((bounds.width * pxPerPt).rounded())
        let h = buffer?.height ?? Int((bounds.height * pxPerPt).rounded())
        return PixelPoint(
            x: min(max(Int(device.x.rounded(.down)), 0), max(w - 1, 0)),
            y: min(max(Int(device.y.rounded(.down)), 0), max(h - 1, 0))
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
        if let p = hoverPixel, let session, let buffer, buffer.contains(p) {
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

    #if DEBUG
    var debugHoverSnap: SnapResult? { hoverSnap }
    #endif

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
        // After ⌘-Tab another app holds the keyboard; take it back as soon as the mouse moves
        // over the overlay, so Esc and the mode keys keep working.
        if let window, !window.isKeyWindow {
            window.makeKey()
            window.makeFirstResponder(self)
        }
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
            guard let p = hoverPixel, let buffer, buffer.contains(p) else { return }
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
        // ⌥ means "scroll adjusts tolerance": take scroll events back right away.
        if event.modifierFlags.contains(.option) { session?.endScrollPassThrough() }
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.option) else {
            // Plain scrolling belongs to the app underneath (live mode only).
            session?.passScrollThrough()
            return
        }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.002 : event.scrollingDeltaY * 0.01
        session?.adjustTolerance(by: delta)
    }

    override func keyDown(with event: NSEvent) {
        if session?.handleKey(event) != true { super.keyDown(with: event) }
    }

    /// The measurement currently being dragged out, with snapping unless ⌘ is held.
    private var dragMeasurement: ScreenMeasurement? {
        guard let session, let drag, let buffer else { return nil }
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

    // MARK: Keyboard nudging

    /// Moves the cursor by whole device pixels. While dragging, the drag end moves along,
    /// so two-point and area measurements can be finished pixel by pixel.
    func nudge(dx: Int, dy: Int) {
        guard let buffer, let current = hoverPixel else { return }
        let target = PixelPoint(
            x: min(max(current.x + dx, 0), buffer.width - 1),
            y: min(max(current.y + dy, 0), buffer.height - 1)
        )
        let device: CGPoint
        if var d = drag {
            d.current.x += CGFloat(target.x - current.x)
            d.current.y += CGFloat(target.y - current.y)
            drag = d
            device = d.current
        } else {
            device = CGPoint(x: CGFloat(target.x) + 0.5, y: CGFloat(target.y) + 0.5)
        }
        hoverPixel = target
        refreshHover()
        warpCursor(toDevice: device)
    }

    /// Moves the system cursor without posting events (no Accessibility permission needed).
    private func warpCursor(toDevice d: CGPoint) {
        guard let window, let primary = NSScreen.screens.first else { return }
        let inWindow = convert(NSPoint(x: d.x / pxPerPt, y: d.y / pxPerPt), to: nil)
        let onScreen = window.convertPoint(toScreen: inWindow)
        // Quartz display coordinates: origin top-left of the primary display.
        CGWarpMouseCursorPosition(CGPoint(x: onScreen.x, y: primary.frame.maxY - onScreen.y))
        // Without this the mouse ignores physical movement for a moment after a warp.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// Re-reads the cursor position, e.g. after mouse events were passed through for a while.
    func syncHoverToMouse() {
        guard let window else { return }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = convert(inWindow, from: nil)
        setHover(bounds.contains(point) ? point : nil)
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
        if isLive {
            NSColor(white: 0, alpha: 0.004).setFill()
            bounds.fill()
        }
        for m in pinned { draw(m, style: .pinned) }
        if let m = dragMeasurement {
            draw(m, style: .live)
        } else if let m = hoverMeasurement {
            draw(m, style: .live)
        }
        let active = forceActive || (session?.isActive(self) ?? false)
        if active, session?.showLoupe == true, let p = hoverPixel, let buffer {
            drawLoupe(around: p, in: buffer, measurement: dragMeasurement ?? hoverMeasurement)
        }
        if let hud { drawHUD(hud) }
        if active, let flashText { drawFlash(flashText) }
    }

    private var hairline: CGFloat { 1 / pxPerPt }

    /// Pixels shown on each side of the center pixel, and the size of one shown pixel in points.
    private static let loupeRadius = 11
    private static let loupeCell: CGFloat = 6

    /// Magnified device pixels around `p`, read straight from the buffer (Kaliber's own
    /// windows are never in it), with the current measurement on top so small edges can be
    /// checked. Sits below-left of the cursor, away from hover labels.
    private func drawLoupe(around p: PixelPoint, in buffer: PixelBuffer, measurement: ScreenMeasurement?) {
        guard let ctx = NSGraphicsContext.current?.cgContext,
              let space = window?.screen?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        else { return }
        let r = Self.loupeRadius, cell = Self.loupeCell
        let n = 2 * r + 1
        let size = CGFloat(n) * cell
        let cursor = CGPoint(x: c(p.x), y: c(p.y))
        let gap: CGFloat = 24
        var rect = CGRect(x: cursor.x - gap - size, y: cursor.y + gap, width: size, height: size)
        if rect.minX < 4 { rect.origin.x = cursor.x + gap }
        if rect.maxY > bounds.height - 4 || (reservedRect?.intersects(rect) ?? false) {
            rect.origin.y = cursor.y - gap - size
        }
        // Whole device pixels, so the cells stay crisp.
        rect.origin.x = (rect.minX * pxPerPt).rounded() / pxPerPt
        rect.origin.y = (rect.minY * pxPerPt).rounded() / pxPerPt

        ctx.saveGState()
        NSColor.black.withAlphaComponent(0.35).setStroke()
        let shadow = NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: 7, yRadius: 7)
        shadow.lineWidth = 2
        shadow.stroke()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).addClip()
        NSColor.black.setFill()
        rect.fill()
        for j in 0..<n {
            for i in 0..<n {
                guard let px = buffer.colorIfInside(x: p.x - r + i, y: p.y - r + j),
                      let color = CGColor(colorSpace: space, components: [
                        CGFloat(px.r) / 255, CGFloat(px.g) / 255, CGFloat(px.b) / 255, 1,
                      ])
                else { continue }
                ctx.setFillColor(color)
                ctx.fill(CGRect(x: rect.minX + CGFloat(i) * cell, y: rect.minY + CGFloat(j) * cell, width: cell, height: cell))
            }
        }
        // Pixel grid.
        let grid = NSBezierPath()
        for k in 1..<n {
            let o = CGFloat(k) * cell + hairline / 2
            grid.move(to: CGPoint(x: rect.minX + o, y: rect.minY))
            grid.line(to: CGPoint(x: rect.minX + o, y: rect.maxY))
            grid.move(to: CGPoint(x: rect.minX, y: rect.minY + o))
            grid.line(to: CGPoint(x: rect.maxX, y: rect.minY + o))
        }
        grid.lineWidth = hairline
        NSColor.gray.withAlphaComponent(0.25).setStroke()
        grid.stroke()
        var labels: [String] = []
        if let measurement {
            labels = drawInLoupe(measurement, origin: PixelPoint(x: p.x - r, y: p.y - r), count: n, rect: rect)
        }
        // Center pixel: dark and light outline, visible on any color.
        let center = CGRect(x: rect.minX + CGFloat(r) * cell, y: rect.minY + CGFloat(r) * cell, width: cell, height: cell)
        let outer = NSBezierPath(rect: center.insetBy(dx: -hairline, dy: -hairline))
        outer.lineWidth = 2 * hairline
        NSColor.black.withAlphaComponent(0.6).setStroke()
        outer.stroke()
        let inner = NSBezierPath(rect: center.insetBy(dx: hairline, dy: hairline))
        inner.lineWidth = 2 * hairline
        NSColor.white.setStroke()
        inner.stroke()
        ctx.restoreGState()

        let border = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        border.lineWidth = 1
        NSColor.white.withAlphaComponent(0.85).setStroke()
        border.stroke()

        // Sizes whose ends are visible in the loupe, below it (above if there's no room).
        let spacing: CGFloat = 20
        let band = CGRect(x: rect.minX - 40, y: rect.maxY, width: rect.width + 80, height: CGFloat(labels.count) * spacing + 6)
        let below = band.maxY < bounds.height && !(reservedRect?.intersects(band) ?? false)
        for (i, label) in labels.enumerated() {
            let y = below ? rect.maxY + 12 + CGFloat(i) * spacing : rect.minY - 12 - CGFloat(i) * spacing
            drawLabel(label, at: CGPoint(x: rect.midX, y: y), color: accent)
        }
    }

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

    /// The measurement in loupe coordinates: lines through pixel centers, end marks exactly
    /// on the boundary between the last measured pixel and the edge. Returns the labels of
    /// the parts with an end inside the loupe.
    private func drawInLoupe(_ m: ScreenMeasurement, origin: PixelPoint, count n: Int, rect: CGRect) -> [String] {
        let cell = Self.loupeCell
        let format = session?.lengthFormat ?? LengthFormat()
        var labels: [String] = []
        func shows(_ b: Int, from o: Int) -> Bool { b >= o && b <= o + n }
        func vx(_ b: Int) -> CGFloat { rect.minX + CGFloat(b - origin.x) * cell }
        func vy(_ b: Int) -> CGFloat { rect.minY + CGFloat(b - origin.y) * cell }
        let path = NSBezierPath()
        func segment(_ a: CGPoint, _ b: CGPoint) { path.move(to: a); path.line(to: b) }
        func horizontal(y: Int, from: Int, to: Int) {
            let cy = vy(y) + cell / 2
            segment(CGPoint(x: vx(from), y: cy), CGPoint(x: vx(to), y: cy))
            for b in [from, to] { segment(CGPoint(x: vx(b), y: cy - cell), CGPoint(x: vx(b), y: cy + cell)) }
        }
        func vertical(x: Int, from: Int, to: Int) {
            let cx = vx(x) + cell / 2
            segment(CGPoint(x: cx, y: vy(from)), CGPoint(x: cx, y: vy(to)))
            for b in [from, to] { segment(CGPoint(x: cx - cell, y: vy(b)), CGPoint(x: cx + cell, y: vy(b))) }
        }
        switch m {
        case let .cross(o, h, vs):
            if h.length > 0 {
                horizontal(y: o.y, from: h.start, to: h.end + 1)
                if shows(h.start, from: origin.x) || shows(h.end + 1, from: origin.x) {
                    labels.append("↔ " + format.label(pixels: h.length, scale: displayScaleFactor))
                }
            }
            if vs.length > 0 {
                vertical(x: o.x, from: vs.start, to: vs.end + 1)
                if shows(vs.start, from: origin.y) || shows(vs.end + 1, from: origin.y) {
                    labels.append("↕ " + format.label(pixels: vs.length, scale: displayScaleFactor))
                }
            }
        case let .line(l):
            let (along, across) = l.axis == .horizontal ? (origin.x, origin.y) : (origin.y, origin.x)
            if l.axis == .horizontal { horizontal(y: l.line, from: l.lower, to: l.upper) }
            else { vertical(x: l.line, from: l.lower, to: l.upper) }
            if l.line >= across, l.line < across + n, shows(l.lower, from: along) || shows(l.upper, from: along) {
                labels.append(m.label(format: format, scale: displayScaleFactor))
            }
        case let .box(b):
            let box = CGRect(x: vx(b.minX), y: vy(b.minY), width: CGFloat(b.width) * cell, height: CGFloat(b.height) * cell)
            path.appendRect(box)
            if box.intersects(rect), !box.contains(rect) {
                labels.append(m.label(format: format, scale: displayScaleFactor))
            }
        }
        path.lineWidth = 1
        accent.withAlphaComponent(0.9).setStroke()
        path.stroke()
        return labels
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
        var status = "\(session.mode.title)   \(session.scaleMode.label(displayScale: displayScale))   Tolerance \(Int((session.tolerance * 100).rounded()))%"
        if isLive {
            status += buffer == nil
                ? "   Live: waiting for first frame"
                : "   Live \(liveFPS) fps" + (lastCopyMilliseconds.map { String(format: " · copy %.1f ms", $0) } ?? "")
        } else {
            status += "   Frozen"
        }
        if let p = hoverPixel {
            let fmt = session.lengthFormat
            status += "   x \(fmt.string(pixels: p.x, scale: displayScaleFactor))  y \(fmt.string(pixels: p.y, scale: displayScaleFactor))"
        }
        let hints = "1–4 mode · L live/frozen · ←→↑↓ nudge · Z loupe · S scale · - + or ⌥-scroll tolerance · ⌥ outside · ⌘ no snap · ⌘C copy · ⌘Z undo · X clear · H hide · Esc"
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

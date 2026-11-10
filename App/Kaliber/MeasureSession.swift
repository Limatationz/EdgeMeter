import AppKit
import KaliberCore

enum MeasureMode: Int, CaseIterable {
    case hover = 1, twoPoint, object, area

    var title: String {
        switch self {
        case .hover: "Hover"
        case .twoPoint: "Two-point"
        case .object: "Object"
        case .area: "Area"
        }
    }
}

/// State of one measuring session: one overlay window per display plus the settings
/// all overlays share (mode, scale, tolerance). Ends on Esc or the hotkey.
@MainActor
final class MeasureSession {
    var mode: MeasureMode = .hover { didSet { refreshAll() } }
    var scaleMode: ScaleMode = .auto { didSet { refreshAll() } }
    /// 0.02 ≈ 5 of 255 per channel: catches subtle UI edges (light borders, hairline
    /// separators) while ignoring capture noise. Adjustable live with [ ] and ⌥-scroll.
    var tolerance: Double = 0.02 { didSet { refreshAll() } }
    var showHUD = true { didSet { redrawAll() } }
    let lengthFormat = LengthFormat(maxDecimals: 1)
    /// Snap radius for two-point and area mode, in points (converted per display).
    let snapRadiusPoints: Double = 6

    private let snapshots: [DisplaySnapshot]
    private var windows: [OverlayWindow] = []
    private let onEnd: () -> Void
    private var ended = false

    init(snapshots: [DisplaySnapshot], onEnd: @escaping () -> Void) {
        self.snapshots = snapshots
        self.onEnd = onEnd
    }

    var detector: EdgeDetector { EdgeDetector(tolerance: tolerance, metric: .maxChannel) }

    func begin() {
        windows = snapshots.map { OverlayWindow(snapshot: $0, session: self) }
        for window in windows { window.orderFrontRegardless() }
        if let key = windowUnderMouse ?? windows.first {
            key.makeKeyAndOrderFront(nil)
            key.makeFirstResponder(key.measureView)
        }
        NSCursor.crosshair.set()
        refreshAll()
    }

    func end() {
        guard !ended else { return }
        ended = true
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        NSCursor.arrow.set()
        onEnd()
    }

    private var windowUnderMouse: OverlayWindow? {
        let mouse = NSEvent.mouseLocation
        return windows.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    /// The overlay under the mouse – keyboard commands act on it.
    var activeView: MeasureView? { (windowUnderMouse ?? windows.first)?.measureView }

    func isActive(_ view: MeasureView) -> Bool { activeView === view }

    /// Diagnostics for the debug session check: is keyboard input routed to an overlay?
    var keyboardState: String {
        let key = windows.first { $0.isKeyWindow }
        let responderOK = key.map { $0.firstResponder === $0.measureView } ?? false
        return "overlays=\(windows.count) keyOverlay=\(key != nil) firstResponderIsMeasureView=\(responderOK) appActive=\(NSApp.isActive)"
    }

    /// Recompute hover results (after tolerance/mode changes) and redraw.
    func refreshAll() {
        for window in windows { window.measureView.refreshHover() }
    }

    func redrawAll() {
        for window in windows { window.measureView.needsDisplay = true }
    }

    // MARK: Keyboard

    /// Returns `true` if the key was handled.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch event.keyCode {
        case 53: // Esc
            end()
            return true
        case 51, 117: // Delete, Forward Delete
            activeView?.deleteLast()
            return true
        default:
            break
        }

        if command {
            switch key {
            case "z":
                if shift { activeView?.redo() } else { activeView?.undo() }
                return true
            case "c":
                copy(all: shift)
                return true
            default:
                return false
            }
        }

        switch key {
        case "1", "2", "3", "4":
            if let n = Int(key), let m = MeasureMode(rawValue: n) { mode = m }
        case "s":
            scaleMode = scaleMode.next
        case "h":
            showHUD.toggle()
        case "[":
            tolerance = max(0, tolerance - 0.01)
        case "]":
            tolerance = min(1, tolerance + 0.01)
        case "x":
            activeView?.clearAll()
        default:
            return false
        }
        return true
    }

    func adjustTolerance(by delta: Double) {
        tolerance = min(1, max(0, tolerance + delta))
    }

    private func copy(all: Bool) {
        guard let view = activeView else { return }
        let text = all ? view.allMeasurementsText() : view.currentMeasurementText()
        guard let text, !text.isEmpty else { NSSound.beep(); return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        view.flash("Copied \(text.contains("\n") ? "all" : text)")
    }
}

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
    /// Edge tolerance, remembered across sessions. Default 0.04 ≈ 10 of 255 per channel:
    /// found by hand-testing on real UIs to catch very light borders (#F5F5F5 on white)
    /// while ignoring anti-aliasing and subtle gradients. Adjustable live with - + ([ ]) and ⌥-scroll.
    var tolerance: Double = MeasureSession.storedTolerance {
        didSet {
            UserDefaults.standard.set(tolerance, forKey: Self.toleranceKey)
            refreshAll()
        }
    }

    static let defaultTolerance = 0.04
    private static let toleranceKey = "edgeTolerance"

    private static var storedTolerance: Double {
        guard let value = UserDefaults.standard.object(forKey: toleranceKey) as? Double,
              (0...1).contains(value) else { return defaultTolerance }
        return value
    }
    var showHUD = true { didSet { redrawAll() } }
    /// Magnified pixels around the cursor. Toggled with Z and remembered across sessions.
    var showLoupe: Bool = UserDefaults.standard.object(forKey: MeasureSession.loupeKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showLoupe, forKey: Self.loupeKey)
            redrawAll()
        }
    }
    private static let loupeKey = "showLoupe"
    let lengthFormat = LengthFormat(maxDecimals: 1)
    /// Snap radius for two-point and area mode, in points (converted per display).
    let snapRadiusPoints: Double = 6

    /// Live mode (transparent overlay, continuous capture, default) vs. frozen snapshot.
    /// Toggled with L and remembered across sessions.
    private(set) var isLive: Bool

    /// Live is the default: measured at under 10 % of one core even with constant animation
    /// (FEATURES.md §19), and it keeps ⌘-Tab and moving content usable. Frozen stays one
    /// key away (L), and the last choice wins.
    static var storedLiveMode: Bool {
        UserDefaults.standard.object(forKey: liveModeKey) as? Bool ?? true
    }
    private static let liveModeKey = "liveMode"

    private let screens: [NSScreen]
    private let initialSnapshots: [DisplaySnapshot]
    private var windows: [OverlayWindow] = []
    private var liveCapture: LiveCapture?
    private let onEnd: () -> Void
    private var ended = false

    /// - Parameters:
    ///   - snapshots: frozen captures to start with; ignored when starting live.
    init(screens: [NSScreen], snapshots: [DisplaySnapshot], live: Bool, onEnd: @escaping () -> Void) {
        self.screens = screens
        self.initialSnapshots = snapshots
        self.isLive = live
        self.onEnd = onEnd
    }

    var detector: EdgeDetector { EdgeDetector(tolerance: tolerance, metric: .maxChannel) }

    func begin() {
        windows = screens.map { OverlayWindow(screen: $0, session: self) }
        if isLive {
            startLive()
        } else {
            for window in windows {
                if let snap = initialSnapshots.first(where: { $0.screen.displayID == window.displayID }) {
                    window.showFrozen(image: snap.image, buffer: snap.buffer)
                }
            }
        }
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
        endScrollPassThrough()
        liveCapture?.stop()
        liveCapture = nil
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

    // MARK: Live / frozen

    func toggleLive() {
        if isLive { freeze() } else { goLive() }
    }

    private func goLive() {
        isLive = true
        UserDefaults.standard.set(true, forKey: Self.liveModeKey)
        for window in windows { window.showLive() }
        startLive()
        refreshAll()
    }

    /// Freezes the newest live frame of every display – no new capture needed.
    private func freeze() {
        endScrollPassThrough()
        liveCapture?.stop()
        liveCapture = nil
        isLive = false
        UserDefaults.standard.set(false, forKey: Self.liveModeKey)
        for window in windows {
            guard let buffer = window.measureView.buffer,
                  let space = window.screen?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                  let image = buffer.makeCGImage(colorSpace: space)
            else { continue }
            window.showFrozen(image: image, buffer: buffer)
        }
        refreshAll()
    }

    private func startLive() {
        let capture = LiveCapture(
            onFrame: { [weak self] frame in self?.receive(frame) },
            onError: { [weak self] error in self?.liveFailed(error) }
        )
        liveCapture = capture
        Task { [weak self] in
            do {
                try await capture.start(screens: self?.screens ?? [])
            } catch {
                self?.liveFailed(error)
            }
        }
    }

    private func receive(_ frame: LiveFrame) {
        guard isLive, !ended else { return }
        windows.first { $0.displayID == frame.displayID }?
            .measureView.setBuffer(frame.buffer, copyMilliseconds: frame.copyMilliseconds)
    }

    private func liveFailed(_ error: Error) {
        guard !ended else { return }
        NSLog("Kaliber: live capture failed: \(error)")
        activeView?.flash("Live capture failed: \(error.localizedDescription)")
    }

    // MARK: Scroll pass-through (live mode)
    //
    // An overlay window can't hand a single event to the window below it, and re-posting
    // events would need Accessibility permission. Instead the overlays briefly stop taking
    // mouse events, so the rest of the scroll gesture lands in the app underneath. A global
    // scroll monitor (no permission needed for mouse events) notices when scrolling stops,
    // then the overlays take the mouse back. The first scroll event of a gesture is lost,
    // which is one tick and not noticeable on a trackpad.

    private var scrollMonitor: Any?
    private var restoreTask: Task<Void, Never>?
    private(set) var isPassingScrollThrough = false
    /// Quiet time after the last scroll event (incl. trackpad momentum) before the overlay
    /// takes the mouse back.
    private let scrollIdle: Duration = .milliseconds(300)

    func passScrollThrough() {
        // Frozen: the app underneath is hidden behind the snapshot, so scrolling it would
        // only make the measurements stale without any visible effect.
        guard isLive, !ended else { return }
        if !isPassingScrollThrough {
            isPassingScrollThrough = true
            for window in windows { window.ignoresMouseEvents = true }
            scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let option = event.modifierFlags.contains(.option)
                MainActor.assumeIsolated {
                    if option { self?.endScrollPassThrough() } else { self?.scheduleScrollRestore() }
                }
            }
        }
        scheduleScrollRestore()
    }

    func endScrollPassThrough() {
        restoreTask?.cancel()
        restoreTask = nil
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        guard isPassingScrollThrough else { return }
        isPassingScrollThrough = false
        for window in windows { window.ignoresMouseEvents = false }
        activeView?.syncHoverToMouse()
    }

    private func scheduleScrollRestore() {
        restoreTask?.cancel()
        restoreTask = Task { [weak self, scrollIdle] in
            try? await Task.sleep(for: scrollIdle)
            guard !Task.isCancelled else { return }
            self?.endScrollPassThrough()
        }
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
        case 123, 124, 125, 126: // ← → ↓ ↑: move by one device pixel, ⇧ by ten
            guard !command else { return false }
            let step = shift ? 10 : 1
            let (dx, dy) = switch event.keyCode {
            case 123: (-step, 0)
            case 124: (step, 0)
            case 125: (0, step)
            default: (0, -step)
            }
            activeView?.nudge(dx: dx, dy: dy)
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

        // Tolerance by the typed character, so layouts where [ ] need ⌥ (German: ⌥5 ⌥6) work;
        // - and + (or = on US layouts) are reachable without modifiers everywhere.
        switch event.characters ?? "" {
        case "[", "-":
            tolerance = max(0, tolerance - 0.01)
            return true
        case "]", "+", "=":
            tolerance = min(1, tolerance + 0.01)
            return true
        default:
            break
        }

        switch key {
        case "1", "2", "3", "4":
            if let n = Int(key), let m = MeasureMode(rawValue: n) { mode = m }
        case "l":
            toggleLive()
        case "s":
            scaleMode = scaleMode.next
        case "h":
            showHUD.toggle()
        case "z":
            showLoupe.toggle()
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

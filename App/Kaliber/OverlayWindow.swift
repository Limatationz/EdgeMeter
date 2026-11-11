import AppKit
import KaliberCore

/// Borderless full-screen window above everything for one display (FEATURES.md 3.3, 17).
///
/// *Frozen*: shows a snapshot under the measurement layer and covers the screen.
/// *Live*: transparent; the real screen shows through and frames come from a stream.
///
/// It is a *non-activating panel*: it can become the key window and receive keyboard
/// events while Kaliber stays a background app. A plain NSWindow needs the app to be
/// activated first, and since macOS 14 activation from a hot key is only a request the
/// system may ignore – the keys then go to the previously active app.
final class OverlayWindow: NSPanel {
    let measureView: MeasureView
    let displayID: CGDirectDisplayID?
    private let container: NSView
    private var snapshotView: SnapshotView?

    init(screen: NSScreen, session: MeasureSession) {
        let frame = screen.frame
        displayID = screen.displayID
        measureView = MeasureView(screen: screen, session: session)
        container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(frame, display: false)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hasShadow = false
        // Explicitly false: receive mouse events even where the window is transparent (live mode).
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false

        measureView.frame = container.bounds
        measureView.autoresizingMask = [.width, .height]
        container.addSubview(measureView)
        if let backdrop = GlassBackdrop.makeIfAvailable(frame: container.bounds) {
            backdrop.autoresizingMask = [.width, .height]
            container.addSubview(backdrop, positioned: .below, relativeTo: measureView)
            measureView.backdrop = backdrop
        }
        contentView = container
        makeFirstResponder(measureView)
        showLive() // neutral state until a mode is chosen
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Frozen: snapshot below the measurement layer; covers everything incl. the menu bar.
    func showFrozen(image: CGImage, buffer: PixelBuffer) {
        snapshotView?.removeFromSuperview()
        let view = SnapshotView(image: image, frame: container.bounds)
        view.autoresizingMask = [.width, .height]
        container.addSubview(view, positioned: .below, relativeTo: nil) // under glass and measure view
        snapshotView = view
        isOpaque = true
        backgroundColor = .black
        level = .screenSaver
        measureView.isLive = false
        measureView.setBuffer(buffer)
    }

    /// Live: transparent, so apps (and app switching) stay visible underneath. Sits just
    /// above the menu bar instead of at screen-saver level, so system UI like the ⌘-Tab
    /// switcher can still appear on top.
    func showLive() {
        snapshotView?.removeFromSuperview()
        snapshotView = nil
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        measureView.isLive = true
    }
}

/// Shows the frozen capture via a layer, so mouse moves never redraw the full image.
final class SnapshotView: NSView {
    init(image: CGImage, frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

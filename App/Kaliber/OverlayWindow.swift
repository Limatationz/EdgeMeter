import AppKit

/// Borderless full-screen window above everything, showing the frozen snapshot of one
/// display with the measurement layer on top (FEATURES.md 3.3, 17).
///
/// It is a *non-activating panel*: it can become the key window and receive keyboard
/// events while Kaliber stays a background app. A plain NSWindow needs the app to be
/// activated first, and since macOS 14 activation from a hot key is only a request the
/// system may ignore – the keys then go to the previously active app.
final class OverlayWindow: NSPanel {
    let measureView: MeasureView

    init(snapshot: DisplaySnapshot, session: MeasureSession) {
        let frame = snapshot.screen.frame
        measureView = MeasureView(snapshot: snapshot, session: session)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        let snapshotView = SnapshotView(image: snapshot.image, frame: container.bounds)
        snapshotView.autoresizingMask = [.width, .height]
        measureView.frame = container.bounds
        measureView.autoresizingMask = [.width, .height]
        container.addSubview(snapshotView)
        container.addSubview(measureView)
        contentView = container
        makeFirstResponder(measureView)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
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

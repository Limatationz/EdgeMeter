import AppKit

/// Borderless full-screen window above everything, showing the frozen snapshot of one
/// display with the measurement layer on top (FEATURES.md 3.3, 17).
final class OverlayWindow: NSWindow {
    let measureView: MeasureView

    init(snapshot: DisplaySnapshot, session: MeasureSession) {
        let frame = snapshot.screen.frame
        measureView = MeasureView(snapshot: snapshot, session: session)
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
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
    override var canBecomeMain: Bool { true }
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

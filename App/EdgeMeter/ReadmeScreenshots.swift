#if DEBUG
import AppKit
import EdgeMeterCore

/// `-readmeScreenshots <dir>`: stages a neutral demo window, measures it live and captures the
/// README images (`hero.png`, `pinned.png`, `settings.png`). Covers the middle of the main
/// display for about ten seconds; the cursor is not moved.
@MainActor
enum ReadmeScreenshots {
    static func runIfRequested() -> Bool {
        guard let dir = UserDefaults.standard.string(forKey: "readmeScreenshots") else { return false }
        Task { await run(into: URL(fileURLWithPath: dir)) }
        return true
    }

    private static func run(into dir: URL) async {
        guard let screen = NSScreen.main else { exit(1) }
        NSApp.appearance = NSAppearance(named: .aqua)
        let settings = AppSettings.shared
        let savedLoupe = settings.showLoupe

        let size = NSSize(width: 920, height: 580)
        let frame = NSRect(x: (screen.frame.midX - size.width / 2).rounded(),
                           y: (screen.frame.midY - size.height / 2).rounded(),
                           width: size.width, height: size.height)
        let crop = frame.insetBy(dx: -56, dy: -56)
        let backdrop = makeBackdrop(covering: crop.insetBy(dx: -20, dy: -20))
        let demo = DemoWindow(frame: frame)
        backdrop.orderFrontRegardless()
        demo.orderFrontRegardless()
        LiveCapture.debugCaptureOwnWindows = true
        try? await Task.sleep(for: .milliseconds(600))

        let session = MeasureSession(screens: [screen], snapshots: [], live: true) {}
        session.showHUD = false
        session.showLoupe = true
        session.begin()
        try? await Task.sleep(for: .seconds(1.5))
        guard let view = session.activeView, let buffer = view.buffer else { exit(1) }

        // Hero: hover between the two fields, loupe at the field's corner.
        view.simulateHover(at: view.debugPixel(atScreen: demo.heroPoint))
        try? await Task.sleep(for: .milliseconds(700))
        capture(crop, to: dir.appendingPathComponent("hero.png"))

        // Pinned: object (Continue button), area (email field), gap between the buttons.
        session.showLoupe = false
        view.simulateHover(at: nil)
        let detector = session.detector
        if let p = view.debugPixel(atScreen: demo.continueButtonPoint) {
            view.simulatePin(.box(ObjectDetector(from: detector).objectBounds(at: p, in: buffer).rect))
        }
        if let a = view.debugPixel(atScreen: NSPoint(x: demo.emailFieldFrame.minX - 4, y: demo.emailFieldFrame.maxY + 4)),
           let b = view.debugPixel(atScreen: NSPoint(x: demo.emailFieldFrame.maxX + 4, y: demo.emailFieldFrame.minY - 4)) {
            let rough = PixelRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            view.simulatePin(.box(AreaSnapper(detector: detector, radius: 16).snap(rough, in: buffer)))
        }
        if let from = view.debugPixel(atScreen: demo.gapStart), let to = view.debugPixel(atScreen: demo.gapEnd) {
            let start = detector.nearestBoundary(to: from.x, along: from.y, axis: .horizontal, radius: 12, in: buffer) ?? from.x
            let end = detector.nearestBoundary(to: to.x, along: from.y, axis: .horizontal, radius: 12, in: buffer) ?? to.x
            view.simulatePin(.line(LineMeasurement(axis: .horizontal, line: from.y, from: start, to: end)))
        }
        try? await Task.sleep(for: .milliseconds(500))
        capture(crop, to: dir.appendingPathComponent("pinned.png"))

        session.end()
        settings.showLoupe = savedLoupe
        demo.orderOut(nil)
        backdrop.orderOut(nil)

        // Settings window, with its shadow.
        SettingsWindowController.shared.show()
        try? await Task.sleep(for: .milliseconds(800))
        if let window = NSApp.windows.first(where: { $0.title == "EdgeMeter Settings" }) {
            run("/usr/sbin/screencapture", ["-x", "-l", "\(window.windowNumber)", dir.appendingPathComponent("settings.png").path])
        }
        print("EdgeMeter: wrote README screenshots to \(dir.path)")
        exit(0)
    }

    private static func capture(_ rect: NSRect, to url: URL) {
        let top = NSScreen.screens[0].frame.maxY - rect.maxY
        let region = "\(Int(rect.minX)),\(Int(top)),\(Int(rect.width)),\(Int(rect.height))"
        run("/usr/sbin/screencapture", ["-x", "-R", region, url.path])
    }

    private static func run(_ tool: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
    }

    /// Soft gradient behind the demo window, so no private desktop shows in the crop.
    private static func makeBackdrop(covering rect: NSRect) -> NSWindow {
        let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let gradient = NSView(frame: NSRect(origin: .zero, size: rect.size))
        gradient.wantsLayer = true
        let layer = CAGradientLayer()
        layer.colors = [NSColor(srgbRed: 0.80, green: 0.85, blue: 0.96, alpha: 1).cgColor,
                        NSColor(srgbRed: 0.93, green: 0.84, blue: 0.93, alpha: 1).cgColor]
        layer.startPoint = CGPoint(x: 0, y: 1)
        layer.endPoint = CGPoint(x: 1, y: 0)
        gradient.layer = layer
        window.contentView = gradient
        return window
    }
}

/// A neutral "create account" window built from real AppKit controls.
@MainActor
private final class DemoWindow: NSWindow {
    // Positions in content coordinates; converted to the screen when asked, after the window
    // is on screen and has its final frame.
    private var hero = NSPoint.zero
    private var continueButton = NSPoint.zero
    private var emailField = NSRect.zero
    private var gapFrom = NSPoint.zero
    private var gapTo = NSPoint.zero

    var heroPoint: NSPoint { screen(hero) }
    var continueButtonPoint: NSPoint { screen(continueButton) }
    var emailFieldFrame: NSRect { convertToScreen(contentView!.convert(emailField, to: nil)) }
    var gapStart: NSPoint { screen(gapFrom) }
    var gapEnd: NSPoint { screen(gapTo) }

    private func screen(_ point: NSPoint) -> NSPoint {
        convertPoint(toScreen: contentView!.convert(point, to: nil))
    }

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        titlebarAppearsTransparent = true
        title = ""
        let content = FlippedView(frame: NSRect(origin: .zero, size: frame.size))
        contentView = content

        let sidebar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 220, height: frame.height))
        sidebar.material = .sidebar
        content.addSubview(sidebar)
        for (i, item) in [("person.crop.circle", "Account"), ("bell", "Notifications"), ("lock", "Privacy"), ("creditcard", "Billing")].enumerated() {
            let row = NSStackView(views: [
                NSImageView(image: NSImage(systemSymbolName: item.0, accessibilityDescription: nil)!),
                NSTextField(labelWithString: item.1),
            ])
            row.frame = NSRect(x: 24, y: 64 + CGFloat(i) * 34, width: 172, height: 24)
            content.addSubview(row)
        }

        let x: CGFloat = 268
        let title = NSTextField(labelWithString: "Create your account")
        title.font = .systemFont(ofSize: 26, weight: .bold)
        title.frame = NSRect(x: x, y: 56, width: 500, height: 34)
        content.addSubview(title)
        let subtitle = NSTextField(labelWithString: "It takes less than a minute. You can change everything later.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: x, y: 96, width: 560, height: 20)
        content.addSubview(subtitle)

        let card = NSBox(frame: NSRect(x: x, y: 140, width: 600, height: 340))
        card.boxType = .custom
        card.fillColor = .white
        card.borderColor = NSColor(white: 0.86, alpha: 1)
        card.cornerRadius = 14
        content.addSubview(card)

        func label(_ text: String, y: CGFloat) {
            let l = NSTextField(labelWithString: text)
            l.font = .systemFont(ofSize: 13, weight: .medium)
            l.frame = NSRect(x: x + 32, y: y, width: 300, height: 18)
            content.addSubview(l)
        }
        func field(_ placeholder: String, y: CGFloat) -> NSTextField {
            let f = NSTextField(frame: NSRect(x: x + 32, y: y, width: 536, height: 28))
            f.placeholderString = placeholder
            f.bezelStyle = .roundedBezel
            content.addSubview(f)
            return f
        }
        label("Name", y: 172)
        let name = field("Jane Appleseed", y: 196)
        label("Email", y: 248)
        let email = field("jane@example.com", y: 272)
        let updates = NSButton(checkboxWithTitle: "Send me product updates", target: nil, action: nil)
        updates.frame = NSRect(x: x + 32, y: 324, width: 300, height: 20)
        content.addSubview(updates)

        let cancel = NSButton(title: "Cancel", target: nil, action: nil)
        cancel.bezelStyle = .push
        cancel.controlSize = .large
        cancel.frame = NSRect(x: x + 344, y: 410, width: 100, height: 36)
        content.addSubview(cancel)
        let go = NSButton(title: "Continue", target: nil, action: nil)
        go.bezelStyle = .push
        go.controlSize = .large
        go.keyEquivalent = "\r"
        go.frame = NSRect(x: x + 456, y: 410, width: 112, height: 36)
        content.addSubview(go)

        // Just below the name field's bottom edge: the loupe shows that edge with the end mark.
        hero = NSPoint(x: x + 220, y: name.frame.maxY + 2.5)
        continueButton = NSPoint(x: go.frame.minX + 10, y: go.frame.midY)
        emailField = email.frame
        gapFrom = NSPoint(x: cancel.frame.maxX - 3, y: cancel.frame.midY)
        gapTo = NSPoint(x: go.frame.minX + 3, y: cancel.frame.midY)
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
#endif

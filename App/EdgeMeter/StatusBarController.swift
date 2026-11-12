import AppKit
import EdgeMeterCore

/// Owns the menu-bar item (FEATURES.md 3.1). The shortcut shown next to "Measure" is only a
/// hint; the global shortcut itself is registered by `HotKeyCenter`.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let measureItem = NSMenuItem(title: "Measure", action: #selector(startMeasuring), keyEquivalent: "")

    func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.menuBarImage
            button.toolTip = "EdgeMeter – screen measurement"
        }
        item.menu = makeMenu()
        return item
    }

    /// The app icon's caliper as a template image (18 pt): beam with a few scale marks, slider,
    /// two pointed jaws and the measure line between them. Drawn as vectors, so it stays crisp
    /// at every scale; template rendering lets macOS tint it for light and dark menu bars.
    static let menuBarImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            // Beam with scale marks cut out.
            let beam = NSBezierPath(roundedRect: NSRect(x: 1, y: 3, width: 16, height: 3), xRadius: 0.8, yRadius: 0.8)
            for x in stride(from: 4.5, through: 8.5, by: 2) {
                beam.append(NSBezierPath(rect: NSRect(x: x, y: 3.6, width: 0.7, height: 1.3)))
            }
            beam.windingRule = .evenOdd
            beam.fill()
            // Slider housing.
            NSBezierPath(roundedRect: NSRect(x: 10.3, y: 2, width: 4.4, height: 5), xRadius: 1, yRadius: 1).fill()
            // Jaws, measuring faces inside, tips pointing at each other.
            let fixed = NSBezierPath()
            fixed.move(to: NSPoint(x: 1, y: 5))
            fixed.line(to: NSPoint(x: 3.6, y: 5))
            fixed.line(to: NSPoint(x: 3.6, y: 16.5))
            fixed.line(to: NSPoint(x: 1, y: 12.5))
            fixed.close()
            fixed.fill()
            let sliding = NSBezierPath()
            sliding.move(to: NSPoint(x: 10.9, y: 6))
            sliding.line(to: NSPoint(x: 13.5, y: 6))
            sliding.line(to: NSPoint(x: 13.5, y: 12.5))
            sliding.line(to: NSPoint(x: 10.9, y: 16.5))
            sliding.close()
            sliding.fill()
            // Measure line with end marks.
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 4.6, y: 12))
            line.line(to: NSPoint(x: 9.9, y: 12))
            line.move(to: NSPoint(x: 4.6, y: 10.2))
            line.line(to: NSPoint(x: 4.6, y: 13.8))
            line.move(to: NSPoint(x: 9.9, y: 10.2))
            line.line(to: NSPoint(x: 9.9, y: 13.8))
            line.lineWidth = 1.1
            NSColor.black.setStroke()
            line.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "EdgeMeter"
        return image
    }()

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        measureItem.target = self
        menu.addItem(measureItem)

        menu.addItem(.separator())

        let version = NSMenuItem(title: "EdgeMeter \(appVersion) · Core \(EdgeMeterCore.version)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        let intro = NSMenuItem(title: "Introduction…", action: #selector(openIntroduction), keyEquivalent: "")
        intro.target = self
        menu.addItem(intro)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit EdgeMeter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    @objc private func startMeasuring() {
        MeasureController.shared.toggle()
    }

    /// Keeps the shortcut hint in sync with the settings.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let hotKey = AppSettings.shared.hotKey
        // Menus can only show printable keys as key equivalents.
        let printable = hotKey.keyLabel.count == 1
        measureItem.keyEquivalent = printable ? hotKey.keyLabel.lowercased() : ""
        measureItem.keyEquivalentModifierMask = printable ? hotKey.modifierFlags : []
        measureItem.title = printable ? "Measure" : "Measure (\(hotKey.display))"
    }

    @objc private func openIntroduction() {
        OnboardingWindowController.shared.show()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }
}

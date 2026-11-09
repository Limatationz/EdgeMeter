import AppKit
import KaliberCore

/// Owns the menu-bar item (FEATURES.md 3.1). Measuring mode itself is not wired up yet;
/// the menu is the skeleton the overlay, shortcut and settings will hang off.
@MainActor
final class StatusBarController: NSObject {
    func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "ruler", accessibilityDescription: "Kaliber")
            button.image?.isTemplate = true
            button.toolTip = "Kaliber – screen measurement"
        }
        item.menu = makeMenu()
        return item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let measure = NSMenuItem(title: "Measure", action: #selector(startMeasuring), keyEquivalent: "m")
        measure.keyEquivalentModifierMask = [.control, .option, .command]
        measure.target = self
        menu.addItem(measure)

        menu.addItem(.separator())

        let version = NSMenuItem(title: "Kaliber \(appVersion) · Core \(KaliberCore.version)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Kaliber", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    @objc private func startMeasuring() {
        // TODO: capture snapshot per display (ScreenCaptureKit), show overlay windows,
        // run EdgeDetector.snap on hover. See docs/FEATURES.md §3, §4, §17.
        let alert = NSAlert()
        alert.messageText = "Measuring mode is not implemented yet"
        alert.informativeText = "The detection core (KaliberCore) is in place and tested; the overlay UI comes next."
        alert.runModal()
    }

    @objc private func openSettings() {
        // TODO: settings window (FEATURES.md §14).
    }
}

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
            button.image = NSImage(systemSymbolName: "ruler", accessibilityDescription: "EdgeMeter")
            button.image?.isTemplate = true
            button.toolTip = "EdgeMeter – screen measurement"
        }
        item.menu = makeMenu()
        return item
    }

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

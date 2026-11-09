import AppKit
import KaliberCore

/// Owns the menu-bar item (FEATURES.md 3.1). The ⌃⌥⌘M shown in the menu is only a hint;
/// the actual global shortcut is registered in `AppDelegate`.
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
        MeasureController.shared.toggle()
    }

    @objc private func openSettings() {
        // TODO: settings window (FEATURES.md §14).
    }
}

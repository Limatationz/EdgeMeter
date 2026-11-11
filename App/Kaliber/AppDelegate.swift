import AppKit
import Carbon.HIToolbox
import KaliberCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let statusBarController = StatusBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if DebugRenderer.runIfRequested() || DebugRenderer.runSessionIfRequested()
            || DebugRenderer.runLiveProbeIfRequested()
            || DebugRenderer.renderSettingsIfRequested() { return }
        #endif
        if LiveBenchmark.runIfRequested() { return }

        statusItem = statusBarController.makeStatusItem()
        // Default ⌃⌥⌘M (FEATURES.md 3.2), changeable in the settings window.
        HotKeyCenter.shared.action = { MeasureController.shared.toggle() }
        let hotKey = AppSettings.shared.hotKey
        if !HotKeyCenter.shared.register(hotKey) {
            NSLog("Kaliber: could not register \(hotKey.display) – another app may already use it.")
        }

        if !ScreenCapture.hasPermission {
            // Triggers the system prompt on first launch so the user isn't surprised later.
            ScreenCapture.requestPermission()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

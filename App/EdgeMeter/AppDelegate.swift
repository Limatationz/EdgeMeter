import AppKit
import Carbon.HIToolbox
import EdgeMeterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let statusBarController = StatusBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if DebugRenderer.runIfRequested() || DebugRenderer.runSessionIfRequested()
            || DebugRenderer.runLiveProbeIfRequested()
            || DebugRenderer.renderSettingsIfRequested()
            || DebugRenderer.renderOnboardingIfRequested()
            || DebugRenderer.renderMenuIconIfRequested()
            || ReadmeScreenshots.runIfRequested() { return }
        #endif
        if LiveBenchmark.runIfRequested() { return }

        statusItem = statusBarController.makeStatusItem()
        // Default ⌃⌥⌘M (FEATURES.md 3.2), changeable in the settings window.
        HotKeyCenter.shared.action = { MeasureController.shared.toggle() }
        let hotKey = AppSettings.shared.hotKey
        if !HotKeyCenter.shared.register(hotKey) {
            NSLog("EdgeMeter: could not register \(hotKey.display) – another app may already use it.")
        }

        if !OnboardingWindowController.shared.isCompleted {
            // Explains the Screen Recording permission before macOS asks for it.
            OnboardingWindowController.shared.show()
        } else if !ScreenCapture.hasPermission {
            OnboardingWindowController.shared.show(page: .permission)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

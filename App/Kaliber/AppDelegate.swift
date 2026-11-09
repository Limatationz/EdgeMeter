import AppKit
import Carbon.HIToolbox
import KaliberCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let statusBarController = StatusBarController()
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if DebugRenderer.runIfRequested() { return }
        #endif

        statusItem = statusBarController.makeStatusItem()
        // ⌃⌥⌘M (FEATURES.md 3.2). Configurable shortcuts come with the settings window.
        hotKey = GlobalHotKey(keyCode: kVK_ANSI_M, modifiers: controlKey | optionKey | cmdKey) {
            MeasureController.shared.toggle()
        }
        if hotKey == nil {
            NSLog("Kaliber: could not register ⌃⌥⌘M – another app may already use it.")
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

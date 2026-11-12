import AppKit

/// Starts and stops measuring sessions; the single entry point for the hotkey and the menu.
@MainActor
final class MeasureController {
    static let shared = MeasureController()

    private var session: MeasureSession?
    private var isStarting = false

    var isMeasuring: Bool { session != nil }

    func toggle() {
        if let session {
            session.end()
        } else {
            Task { await start() }
        }
    }

    private func start() async {
        guard !isStarting, session == nil else { return }
        isStarting = true
        defer { isStarting = false }

        guard ScreenCapture.hasPermission else {
            OnboardingWindowController.shared.show(page: .permission)
            return
        }

        do {
            // Live mode needs no up-front capture: the stream delivers frames right away.
            let live = AppSettings.shared.liveMode
            let snapshots = live ? [] : try await ScreenCapture.captureAllScreens()
            let session = MeasureSession(screens: NSScreen.screens, snapshots: snapshots, live: live) { [weak self] in
                self?.session = nil
            }
            self.session = session
            session.begin()
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Could not capture the screen"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

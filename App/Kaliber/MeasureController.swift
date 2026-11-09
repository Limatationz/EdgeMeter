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
            ScreenCapture.requestPermission()
            showPermissionAlert()
            return
        }

        do {
            let snapshots = try await ScreenCapture.captureAllScreens()
            let session = MeasureSession(snapshots: snapshots) { [weak self] in
                self?.session = nil
            }
            self.session = session
            session.begin()
        } catch {
            showError(error)
        }
    }

    private func showPermissionAlert() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Kaliber needs Screen Recording permission"
        alert.informativeText = """
            Kaliber measures the actual pixels on screen, so it needs to capture the display. \
            Nothing is stored or sent anywhere.

            Enable Kaliber under System Settings › Privacy & Security › Screen & System Audio Recording, \
            then quit and reopen Kaliber.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            ScreenCapture.openPrivacySettings()
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

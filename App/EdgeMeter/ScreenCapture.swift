import AppKit
import ScreenCaptureKit
import EdgeMeterCore

/// One frozen display: the image shown on the overlay and the buffer the detectors read.
struct DisplaySnapshot {
    let screen: NSScreen
    let image: CGImage
    let buffer: PixelBuffer
    /// Backing scale of the display (device pixels per point).
    let displayScale: Double
}

enum CaptureError: LocalizedError {
    case noDisplays
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .noDisplays: "No display could be captured."
        case .conversionFailed: "The screen capture could not be read."
        }
    }
}

/// Screen Recording permission and per-display snapshots (FEATURES.md 3.4, 13.1, 15.1, 17).
@MainActor
enum ScreenCapture {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time; afterwards it only returns the current state.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Captures every connected display at native resolution, without the cursor and
    /// without EdgeMeter's own windows.
    static func captureAllScreens() async throws -> [DisplaySnapshot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == pid }

        var snapshots: [DisplaySnapshot] = []
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == displayID })
            else { continue }

            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            let pixelScale = CGFloat(filter.pointPixelScale)
            config.width = Int((filter.contentRect.width * pixelScale).rounded())
            config.height = Int((filter.contentRect.height * pixelScale).rounded())
            config.showsCursor = false
            config.captureResolution = .best

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard let buffer = PixelBuffer(cgImage: image) else { throw CaptureError.conversionFailed }
            snapshots.append(DisplaySnapshot(
                screen: screen,
                image: image,
                buffer: buffer,
                displayScale: Double(screen.backingScaleFactor)
            ))
        }
        guard !snapshots.isEmpty else { throw CaptureError.noDisplays }
        return snapshots
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

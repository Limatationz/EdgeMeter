import AppKit
import CoreMedia
import ScreenCaptureKit
import EdgeMeterCore

/// One frame from a live stream, already copied out of the stream's IOSurface.
struct LiveFrame: Sendable {
    let displayID: CGDirectDisplayID
    let buffer: PixelBuffer
    /// Time spent copying the frame on the capture queue.
    let copyMilliseconds: Double
}

/// Continuous capture of every display for live mode.
///
/// ScreenCaptureKit only delivers a new frame when the screen content changed, so a
/// static screen costs (almost) nothing. Frames are copied on a background queue and
/// handed to the main actor; detection then runs on the newest frame.
@MainActor
final class LiveCapture: NSObject, SCStreamDelegate {
    /// Upper bound for the frame rate; detection doesn't need more and it keeps the GPU idle.
    static let maxFramesPerSecond: Int32 = 30

    private var streams: [SCStream] = []
    private var outputs: [StreamOutput] = []
    private let queue = DispatchQueue(label: "de.ErikRill.EdgeMeter.live-capture", qos: .userInteractive)
    private let onFrame: @MainActor (LiveFrame) -> Void
    private let onError: @MainActor (Error) -> Void

    init(onFrame: @escaping @MainActor (LiveFrame) -> Void, onError: @escaping @MainActor (Error) -> Void) {
        self.onFrame = onFrame
        self.onError = onError
    }

    func start(screens: [NSScreen]) async throws {
        let (content, ownApps, ownWindows) = try await Self.shareableContentWithSelf()
        let deliver = onFrame

        for screen in screens {
            guard let displayID = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == displayID })
            else { continue }

            // Exclude EdgeMeter itself so our own lines and labels never feed back into detection.
            // By app if ScreenCaptureKit lists it (covers windows created later), else by window.
            var filter = ownApps.isEmpty
                ? SCContentFilter(display: display, excludingWindows: ownWindows)
                : SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            #if DEBUG
            if Self.debugCaptureOwnWindows {
                // README screenshots measure a demo window of our own: exclude only the overlays.
                let overlays = Set(NSApp.windows.compactMap { $0 as? OverlayWindow }.map { CGWindowID($0.windowNumber) })
                filter = SCContentFilter(display: display, excludingWindows: ownWindows.filter { overlays.contains($0.windowID) })
            }
            #endif
            let config = SCStreamConfiguration()
            let pixelScale = CGFloat(filter.pointPixelScale)
            config.width = Int((filter.contentRect.width * pixelScale).rounded())
            config.height = Int((filter.contentRect.height * pixelScale).rounded())
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false
            config.captureResolution = .best
            config.minimumFrameInterval = CMTime(value: 1, timescale: Self.maxFramesPerSecond)
            config.queueDepth = 3

            let output = StreamOutput(displayID: displayID) { frame in
                Task { @MainActor in deliver(frame) }
            }
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            streams.append(stream)
            outputs.append(output)
        }
    }

    /// Right after launch ScreenCaptureKit may not list EdgeMeter or its fresh overlay windows
    /// yet; excluding nothing would let our own drawing into the frames (wrong spans in the
    /// first session). Retries briefly until EdgeMeter shows up.
    private static func shareableContentWithSelf() async throws
        -> (SCShareableContent, [SCRunningApplication], [SCWindow]) {
        let pid = ProcessInfo.processInfo.processIdentifier
        var attempt = 0
        while true {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let apps = content.applications.filter { $0.processID == pid }
            let windows = content.windows.filter { $0.owningApplication?.processID == pid }
            attempt += 1
            if !apps.isEmpty || !windows.isEmpty || attempt >= 20 {
                NSLog("EdgeMeter: live capture excludes \(apps.count) app(s), \(windows.count) window(s) after \(attempt) attempt(s)")
                return (content, apps, windows)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    #if DEBUG
    /// Capture EdgeMeter's own non-overlay windows too (README screenshot scene).
    static var debugCaptureOwnWindows = false
    #endif

    func stop() {
        for stream in streams { stream.stopCapture { _ in } }
        streams.removeAll()
        outputs.removeAll()
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.onError(error) }
    }
}

/// Receives sample buffers on the capture queue. Holds only immutable state.
private final class StreamOutput: NSObject, SCStreamOutput, Sendable {
    let displayID: CGDirectDisplayID
    let deliver: @Sendable (LiveFrame) -> Void

    init(displayID: CGDirectDisplayID, deliver: @escaping @Sendable (LiveFrame) -> Void) {
        self.displayID = displayID
        self.deliver = deliver
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, Self.isComplete(sampleBuffer),
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return }

        let start = DispatchTime.now().uptimeNanoseconds
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = PixelBuffer(
            copying: UnsafeRawBufferPointer(start: base, count: bytesPerRow * height),
            width: width, height: height, bytesPerRow: bytesPerRow, format: .bgra8
        )
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        deliver(LiveFrame(displayID: displayID, buffer: buffer, copyMilliseconds: ms))
    }

    /// Idle/blank frames carry no new pixels; only `.complete` frames do.
    private static func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete
    }
}

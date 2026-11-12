#if DEBUG
import AppKit
import EdgeMeterCore
import SwiftUI

/// Renders the measurement layer over a synthetic UI into a PNG and exits, so overlay
/// drawing can be checked without Screen Recording permission or a live session:
///
///     EdgeMeter.app/Contents/MacOS/EdgeMeter -renderDemo /tmp/edgemeter-demo.png
@MainActor
enum DebugRenderer {
    /// `-demoSession <seconds>`: opens a real overlay session (synthetic image instead of a
    /// capture, so no permission is needed), logs where keyboard input goes, then exits.
    /// `-demoLive YES` runs it live on the real screen instead, `-demoHover x,y` (device
    /// pixels) places the hover without moving the cursor, `-demoScreenshot <png>` captures
    /// the screen with the overlay after one second.
    static func runSessionIfRequested() -> Bool {
        let defaults = UserDefaults.standard
        let seconds = defaults.double(forKey: "demoSession")
        guard seconds > 0 else { return false }
        let live = defaults.bool(forKey: "demoLive")
        let image = syntheticUI()
        guard let buffer = PixelBuffer(cgImage: image) else { return false }
        let snapshots = live ? [] : NSScreen.screens.map {
            DisplaySnapshot(screen: $0, image: image, buffer: buffer, displayScale: 2)
        }
        let originalLive = AppSettings.shared.liveMode
        let session = MeasureSession(screens: NSScreen.screens, snapshots: snapshots, live: live) {
            AppSettings.shared.liveMode = originalLive
            exit(0)
        }
        let hover = defaults.string(forKey: "demoHover")?.split(separator: ",").compactMap { Int($0) }
        let screenshot = defaults.string(forKey: "demoScreenshot")
        Task { @MainActor in
            // Reproduce the hot-key situation: another app is frontmost when measuring starts.
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
            try? await Task.sleep(for: .milliseconds(700))
            print("EdgeMeter demo session: before begin appActive=\(NSApp.isActive)")
            session.begin()
            try? await Task.sleep(for: .milliseconds(300))
            print("EdgeMeter demo session: \(session.keyboardState)")
            if let hover, hover.count == 2 {
                session.activeView?.simulateHover(at: PixelPoint(x: hover[0], y: hover[1]))
            }
            if let screenshot {
                try? await Task.sleep(for: .seconds(1))
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-m", screenshot]
                try? process.run()
                process.waitUntilExit()
                print("EdgeMeter demo session: screenshot \(screenshot)")
            }
            try? await Task.sleep(for: .seconds(seconds))
            session.end()
        }
        return true
    }

    /// `-liveProbe <dir> [-probeAt x,y]`: starts a real live session, puts the cursor at
    /// (x, y) (points, top-left of the main display; default: its center), then logs the
    /// hover spans with the loupe on and off and saves the captured pixels around the
    /// cursor. Shows whether EdgeMeter's own drawing leaks into the frames it analyzes.
    static func runLiveProbeIfRequested() -> Bool {
        guard let dir = UserDefaults.standard.string(forKey: "liveProbe"),
              let main = NSScreen.screens.first else { return false }
        let at = UserDefaults.standard.string(forKey: "probeAt")?.split(separator: ",").compactMap { Double($0) }
        let point = at?.count == 2 ? CGPoint(x: at![0], y: at![1]) : CGPoint(x: main.frame.midX, y: main.frame.midY)
        let session = MeasureSession(screens: NSScreen.screens, snapshots: [], live: true) { exit(0) }
        let originalLoupe = session.showLoupe
        Task { @MainActor in
            session.begin()
            try? await Task.sleep(for: .seconds(1.5))
            CGWarpMouseCursorPosition(point)
            CGAssociateMouseAndMouseCursorPosition(1)
            for loupe in [true, false, true] {
                session.showLoupe = loupe
                session.activeView?.syncHoverToMouse()
                try? await Task.sleep(for: .seconds(1.2))
                guard let view = session.activeView, let snap = view.debugHoverSnap, let buffer = view.buffer else {
                    print("probe loupe=\(loupe): no hover"); continue
                }
                print("probe loupe=\(loupe) origin=\(snap.origin) h=\(snap.horizontal) v=\(snap.vertical)")
                let o = snap.origin
                let crop = CGRect(x: max(o.x - 400, 0), y: max(o.y - 200, 0), width: 800, height: 400)
                if let image = buffer.makeCGImage(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)?.cropping(to: crop) {
                    let rep = NSBitmapImageRep(cgImage: image)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: dir).appendingPathComponent("probe-loupe-\(loupe).png"))
                }
            }
            session.showLoupe = originalLoupe
            session.end()
        }
        return true
    }

    /// `-renderSettings <png>`: renders the settings window content and exits.
    static func renderSettingsIfRequested() -> Bool {
        guard let path = UserDefaults.standard.string(forKey: "renderSettings") else { return false }
        let view = NSHostingView(rootView: SettingsView())
        view.frame.size = view.fittingSize
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("EdgeMeter: wrote \(path) \(view.fittingSize)")
        exit(0)
    }

    /// `-renderOnboarding <dir>`: opens the real onboarding window, captures each page to
    /// `onboarding-<n>.png` with `screencapture -l` (offscreen rendering drops SwiftUI text),
    /// then exits without marking onboarding as completed.
    static func renderOnboardingIfRequested() -> Bool {
        guard let dir = UserDefaults.standard.string(forKey: "renderOnboarding") else { return false }
        Task { @MainActor in
            for page in OnboardingPage.allCases {
                OnboardingWindowController.shared.show(page: page)
                try? await Task.sleep(for: .milliseconds(600))
                guard let window = NSApp.windows.first(where: { $0.title == "Welcome to EdgeMeter" }) else { exit(1) }
                let path = URL(fileURLWithPath: dir).appendingPathComponent("onboarding-\(page.rawValue).png").path
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", path]
                try? process.run()
                process.waitUntilExit()
            }
            print("EdgeMeter: wrote onboarding pages to \(dir)")
            exit(0)
        }
        return true
    }

    static func runIfRequested() -> Bool {
        guard let path = UserDefaults.standard.string(forKey: "renderDemo") else { return false }
        do {
            try render(to: URL(fileURLWithPath: path))
            print("EdgeMeter: wrote \(path)")
            exit(0)
        } catch {
            print("EdgeMeter: render failed: \(error)")
            exit(1)
        }
    }

    /// 600×400 pt "window" at 2× with a card, a button with a label and a text field.
    static func syntheticUI(scale: Int = 2) -> CGImage {
        let w = 600 * scale, h = 400 * scale
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setShouldAntialias(false)
        // Flip to top-left origin so rects read like layout code.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        func fill(_ r: CGRect, _ gray: CGFloat) {
            ctx.setFillColor(CGColor(gray: gray, alpha: 1)); ctx.fill(r)
        }
        func fill(_ r: CGRect, r red: CGFloat, g: CGFloat, b: CGFloat) {
            ctx.setFillColor(CGColor(srgbRed: red, green: g, blue: b, alpha: 1)); ctx.fill(r)
        }
        fill(CGRect(x: 0, y: 0, width: 600, height: 400), 0.93)                 // window background
        fill(CGRect(x: 40, y: 40, width: 520, height: 320), 1.0)                 // card
        fill(CGRect(x: 72, y: 72, width: 220, height: 16), 0.2)                  // title "text"
        fill(CGRect(x: 72, y: 100, width: 300, height: 10), 0.6)                 // subtitle "text"
        fill(CGRect(x: 72, y: 140, width: 456, height: 36), 0.85)                // text field border
        fill(CGRect(x: 73, y: 141, width: 454, height: 34), 0.98)                // text field
        fill(CGRect(x: 72, y: 290, width: 140, height: 40), r: 0.0, g: 0.48, b: 1.0) // button
        fill(CGRect(x: 104, y: 304, width: 76, height: 12), 1.0)                 // button label
        fill(CGRect(x: 228, y: 290, width: 120, height: 40), 0.9)                // secondary button
        return ctx.makeImage()!
    }

    static func render(to url: URL) throws {
        let image = syntheticUI()
        guard let buffer = PixelBuffer(cgImage: image), let screen = NSScreen.main ?? NSScreen.screens.first else {
            throw CaptureError.conversionFailed
        }
        let snapshot = DisplaySnapshot(screen: screen, image: image, buffer: buffer, displayScale: 2)
        let session = MeasureSession(screens: [screen], snapshots: [snapshot], live: false) {}
        let size = NSSize(width: 600, height: 400)
        let view = MeasureView(screen: screen, session: session)
        view.frame = NSRect(origin: .zero, size: size)
        if UserDefaults.standard.bool(forKey: "demoLiveHUD") {
            // Simulate a few live frames so the HUD shows live statistics.
            view.isLive = true
            for _ in 0..<5 { view.setBuffer(buffer, copyMilliseconds: 0.7) }
        } else {
            view.setBuffer(buffer)
        }
        view.forceActive = true

        let detector = session.detector
        // Pinned: object click on the primary button, two-point gap between buttons,
        // area drag around the text field (sloppy by a few points, gets snapped).
        view.simulatePin(.box(ObjectDetector(from: detector).objectBounds(at: PixelPoint(x: 160, y: 600), in: buffer).rect))
        let gapFrom = detector.nearestBoundary(to: 430, along: 620, axis: .horizontal, radius: 12, in: buffer) ?? 430
        let gapTo = detector.nearestBoundary(to: 452, along: 620, axis: .horizontal, radius: 12, in: buffer) ?? 452
        view.simulatePin(.line(LineMeasurement(axis: .horizontal, line: 620, from: gapFrom, to: gapTo)))
        let area = AreaSnapper(detector: detector, radius: 12)
            .snap(PixelRect(x: 138, y: 274, width: 920, height: 82), in: buffer)
        view.simulatePin(.box(area))
        // Live hover inside the card, between title block and text field.
        // `-demoHover x,y` (device pixels) moves it, e.g. onto an edge to check the loupe.
        let hover = UserDefaults.standard.string(forKey: "demoHover")?.split(separator: ",").compactMap { Int($0) }
        if let hover, hover.count == 2 {
            view.simulateHover(at: PixelPoint(x: hover[0], y: hover[1]))
        } else {
            view.simulateHover(at: PixelPoint(x: 800, y: 250))
        }

        // Render at the snapshot's pixel size (2×), so 1-px lines can be checked.
        func makeRep() -> NSBitmapImageRep? {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: buffer.width, pixelsHigh: buffer.height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )
            rep?.size = size
            return rep
        }
        guard let output = makeRep(),
              let context = NSGraphicsContext(bitmapImageRep: output) else { throw CaptureError.conversionFailed }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .none
        context.cgContext.draw(image, in: CGRect(origin: .zero, size: size))
        // Draw the flipped view on top, the same way AppKit would in a window.
        context.cgContext.translateBy(x: 0, y: size.height)
        context.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()

        guard let png = output.representation(using: .png, properties: [:]) else { throw CaptureError.conversionFailed }
        try png.write(to: url)
    }
}
#endif

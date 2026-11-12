import AppKit
import EdgeMeterCore

/// `-liveBenchmark <seconds>`: runs live capture without any overlay and prints frame
/// rate, copy time, detection time, CPU load and memory, then exits. Compiled into all
/// configurations so Debug and Release can be compared; does nothing without the flag.
@MainActor
enum LiveBenchmark {
    static func runIfRequested() -> Bool {
        let seconds = UserDefaults.standard.double(forKey: "liveBenchmark")
        guard seconds > 0 else { return false }
        Task { await run(seconds: seconds) }
        return true
    }

    @MainActor
    private final class Stats {
        var copyMs: [CGDirectDisplayID: [Double]] = [:]
        var sizes: [CGDirectDisplayID: (Int, Int)] = [:]
        var snapMs: [Double] = []
        var firstFrameAt: Double?
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return s(usage.ru_utime) + s(usage.ru_stime)
    }

    private static func maxRSSMegabytes() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_maxrss) / 1_048_576 // bytes on macOS
    }

    private static func now() -> Double { ProcessInfo.processInfo.systemUptime }

    private static func run(seconds: Double) async {
        #if DEBUG
        let config = "Debug"
        #else
        let config = "Release"
        #endif
        let stats = Stats()
        let detector = EdgeDetector(tolerance: AppSettings.defaultTolerance)
        let started = now()

        let capture = LiveCapture(
            onFrame: { frame in
                if stats.firstFrameAt == nil { stats.firstFrameAt = now() }
                stats.copyMs[frame.displayID, default: []].append(frame.copyMilliseconds)
                stats.sizes[frame.displayID] = (frame.buffer.width, frame.buffer.height)
                // What the overlay does per frame while hovering: one snap at the cursor.
                let t = now()
                _ = detector.snap(at: PixelPoint(frame.buffer.width / 2, frame.buffer.height / 2), in: frame.buffer)
                stats.snapMs.append((now() - t) * 1000)
            },
            onError: { error in print("EdgeMeter benchmark: stream error: \(error)") }
        )

        do {
            try await capture.start(screens: NSScreen.screens)
        } catch {
            print("EdgeMeter benchmark: could not start capture: \(error)")
            exit(1)
        }
        let streamStartMs = (now() - started) * 1000
        let cpu0 = cpuSeconds(), t0 = now()
        try? await Task.sleep(for: .seconds(seconds))
        let cpu1 = cpuSeconds(), t1 = now()
        capture.stop()

        func pct(_ xs: [Double], _ p: Double) -> Double {
            guard !xs.isEmpty else { return 0 }
            let s = xs.sorted()
            return s[min(s.count - 1, Int(Double(s.count - 1) * p))]
        }
        func avg(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }

        print(String(format: "EdgeMeter benchmark [%@] %.1f s, stream start %.0f ms, first frame after %@",
                     config, t1 - t0, streamStartMs,
                     stats.firstFrameAt.map { String(format: "%.0f ms", ($0 - started) * 1000) } ?? "–"))
        for (id, copies) in stats.copyMs.sorted(by: { $0.key < $1.key }) {
            let size = stats.sizes[id] ?? (0, 0)
            print(String(format: "  display %u %dx%d: %d frames = %.1f fps | copy avg %.2f ms, p95 %.2f ms, max %.2f ms",
                         id, size.0, size.1, copies.count, Double(copies.count) / (t1 - t0),
                         avg(copies), pct(copies, 0.95), copies.max() ?? 0))
        }
        if stats.copyMs.isEmpty { print("  no frames (screen did not change)") }
        print(String(format: "  snap avg %.3f ms, max %.3f ms | CPU %.1f %% of one core | max RSS %.0f MB",
                     avg(stats.snapMs), stats.snapMs.max() ?? 0,
                     (cpu1 - cpu0) / (t1 - t0) * 100, maxRSSMegabytes()))
        exit(0)
    }
}

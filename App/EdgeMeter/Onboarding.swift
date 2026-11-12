import AppKit
import SwiftUI

/// First-launch introduction (FEATURES.md §15): what EdgeMeter does, the Screen Recording
/// permission and the purple indicator, and the main keys. Reopened from the menu, and on the
/// permission page whenever measuring is started without permission.
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private nonisolated static let completedKey = "onboardingCompleted"
    private var window: NSWindow?
    private let model = OnboardingModel()

    var isCompleted: Bool { UserDefaults.standard.bool(forKey: Self.completedKey) }

    func show(page: OnboardingPage = .welcome) {
        model.page = page
        if window == nil {
            let host = NSHostingController(rootView: OnboardingView(model: model) { [weak self] in self?.finish() })
            host.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: host)
            window.title = "Welcome to EdgeMeter"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            // Closing counts as seen, like Done.
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in
                UserDefaults.standard.set(true, forKey: Self.completedKey)
            }
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        window?.close()
    }

    /// Screen Recording permission usually only takes effect after a restart.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}

enum OnboardingPage: Int, CaseIterable {
    case welcome, permission, ready
}

@MainActor
@Observable
final class OnboardingModel {
    var page: OnboardingPage = .welcome
}

struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    var onFinish: () -> Void

    @State private var hasPermission = ScreenCapture.hasPermission
    @State private var askedForPermission = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.page {
                case .welcome: welcome
                case .permission: permission
                case .ready: ready
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)

            Divider()
            HStack {
                pageDots
                Spacer()
                if model.page != .welcome {
                    Button("Back") { step(-1) }
                }
                if model.page == .ready {
                    Button("Done", action: onFinish)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { step(1) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            // Reflect permission changes made in System Settings while the window is open.
            while !Task.isCancelled {
                hasPermission = ScreenCapture.hasPermission
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            header(symbol: "ruler", title: "Measure anything on screen",
                   subtitle: "Distances, sizes and gaps in points and pixels, snapped to the edges of what you see.")
            row("keyboard", "Press **\(AppSettings.shared.hotKey.display)** or choose Measure from the ruler in the menu bar.")
            row("cursorarrow.motionlines", "**Hover** shows the distances to the nearest edges. Click pins a measurement.")
            row("square.dashed", "**2** two points, **3** click an object, **4** drag an area. **1** back to hover.")
            row("doc.on.clipboard", "**⌘C** copies the value, **Esc** ends measuring.")
        }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 18) {
            header(symbol: "rectangle.dashed.badge.record", title: "Screen Recording permission",
                   subtitle: "EdgeMeter finds edges by reading the pixels on screen. macOS only allows that with the Screen Recording permission.")
            row("lock.shield", "Pixels are read in memory while you measure. Nothing is saved, recorded or sent anywhere.")
            row("record.circle", "While measuring live, macOS shows a **purple indicator** in the menu bar. That's expected and goes away when you press Esc.")

            HStack(spacing: 10) {
                Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(hasPermission ? .green : .orange)
                    .font(.title2)
                Text(hasPermission ? "Screen Recording is allowed." : "Screen Recording is not allowed yet.")
                    .font(.headline)
                Spacer()
                if !hasPermission {
                    Button("Allow…") {
                        askedForPermission = true
                        if !ScreenCapture.requestPermission() { ScreenCapture.openPrivacySettings() }
                    }
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            if !hasPermission && askedForPermission {
                HStack {
                    Text("Turned EdgeMeter on in System Settings? macOS applies it after EdgeMeter reopens.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Reopen EdgeMeter") { OnboardingWindowController.relaunch() }
                }
            }
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 18) {
            header(symbol: "checkmark.seal", title: "Ready to measure",
                   subtitle: "A few keys that help while measuring:")
            row("magnifyingglass", "**Z** loupe with the exact pixels, **← → ↑ ↓** move by one pixel (⇧ ten).")
            row("slider.horizontal.3", "**-** and **+** change the edge tolerance when an edge is missed or found too early.")
            row("pause.circle", "**L** freezes the screen, e.g. for menus or animations, and back to live.")
            row("gearshape", "Shortcut, launch at login and defaults are in **Settings…** in the menu bar item.")
            if hasPermission {
                Button("Try it now") {
                    onFinish()
                    MeasureController.shared.toggle()
                }
            }
        }
    }

    // MARK: Building blocks

    private func header(symbol: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold())
                Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 40)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingPage.allCases, id: \.self) { page in
                Circle()
                    .fill(page == model.page ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private func step(_ delta: Int) {
        if let page = OnboardingPage(rawValue: model.page.rawValue + delta) { model.page = page }
    }
}

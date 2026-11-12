import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

/// The settings window (FEATURES.md §14), opened from the menu-bar item.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView())
            host.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: host)
            window.title = "EdgeMeter Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // EdgeMeter is a menu-bar app; without activating, the window opens behind others.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var shortcutError: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginNote: String?

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Measure shortcut") {
                    HStack {
                        ShortcutRecorder(hotKey: settings.hotKey) { new in
                            shortcutError = settings.setHotKey(new)
                                ? nil
                                : "\(new.display) is already used by another app or the system."
                        }
                        .frame(width: 130)
                        if settings.hotKey != .default {
                            Button("Reset") {
                                shortcutError = settings.setHotKey(.default) ? nil : "\(HotKey.default.display) is not available."
                            }
                            .glassButtonStyle()
                        }
                    }
                }
                if let shortcutError {
                    Text(shortcutError).foregroundStyle(.red).font(.callout)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginNote {
                    Text(loginNote).foregroundStyle(.secondary).font(.callout)
                }
            }

            Section {
                Toggle("Start in live mode", isOn: $settings.liveMode)
                Toggle("Show loupe", isOn: $settings.showLoupe)
                LabeledContent("Edge tolerance") {
                    HStack {
                        Slider(value: $settings.tolerance, in: 0...0.2, step: 0.01)
                            .frame(width: 160)
                        Text("\(Int((settings.tolerance * 100).rounded())) %")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                        Button("Reset") { settings.tolerance = AppSettings.defaultTolerance }
                            .glassButtonStyle()
                            .disabled(abs(settings.tolerance - AppSettings.defaultTolerance) < 0.001)
                    }
                }
            } header: {
                Text("Measuring")
            } footer: {
                Text("""
                    Live keeps the screen real and usable (⌘-Tab, scrolling); otherwise the screen \
                    is frozen when measuring starts. L switches while measuring. Lower tolerance \
                    finds fainter edges but stops at shadows and gradients; - and + change it \
                    while measuring.
                    """)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            loginNote = service.status == .requiresApproval
                ? "Allow EdgeMeter under System Settings › General › Login Items."
                : nil
        } catch {
            loginNote = "Could not change: \(error.localizedDescription)"
            let actual = service.status == .enabled
            if actual != launchAtLogin { launchAtLogin = actual }
        }
    }
}

/// A button that records the next key combination as the new shortcut. Esc cancels.
struct ShortcutRecorder: NSViewRepresentable {
    var hotKey: HotKey
    var onRecord: (HotKey) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.hotKey = hotKey
        button.onRecord = onRecord
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.hotKey = hotKey
        button.onRecord = onRecord
    }
}

final class RecorderButton: NSButton {
    var hotKey: HotKey = .default { didSet { updateTitle() } }
    var onRecord: (HotKey) -> Void = { _ in }

    private var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            // The current shortcut would otherwise fire instead of being recorded.
            if isRecording { HotKeyCenter.shared.suspend() } else { HotKeyCenter.shared.resume() }
            updateTitle()
        }
    }

    init() {
        super.init(frame: .zero)
        if #available(macOS 26, *) {
            bezelStyle = .glass
        } else {
            bezelStyle = .rounded
        }
        target = self
        action = #selector(toggleRecording)
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    @objc private func toggleRecording() {
        isRecording.toggle()
        if isRecording { window?.makeFirstResponder(self) }
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { isRecording = false }
        super.viewWillMove(toWindow: newWindow)
    }

    // Combinations with ⌘ or ⌃ arrive here first, before keyDown.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        record(event)
    }

    private func record(_ event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            isRecording = false
            return
        }
        guard let new = HotKey(event: event) else {
            NSSound.beep() // needs ⌃, ⌥ or ⌘
            return
        }
        isRecording = false
        onRecord(new)
    }

    private func updateTitle() {
        title = isRecording ? "Type shortcut…" : hotKey.display
    }
}

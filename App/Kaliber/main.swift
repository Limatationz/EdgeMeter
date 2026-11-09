import AppKit

// Entry point. We use main.swift instead of @main so the app delegate can be
// created explicitly and the process stays a plain NSApplication (menu-bar app).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

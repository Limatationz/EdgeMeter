# EdgeMeter

macOS screen measurement tool (PixelSnap alternative). Swift 6 (strict concurrency), AppKit +
ScreenCaptureKit, macOS 14+, MIT. Layout, keys and build commands: README.md. Feature catalog and
recorded decisions: docs/FEATURES.md (§19).

## Project rules

- Personal project of Erik Rill, not codivo: bundle id `de.ErikRill.EdgeMeter`, team 25ZPKD8P86,
  private repo github.com/Limatationz/EdgeMeter.
- `project.yml` is the source of truth; run `xcodegen generate` after adding files or changing settings.
- Detection code stays AppKit-free in `Packages/EdgeMeterCore` (Swift Testing, `swift test --package-path Packages/EdgeMeterCore`).
- Hover snap uses pixel coordinates (inclusive spans); two-point and area snapping use boundary
  coordinates (boundary b lies between pixel b-1 and b).
- Settings live in `AppSettings` (UserDefaults); measuring sessions read and write them there.

## Checking changes

- Build: `xcodebuild -project EdgeMeter.xcodeproj -scheme EdgeMeter -configuration Debug -derivedDataPath build build`
- DEBUG flags on `build/Build/Products/Debug/EdgeMeter.app/Contents/MacOS/EdgeMeter`:
  `-renderDemo <png>` (overlay over a synthetic UI at 2×, with `-demoHover x,y`, `-demoLiveHUD YES`),
  `-renderSettings <png>`, `-renderOnboarding <dir>` (real window, brief), `-demoSession <s>` (+ `-demoLive YES`, `-demoHover x,y`,
  `-demoScreenshot <png>` for a real-window screenshot incl. glass), `-liveProbe <dir>`.
  `-renderDemo` draws without glass (classic look); use `-demoScreenshot` to check glass. All configs: `-liveBenchmark <s>`.
- Don't kill a running EdgeMeter (the user runs it from the Xcode debugger) and don't move the cursor
  without asking; the debug flags run alongside it.

## Apple documentation

Xcode ships current API guides (Xcode 26 / macOS 26 era) as Markdown:
`/Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation`

Read the matching guide before working in its area, notably:
- `AppKit-Implementing-Liquid-Glass-Design.md` / `SwiftUI-Implementing-Liquid-Glass-Design.md` for UI
  look (HUD, loupe, settings). Glass APIs are macOS 26+, so gate them with `#available` (target is macOS 14).
- `Swift-Concurrency-Updates.md` (Swift 6.2 default actor isolation) for concurrency changes.
- `Swift-InlineArray-Span.md` for pixel-buffer performance work; check runtime availability first.

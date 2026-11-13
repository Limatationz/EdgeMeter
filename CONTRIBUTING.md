# Contributing to EdgeMeter

Thanks for helping! Bug reports and ideas go to [GitHub Issues](https://github.com/Limatationz/EdgeMeter/issues)
(EdgeMeter's menu › Send Feedback… opens one with your versions filled in). Pull requests are welcome –
for bigger changes, please open an issue first so we can agree on the approach.

EdgeMeter only measures. Screenshot, annotation and export features are out of scope
([FEATURES.md §8](docs/FEATURES.md)).

## Build and test

Requirements: Xcode 26 (macOS 26 SDK), [XcodeGen](https://github.com/yonaskolb/XcodeGen). The app runs on macOS 14+.

```sh
brew install xcodegen
xcodegen generate                 # after cloning, adding files or editing project.yml
open EdgeMeter.xcodeproj          # run with ⌘R

# Core only – fast, no Xcode project needed
swift test --package-path Packages/EdgeMeterCore

# App + core tests
xcodebuild -project EdgeMeter.xcodeproj -scheme EdgeMeter test
```

`project.yml` is the source of truth; the generated `.xcodeproj` is checked in for convenience.
Local builds are signed with your own team – change `DEVELOPMENT_TEAM` in `project.yml` (or pick your
team in Xcode) before running.

## Layout

```
project.yml                  XcodeGen spec (source of truth for the Xcode project)
App/EdgeMeter/               menu-bar app (AppKit + a little SwiftUI)
  AppDelegate.swift          launch, global shortcut, onboarding
  GlobalHotKey.swift         global shortcut via Carbon RegisterEventHotKey
  AppSettings.swift          persisted settings (tolerance, live, loupe, shortcut) + HotKeyCenter
  SettingsWindow.swift       SwiftUI settings window incl. shortcut recorder, launch at login
  Onboarding.swift           first-launch introduction, Screen Recording permission flow
  StatusBarController.swift  menu-bar item, menu, feedback link
  ScreenCapture.swift        permission + per-display ScreenCaptureKit snapshots (frozen mode)
  LiveCapture.swift          live mode: one SCStream per display, frames copied off-main
  MeasureController.swift    starts/stops measuring sessions
  MeasureSession.swift       shared mode/scale/tolerance, keyboard commands, scroll pass-through
  OverlayWindow.swift        non-activating panel per display, frozen (snapshot) or live (transparent)
  MeasureView.swift          input for all modes, device-pixel drawing, labels, loupe, HUD
  GlassBackdrop.swift        Liquid Glass behind HUD and loupe (macOS 26+, plain dark before)
  AppIcon.icon/              app icon (Icon Composer); Xcode derives the classic icns for macOS 14–25
  DebugRenderer.swift        DEBUG only: render/demo flags below
Packages/EdgeMeterCore/      pure-Swift measurement core, no AppKit dependency
  Sources/EdgeMeterCore/
    PixelBuffer.swift        frozen BGRA/RGBA framebuffer copy (+ CGImage bridge)
    RGBA.swift               color + distance metrics (maxChannel, euclidean, perceptual)
    EdgeDetector.swift       ray scan, hover snap, nearest-boundary snapping
    ObjectDetector.swift     scanline flood fill → bounding box (object mode)
    AreaSnapper.swift        snaps a dragged rect's four sides to edges
    ScreenMeasurement.swift  measurement model + clipboard text
    Units.swift              scale modes (Auto/1×/2×/3×) and length formatting
  Tests/EdgeMeterCoreTests/  tests against synthetic images (boxes, glyphs, gradients, AA fringes)
scripts/release.sh           universal Developer ID build → DMG → notarization
docs/FEATURES.md             feature catalog, roadmap and recorded decisions
```

## Core concepts

- Detection compares every pixel against the **start pixel**, not its neighbour, so gradients
  and soft shadows yield a finite run instead of being crossed.
- `tolerance` is a color distance in `0...1` (default 0.04 ≈ 10 of 255 per channel with `maxChannel`).
- Hover snap (`EdgeDetector.snap`) works in **pixel** coordinates and returns inclusive runs.
- Two-point and area snapping work in **boundary** coordinates: boundary `b` lies between
  pixel `b-1` and `b`, so a box on columns 100…199 has boundaries 100 and 200 and width 100.
- Measurements are drawn in device pixels: 1-px lines sit exactly on pixel centers.
- EdgeMeter excludes its own windows from capture, so its drawing never feeds back into detection.
- New algorithm code stays AppKit-free in `EdgeMeterCore` and gets a test.

## Checking UI changes without a live session

Debug builds accept flags (`build/Build/Products/Debug/EdgeMeter.app/Contents/MacOS/EdgeMeter …`):

| Flag | What it does |
|---|---|
| `-renderDemo <png>` | Overlay over a synthetic UI at 2× (`-demoHover x,y`, `-demoLiveHUD YES`); no glass |
| `-renderSettings <png>` | Settings window content |
| `-renderOnboarding <dir>` | Opens the onboarding briefly and captures each page |
| `-renderMenuIcon <png>` | Menu-bar icon at 10× on light and dark |
| `-demoSession <s>` | Real overlay session (`-demoLive YES`, `-demoHover x,y`, `-demoScreenshot <png>`) |
| `-readmeScreenshots <dir>` | Stages a demo window and regenerates the README screenshots |
| `-liveProbe <dir>` | Saves the captured pixels and hover spans of a live session |
| `-liveBenchmark <s>` | (all configurations) fps, copy/snap time, CPU and memory of live mode |

## Releasing (maintainer)

```sh
scripts/release.sh                  # → build/release/EdgeMeter-<version>.dmg, notarized
scripts/release.sh --skip-notarize  # same without notarization
```

Needs the maintainer's Developer ID certificate and a notarytool profile named `edgemeter`
(`xcrun notarytool store-credentials edgemeter --apple-id <apple-id> --team-id <team>`, run in Terminal.app).
Bump `CFBundleShortVersionString` / `CFBundleVersion` in `project.yml` first.

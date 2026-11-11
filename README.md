# Kaliber

Open-source screen measurement tool for macOS. Measure distances, sizes and spacing of anything
on screen, pixel-exact, with smart edge snapping – an open alternative to PixelSnap.

> Working title. Status: first usable prototype – global shortcut, frozen overlay per display,
> hover / two-point / object / area measuring, undo, copy. No settings window or export yet.

- [Feature catalog](docs/FEATURES.md)

Stack: Swift 6, AppKit, ScreenCaptureKit, macOS 14+. License: MIT.

## Layout

```
Kaliber.xcodeproj          generated from project.yml (XcodeGen) – open this in Xcode
project.yml                source of truth for the Xcode project
App/Kaliber/               menu-bar app (AppKit)
  GlobalHotKey.swift         global shortcut via Carbon RegisterEventHotKey
  AppSettings.swift          persisted settings (tolerance, live, loupe, shortcut) + HotKeyCenter
  SettingsWindow.swift       SwiftUI settings window incl. shortcut recorder, launch at login
  ScreenCapture.swift        permission + per-display ScreenCaptureKit snapshots
  LiveCapture.swift          live mode: one SCStream per display, frames copied off-main
  MeasureController.swift    starts/stops sessions, permission and error alerts
  MeasureSession.swift       shared mode/scale/tolerance, keyboard commands
  OverlayWindow.swift        non-activating panel per display, frozen (snapshot) or live (transparent)
  MeasureView.swift          input for all modes, device-pixel drawing, HUD
  GlassBackdrop.swift        Liquid Glass behind HUD and loupe (macOS 26+, plain dark before)
  DebugRenderer.swift        DEBUG only: overlay/settings to PNG, demo session, live probe
Packages/KaliberCore/      pure-Swift measurement core, no AppKit dependency
  Sources/KaliberCore/
    PixelBuffer.swift        frozen BGRA/RGBA framebuffer copy (+ CGImage bridge)
    RGBA.swift               color + distance metrics (maxChannel, euclidean, perceptual)
    EdgeDetector.swift       ray scan, hover snap, nearest-boundary snapping
    ObjectDetector.swift     scanline flood fill → bounding box (object mode)
    AreaSnapper.swift        snaps a dragged rect's four sides to edges
    ScreenMeasurement.swift  pinned measurement model + clipboard text
    Units.swift              scale modes (Auto/1×/2×/3×) and length formatting
  Tests/KaliberCoreTests/  51 tests against synthetic images (boxes, glyphs, gradients, AA fringes)
docs/FEATURES.md           feature catalog and roadmap
```

## Build and test

```sh
# Core only – fast, no Xcode project needed
swift test --package-path Packages/KaliberCore

# App + tests through Xcode
xcodebuild -project Kaliber.xcodeproj -scheme Kaliber test
open Kaliber.xcodeproj

# Regenerate the project after editing project.yml
brew install xcodegen && xcodegen generate
```

## Using it

Press **⌃⌥⌘M** (or the ruler icon › Measure; the shortcut can be changed under ruler icon › Settings…). Measuring starts live on the real screen; L freezes it. Esc leaves.
On first use macOS asks for Screen Recording permission – grant it, then restart Kaliber.

| Key | Action |
|---|---|
| 1 / 2 / 3 / 4 | Hover / Two-point / Object / Area mode |
| L | Toggle live (default) / frozen, remembered. Live: screen stays real, ⌘-Tab works, HUD shows fps |
| Click | Pin hover measurement, or measure the clicked object (mode 3) |
| Drag | Two-point line (axis-locked) or area (modes 2, 4) |
| ⌥ (hold) | Outside edges instead of inside (hover) |
| ⌘ (hold) | Disable snapping while dragging |
| ← → ↑ ↓ (⇧: 10) | Move the cursor by one device pixel; also moves the end of a drag |
| Z | Toggle loupe (magnified pixels around the cursor), remembered |
| - / + (also [ ] and =) or ⌥-scroll | Edge tolerance −/+ in 1 % steps |
| Scroll | Live: scrolls the app underneath. Frozen: ignored |
| S | Cycle scale: Auto, 1×, 2×, 3× |
| ⌘C / ⇧⌘C | Copy current / all measurements |
| ⌘Z / ⇧⌘Z, ⌫ | Undo / redo, delete last |
| X | Clear all |
| H | Toggle HUD |

Overlay drawing can be checked without a live session or permission:

```sh
Kaliber.app/Contents/MacOS/Kaliber -renderDemo /tmp/kaliber-demo.png   # Debug builds only
```

## Core concepts (see also FEATURES.md §2, §17)

- Detection compares every pixel against the **start pixel**, not its neighbour, so gradients
  and soft shadows yield a finite run instead of being crossed.
- `tolerance` is a color distance in `0...1` (0.1 ≈ 25 of 255 per channel with `maxChannel`).
- Hover snap (`EdgeDetector.snap`) works in **pixel** coordinates and returns inclusive runs;
  `insideSize`/`outsideSize` map to PixelSnap's inside/outside toggle.
- Two-point and area snapping work in **boundary** coordinates: boundary `b` lies between
  pixel `b-1` and `b`, so a box on columns 100…199 has boundaries 100 and 200 and width 100.

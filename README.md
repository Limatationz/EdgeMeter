# Kaliber

Open-source screen measurement tool for macOS. Measure distances, sizes and spacing of anything
on screen, pixel-exact, with smart edge snapping – an open alternative to PixelSnap.

> Working title. Status: detection core done and tested, overlay UI not started.

- [Feature catalog](docs/FEATURES.md)

Stack: Swift 6, AppKit, ScreenCaptureKit, macOS 14+. License: MIT.

## Layout

```
Kaliber.xcodeproj          generated from project.yml (XcodeGen) – open this in Xcode
project.yml                source of truth for the Xcode project
App/Kaliber/               menu-bar app skeleton (AppKit); measuring mode not wired up yet
Packages/KaliberCore/      pure-Swift measurement core, no AppKit dependency
  Sources/KaliberCore/
    PixelBuffer.swift        frozen BGRA/RGBA framebuffer copy (+ CGImage bridge)
    RGBA.swift               color + distance metrics (maxChannel, euclidean, perceptual)
    EdgeDetector.swift       ray scan, hover snap, nearest-boundary snapping
    ObjectDetector.swift     scanline flood fill → bounding box (object mode)
    AreaSnapper.swift        snaps a dragged rect's four sides to edges
  Tests/KaliberCoreTests/  40 tests against synthetic images (boxes, glyphs, gradients, AA fringes)
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

## Core concepts (see also FEATURES.md §2, §17)

- Detection compares every pixel against the **start pixel**, not its neighbour, so gradients
  and soft shadows yield a finite run instead of being crossed.
- `tolerance` is a color distance in `0...1` (0.1 ≈ 25 of 255 per channel with `maxChannel`).
- Hover snap (`EdgeDetector.snap`) works in **pixel** coordinates and returns inclusive runs;
  `insideSize`/`outsideSize` map to PixelSnap's inside/outside toggle.
- Two-point and area snapping work in **boundary** coordinates: boundary `b` lies between
  pixel `b-1` and `b`, so a box on columns 100…199 has boundaries 100 and 200 and width 100.

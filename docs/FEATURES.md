# Kaliber – Feature Catalog

> Kaliber is an open-source macOS screen measurement tool in the spirit of
> [PixelSnap](https://pixelsnap.com/): measure anything on screen in pixels with smart edge
> snapping, two-point measurements and object measurements. Kaliber only measures; it is not a
> screenshot tool.
>
> Status: planning. Priorities: **P0** = MVP, **P1** = v1.0, **P2** = later / nice to have.
> "Parity" marks features PixelSnap 2 has today.

---

## 1. Vision and positioning

- **One-key measuring.** Press a global shortcut, the screen freezes into a measuring surface,
  hover shows distances, click pins them, Esc leaves. Nothing to set up.
- **Pixel-exact, not approximately.** Measurements come from the actual framebuffer pixels
  (edge detection on a screen capture), never from guessed UI geometry.
- **Native, small, fast.** Swift + AppKit menu-bar app, no Electron, launches in well under a
  second, idle CPU ~0 %.
- **Open source (MIT).** Reproducible build, no account, no telemetry, no license server.
- **Target users.** UI/UX designers, front-end developers, QA, anyone comparing a design to an
  implementation or inspecting someone else's UI.

### Non-goals (for now)

- No design-tool plugin (Figma/Sketch) – we measure the screen, not design files.
- No Windows/Linux port in the first phase (architecture should not prevent it later).
- No color picker as a core feature (see 12, optional P2).
- No OCR / font detection.

---

## 2. Core concepts

| Concept | Meaning |
|---|---|
| **Session** | The state while measurement mode is active: a frozen screen capture per display, plus all pinned measurements. |
| **Snapshot** | The frozen framebuffer of one display used for edge detection and rendering. |
| **Edge** | A position where neighbouring pixel colors differ by more than the tolerance. |
| **Measurement** | A pinned result: a distance line (2 points), an object box (w×h) or a hover cross. |
| **Scale factor** | Divisor applied to raw device pixels, e.g. 2 for a Retina display shows "logical points". |
| **Guide** | A persistent horizontal/vertical line used as a reference for further measurements. |

---

## 3. Activation and modes

| # | Feature | Prio | Parity | Notes |
|---|---|---|---|---|
| 3.1 | Menu-bar app (no Dock icon by default) | P0 | ✓ | Toggle Dock icon in settings. |
| 3.2 | Global shortcut starts/stops measuring (default ⌃⌥⌘M, customizable) | P0 | ✓ | Record shortcut in settings. |
| 3.3 | Measuring mode = full-screen transparent overlay window per display, above everything | P0 | ✓ | Level above menu bar; captures all mouse/keyboard events. |
| 3.4 | Live by default; **freeze** the screen with L (snapshot) | P0 | ✓ | Frozen avoids measuring moving content; live keeps ⌘-Tab and animations usable. |
| 3.5 | Esc / shortcut again leaves mode and clears measurements | P0 | ✓ | Option: keep measurements for next session (6.7). |
| 3.6 | Re-capture current screen without leaving mode (R) | P1 | – | Useful when underlying UI changed. |
| 3.7 | Mode switching while measuring: Hover-snap (default) / Two-point / Object / Area | P0 | ✓ | Keys 1–4 or tab cycling, shown in HUD. |
| 3.8 | Launch at login | P1 | ✓ | |
| 3.9 | Quick-measure from menu-bar menu (click menu item instead of shortcut) | P1 | ✓ | |

---

## 4. Smart snapping (automatic measurement on hover)

The headline feature. The cursor is a crosshair; the app automatically finds the nearest
edges in all four directions and shows the distances without any clicking.

| # | Feature | Prio | Parity | Notes |
|---|---|---|---|---|
| 4.1 | From the cursor, scan left/right/up/down until a pixel differs from the start pixel by more than the tolerance → four edge positions | P0 | ✓ | Works on the snapshot, so it is O(distance) per direction. |
| 4.2 | Show horizontal and vertical distance lines with labels (e.g. `240` / `56`) | P0 | ✓ | |
| 4.3 | Click pins the current hover measurement (both axes) | P0 | ✓ | |
| 4.4 | Shift: constrain to one axis (horizontal or vertical only) | P0 | ✓ | Axis chosen by cursor movement direction. |
| 4.5 | Edge tolerance / color threshold adjustable (slider in settings + ⌥-scroll while measuring) | P0 | ✓ | PixelSnap calls this "precision". Anti-aliased edges and gradients need this. |
| 4.6 | Inclusive/exclusive edge handling: measure "inside" a box (between edges) vs "outside" (edge to edge including borders) | P1 | ✓ | Toggle with ⌥ while hovering. |
| 4.7 | Visual highlight of the detected region (fill the area the scan found) | P1 | ✓ | Helps verify the snap hit the intended element. |
| 4.8 | Snap only within active window bounds (optional) | P1 | – | Uses CGWindowList bounds; prevents snapping to the desktop/background. |
| 4.9 | Ignore configurable colors (e.g. transparent-checkerboard, cursor) | P2 | – | |
| 4.10 | Perceptual color distance (ΔE / weighted RGB) instead of raw RGB distance | P1 | – | Better behaviour on gradients and shadows. |
| 4.11 | Snap to text baseline / glyph bounds (treat anti-aliased text as a block) | P2 | – | Morphological closing on the snapshot before scanning. |

---

## 5. Two-point and object measurement

| # | Feature | Prio | Parity | Notes |
|---|---|---|---|---|
| 5.1 | Click-drag draws a measurement from point A to B; label shows length | P0 | ✓ | Default: axis-locked (horizontal or vertical) like PixelSnap. |
| 5.2 | Both endpoints snap to nearest edges while dragging (toggle with ⌘) | P0 | ✓ | Snap radius configurable. |
| 5.3 | Free diagonal measurement (hold ⇧ to unlock axis) shows length, Δx, Δy and angle | P1 | – | PixelSnap is axis-only; this is a differentiator. |
| 5.4 | Click-click (two clicks instead of drag) alternative input | P1 | – | Easier on trackpads. |
| 5.5 | **Object mode**: single click on an element measures its bounding box (w × h) by flood-scanning edges in all directions | P0 | ✓ | Shows width, height, and optionally x/y position. |
| 5.6 | **Area mode**: drag a rectangle, shows w × h, snapped on all four sides | P0 | ✓ | |
| 5.7 | Edit after pinning: drag endpoints/edges of an existing measurement | P1 | – | |
| 5.8 | Arrow keys nudge the active point by 1 px (⇧ = 10 px) | P0 | ✓ | |
| 5.9 | Delete selected measurement (⌫), undo/redo (⌘Z / ⇧⌘Z) | P0 | ✓ | |
| 5.10 | Measure distance between two pinned measurements / objects (gap) | P2 | – | E.g. spacing between two buttons. |
| 5.11 | Distance from a point to the window edges (padding) in one click | P2 | – | Useful for checking insets. |

---

## 6. Multiple measurements and session handling

| # | Feature | Prio | Parity | Notes |
|---|---|---|---|---|
| 6.1 | Unlimited pinned measurements per session | P0 | ✓ | |
| 6.2 | Select, move and delete individual measurements | P1 | ✓ | |
| 6.3 | Measurements list panel (sidebar/HUD) with all values | P2 | – | |
| 6.4 | Copy value of hovered/selected measurement (⌘C), copy all as text (⇧⌘C) | P0 | ✓ | Formats: `240`, `240 × 56`, CSV, JSON. |
| 6.5 | Color per measurement / cycle colors automatically | P1 | ✓ | |
| 6.6 | Label text: free annotation on a measurement | P2 | – | |
| 6.7 | Keep measurements across sessions (until explicitly cleared) | P1 | ✓ | Option. |
| 6.8 | Measurements follow the window they were made on when it moves | P2 | – | Needs window tracking via CGWindowList / Accessibility; hard, maybe later. |

---

## 7. Display: HUD, labels, units

| # | Feature | Prio | Parity | Notes |
|---|---|---|---|---|
| 7.1 | Crosshair cursor with coordinate readout (x, y) | P0 | ✓ | |
| 7.2 | Distance labels auto-placed so they do not overlap lines; readable on any background (outlined/boxed text) | P0 | ✓ | |
| 7.3 | **Scale factor**: Auto (display backing scale), 1×, 2×, 3×, custom (e.g. 1.5 for a 150 % zoomed browser) | P0 | ✓ | Shown in HUD, cycled with a key. |
| 7.4 | Units: px (device), pt (logical), optional mm/cm/in via display DPI | P1 | ✓ (px/pt) | |
| 7.5 | Decimal precision (0, 1, 2 digits) when scale produces fractions | P1 | ✓ | |
| 7.6 | HUD showing mode, scale, tolerance, shortcuts hint; hideable (H) | P0 | ✓ | |
| 7.7 | Theme: auto light/dark, accent color, line thickness | P1 | ✓ | |
| 7.8 | Dim everything outside the active window (focus mode) | P2 | – | |
| 7.9 | Magnifier loupe near the cursor (pixel grid, 4–16×) for exact placement | P1 | ✓ | Toggle Z or hold Space. |
| 7.10 | Show hovered pixel color (hex/rgb) in loupe | P2 | – | Light-weight color picker, see 12. |

---

## 8. Screenshots and export – out of scope

Decided 2026-11-11: Kaliber only measures. Screenshots with or without overlays, saving images,
SVG export and share sheets (former 8.1–8.5, 8.7, 8.8) are dropped; the system screenshot tool
covers that. Measurement values leave Kaliber as text (⌘C / ⇧⌘C).

| # | Feature | Prio | Parity | Notes |
|---|---|---|---|---|
| 8.6 | Copy measurements as JSON/CSV text (for bug reports, regression checks) | P2 | – | Text only, no images. |

---

## 9. Window and app awareness

| # | Feature | Prio | Parity | Notes |
|---|---|---|---|---|
| 9.1 | Measure within the active (frontmost) window only: snapping stops at window bounds | P1 | ✓ | Default off; toggle W. |
| 9.2 | Highlight window frame on hover; click to measure window size | P1 | – | |
| 9.3 | Per-app overrides: default scale factor (e.g. 2× for Figma at 100 %), default tolerance | P2 | ✓ | Keyed by bundle id. |
| 9.4 | Exclude apps: shortcut disabled while a given app is frontmost (e.g. games) | P2 | – | |
| 9.5 | Browser zoom awareness: read zoom level via Accessibility where exposed and suggest scale | P2 | – | |
| 9.6 | Accessibility-API hybrid: optionally snap to AX element frames (buttons, text) instead of pixels | P2 | – | Differentiator; gives semantic boxes even on flat designs. |

---

## 10. Guides, rulers and grids

| # | Feature | Prio | Parity | Notes |
|---|---|---|---|---|
| 10.1 | Drop horizontal/vertical guides (G) at cursor or snapped edge; measurements snap to guides | P1 | – | |
| 10.2 | Distance readout between adjacent guides | P1 | – | |
| 10.3 | Screen rulers along the top/left edge, zero point movable | P2 | – | |
| 10.4 | Grid overlay (configurable spacing, e.g. 8 px) for layout checks | P2 | – | |
| 10.5 | Guides persist per display across sessions (optional) | P2 | – | |

---

## 11. Keyboard and input reference (draft)

| Key | Action |
|---|---|
| ⌃⌥⌘M | Start / stop measuring (global, configurable) |
| Esc | Leave measuring mode |
| 1 / 2 / 3 / 4 | Hover-snap / Two-point / Object / Area |
| Click | Pin hover measurement / place point |
| Drag | Two-point or area measurement |
| ⇧ | Constrain to one axis (hover) / unlock free angle (two-point) |
| ⌥ | Inside ↔ outside edge handling |
| ⌘ (hold) | Disable snapping temporarily |
| Arrows / ⇧Arrows | Nudge 1 px / 10 px |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌫ | Delete selected measurement |
| ⌘C / ⇧⌘C | Copy value / copy all |
| S | Cycle scale factor (Auto, 1×, 2×, 3×, custom) |
| Z / Space | Toggle / hold loupe |
| H | Toggle HUD |
| W | Toggle active-window-only |
| G | Drop guide at cursor |
| R | Re-capture screen |
| ⌥ + scroll | Adjust edge tolerance |

All bindings configurable (P1).

---

## 12. Optional: color picker (P2)

Not core, but cheap once we have the snapshot and loupe.

- Show hex/rgb/hsl of hovered pixel in the loupe (7.10).
- Click with modifier copies the color; configurable format (`#RRGGBB`, `rgb()`, Swift `Color(…)`).
- Color-space correct sampling (Display P3 vs sRGB) with option to convert.

---

## 13. Multi-display and Retina

| # | Feature | Prio | Notes |
|---|---|---|---|
| 13.1 | One overlay + snapshot per connected display; measuring works on any display | P0 | |
| 13.2 | Mixed scale factors (Retina + external 1×) handled per display | P0 | Scale "Auto" reads `backingScaleFactor` of the display under the cursor. |
| 13.3 | Measurements spanning displays are prevented or clearly marked | P1 | |
| 13.4 | Display hot-plug while measuring handled gracefully (exit mode) | P1 | |
| 13.5 | Sidecar / virtual displays supported like normal displays | P1 | |

---

## 14. Settings

- General: launch at login, Dock icon, check for updates, keep measurements.
- Shortcuts: all bindings from section 11.
- Measuring: default mode, default scale, tolerance, inside/outside, snap radius, nudge step.
- Appearance: theme, accent color, line width, label size, show coordinates, HUD position.
- Apps: per-app overrides (9.3), excluded apps (9.4).
- Advanced: perceptual color distance, loupe zoom, debug overlays (show detected edges).

Settings stored in `UserDefaults`; export/import as JSON (P2).

---

## 15. Onboarding, permissions, help

| # | Feature | Prio | Notes |
|---|---|---|---|
| 15.1 | First-run flow requesting **Screen Recording** permission with explanation and deep link to System Settings | P0 | Mandatory; without it the capture is black. |
| 15.2 | Optional **Accessibility** permission flow (only for 9.5 / 9.6 / 6.8) | P2 | Must not be required for the core. |
| 15.3 | In-app shortcut cheat sheet (?) | P1 | |
| 15.4 | Detect missing permission at runtime and show actionable alert instead of silently failing | P0 | |

---

## 16. Distribution, quality, project

| # | Feature | Prio | Notes |
|---|---|---|---|
| 16.1 | Signed and notarized `.dmg` via GitHub Releases | P0 | Needs Apple Developer ID; document how forks build unsigned. |
| 16.2 | Homebrew cask | P1 | |
| 16.3 | In-app updates via Sparkle | P1 | |
| 16.4 | Mac App Store build | P2 | Sandboxing + ScreenCaptureKit is possible; global shortcuts need care. |
| 16.5 | Universal binary (Apple Silicon + Intel) | P0 | |
| 16.6 | Minimum macOS: 14 (Sonoma) to use modern ScreenCaptureKit APIs | P0 | Decide; 13 would widen reach but complicate capture. |
| 16.7 | Unit tests for edge detection against synthetic images (known gaps, gradients, anti-aliased text) | P0 | Core algorithm must be regression-tested. |
| 16.8 | UI tests / screenshot tests for overlay rendering | P2 | |
| 16.9 | CI on GitHub Actions (build, test, lint, notarize on tag) | P1 | |
| 16.10 | Localization: English first, German second | P1 | |
| 16.11 | MIT license, CONTRIBUTING.md, issue templates | P0 | |

---

## 17. Technical constraints that shape the features

- **Capture**: `ScreenCaptureKit` (`SCScreenshotManager` on macOS 14+) gives a per-display
  `CGImage` at native resolution. Requires Screen Recording permission. The old
  `CGWindowListCreateImage` is deprecated and prints a system warning on 14+.
- **Overlay**: borderless `NSWindow` per screen, `level = .screenSaver` or above,
  `ignoresMouseEvents = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`,
  content drawn via `CALayer`/Core Graphics or SwiftUI `Canvas`. Must be in device-pixel space to
  draw exact 1-px lines on Retina.
- **Edge detection**: operate on the raw `CGImage` bitmap (BGRA, premultiplied). Scanning four
  rays from a point is trivial; object detection (5.5) is four rays + boundary refinement; area
  snapping snaps each rectangle edge independently. Tolerance compares color distance to the
  *start* pixel, not to the previous pixel, which avoids drifting across gradients.
- **Global shortcut**: `NSEvent.addGlobalMonitorForEvents` cannot consume events; use Carbon
  `RegisterEventHotKey` (still works) or a small library (KeyboardShortcuts by sindresorhus).
- **Window bounds** (9.x): `CGWindowListCopyWindowInfo` gives frames without Accessibility
  permission. Element frames (9.6) need Accessibility.
- **Performance target**: entering measure mode < 150 ms on a 5K display; hover snap < 1 ms;
  rendering at display refresh rate.

---

## 18. Suggested roadmap

1. **MVP (P0)**: menu bar + shortcut → frozen overlay → hover snap, two-point, object, area →
   pin, nudge, undo, copy → scale factor → permissions flow →
   multi-display → tests for edge detection → notarized release.
2. **v1.0 (P1)**: loupe, guides, inside/outside, free-angle, perceptual color distance,
   active-window-only, themes, Sparkle, Homebrew, localization.
3. **Later (P2)**: measurements list, following windows, AX-based snapping, per-app profiles,
   color picker, App Store.

---

## 19. Open questions

- Name settled 2026-11-12: **Kaliber** (German for caliber/gauge). Checked: no Mac measuring tool, Homebrew
  cask or relevant GitHub project of that name; kaliber.app/.dev are taken, kaliberapp.com was free.
  Nearby: calibre (e-book manager), Kaliber Interactive (Dutch agency). Considered and dropped:
  Caliper/Screen Calipers (existing Mac tools), Vernier, Snapline, Gauge, Edgewise, Spanwise, EdgeMeter.
  Trademark registers (TMview, DPMA; classes 9/42) not yet checked.
- Scope settled 2026-11-11: measuring only, no screenshot/export features (§8).

### Decided for the prototype (2026-11-09, revisit if needed)

- **Minimum macOS 14**: `SCScreenshotManager` and `SCContentFilter.pointPixelScale` need it.
- **Overlay in AppKit + Core Graphics**, not SwiftUI `Canvas`: snapshot shown via a layer,
  measurements drawn in a flipped view at device-pixel coordinates (verified 1-px exact).
- **Live mode is the default** (changed 2026-11-10 after measuring; PixelSnap freezes). Frozen is
  one key away (L), and the last choice is remembered. Live mode:
  transparent overlay at status-bar level, one `SCStream` per display capped at 30 fps that only
  delivers frames on change; detection runs on the newest frame. Lets ⌘-Tab and animations
  through. Offline cost at 3024×1964 on M1 Pro (release): frame copy 0.7 ms, hover snap
  0.01 ms, freezing a live frame 1.1 ms. ScreenCaptureKit's own cost is shown live in the HUD.
  L in live mode freezes the newest frame without a new capture.
  Measured live (2026-11-10, M1 Pro, 3024×1964, `-liveBenchmark 5`, Release):

  | Screen | fps | copy avg / p95 | snap avg | Kaliber CPU | RSS |
  |---|---|---|---|---|---|
  | mostly static (terminal spinner) | 16 | 2.2 / 3.7 ms | 0.04 ms | 4.5 % | 126 MB |
  | 60 Hz animation | 29 (cap 30) | 2.5 / 4.0 ms | 0.05 ms | 8.8 % | 126 MB |

  System side: WindowServer +0.8 points, replayd +0.6 points. Stream start ~170 ms,
  first frame ~180 ms after start. Debug builds: same fps, snap ~1.5 ms (unoptimised core).
- **Inside edges by default**, ⌥ held switches to outside.
- **Default tolerance 4 %** (≈10/255 per channel). 5 % worked well in the first hands-on test on
  real UIs, 4 % additionally catches very light separators (#F5F5F5 on white); 10 % missed light
  card borders and light-grey buttons, 2–3 % gets caught on shadows and gradients. The last used
  value is remembered across sessions (UserDefaults key `edgeTolerance`).

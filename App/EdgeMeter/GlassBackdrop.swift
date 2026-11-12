import AppKit

/// Liquid Glass behind the HUD and the loupe (macOS 26+).
///
/// Sits *below* the measure view, which keeps drawing the HUD text and the loupe pixels on
/// top: the loupe must show the exact captured pixels, never pixels seen through glass.
/// Only exists on macOS 26 and later; without it the measure view draws plain dark
/// backgrounds instead.
final class GlassBackdrop: NSView {
    static let hudCornerRadius: CGFloat = 14
    static let loupeCornerRadius: CGFloat = 13
    /// Glass rim around the loupe's pixel area.
    static let loupeRim: CGFloat = 6

    private let hud: NSView
    private let loupe: NSView

    static func makeIfAvailable(frame: NSRect) -> GlassBackdrop? {
        guard #available(macOS 26, *) else { return nil }
        return GlassBackdrop(
            frame: frame,
            hud: glass(cornerRadius: hudCornerRadius),
            loupe: glass(cornerRadius: loupeCornerRadius)
        )
    }

    private init(frame: NSRect, hud: NSView, loupe: NSView) {
        self.hud = hud
        self.loupe = loupe
        super.init(frame: frame)
        addSubview(hud)
        addSubview(loupe)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    @available(macOS 26, *)
    private static func glass(cornerRadius: CGFloat) -> NSView {
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.style = .regular
        // Dark glass keeps the white HUD text readable on light and dark content alike.
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.isHidden = true
        return glass
    }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Frames in the measure view's (flipped) coordinates; `nil` hides that piece.
    func update(hud hudFrame: CGRect?, loupe loupeFrame: CGRect?) {
        place(hud, at: hudFrame)
        place(loupe, at: loupeFrame)
    }

    private func place(_ view: NSView, at frame: CGRect?) {
        guard let frame else {
            view.isHidden = true
            return
        }
        if view.frame != frame { view.frame = frame }
        view.isHidden = false
    }
}

import KaliberCore

/// Tiny drawing helper for building test fixtures without any graphics framework.
struct SyntheticImage {
    let width: Int
    let height: Int
    private(set) var pixels: [RGBA]

    init(width: Int, height: Int, background: RGBA = .white) {
        self.width = width
        self.height = height
        self.pixels = Array(repeating: background, count: width * height)
    }

    subscript(x: Int, y: Int) -> RGBA {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    mutating func fill(_ rect: PixelRect, _ color: RGBA) {
        for y in rect.minY...rect.maxY {
            for x in rect.minX...rect.maxX where x >= 0 && y >= 0 && x < width && y < height {
                self[x, y] = color
            }
        }
    }

    /// Horizontal gradient from `from` at `rect.minX` to `to` at `rect.maxX` (linear per channel).
    mutating func horizontalGradient(_ rect: PixelRect, from: RGBA, to: RGBA) {
        let n = max(rect.width - 1, 1)
        for x in rect.minX...rect.maxX {
            let t = Double(x - rect.minX) / Double(n)
            let c = SyntheticImage.mix(from, to, t)
            fill(PixelRect(x: x, y: rect.minY, width: 1, height: rect.height), c)
        }
    }

    /// Draws `rect` in `color` with a one-pixel anti-aliased fringe of `coverage` (0...1)
    /// blended with whatever is currently outside the rect.
    mutating func antialiasedRect(_ rect: PixelRect, _ color: RGBA, coverage: Double) {
        fill(rect, color)
        let fringe = PixelRect(x: rect.minX - 1, y: rect.minY - 1, width: rect.width + 2, height: rect.height + 2)
        for y in fringe.minY...fringe.maxY {
            for x in fringe.minX...fringe.maxX where x >= 0 && y >= 0 && x < width && y < height && !rect.contains(PixelPoint(x, y)) {
                self[x, y] = SyntheticImage.mix(self[x, y], color, coverage)
            }
        }
    }

    static func mix(_ a: RGBA, _ b: RGBA, _ t: Double) -> RGBA {
        func ch(_ x: UInt8, _ y: UInt8) -> UInt8 {
            UInt8(clamping: Int((Double(x) * (1 - t) + Double(y) * t).rounded()))
        }
        return RGBA(r: ch(a.r, b.r), g: ch(a.g, b.g), b: ch(a.b, b.b), a: ch(a.a, b.a))
    }

    func buffer(format: PixelFormat = .rgba8, rowPadding: Int = 0) -> PixelBuffer {
        let bytesPerRow = width * 4 + rowPadding
        var data = [UInt8](repeating: 0xEE, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let c = self[x, y]
                let base = y * bytesPerRow + x * 4
                switch format {
                case .rgba8:
                    data[base] = c.r; data[base + 1] = c.g; data[base + 2] = c.b; data[base + 3] = c.a
                case .bgra8:
                    data[base] = c.b; data[base + 1] = c.g; data[base + 2] = c.r; data[base + 3] = c.a
                }
            }
        }
        return PixelBuffer(width: width, height: height, bytesPerRow: bytesPerRow, format: format, data: data)
    }
}

extension RGBA {
    static let red = RGBA(r: 220, g: 40, b: 40)
    static let blue = RGBA(r: 40, g: 80, b: 220)
    static let lightGray = RGBA(gray: 240)
    static let midGray = RGBA(gray: 128)
}

/// 400×300 white canvas with a 100×50 blue box at (100, 100) and red text-like blobs inside it.
func buttonFixture() -> SyntheticImage {
    var img = SyntheticImage(width: 400, height: 300)
    img.fill(PixelRect(x: 100, y: 100, width: 100, height: 50), .blue)
    // "Label": three small red glyph blocks inside the button.
    img.fill(PixelRect(x: 120, y: 118, width: 8, height: 14), .red)
    img.fill(PixelRect(x: 132, y: 118, width: 8, height: 14), .red)
    img.fill(PixelRect(x: 144, y: 122, width: 8, height: 10), .red)
    return img
}

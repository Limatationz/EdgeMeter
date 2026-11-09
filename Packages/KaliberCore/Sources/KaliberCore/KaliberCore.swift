/// Kaliber's measurement core: pure-Swift edge detection over a frozen pixel buffer.
///
/// Nothing in this module depends on AppKit, so it builds and tests on any platform
/// with the Swift toolchain. The optional CoreGraphics bridge lives in
/// `PixelBuffer+CoreGraphics.swift` behind `#if canImport(CoreGraphics)`.
public enum KaliberCore {
    public static let version = "0.1.0"
}

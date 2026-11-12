import Testing
import EdgeMeterCore

@Suite("Color metrics")
struct ColorMetricTests {
    @Test("identical colors have zero distance", arguments: ColorMetric.allCases)
    func identity(metric: ColorMetric) {
        #expect(metric.distance(.red, .red) == 0)
        #expect(metric.distance(.black, .black) == 0)
    }

    @Test("black vs white is exactly 1", arguments: ColorMetric.allCases)
    func fullRange(metric: ColorMetric) {
        #expect(abs(metric.distance(.black, .white) - 1) < 1e-9)
    }

    @Test("stays within 0...1 and is symmetric", arguments: ColorMetric.allCases)
    func rangeAndSymmetry(metric: ColorMetric) {
        let samples: [RGBA] = [.black, .white, .red, .blue, RGBA(r: 255, g: 0, b: 0), RGBA(r: 0, g: 255, b: 0), RGBA(r: 0, g: 0, b: 255), RGBA(r: 255, g: 255, b: 0), .midGray]
        for a in samples {
            for b in samples {
                let d = metric.distance(a, b)
                #expect(d >= 0 && d <= 1)
                #expect(abs(d - metric.distance(b, a)) < 1e-12)
            }
        }
    }

    @Test("alpha is ignored", arguments: ColorMetric.allCases)
    func alphaIgnored(metric: ColorMetric) {
        #expect(metric.distance(RGBA(r: 10, g: 20, b: 30, a: 255), RGBA(r: 10, g: 20, b: 30, a: 0)) == 0)
    }

    @Test("maxChannel is the largest channel difference")
    func maxChannel() {
        let d = ColorMetric.maxChannel.distance(RGBA(r: 0, g: 0, b: 0), RGBA(r: 51, g: 10, b: 0))
        #expect(abs(d - 0.2) < 1e-9)
    }

    @Test("perceptual weights green more than blue")
    func perceptualWeights() {
        let g = ColorMetric.perceptual.distance(.midGray, RGBA(r: 128, g: 168, b: 128))
        let b = ColorMetric.perceptual.distance(.midGray, RGBA(r: 128, g: 128, b: 168))
        #expect(g > b)
        // Euclidean treats them the same.
        let eg = ColorMetric.euclidean.distance(.midGray, RGBA(r: 128, g: 168, b: 128))
        let eb = ColorMetric.euclidean.distance(.midGray, RGBA(r: 128, g: 128, b: 168))
        #expect(abs(eg - eb) < 1e-12)
    }
}

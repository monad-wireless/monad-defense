import Charts
import SwiftUI

/// M0 / M2: mean, SD and CV of one seeded window of amplitudes. A gain moves
/// the mean and the SD together and leaves the CV alone.
struct SpreadWidget: View {
    let windows: Bool
    @State private var m = 60.0
    @State private var mu = 10.0
    @State private var sigma: Double
    @State private var gain = 1.0

    init(windows: Bool) {
        self.windows = windows
        _sigma = State(initialValue: windows ? 0.4 : 1.5)
    }

    var body: some View {
        var rng = SeededRandom(seed: 11)
        let xs = (0..<Int(m)).map { _ in gain * max(0.01, mu + sigma * rng.normal()) }
        let mean = xs.reduce(0, +) / Double(xs.count)
        let sd = (xs.reduce(0) { $0 + pow($1 - mean, 2) } / Double(xs.count - 1)).squareRoot()
        WidgetLayout(
            formula: "\\bar A=\(tex(mean, 2)),\\ s_A=\(tex(sd, 3)),\\ \\mathrm{CV}=\(tex(sd / mean, 4))",
            words: "move the gain: mean and SD scale with it, CV does not. Raise the spread at fixed gain and CV rises too. CV cancels a gain, and only a gain."
        ) {
            Chart {
                RectangleMark(yStart: .value("lo", mean - sd), yEnd: .value("hi", mean + sd))
                    .foregroundStyle(GuideColors.accent.opacity(0.12))
                RuleMark(y: .value("mean", mean)).foregroundStyle(GuideColors.alt)
                ForEach(Array(xs.enumerated()), id: \.offset) { i, v in
                    PointMark(x: .value("i", i + 1), y: .value("A", v))
                        .foregroundStyle(GuideColors.accent)
                        .symbolSize(18)
                }
            }
            .chartYScale(domain: 0...max(25, (xs.max() ?? 0) * 1.05))
            .chartXAxisLabel("sample i · band: mean ± SD")
        } controls: {
            GSlider(label: "Samples m", value: $m, range: 5...200, step: 1, digits: 0)
            GSlider(label: "True level", value: $mu, range: 2...20, digits: 1)
            GSlider(label: "True spread", value: $sigma, range: 0.05...4)
            GSlider(label: "Receiver gain g", value: $gain, range: 0.5...2, unit: "×")
        }
    }
}

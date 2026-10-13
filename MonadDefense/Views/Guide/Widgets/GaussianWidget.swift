import Charts
import SwiftUI

/// M0: a central Gaussian interval and its full width 2zσ.
struct GaussianWidget: View {
    @State private var sigma = 1.0
    @State private var level = 0.9

    var body: some View {
        let z = GuideMath.normPpf(1 - (1 - level) / 2)
        let half = z * sigma
        let curve = sample(-5, 5, 240) { GuideMath.normPdf($0, sd: sigma) }
        WidgetLayout(
            formula: "z_{1-\\alpha/2}=\(tex(z, 3)),\\quad W=2z\\sigma=\(tex(2 * half, 3))",
            readout: ["interval μ ± \(fmt(half, 3)) · full width \(fmt(2 * half, 3))"],
            words: "the shaded mass is the coverage. At 90 % the full width is about 3.29 σ; a count interval built this way follows the same rule, with σ the count uncertainty."
        ) {
            Chart {
                ForEach(curve.filter { abs($0.x) <= half }) { p in
                    AreaMark(x: .value("x", p.x), y: .value("p", p.y))
                        .foregroundStyle(GuideColors.accent.opacity(0.2))
                }
                ForEach(curve) { p in
                    LineMark(x: .value("x", p.x), y: .value("p", p.y)).foregroundStyle(GuideColors.accent)
                }
                RuleMark(x: .value("lo", -half)).foregroundStyle(GuideColors.alt).lineStyle(StrokeStyle(dash: [4, 3]))
                RuleMark(x: .value("hi", half)).foregroundStyle(GuideColors.alt).lineStyle(StrokeStyle(dash: [4, 3]))
            }
            .chartXScale(domain: -5...5)
            .chartXAxisLabel("x − μ")
        } controls: {
            GSlider(label: "Spread σ", value: $sigma, range: 0.2...2.5)
            GChoice(label: "Coverage", selection: $level, options: [(0.68, "68 %"), (0.8, "80 %"), (0.9, "90 %"), (0.95, "95 %"), (0.99, "99 %")])
        }
    }
}

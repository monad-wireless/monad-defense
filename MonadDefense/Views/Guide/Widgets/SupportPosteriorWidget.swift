import Charts
import SwiftUI

/// M5, §6.1.1: the observation equals the three-person anchor (1.12 oct),
/// σ = 0.23 oct, knee averaged over 161 log-spaced values 0.5–20. Defaults
/// reproduce the companion notebook's posterior means (uniform 4.46, 7.76,
/// 15.15 for supports 0–8, 0–16, 0–32; geometric 3.58, 4.43, 4.75).
struct SupportPosteriorWidget: View {
    @State private var kMax = 8.0
    @State private var geometric = false
    @State private var sigma = 0.23

    var body: some View {
        let p = GuideMath.conditionalPmf(maxCount: Int(kMax), geometric: geometric, sigma: sigma)
        let s = GuideMath.summary(p)
        let above3 = p.dropFirst(4).reduce(0, +)
        let table = [8, 16, 32].map { m in (m, GuideMath.summary(GuideMath.conditionalPmf(maxCount: m, geometric: geometric, sigma: sigma)).mean) }
        WidgetLayout(
            formula: "\\mathbb{E}[N\\mid L_a]=\(tex(s.mean, 2)),\\quad 90\\,\\%\\ [\(s.lo),\(s.hi)],\\quad P(N>3)=\(tex(above3, 3))",
            readout: [table.map { "0–\($0.0): mean \(fmt($0.1, 2))" }.joined(separator: " · ")],
            words: "the observation is the three-person level itself (red bar), yet the posterior mean moves with $K_{\\max}$. The likelihood is too flat to say \"three\". That is the signal to coarsen, not to report a number."
        ) {
            Chart {
                ForEach(Array(p.enumerated()), id: \.offset) { k, v in
                    BarMark(x: .value("k", k), y: .value("p", v)).foregroundStyle(k == 3 ? GuideColors.alt : GuideColors.accent)
                }
                RuleMark(x: .value("mean", s.mean)).foregroundStyle(.primary).lineStyle(StrokeStyle(dash: [4, 3]))
            }
            .chartXAxisLabel("count k · dashed: posterior mean")
        } controls: {
            GSlider(label: "Support K_max", value: $kMax, range: 4...40, step: 1, digits: 0)
            GChoice(label: "Count prior", selection: $geometric, options: [(false, "uniform"), (true, "geometric 0.2·0.8ᵏ")])
            GSlider(label: "Level noise σ", value: $sigma, range: 0.05...0.5, unit: "oct")
        }
    }
}

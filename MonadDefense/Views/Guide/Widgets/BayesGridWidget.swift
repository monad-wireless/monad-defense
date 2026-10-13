import Charts
import SwiftUI

/// M0: posterior = likelihood × prior on a finite count support. A flat
/// likelihood hands the answer to the prior and the support.
struct BayesGridWidget: View {
    @State private var kMax = 12.0
    @State private var centre = 4.0
    @State private var width = 1.5
    @State private var geometric = false

    var body: some View {
        let ks = Array(0...Int(kMax))
        let prior = ks.map { geometric ? 0.2 * pow(0.8, Double($0)) : 1.0 }
        let pz = prior.reduce(0, +)
        let raw = ks.map { GuideMath.normPdf(Double($0), mu: centre, sd: width) * prior[$0] }
        let z = raw.reduce(0, +)
        let post = raw.map { $0 / z }
        let s = GuideMath.summary(post)
        WidgetLayout(
            formula: "\\mathbb{E}[N\\mid L]=\(tex(s.mean, 2)),\\quad 90\\,\\%\\ [\(s.lo),\(s.hi)]",
            words: "make the likelihood wide, then move $K_{\\max}$. The posterior mean follows the support, not the data. A confident answer can then come from the prior, not from the observation."
        ) {
            Chart {
                ForEach(ks, id: \.self) { k in
                    BarMark(x: .value("k", k), y: .value("p", prior[k] / pz), width: .ratio(0.9))
                        .foregroundStyle(.secondary.opacity(0.35))
                    BarMark(x: .value("k", k), y: .value("p", post[k]), width: .ratio(0.45))
                        .foregroundStyle(GuideColors.accent)
                }
            }
            .chartXAxisLabel("count k · grey prior · blue posterior")
        } controls: {
            GSlider(label: "Support K_max", value: $kMax, range: 4...40, step: 1, digits: 0)
            GChoice(label: "Prior", selection: $geometric, options: [(false, "uniform"), (true, "geometric")])
            GSlider(label: "Likelihood centre", value: $centre, range: 0...20, digits: 1)
            GSlider(label: "Likelihood width", value: $width, range: 0.3...30, digits: 1, log: true)
        }
    }
}

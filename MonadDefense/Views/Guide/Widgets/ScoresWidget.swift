import Charts
import SwiftUI

/// M4: scoring a predicted count distribution: RPS, absolute error of the
/// median, and whether the central 90 % set covers. The prediction is a
/// discretised normal (illustrative).
struct ScoresWidget: View {
    @State private var centre = 3.0
    @State private var spread = 1.2
    @State private var truth = 4.0

    var body: some View {
        let ks = Array(0...10)
        let raw = ks.map { GuideMath.normPdf(Double($0), mu: centre, sd: spread) }
        let z = raw.reduce(0, +)
        let p = raw.map { $0 / z }
        var acc = 0.0
        let F = p.map { acc += $0; return acc }
        let y = Int(truth)
        let rps = zip(ks, F).reduce(0) { $0 + pow($1.1 - ($1.0 >= y ? 1 : 0), 2) }
        let median = F.firstIndex { $0 >= 0.5 } ?? 0
        let s = GuideMath.summary(p)
        WidgetLayout(
            formula: "\\mathrm{RPS}=\\sum_k\\big(F(k)-\\mathbb{1}\\{k\\ge \(y)\\}\\big)^2=\(tex(rps, 3))",
            readout: ["|median − y| = \(abs(median - y)) · P(y) = \(fmt(p[y], 3))",
                      "90 % set \(s.lo)–\(s.hi) \(y >= s.lo && y <= s.hi ? "covers" : "misses")"],
            words: "RPS is the squared gap between the predicted cumulative curve and the truth step. A sharp prediction near the truth scores low; a very wide one always covers and still scores poorly."
        ) {
            Chart {
                ForEach(ks, id: \.self) { k in
                    BarMark(x: .value("k", k), y: .value("p", p[k])).foregroundStyle(GuideColors.accent.opacity(0.3))
                    LineMark(x: .value("k", k), y: .value("F", F[k]), series: .value("s", "F"))
                        .interpolationMethod(.stepCenter)
                        .foregroundStyle(GuideColors.accent)
                    LineMark(x: .value("k", k), y: .value("F", k >= y ? 1.0 : 0.0), series: .value("s", "truth"))
                        .interpolationMethod(.stepCenter)
                        .foregroundStyle(GuideColors.alt)
                        .lineStyle(StrokeStyle(dash: [4, 3]))
                }
            }
            .chartYScale(domain: 0...1.05)
            .chartXAxisLabel("count k · blue: predicted F(k) · red: truth step")
        } controls: {
            GSlider(label: "Prediction centre", value: $centre, range: 0...10, digits: 1)
            GSlider(label: "Prediction spread", value: $spread, range: 0.2...5)
            GSlider(label: "True count y", value: $truth, range: 0...10, step: 1, digits: 0)
        }
    }
}

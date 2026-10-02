import Charts
import SwiftUI

/// M5, §6.8.2: the split-conformal threshold is the ⌈(m + 1)(1 − α)⌉-th
/// smallest of m calibration scores, infinite when that rank exceeds m:
/// at least 9 scores for 90 %, 19 for 95 %. Scores are seeded and synthetic.
struct ConformalRankWidget: View {
    @State private var m = 9.0
    @State private var alpha = 0.1

    var body: some View {
        let mm = Int(m)
        var rng = SeededRandom(seed: 9)
        let scores = (0..<mm).map { _ in abs(rng.normal()) * 1.2 }.sorted()
        let cr = GuideMath.conformalRank(m: mm, alpha: alpha)
        let minM = (1...200).first { GuideMath.conformalRank(m: $0, alpha: alpha).finite } ?? 0
        let threshold = cr.finite ? scores[cr.rank - 1] : .infinity
        WidgetLayout(
            formula: "r=\\lceil(\(mm)+1)(1-\(tex(alpha, 2)))\\rceil=\(cr.rank)\\ \(cr.finite ? "\\le" : ">")\\ m\\ \\Rightarrow\\ \\hat q=\(cr.finite ? tex(threshold, 3) : "\\infty")",
            readout: ["smallest m with a finite threshold: \(minM)", cr.finite ? "finite set" : "the set is every count"],
            words: "with eight scores, no score is high enough to promise 90 %, so the only honest set is \"anything\". Nine is the arithmetic minimum, not an adequate sample. A day-level band needs nine exchangeable labelled days."
        ) {
            Chart {
                ForEach(Array(scores.enumerated()), id: \.offset) { i, s in
                    BarMark(x: .value("rank", i + 1), y: .value("score", s))
                        .foregroundStyle(i + 1 == cr.rank ? GuideColors.alt : GuideColors.accent.opacity(0.35))
                }
                RuleMark(x: .value("r", cr.rank)).foregroundStyle(cr.finite ? GuideColors.alt : .secondary).lineStyle(StrokeStyle(dash: [4, 3]))
                if cr.finite {
                    RuleMark(y: .value("q", threshold)).foregroundStyle(GuideColors.alt).lineStyle(StrokeStyle(dash: [4, 3]))
                }
            }
            .chartXScale(domain: 0...(max(mm, cr.rank) + 1))
            .chartYScale(domain: 0...4.5)
            .chartXAxisLabel("rank of the sorted score · dashed: required rank")
        } controls: {
            GSlider(label: "Calibration scores m", value: $m, range: 1...40, step: 1, digits: 0)
            GChoice(label: "Target coverage", selection: $alpha, options: [(0.2, "80 %"), (0.1, "90 %"), (0.05, "95 %")])
        }
    }
}

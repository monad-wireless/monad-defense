import Charts
import SwiftUI

/// M5, Eqs. (6.6)–(6.8) under the companion notebook's planning scenario.
/// At t = 0 the widths reproduce Fig. 6.3; T* = 3385 h, 124 h, 7.48 h at
/// N = 0, 1, 2, and the target is missed at calibration from N = 3.
struct ResolutionWidget: View {
    @State private var hours = 0.0
    @State private var target = 2.0
    @State private var sigma = 0.05
    @State private var s0Scale = 1.0
    @State private var qScale = 1.0

    private var plan: GuideMath.Plan {
        var plan = GuideMath.Plan()
        plan.target = target
        plan.sigma = sigma
        plan.s0 = plan.s0.map { $0 * s0Scale }
        plan.q = plan.q.map { $0 * qScale }
        return plan
    }

    var body: some View {
        let plan = self.plan
        let rows = (0...8).map { n in (n, GuideMath.resolution(Double(n), hours: hours, plan: plan), GuideMath.resolution(Double(n), hours: 0, plan: plan)) }
        let yMax = min(25, max(6, rows.map(\.1.width).max() ?? 6) * 1.1)
        let two = rows[2].1
        WidgetLayout(
            formula: "W(2,\(tex(hours, 0))\\,\\mathrm h)=\\frac{2\\cdot\(tex(two.z, 3))}{\(tex(two.slope, 4))}\\sqrt{\\sigma^2+J\\Sigma_0J^\\top+tJQJ^\\top}=\(tex(two.width, 2))",
            readout: rows.prefix(4).map { n, _, zero in
                let h = zero.horizon.map { $0.isInfinite ? "no finite expiry" : "horizon \(sig($0)) h" } ?? "unavailable at t = 0"
                return "N = \(n): width \(fmt(zero.width, 2)) at t = 0 · \(h)"
            },
            words: "hollow points miss the target. From three people the target is missed at $t=0$, so no reference schedule helps. Below that, drift spends the budget $B$; the horizon is $B$ over the drift rate. All inputs are the companion notebook's assumptions."
        ) {
            Chart {
                RectangleMark(yStart: .value("0", 0), yEnd: .value("W*", target)).foregroundStyle(GuideColors.accent.opacity(0.1))
                RuleMark(y: .value("W*", target)).foregroundStyle(.secondary).lineStyle(StrokeStyle(dash: [4, 3]))
                ForEach(rows, id: \.0) { n, now, zero in
                    LineMark(x: .value("N", n), y: .value("W", min(zero.width, yMax)), series: .value("s", "t0"))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(dash: [4, 3]))
                    LineMark(x: .value("N", n), y: .value("W", min(now.width, yMax)), series: .value("s", "now"))
                        .foregroundStyle(GuideColors.accent)
                    PointMark(x: .value("N", n), y: .value("W", min(now.width, yMax)))
                        .symbol(now.width <= target ? .circle : .square)
                        .foregroundStyle(now.width <= target ? GuideColors.accent : GuideColors.alt)
                }
            }
            .chartYScale(domain: 0...yMax)
            .chartXAxisLabel("assumed occupancy N · dashed t = 0 · red squares miss W*")
            .chartYAxisLabel("full 90 % width (people)")
        } controls: {
            GSlider(label: "Time since reference t", value: $hours, range: 0...48, step: 1, unit: "h", digits: 0)
            GSlider(label: "Requested width W*", value: $target, range: 0.5...6, unit: "people", digits: 1)
            GSlider(label: "Level noise σ", value: $sigma, range: 0.01...0.2, unit: "oct", digits: 3)
            GSlider(label: "Calibration SD ×", value: $s0Scale, range: 0...3)
            GSlider(label: "Drift SD ×", value: $qScale, range: 0...5)
        }
    }
}

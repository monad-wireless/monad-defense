import Charts
import SwiftUI

/// M0: decay e^(−x/K), saturation 1 − e^(−x/K) and the tangent at a cursor.
struct SaturationWidget: View {
    @State private var K = 3.0
    @State private var x0 = 2.0

    var body: some View {
        let sat = -expm1(-x0 / K)
        let slope = exp(-x0 / K) / K
        WidgetLayout(
            formula: "1-e^{-\(tex(x0, 1))/\(tex(K, 1))}=\(tex(sat, 3)),\\quad \\text{slope}=\(tex(slope, 3))",
            readout: ["height \(fmt(sat * 100, 1)) % of the ceiling", "slope at 0: \(fmt(1 / K, 3)) per person"],
            words: "the orange tangent is the exchange rate between people and output. Past a few multiples of $K$ the curve still rises, but almost nothing changes per extra person."
        ) {
            Chart {
                ForEach(sample(0, 12) { exp(-$0 / K) }) { p in
                    LineMark(x: .value("x", p.x), y: .value("y", p.y), series: .value("s", "decay"))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
                ForEach(sample(0, 12) { -expm1(-$0 / K) }) { p in
                    LineMark(x: .value("x", p.x), y: .value("y", p.y), series: .value("s", "saturation"))
                        .foregroundStyle(GuideColors.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                LineMark(x: .value("x", x0 - 2), y: .value("y", sat - 2 * slope), series: .value("s", "tangent"))
                    .foregroundStyle(GuideColors.amber)
                LineMark(x: .value("x", x0 + 2), y: .value("y", sat + 2 * slope), series: .value("s", "tangent"))
                    .foregroundStyle(GuideColors.amber)
                RuleMark(x: .value("K", K))
                    .foregroundStyle(GuideColors.accent.opacity(0.5))
                    .lineStyle(StrokeStyle(dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) { Text("x = K").font(.caption2) }
                PointMark(x: .value("x", x0), y: .value("y", sat)).foregroundStyle(GuideColors.amber)
            }
            .chartXScale(domain: 0...12)
            .chartYScale(domain: -0.05...1.05)
            .chartXAxisLabel("input x (people)")
        } controls: {
            GSlider(label: "Knee K", value: $K, range: 0.5...10, unit: "people", digits: 1)
            GSlider(label: "Cursor x", value: $x0, range: 0...12, unit: "people", digits: 1)
        }
    }
}
